# AFOTRA - Awema Focus Tracker

Local Windows focus tracker (PowerShell). Samples the foreground window every N
seconds, classifies it via `rules.json`, logs to `logs/activity-<date>.csv`, and
reports to `logs/reports/summary-<date>.json`.

## Running the tests

- `.\Run-Tests.ps1` — core verification suite (17 cases)
- `.\Run-Full-Tests.ps1` — full use-case suite (35 cases); writes `TEST_REPORT.md`

Both exit 0 on success, 1 on any failure. Invoke directly (see gotchas).

## Running the app

- `.\tracker.ps1` / `-Check` / `-Stop` — standalone tracker (CLI)
- `.\daily-report.ps1` — generate today's JSON report
- `.\dashboard-wpf.ps1` — WPF dashboard

## Gotchas (PowerShell 5.1 / this environment)

- Don't use `-ExecutionPolicy Bypass` — blocked by the permission classifier. Run scripts directly (`.\script.ps1`).
- Wrap `Where-Object` results in `@()` before `.Count` — a single `PSCustomObject`'s `.Count` returns blank.
- Never name a function `Group` — it's the alias for `Group-Object`, and aliases shadow functions.
- Keep `.ps1` files ASCII-only (or save as UTF-8 with BOM) — no-BOM files are read as Windows-1252, corrupting emoji/accents.
- Tests have side effects: the dashboard test briefly opens a real WPF window; the tracker test appends to today's real `logs/activity-<date>.csv`.
