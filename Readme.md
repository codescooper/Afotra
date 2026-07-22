# AFOTRA - Awema Focus Tracker

[![CI](https://github.com/codescooper/Afotra/actions/workflows/ci.yml/badge.svg)](https://github.com/codescooper/Afotra/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Version:** 2.1  
**Author/Maintainer:** CodeScooper  
**License:** MIT  

---

## Table of Contents

1. [Description](#description)
2. [Project Objectives](#project-objectives)
3. [Features](#features)
4. [Architecture](#architecture)
5. [System Requirements](#system-requirements)
6. [Installation](#installation)
7. [Quick Start](#quick-start)
8. [Configuration](#configuration)
9. [Usage](#usage)
10. [CSV Format](#csv-format)
11. [Troubleshooting](#troubleshooting)
12. [FAQ](#faq)
13. [Limitations](#limitations)

---

## Description

**AFOTRA - Awema Focus Tracker** is a local Windows application built in PowerShell with a WPF dashboard. It monitors your PC activity in real time, classifies active windows automatically, manages work tasks/sessions, and generates detailed reports to help you understand your productivity patterns.

The interface is a **dark, honey-yellow theme** with a **bee mascot** 🐝: dark `#222222`
surfaces, `#FFC107` accents, metric tiles on the dashboard, and the floating assistant rendered
as a small animated bee whose colour/size communicate your focus state at a glance.

The application runs entirely locally on your machine with no external dependencies beyond what's already installed on Windows. Your data remains private and never leaves your computer.

---

## Project Objectives

- Monitor real-time PC usage with minimal overhead
- Automatically classify activities into customizable categories
- Store daily activity logs for analysis and archival
- Generate productivity reports with focus scores
- Provide an intuitive graphical interface for management
- Support easy customization without code changes
- Help identify productivity patterns and areas for improvement

---

## Features

### Core Capabilities
- ✅ **Real-time Tracking**: Detects active application and window title every 10 seconds (configurable)
- ✅ **Smart Classification**: Automatically categorizes activities based on process name or window title
- ✅ **Daily CSV Logs**: Stores detailed activity history with timestamps and metadata
- ✅ **Statistical Reports**: Generates focus scores, category breakdowns, and context switch metrics
- ✅ **WPF Dashboard**: dark themed interface for tracking, tasks, reports, and the assistant overlay
- ✅ **Customizable Rules**: Add/modify classification rules without editing code
- ✅ **Unknown Tracking**: Identifies and tracks unclassified activities for later review

### Dashboard Interface
- **Dashboard Tab**: focus metrics, activity chart, task summary, and report generation
- **Live Tracking Tab**: start/stop tracking and monitor current activity
- **Unknown / Rules Tabs**: categorize unknown apps and manage classification rules
- **Taches Tab**: task manager, sessions, Pomodoro controls, and task/session reports

### Logging & Reports
- Precise timestamps with process ID and window title
- UTF-8 encoded CSV files for international character support
- JSON summary reports with focus metrics
- Daily breakdown by category
- Append-only logging prevents data loss

---

## Architecture

```
Dashboard (dashboard-wpf.ps1)
    |
Core Modules (./modules/)
    - Tracker.Core.psm1       - Window detection & activity logging
    - Rules.Core.psm1         - Rule management & classification
    - Report.Core.psm1        - Daily report generation & analytics
    - Tasks.Core.psm1         - Task storage and task queries
    - Session.Core.psm1       - Timed sessions and Pomodoro state machine
    - SessionReport.Core.psm1 - Session/task report aggregation
    - Orb.Core.psm1           - Assistant visual language and focus guard rules
    |
File System
    - logs/activity-YYYY-MM-DD.csv - Daily activity records
    - logs/reports/summary-*.json  - Statistical breakdowns
    - logs/reports/task-*.json/.md - Per-task session reports
    - tasks.json                   - Local personal task store (gitignored)
```

---

## System Requirements

### Minimum
- **OS**: Windows 10 (Build 1909+) or Windows Server 2016+
- **PowerShell**: 5.0 or later (included with Windows 10)
- **.NET Framework**: 4.5+ (included with Windows)
- **RAM**: 50 MB
- **Disk**: ~1 MB per day of tracking

### Recommended
- Windows 10 22H2 or later
- SSD storage for logs
- 8+ GB RAM

---

## Installation

### Step 1: Download & Extract
```powershell
# Clone or download the AFOTRA project to your computer
# Place in: C:\AFOTRA - Awema Focus Tracker

# Verify installation
cd "C:\AFOTRA - Awema Focus Tracker"
dir
```

### Step 2: Configure PowerShell
As Administrator:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Step 3: Test Installation
```powershell
cd "C:\AFOTRA - Awema Focus Tracker"
.\tracker.ps1 -Check
# Output: "✓ Tracker is running" or "✗ Tracker is not running"
```

---

## Quick Start

### Launch Dashboard
```powershell
cd "C:\AFOTRA - Awema Focus Tracker"
.\dashboard-wpf.ps1
```

Or double-click `run-dashboard-wpf.bat` in Windows Explorer.

### Start Tracking
1. Click the "Start Tracking" button in the Live Tracking tab
2. Status changes to "Status: Running"
3. Activity logs to `logs/activity-2026-03-30.csv`

### Generate Report
1. After tracking for a while, click "📊 Generate Report"
2. Report saved to `logs/reports/summary-2026-03-30.json`
3. Shows focus score and time breakdown

---

## Configuration

### config.json

```json
{
  "sampleIntervalSeconds": 10,
  "focusMinPerDay": 480,
  "maxDistractionMinPerDay": 120,
  "logFolder": "logs",
  "enableNotifications": true
}
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `sampleIntervalSeconds` | 10 | Log activity every N seconds |
| `focusMinPerDay` | 480 | Daily focus goal in minutes (8 hours) |
| `maxDistractionMinPerDay` | 120 | Max distraction time in minutes (2 hours) |
| `logFolder` | logs | Folder for activity logs (relative path) |
| `enableNotifications` | true | Show desktop notifications |

### rules.json

```json
{
  "categories": ["travail", "etude", "communication", "distraction", "inconnu"],
  "processRules": [
    { "process": "Code", "category": "travail" },
    { "process": "chrome", "category": "distraction" }
  ],
  "titleRules": [
    { "contains": "YouTube", "category": "distraction" },
    { "contains": "GitHub", "category": "travail" }
  ]
}
```

**How it works:**
1. Checks all process rules (e.g., "Code.exe" → "travail")
2. If no match, checks title rules (e.g., window contains "GitHub")
3. If no match, assigns "inconnu" (unknown)

**Add Custom Rule Example:**
```json
{
  "processRules": [
    { "process": "Slack", "category": "communication" }
  ]
}
```

---

## Usage

### Running the Tracker

**From Dashboard:**
1. Launch `dashboard-wpf.ps1`
2. Click "Start Tracking"
3. Status shows the active process and category in the sidebar/overlay.

**Standalone (Headless):**
```powershell
.\tracker.ps1                    # Start tracking
.\tracker.ps1 -Check             # Check if running
.\tracker.ps1 -Stop              # Stop tracking
```

### Generating Reports

**From Dashboard:**
Click "📊 Generate Report" button

**From Command Line:**
```powershell
.\daily-report.ps1
# Output: Creates logs/reports/summary-2026-03-30.json
```

### Opening Logs

**In Dashboard:**
Click "📁 Open Logs" to browse logs in Windows Explorer

**From Command Line:**
```powershell
explorer "C:\AFOTRA - Awema Focus Tracker\logs"
```

---

## CSV Format

Each line in `activity-YYYY-MM-DD.csv`:

```
Timestamp,Date,Time,ProcessName,ProcessId,WindowTitle,Category,SampleSeconds,UserName,MachineName
2026-03-30 14:23:45,2026-03-30,14:23:45,Code,5432,README.md - Code,travail,10,User,DESKTOP-ABC
```

| Column | Example | Notes |
|--------|---------|-------|
| Timestamp | 2026-03-30 14:23:45 | Full datetime |
| Date | 2026-03-30 | YYYY-MM-DD format |
| Time | 14:23:45 | HH:MM:SS format |
| ProcessName | Code | Executable name |
| ProcessId | 5432 | Windows PID |
| WindowTitle | README.md - Code | Active window title |
| Category | travail | Assigned category |
| SampleSeconds | 10 | Sample interval |
| UserName | User | Windows username |
| MachineName | DESKTOP-ABC | Computer name |

---

## Troubleshooting

### "Cannot find path" looking for artifacts
```
Cannot find path 'C:\AFOTRA - Awema Focus Tracker\logs'
```
**Fix:** Create manually
```powershell
New-Item -ItemType Directory -Path "C:\AFOTRA - Awema Focus Tracker\logs"
```

### "The PowerShell script cannot be loaded"
```
The execution of scripts is disabled on this system
```
**Fix:** Set execution policy
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Tracker not detecting application
**Cause:** Process name doesn't match any rule  
**Solution:** Add rule to `rules.json`
```json
{
  "titleRules": [
    { "contains": "MyApp Window Title", "category": "travail" }
  ]
}
```

### High CPU or Disk Usage
**Solution:** Increase sample interval in `config.json`
```json
{
  "sampleIntervalSeconds": 30
}
```

---

## FAQ

**Q: Is my data sent to the internet?**  
A: No. 100% local. No internet connection required.

**Q: Can I modify rules while tracker is running?**  
A: Yes. Changes take effect on the next sample interval.

**Q: How much storage needed for one year?**  
A: ~365 MB with default settings.

**Q: Can I run this on multiple computers?**  
A: Yes. Each needs its own installation and logs folder.

**Q: How do I export data to Excel?**  
A: The CSV files in `logs/` open directly in Excel.

**Q: Can I track remote desktop sessions?**  
A: Yes, AFOTRA will track the window active in your RDP connection.

---

## Tasks (Tâches)

AFOTRA includes an integrated task manager, reachable from the **Tâches** tab.

### Manage tasks
- **Ajouter / Éditer**: opens a form covering every field (titre, description, catégorie,
  projet, contact, priorité, statut, échéance, rappel du soir, bloquée par, notes).
- **Terminer**: marks the task done (records the completion time). **Archiver**: hides it
  from the active list.
- **Filters & search**: quick filters (À faire, En cours, Dues aujourd'hui, En retard) and a
  text search box. Rows are colour-coded — **red** = overdue, **orange** = due today,
  **gray** = done/archived.

### Where tasks are stored
`tasks.json` at the project root — a plain JSON array, written atomically to avoid
corruption. It stays on your machine (gitignored) because it can contain personal contacts.
On first launch the app seeds a starter set; run `.\seed-tasks.ps1` to (re)create it.

### Evening reminders
Tasks with a **Rappel du soir** trigger a Windows notification that evening, and again each
evening until the task is done. If the [BurntToast](https://github.com/Windos/BurntToast)
module is installed (`Install-Module BurntToast -Scope CurrentUser`) you get native toasts;
otherwise AFOTRA falls back to a system-tray balloon (no extra dependency).

To get reminders **even when the dashboard is closed**, schedule the silent notifier at 20:00:

```powershell
schtasks /Create /SC DAILY /ST 20:00 /TN "AFOTRA Rappel du soir" /F `
  /TR "powershell -NoProfile -WindowStyle Hidden -File \"C:\path\to\Afotra\afotra-notify.ps1\""
```

(Replace the path with your install folder. Remove with
`schtasks /Delete /TN "AFOTRA Rappel du soir" /F`.)

### In reports
Daily reports (`daily-report.ps1` or the **Generate Report** button) include a `Tasks`
section — counts of à faire / en cours / terminées aujourd'hui / en retard, plus minutes
worked today and how many tasks ran over their estimate — and the Dashboard tab shows the
main figures in a card.

### Work sessions (Pomodoro)

Select a task, set an **estimate** (minutes), and hit **Démarrer** to start a timed session
from the **Tâches** tab:

- The big timer **counts down** from your estimate, then turns **red** and counts the
  **overrun** — that overrun is your efficiency signal.
- **Pause / Reprendre** at will, and take **Pomodoro breaks** (suggested automatically after
  each work interval — 25/5, long break every 4 by default). Two clocks are recorded: *work*
  time (excludes pauses) and *global* time (wall-clock), so you can see the breaks you took.
- **Terminer la tâche** ends the session **and** marks the task done; **Arrêter** just saves
  the time. The running timer is also shown in the floating **overlay** so you can keep it in
  view while working in other apps.
- Time is saved onto the task (`Estimé` and `Passé` columns), and daily reports summarise the
  minutes worked and the number of tasks over budget.

### Session & task reports

AFOTRA is meant to be used **through a task, broken into sessions** — so it reports at both levels:

- **End of a session** — closing a session (*Terminer la tâche* or *Arrêter*) pops a **bilan**:
  work / global / pause time, pomodoros, and how far the task has progressed against its estimate.
  One click opens the full task report.
- **Task report** — the **Rapport** button (Tâches tab) shows the **bilan of every session** that
  made up the task: totals, pause ratio, estimate-vs-actual efficiency, pomodoros, digressions,
  and a **chronological timeline** of the sessions. **Exporter** writes it to `logs/reports/` as a
  structured `.json` and a readable `.md`.
- **Daily report** — `daily-report.ps1` (or *Generate Report*) adds a `TasksDetail` section to
  `summary-<date>.json` with the per-task session bilan.

Pomodoro cadence is configurable in `config.json`:

```json
"pomodoro": { "workMinutes": 25, "shortBreakMinutes": 5, "longBreakMinutes": 15, "longBreakEvery": 4, "autoStartNext": false }
```

### The assistant orb

The floating overlay is a **living sphere** that represents the assistant and tells you your
state **at a glance** — no need to read anything:

- **Colour & motion** = mood: calm **teal** when idle, gentle **emerald** while focused, slow
  **violet** on a break/pause, faster **amber-red** when you're over your estimate.
- **Hover the sphere** to reveal the full panel (current app, category, session timer, focus score).
- **Drag** it anywhere; it stays on top and out of the way — until it needs you.

**Focus guard.** While a session is running, if you switch to an app that isn't part of the
task, the sphere **grows, reddens and moves into your way**, and asks *"is this related to the
task?"*:

- **Oui** — the app joins the task's tool list and the sphere calms down (it won't ask again for it).
- **Non** — it does **not** calm down. The longer you stay off-task, and each time you say *Non*,
  the sphere grows **bigger, redder and faster** — and after two refusals it starts sounding an
  alarm. It keeps harassing until you actually go back to a task-related app.
- **Ignorer** — snooze it for the rest of the session (the escape hatch).

Only **returning to a task app** calms it. This way the assistant builds the **list of what each
task needs** and pushes back on everything else, so you re-center the moment you drift. It never
closes or blocks your windows — the pressure is visual (and audible when you keep refusing).

Configurable in `config.json`:

```json
"assistant": { "orbEnabled": true, "focusGuard": true, "guardSound": false, "orbMinSize": 90, "orbMaxSize": 420 }
```

---

## Limitations

### Version 1.0
- Only tracks the foreground window (primary monitor only)
- No idle/away detection
- No historical day-to-day comparison
- No custom report scheduling

### By Design
- Windows only (PowerShell not available on macOS/Linux)
- Requires PowerShell 5.0+ for security
- No cloud sync (privacy-first design)

---

## Support & Maintenance

### Updating
```powershell
# Backup existing logs
Copy-Item "logs" "logs.backup"

# Keep config.json and rules.json
# Replace other files with new versions

# Test
.\tracker.ps1 -Check
```

### Reporting Issues
Check the Troubleshooting section above, then review log files if needed.

---

## Author & Credits

**Maintained by:** CodeScooper  
**Project:** AFOTRA - Awema Focus Tracker  
**Version:** 2.1  
**Last Updated:** July 12, 2026

Built with PowerShell, WPF, and small testable core modules for local-first focus tracking.

---

For more information or to contribute: [GitHub](https://github.com/CodeScooper/AFOTRA)


## Auteur
Maintained by CodeScooper.

## License
This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.
