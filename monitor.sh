#!/bin/bash

# Refresh interval (default: 1 second, or from the first argument e.g. ./monitor.sh 5)
INTERVAL=${1:-1}

# Single-run mode when the '--once' or '-1' argument is given
ONCE_MODE=false
if [ "$1" == "--once" ] || [ "$1" == "-1" ]; then
  ONCE_MODE=true
fi

# Style Monochrome & Minimalist Terminal
BOLD='\033[1m'
DIM='\033[2m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
NC='\033[0m'

# Animation frames for the live spinner & spark star
SPINNER_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
SPARK_FRAMES=("✦" "✧" "✶" "✵")
FRAME_INDEX=0

# Utilisation percentage at which a pie chart switches from green to red
ALERT_AT=90

# Renders three side-by-side pie charts (CPU / Memory / Storage) with legends.
# Each pie is 12x12 half-block pixels, so three of them plus gaps line up exactly
# with the 42-column dividers used elsewhere in the dashboard.
# Arguments: cpu_user% cpu_sys% memory_used% disk_used%  (pass -1 when unknown)
render_pies() {
  awk -v u="$1" -v s="$2" -v m="$3" -v d="$4" -v alert="$ALERT_AT" '
  function fg(c) { return ESC "[38;5;" c "m" }
  function bg(c) { return ESC "[48;5;" c "m" }

  # Colour of the pixel at (px,py) inside pie i, or -1 when outside the circle
  function pixel(i, px, py,   nx, ny, deg, p) {
    nx = (px + 0.5 - W / 2) / (W / 2)
    ny = (py + 0.5 - W / 2) / (W / 2)
    if (nx * nx + ny * ny > 1) return -1
    deg = atan2(nx, -ny) * 180 / PI   # 0 deg at 12 o clock, growing clockwise
    if (deg < 0) deg += 360
    p = deg / 3.6
    if (p < V1[i]) return C1[i]
    if (p < V1[i] + V2[i]) return C2[i]
    return C3[i]
  }

  # One text row of pie i; each character packs two vertical pixels
  function pierow(i, ty,   x, ct, cb, out) {
    out = ""
    for (x = 0; x < W; x++) {
      ct = pixel(i, x, 2 * ty)
      cb = pixel(i, x, 2 * ty + 1)
      if (ct < 0 && cb < 0)  out = out " "
      else if (cb < 0)       out = out fg(ct) "▀" NC
      else if (ct < 0)       out = out fg(cb) "▄" NC
      else                   out = out fg(ct) bg(cb) "▀" NC
    }
    return out
  }

  # A legend entry padded to exactly 12 visible columns
  function legend(colour, glyph, name, value) {
    return fg(colour) glyph NC sprintf(" %-4s%6s", name, value)
  }

  function pct(v) { return (v < 0) ? "n/a" : sprintf("%.1f%%", v) }

  BEGIN {
    ESC = sprintf("%c", 27); NC = ESC "[0m"; BOLD = ESC "[1m"
    PI = 3.141592653589793
    W = 12; H = 6; GAP = "   "; BLANK = "            "

    OK1 = 35;  OK2 = 114     # healthy: green, plus a lighter green for slice 2
    RED1 = 160; RED2 = 210   # >= alert: red, plus a lighter red for slice 2
    IDLE = 240               # unused share stays a recessive grey

    if (u < 0) u = 0
    if (s < 0) s = 0
    V1[1] = u; V2[1] = s
    V1[2] = (m < 0) ? 0 : m; V2[2] = 0
    V1[3] = (d < 0) ? 0 : d; V2[3] = 0
    USED[1] = u + s; USED[2] = m; USED[3] = d

    for (i = 1; i <= 3; i++) {
      if (USED[i] < 0)      { C1[i] = IDLE; C2[i] = IDLE }
      else if (USED[i] >= alert) { C1[i] = RED1; C2[i] = RED2 }
      else                  { C1[i] = OK1;  C2[i] = OK2 }
      C3[i] = IDLE
    }

    TITLE[1] = "◇ CPU Usage "
    TITLE[2] = "◇ Memory    "
    TITLE[3] = "◇ Storage   "

    L[1, 1] = legend(C1[1], "●", "User", pct(u))
    L[1, 2] = legend(C2[1], "●", "Sys",  pct(s))
    L[1, 3] = legend(C3[1], "○", "Idle", pct(100 - u - s))
    L[2, 1] = legend(C1[2], "●", "Used", pct(m))
    L[2, 2] = legend(C3[2], "○", "Free", pct((m < 0) ? -1 : 100 - m))
    L[2, 3] = BLANK
    L[3, 1] = legend(C1[3], "●", "Used", pct(d))
    L[3, 2] = legend(C3[3], "○", "Free", pct((d < 0) ? -1 : 100 - d))
    L[3, 3] = BLANK

    # Headline value, with a glyph so the alert state is never colour-alone
    for (i = 1; i <= 3; i++) {
      if (USED[i] < 0) STAT[i] = sprintf("%-12s", "[i]     n/a")
      else if (USED[i] >= alert)
        STAT[i] = fg(RED1) "[✕]" NC sprintf(" %6.1f%% ", USED[i])
      else
        STAT[i] = fg(OK1) "[✓]" NC sprintf(" %6.1f%% ", USED[i])
    }

    print BOLD TITLE[1] NC GAP BOLD TITLE[2] NC GAP BOLD TITLE[3] NC
    for (ty = 0; ty < H; ty++)
      print pierow(1, ty) GAP pierow(2, ty) GAP pierow(3, ty)
    for (k = 1; k <= 3; k++)
      print L[1, k] GAP L[2, k] GAP L[3, k]
    print STAT[1] GAP STAT[2] GAP STAT[3]
  }'
}

# Restore the cursor when the script is interrupted (Ctrl+C)
cleanup() {
  tput cnorm 2>/dev/null
  echo -e "\n${WHITE}Live monitoring stopped. See you next time!${NC}"
  exit 0
}
trap cleanup INT TERM

# Hide the cursor so the live dashboard renders smoothly
if [ "$ONCE_MODE" = false ]; then
  tput civis 2>/dev/null
fi

render_dashboard() {
  local SPINNER="$1"
  local SPARK="$2"

  # =========================================================
  # 1. COLLECT ALL METRICS FIRST
  #    (Done before clearing the screen so there is no flicker)
  # =========================================================

  # Storage Metric & Diagnostic
  DISK_LINE=$(df -h / | awk 'NR==2 {print $2, $3, $4, $5}')
  DISK_TOTAL=$(echo "$DISK_LINE" | awk '{print $1}')
  DISK_USED=$(echo "$DISK_LINE" | awk '{print $2}')
  DISK_FREE=$(echo "$DISK_LINE" | awk '{print $3}')
  DISK_USAGE=$(echo "$DISK_LINE" | awk '{print $4}' | tr -d '%')

  if [ -n "$DISK_USAGE" ] && [ "$DISK_USAGE" -ge 85 ]; then
    DIAG_DISK="${WHITE}[✕] CRITICAL:${GRAY} Disk almost full (${DISK_USAGE}% used)! Free up space now.${NC}"
  elif [ -n "$DISK_USAGE" ] && [ "$DISK_USAGE" -ge 75 ]; then
    DIAG_DISK="${WHITE}[!] WARNING:${GRAY} High disk usage (${DISK_USAGE}% used).${NC}"
  else
    DIAG_DISK="${WHITE}[✓] OK:${GRAY} Disk capacity is healthy (${DISK_USAGE}% used).${NC}"
  fi

  # Disk SMART Health Diagnostic
  SMART_STATUS=$(diskutil info / 2>/dev/null | grep -i "SMART Status" | awk -F':' '{print $2}' | xargs)
  if [ -n "$SMART_STATUS" ]; then
    if [ "$SMART_STATUS" == "Verified" ]; then
      DIAG_SMART="${WHITE}[✓] OK:${GRAY} SSD/Disk S.M.A.R.T Status Verified.${NC}"
    else
      DIAG_SMART="${WHITE}[✕] CRITICAL:${GRAY} Disk S.M.A.R.T status is $SMART_STATUS! Possible SSD hardware fault.${NC}"
    fi
  else
    DIAG_SMART=""
  fi

  # Memory & Swap Diagnostic
  SWAP_USED_MB=$(sysctl vm.swapusage 2>/dev/null | awk -F'used = ' '{print $2}' | awk '{print $1}' | tr -d 'M' | awk -F'.' '{print $1}')
  SWAP_USED_MB=${SWAP_USED_MB:-0}
  MEM_PRESSURE=$(memory_pressure 2>/dev/null | tail -1)

  # Used-memory share for the pie chart (-1 when the percentage cannot be parsed)
  MEM_FREE_PCT=$(echo "$MEM_PRESSURE" | grep -E -o '[0-9]+%' | tr -d '%' | head -1)
  if [ -n "$MEM_FREE_PCT" ]; then
    MEM_USED_PCT=$((100 - MEM_FREE_PCT))
  else
    MEM_USED_PCT=-1
  fi

  if [ "$SWAP_USED_MB" -gt 2048 ]; then
    DIAG_MEM="${WHITE}[!] WARNING:${GRAY} High swap usage (${SWAP_USED_MB} MB used).${NC}"
  elif echo "$MEM_PRESSURE" | grep -qi "warn\|critical"; then
    DIAG_MEM="${WHITE}[!] WARNING:${GRAY} High memory pressure! (${MEM_PRESSURE})${NC}"
  else
    DIAG_MEM="${WHITE}[✓] OK:${GRAY} RAM & swap usage are normal (${SWAP_USED_MB} MB swap).${NC}"
  fi

  # CPU & Runaway Process Diagnostic
  TOP_PROC=$(ps -eo %cpu,pid,comm -r | awk 'NR==2')
  TOP_CPU=$(echo "$TOP_PROC" | awk '{print $1}' | awk -F'.' '{print $1}')
  TOP_PID=$(echo "$TOP_PROC" | awk '{print $2}')
  TOP_NAME=$(echo "$TOP_PROC" | awk '{$1=""; $2=""; print $0}' | xargs | awk -F'/' '{print $NF}')

  if [ -n "$TOP_CPU" ] && [ "$TOP_CPU" -ge 80 ]; then
    DIAG_CPU="${WHITE}[✕] CRITICAL:${GRAY} Very high CPU load! '$TOP_NAME' (PID: $TOP_PID) is using ${TOP_CPU}% CPU.${NC}"
  elif [ -n "$TOP_CPU" ] && [ "$TOP_CPU" -ge 50 ]; then
    DIAG_CPU="${WHITE}[!] WARNING:${GRAY} '$TOP_NAME' (PID: $TOP_PID) is using ${TOP_CPU}% CPU.${NC}"
  else
    DIAG_CPU="${WHITE}[✓] OK:${GRAY} CPU load and running processes are normal.${NC}"
  fi

  # Battery Health Diagnostic
  BATT_INFO=$(pmset -g batt 2>/dev/null)
  if echo "$BATT_INFO" | grep -q "InternalBattery"; then
    BATT_PERCENT=$(echo "$BATT_INFO" | grep -E -o '[0-9]+%' | tr -d '%')
    BATT_STATE=$(echo "$BATT_INFO" | grep -E -o '[0-9]+%.*' | awk -F';' '{print $2}' | xargs)
    
    if echo "$BATT_INFO" | grep -qi "Service Battery\|Replace Soon"; then
      DIAG_BATT="${WHITE}[✕] CRITICAL:${GRAY} Battery needs servicing! (${BATT_STATE})${NC}"
    elif [ -n "$BATT_PERCENT" ] && [ "$BATT_PERCENT" -le 15 ] && echo "$BATT_STATE" | grep -qv "charging\|AC attached"; then
      DIAG_BATT="${WHITE}[✕] CRITICAL:${GRAY} Only ${BATT_PERCENT}% battery left (charger not connected).${NC}"
    else
      DIAG_BATT="${WHITE}[✓] OK:${GRAY} Battery is normal (${BATT_PERCENT}% - ${BATT_STATE:-discharging}).${NC}"
    fi
  else
    DIAG_BATT="${WHITE}[i] INFO:${GRAY} Desktop device (no battery detected).${NC}"
  fi

  # Extract Detailed CPU Stats
  CPU_RAW=$(top -l 1 | grep -E "^CPU")
  CPU_USER=$(echo "$CPU_RAW" | awk -F'user,' '{print $1}' | awk '{print $NF}')
  CPU_SYS=$(echo "$CPU_RAW" | awk -F'sys,' '{print $1}' | awk '{print $NF}')
  CPU_IDLE=$(echo "$CPU_RAW" | awk -F'idle' '{print $1}' | awk '{print $NF}')

  # Numeric variants of the CPU shares for the pie chart (-1 when unavailable)
  CPU_USER_NUM=$(echo "$CPU_USER" | tr -d '%')
  CPU_SYS_NUM=$(echo "$CPU_SYS" | tr -d '%')
  CPU_USER_NUM=${CPU_USER_NUM:--1}
  CPU_SYS_NUM=${CPU_SYS_NUM:--1}

  # Extract Uptime
  UPTIME_VAL=$(uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1, $2}')

  # =========================================================
  # 2. PRINT THE WHOLE DOCUMENT IN ONE BATCH (FLICKER-FREE)
  # =========================================================

  # Reset the cursor position to the top of the screen
  printf "\033[H\033[J"

  if [ "$ONCE_MODE" = true ]; then
    echo -e "${BOLD}┌──────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}│   MacOS System Monitor & Diagnostics    │${NC}"
    echo -e "${BOLD}└──────────────────────────────────────────┘${NC}"
  else
    echo -e "${BOLD}┌──────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}│   MacOS Live Monitor & Diagnostics  [${SPINNER}] │${NC}"
    echo -e "${BOLD}└──────────────────────────────────────────┘${NC}"
  fi

  ### ❖ SYSTEM HEALTH DIAGNOSTICS
  echo -e "\n${BOLD}❖ System Diagnostics & Health Check${NC}"
  echo -e "${DIM}──────────────────────────────────────────${NC}"
  echo -e "$DIAG_DISK"
  [ -n "$DIAG_SMART" ] && echo -e "$DIAG_SMART"
  echo -e "$DIAG_MEM"
  echo -e "$DIAG_CPU"
  echo -e "$DIAG_BATT"

  ### ❖ DETAILED RESOURCE METRICS (WITH SPARK STAR ANIMATION)
  echo -e "\n${BOLD}❖ Detailed Resource Metrics${NC}"
  echo -e "${DIM}──────────────────────────────────────────${NC}"

  echo ""
  render_pies "$CPU_USER_NUM" "$CPU_SYS_NUM" "$MEM_USED_PCT" "${DISK_USAGE:--1}"

  echo -e "\n  ${GRAY}${MEM_PRESSURE}${NC}"
  echo -e "  ${GRAY}Storage (/): Used ${DISK_USED} / Total ${DISK_TOTAL} | Free ${DISK_FREE}${NC}"

  if echo "$BATT_INFO" | grep -q "InternalBattery"; then
    echo -e "\n${WHITE}◇ Battery Status${NC}"
    echo -e "  Level: ${WHITE}${SPARK} ${BATT_PERCENT}%${NC} (${GRAY}${BATT_STATE:-discharging}${NC})"
  fi

  echo -e "\n${WHITE}◇ System Uptime${NC}"
  echo -e "  ${GRAY}Uptime:${NC} ${WHITE}${UPTIME_VAL}${NC}"

  echo -e "\n${DIM}──────────────────────────────────────────${NC}"
  if [ "$ONCE_MODE" = false ]; then
    echo -e "${DIM}  [ Press Ctrl+C to exit | Live ${SPINNER} | Auto-refreshing every ${INTERVAL}s ]${NC}"
  fi
}

# Main Execution Loop
if [ "$ONCE_MODE" = true ]; then
  render_dashboard "✓" "✦"
else
  while true; do
    SPINNER_CHAR="${SPINNER_FRAMES[$FRAME_INDEX]}"
    SPARK_CHAR="${SPARK_FRAMES[$FRAME_INDEX % ${#SPARK_FRAMES[@]}]}"
    FRAME_INDEX=$(( (FRAME_INDEX + 1) % ${#SPINNER_FRAMES[@]} ))

    render_dashboard "$SPINNER_CHAR" "$SPARK_CHAR"
    sleep "$INTERVAL"
  done
fi