# MacOS Live Monitor & Diagnostics

A Bash-based macOS system monitoring dashboard that runs directly in your terminal.
It shows a **health check** (with OK / WARNING / CRITICAL statuses) and **detailed resource
metrics** on a single screen, using a minimalist monochrome style with a live spinner animation.

All logic lives in one file: [monitor.sh](monitor.sh). No external dependencies.

---

## Features

### 1. System Diagnostics & Health Check

Each component is labelled `[✓] OK`, `[!] WARNING`, `[✕] CRITICAL`, or `[i] INFO`.

| Component | Data source | Thresholds |
|---|---|---|
| **Disk Usage** | `df -h /` | `≥ 85%` → CRITICAL, `≥ 75%` → WARNING |
| **Disk S.M.A.R.T** | `diskutil info /` | anything other than `Verified` → CRITICAL (possible SSD failure). The line is hidden when the status cannot be read |
| **Memory & Swap** | `sysctl vm.swapusage` + `memory_pressure` | swap `> 2048 MB` → WARNING, or memory pressure reporting `warn`/`critical` → WARNING |
| **CPU / Runaway Process** | `ps -eo %cpu,pid,comm -r` | top process at `≥ 80%` → CRITICAL, `≥ 50%` → WARNING (shows process name + PID) |
| **Battery Health** | `pmset -g batt` | `Service Battery` / `Replace Soon` → CRITICAL; battery `≤ 15%` while unplugged → CRITICAL; desktop without a battery → INFO |

### 2. Detailed Resource Metrics

Three **pie charts** rendered side by side directly in the terminal, drawn with half-block
characters (`▀` / `▄`) so each pie is a 12×12 pixel circle. The three columns plus their gaps
measure exactly 42 columns, lining up with the dividers used elsewhere in the dashboard.

| Pie | Slices | Source |
|---|---|---|
| **CPU Usage** | User / Sys / Idle | `top -l 1` |
| **Memory** | Used / Free | `memory_pressure` free percentage |
| **Storage** | Used / Free | `df -h /` |

**Colour rule** — a pie is **green** while healthy and turns **red** once utilisation reaches
**90%** (`User + Sys` for CPU, `Used` for memory and storage). The second slice of the CPU pie
(`Sys`) uses a lighter step of the same hue, and the unused share always stays a recessive grey.
The threshold lives in the `ALERT_AT` variable near the top of the script — change it in one place
to move the alert point.

Every pie carries a legend with the numeric percentage and a headline value marked `[✓]` or `[✕]`,
so the alert state is never signalled by colour alone (readable for colourblind users, on
monochrome terminals, and when piped through `sed`).

Other metrics in this section:

- **Memory Pressure** — condensed `memory_pressure` output, printed below the pies
- **Storage detail** — used, total, and free space in human-readable units
- **Battery Status** — charge level and state (charging / discharging / AC attached); this section
  is hidden automatically on machines without an internal battery
- **System Uptime** — how long the system has been running

> Battery is deliberately **not** drawn as a pie and is excluded from the 90% rule: a battery at
> 95% is a healthy state, not an alert, so the same threshold would invert the meaning.

### 3. Display Quality

- **Flicker-free** — every metric is collected first, then the screen is redrawn once per cycle,
  so there is no flashing or tearing
- **Live spinner & spark star** — `⠋⠙⠹…` and `✦✧✶✵` animations signal that the dashboard is alive
- **Cursor hiding** — the cursor is hidden (`tput civis`) during live mode for a clean view
- **Graceful exit** — a `trap` on `Ctrl+C` / `SIGTERM` restores the cursor (`tput cnorm`) and prints
  a closing message, so the terminal is never left in a broken state

---

## Requirements

- macOS (the script uses `diskutil`, `pmset`, `memory_pressure`, and `sysctl vm.swapusage`)
- Bash and `awk` (both ship with macOS by default)
- A terminal that supports **256 colours**, ANSI escape codes, and Unicode block characters —
  Terminal.app, iTerm2, Ghostty, and VS Code's terminal all qualify

---

## Usage

Make the script executable once:

```bash
chmod +x monitor.sh
```

### Live mode (default)

Auto-refreshes every **1 second**:

```bash
./monitor.sh
```

### Live mode with a custom interval

The first argument is the refresh interval in seconds:

```bash
./monitor.sh 5     # refresh every 5 seconds
./monitor.sh 0.5   # refresh twice per second
```

### Single-run mode (snapshot)

Print the dashboard once and exit — useful for logging or calling from another script:

```bash
./monitor.sh --once
# or
./monitor.sh -1
```

### Exiting live mode

Press `Ctrl+C`. The terminal cursor is restored automatically.

### Changing the alert threshold

Edit `ALERT_AT` near the top of [monitor.sh](monitor.sh) — it controls the utilisation percentage
at which a pie flips from green to red:

```bash
ALERT_AT=90     # default: red at 90% and above
```

---

## Sample Output

```
┌──────────────────────────────────────────┐
│   MacOS Live Monitor & Diagnostics  [⠹] │
└──────────────────────────────────────────┘

❖ System Diagnostics & Health Check
──────────────────────────────────────────
[✓] OK: Disk capacity is healthy (26% used).
[✓] OK: SSD/Disk S.M.A.R.T Status Verified.
[!] WARNING: High swap usage (2567 MB used).
[!] WARNING: 'Antigravity IDE Helper (Renderer)' (PID: 29231) is using 71% CPU.
[✓] OK: Battery is normal (69% - charging).

❖ Detailed Resource Metrics
──────────────────────────────────────────

◇ CPU Usage    ◇ Memory       ◇ Storage
  ▄▄▀▀▀▀▄▄       ▄▄▀▀▀▀▄▄       ▄▄▀▀▀▀▄▄
 ▀▀▀▀▀▀▀▀▀▀     ▀▀▀▀▀▀▀▀▀▀     ▀▀▀▀▀▀▀▀▀▀
▀▀▀▀▀▀▀▀▀▀▀▀   ▀▀▀▀▀▀▀▀▀▀▀▀   ▀▀▀▀▀▀▀▀▀▀▀▀
▀▀▀▀▀▀▀▀▀▀▀▀   ▀▀▀▀▀▀▀▀▀▀▀▀   ▀▀▀▀▀▀▀▀▀▀▀▀
 ▀▀▀▀▀▀▀▀▀▀     ▀▀▀▀▀▀▀▀▀▀     ▀▀▀▀▀▀▀▀▀▀
  ▀▀▀▀▀▀▀▀       ▀▀▀▀▀▀▀▀       ▀▀▀▀▀▀▀▀
● User 12.8%   ● Used 65.0%   ● Used 26.0%
● Sys  18.7%   ○ Free 35.0%   ○ Free 74.0%
○ Idle 68.5%
[✓]   31.5%    [✓]   65.0%    [✓]   26.0%

  System-wide memory free percentage: 35%
  Storage (/): Used 12Gi / Total 228Gi | Free 35Gi

◇ Battery Status
  Level: ✦ 69% (charging)

◇ System Uptime
  Uptime:  4:18  6 users

──────────────────────────────────────────
  [ Press Ctrl+C to exit | Live ⠹ | Auto-refreshing every 1s ]
```

The pie slices above are green in a real terminal; the colour is lost here because the sample was
captured with ANSI codes stripped. Once a pie crosses `ALERT_AT` its slices turn red and its
headline marker changes from `[✓]` to `[✕]`.

In `--once` mode the title becomes `MacOS System Monitor & Diagnostics` (no spinner) and the
auto-refresh footer line is not printed.

---

## Notes

- The interval is read from the first argument, so `--once` / `-1` cannot be combined with an
  interval value. Both flags disable the loop entirely, so the interval is never used there.
- Very small intervals (e.g. `0.2`) call `top -l 1` and `diskutil` very frequently, which adds CPU
  load of its own. An interval of `1`–`5` seconds is a reasonable compromise.
- `diskutil` and `pmset` calls are wrapped with `2>/dev/null`, so the dashboard still renders even
  if those commands fail or are unavailable.
- The **System Uptime** line also includes the number of logged-in users (e.g. `3:55  6 users`)
  because it takes the first two fields of the `uptime` output.
