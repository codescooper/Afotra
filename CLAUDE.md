# AFOTRA - Awema Focus Tracker

Local Windows focus tracker (PowerShell). Samples the foreground window every N
seconds, classifies it via `rules.json`, logs to `logs/activity-<date>.csv`, and
reports to `logs/reports/summary-<date>.json`.

## Running the tests

- `.\Run-Tests.ps1` — core verification suite (17 cases)
- `.\Run-Full-Tests.ps1` — full use-case suite (35 cases); writes `TEST_REPORT.md`

Both exit 0 on success, 1 on any failure. Invoke directly (see gotchas).

Add `-SkipLive` to skip tests needing an interactive desktop (foreground capture, WPF window, live logging). GitHub Actions CI (`.github/workflows/ci.yml`) runs both suites with `-SkipLive` on a `windows-latest` runner.

## Running the app

- `.\tracker.ps1` / `-Check` / `-Stop` — standalone tracker (CLI)
- `.\daily-report.ps1` — generate today's JSON report
- `.\dashboard-wpf.ps1` — WPF dashboard
- `.\seed-tasks.ps1` — create the starter tasks in `tasks.json` (idempotent)
- `.\afotra-notify.ps1` — fire due evening reminders once, then exit (for Task Scheduler)

## Tasks module

Integrated task manager (**Tâches** tab in the dashboard). Data + logic live in
`modules\Tasks.Core.psm1` (UI-free, fully unit-tested — see `Run-Full-Tests.ps1` section H);
notifications in `modules\Notify.Core.psm1`.

- **Storage**: `<repo>\tasks.json` (a JSON array, French field names per the data model),
  written **atomically** (temp file + `File.Replace`). Gitignored — it holds personal
  contacts. Override the path with `$env:AFOTRA_TASK_STORE` (used by the tests).
  Corrupt JSON is preserved as a timestamped `.bak` and treated as empty (never crashes).
- **Seeded on first launch**: `Initialize-TaskSeed` runs from `Initialize-UI`; no-op if
  `tasks.json` already has data. Run `.\seed-tasks.ps1` to seed manually.
- **Add / edit a task**: Tâches tab → *Ajouter* / *Éditer* (WinForms modal covering every
  field). *Terminer* sets `Statut=Termine` + `TermineLe`; *Archiver* sets `Statut=Archive`.
  Quick filters (À faire / En cours / Dues aujourd'hui / En retard) + text search. Rows are
  colour-coded: red = overdue, orange = due today, gray = done/archived (échéance-based).
- **Evening reminder**: a 60 s `DispatcherTimer` fires `Get-DueReminders` (a task with
  `RappelSoir <= now`, not done/archived, not already notified today). It **recurs daily**
  via the internal `NotifieLe` guard (last notified date), so a reminder returns every
  evening until the task is completed. Uses **BurntToast** if installed
  (`Install-Module BurntToast -Scope CurrentUser`), else a tray balloon (`NotifyIcon`).
- **Reminders when the app is closed** — register `afotra-notify.ps1` with Task Scheduler:
  ```
  schtasks /Create /SC DAILY /ST 20:00 /TN "AFOTRA Rappel du soir" /F ^
    /TR "powershell -NoProfile -WindowStyle Hidden -File \"C:\path\to\Afotra\afotra-notify.ps1\""
  ```
  Remove with `schtasks /Delete /TN "AFOTRA Rappel du soir" /F`.
- **Reports**: `daily-report.ps1` and the dashboard's *Generate Report* button add a `Tasks`
  section (à faire / en cours / terminées aujourd'hui / en retard + `TempsTravailJourMin` +
  `EnDepassement`) to `summary-<date>.json`, and the Dashboard tab shows the counts in a card.

## Work sessions & Pomodoro

Timed work sessions on a task, with a Pomodoro break cadence and estimate-vs-actual efficiency.
Pure state machine in `modules\Session.Core.psm1` (no UI, no real clock — every function takes
`-Now`, so it's fully unit-tested; see `Run-Full-Tests.ps1` section I). The dashboard drives it
from a 1 s `DispatcherTimer`; a session's accumulated time is persisted onto the task.

- **Two clocks** are tracked and persisted per session: `TravailSecondes` (active work, excludes
  pauses/breaks), `GlobalSecondes` (wall-clock start→end), `PauseSecondes` = global − work. Totals
  accumulate into the task's `TempsTravailSecondes` / `TempsGlobalSecondes`; each session is logged
  in the task's `Sessions[]`. `Add-TaskSession` is tolerant of tasks created before this feature.
- **Countdown → overrun**: the big timer counts *down* from the estimate (`EstimeMinutes`), then
  flips **red** and counts the overrun (`Get-CountdownState`). No estimate → counts up (no target).
- **Pomodoro** is independent of the estimate and configurable in `config.json` → `pomodoro`
  (`workMinutes`, `shortBreakMinutes`, `longBreakMinutes`, `longBreakEvery`, `autoStartNext`, `sound`).
  After each `workMinutes` of *work*, a break is suggested (notification); long break every
  `longBreakEvery`. During a break/pause the **work** clock freezes but the **global** clock keeps
  running — so you can see whether breaks were taken.
- **Cycle signals** (in the 1 s session tick): *work→break* notifies + soft two-note **chime**;
  *break end* notifies and, if `autoStartNext=false`, drops to **AwaitingResume** — a distinct
  state where the panel shows **Reprendre** and the orb blooms **green/Resume** (`Get-OrbMood
  -AwaitingResume` → `Resume`) to call you back; *resume* (auto or the **Reprendre** button)
  notifies "Focus repris" + a rising **chime**. Chimes are non-blocking (`Start-Chime`, background
  thread) and gated by `pomodoro.sound` (default true) — separate from the guard alarm.
- **Panel** (top of Tâches tab): Démarrer / Pause / Reprendre / Pause Pomodoro / Terminer la tâche
  / Arrêter, plus the estimate input. *Terminer la tâche* persists the session **and** completes
  the task (this is "the session ends when the task is done"); *Arrêter* persists without completing.
  Completing a task from the list also stops+persists any session running on it. The live timer is
  mirrored in the always-on-top **overlay** (`OvSessionText`).
- **Efficiency**: `Get-TaskEfficiency` → `{ EstimeMin, TravailMin, EcartMin, Ratio }` (ratio > 1 =
  under budget). The Tâches grid shows **Estimé** and **Passé** columns.

## Assistant orb & focus guard

The overlay is now a **living sphere** that embodies the assistant. Its **colour, glow,
size and motion** communicate state at a glance; **hovering** it reveals the detail panel
(process/category/duration/focus/session — the old overlay content, now in a Popup).

- **Visual language** is a pure mapping in `modules\Orb.Core.psm1` (unit-tested, section J):
  `Get-OrbMood` (**Idle** teal / **Focus** emerald / **Break**·Paused violet / **Overrun** amber-red
  bigger+faster / **Ask** red, grows toward screen centre) → `Get-OrbVisual` (`Core/Edge/Glow/
  GlowRadius/SizePx/PulseAmp/PulsePeriodMs/WobbleAmp/MoveToCenter`). The dashboard's
  `OrbAnimTimer` (50 ms) interpolates size/colour and applies pulse + gelatinous wobble +
  glow breathing; it is the **sole owner** of the overlay window rect (dragging adopts a new
  home). No Storyboards — plain property updates per tick.
- **Focus guard** (only while a session is **Running**): each 800 ms overlay tick samples the
  foreground process (`Get-ActiveWindowInfo`). If it's not AFOTRA/idle and not on the task's
  **allow-list** (`OutilsTache`) nor session-snoozed, the orb turns **Ask** — grows, reddens,
  recentres — and the `OrbAskPopup` asks *« … en rapport avec la tâche ? »*:
  - **Oui** → `Add-TaskTool` (process joins the task's allow-list, persisted) → orb calms.
  - **Non** → `Add-TaskDigression` (counter) + a "recentre-toi" nudge + a 12 s cooldown; the
    process stays off-list so it re-asks if you linger.
  - **Ignorer** → in-memory snooze for the rest of the session (no lockout; not persisted).
  The guard **never touches the offending window** (visual pressure only).
- **Config** (`config.json` → `assistant`): `orbEnabled`, `focusGuard`, `guardSound`
  (visual-only by default; `true` also fires the existing `Console.Beep` alarm), `orbMinSize`,
  `orbMaxSize`. Per-task fields: `OutilsTache` (allow-list) + `DigressionsCount`.
- The old 5-min distraction-streak shake still runs **outside** a session (the guard supersedes
  it during one); it no longer moves the window (the orb conveys agitation instead).

## Behaviour notes

- `config.json` keys: `idleThresholdSeconds` (AFK threshold; idle/locked samples logged as `inactif`), `focusCategories` (categories counted as focus, default `["travail"]`).
- Focus score = focus / **active** time (total − `inactif`). The `inactif` category is excluded from the denominator.
- `tracker.ps1` writes a PID file `tracker.lock` (gitignored); `-Check`/`-Stop` rely on it, not on window titles. Force-killing the process leaves a stale lock (its dead PID makes `Test-TrackerRunning` return false, so it's harmless).

## Gotchas (PowerShell 5.1 / this environment)

- Don't use `-ExecutionPolicy Bypass` — blocked by the permission classifier. Run scripts directly (`.\script.ps1`).
- Wrap `Where-Object` results in `@()` before `.Count` — a single `PSCustomObject`'s `.Count` returns blank.
- Never name a function `Group` — it's the alias for `Group-Object`, and aliases shadow functions.
- Keep `.ps1` files ASCII-only (or save as UTF-8 with BOM) — no-BOM files are read as Windows-1252, corrupting emoji/accents.
- Tests have side effects: the dashboard test briefly opens a real WPF window; the tracker test appends to today's real `logs/activity-<date>.csv`.
