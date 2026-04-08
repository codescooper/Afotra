# AFOTRA - Awema Focus Tracker - Quick Start Guide v2.0

## Current Status: FULLY FUNCTIONAL

---

## What is AFOTRA?

AFOTRA is a **local Windows activity tracker** that:
- Monitors your active window and application in real-time
- Automatically categorizes activities (work, study, communication, distraction, unknown)
- Generates daily reports with focus scores and productivity metrics
- Provides an intuitive WPF dashboard for management
- Runs 100% locally - your data never leaves your computer

---

## Getting Started (5 minutes)

### Step 1: Verify Installation
```powershell
cd "C:\AFOTRA - Awema Focus Tracker"
powershell -ExecutionPolicy Bypass -File quick-check.ps1
```

### Step 2: Set PowerShell Execution Policy (First Time Only)
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
```

### Step 3: Launch the Dashboard

**Option A - Double-click:**
- `run-dashboard-wpf.bat`

**Option B - PowerShell:**
```powershell
cd "C:\AFOTRA - Awema Focus Tracker"
.\dashboard-wpf.ps1
```

---

## Dashboard Features

### Dashboard Tab
- **Total Time**: Total tracking time today
- **Focus Time**: Time on "travail" activities
- **Focus Score**: % in focus mode
- **Distractions**: Time on distraction categories
- **Chart**: Visual breakdown by category

### Live Tracking Tab
- Real-time current application display
- Category classification
- Time on current activity
- Last 10 activities

### Unknown Activities Tab
- Unclassified activities
- Quick categorization
- Automatic rule creation

### Rules Tab
- Manage categories
- Add/delete rules
- Process-based filtering

### Buttons
- **Generate Report**: Creates JSON report
- **Open Logs**: Browse activity data

---

## Main Controls

### Start/Stop Button
- Green when stopped, Red when running
- Toggles activity monitoring

### Status Indicator  
- Shows "Running" or "Stopped"
- Displays current process

---

## Configuration

### config.json
```json
{
  "sampleIntervalSeconds": 10,
  "focusMinPerDay": 480,
  "maxDistractionMinPerDay": 120,
  "logFolder": "logs"
}
```

### rules.json
Contains categories and classification rules:
- **processRules**: Match by executable name (Code.exe, chrome.exe)
- **titleRules**: Match by window title text

**Classification order:**
1. Check process rules
2. Check title rules
3. Mark as "inconnu" if no match

---

## Log Files

### Activity Logs
`logs/activity-YYYY-MM-DD.csv`

Columns: Timestamp, Date, Time, ProcessName, ProcessId, WindowTitle, Category

### Reports
`logs/reports/summary-YYYY-MM-DD.json`

Contains: Total time, focus score, breakdown by category, top applications

---

## Standalone Usage

Track without UI:
```powershell
.\tracker.ps1               # Start tracking
.\tracker.ps1 -Check        # Check status
.\tracker.ps1 -Stop         # Stop tracking
```

Generate report:
```powershell
.\daily-report.ps1
```

---

## Common Tasks

### Add an Application
1. Go to **Unknown Activities** tab
2. Select your app
3. Click **Categorize Selected**
4. Choose category
5. Save - rule persists

### Change Focus Goal
Edit `config.json`:
```json
"focusMinPerDay": 600  // Set to 10 hours
```

### View Activities
1. Click **Open Logs**
2. Open `activity-TODAY.csv`
3. All activities with timestamps

---

## Troubleshooting

**Dashboard won't start:**
- Check execution policy: `Set-ExecutionPolicy RemoteSigned`
- Restart PowerShell

**No activities logged:**
- Wait 11 seconds for first sample
- Check status shows "Running"
- Switch applications

**Rules not working:**
- Verify `rules.json` is valid JSON
- App name must match exactly
- Window title search is case-insensitive

**Report not generated:**
- Ensure `logs/reports/` folder exists
- Check disk space
- Verify folder permissions

---

## File Structure

```
C:\AFOTRA - Awema Focus Tracker\
├── dashboard-wpf.ps1           (Main dashboard)
├── tracker.ps1                 (Standalone tracker)
├── daily-report.ps1            (Report generator)
├── quick-check.ps1             (Verification)
├── run-dashboard-wpf.bat       (Launcher)
├── config.json                 (Settings)
├── rules.json                  (Categories)
├── Readme.md                   (Full docs)
├── QUICK_START.md              (This file)
├── modules/
│   ├── Tracker.Core.psm1       (Tracking engine)
│   ├── Rules.Core.psm1         (Classification)
│   └── Report.Core.psm1        (Reports)
└── logs/
    ├── activity-*.csv          (Daily logs)
    └── reports/
        └── summary-*.json      (Daily reports)
```

---

## Data Privacy

- 100% local storage (no cloud sync)
- Data in `logs/` folder
- Simple CSV format (human-readable)
- Full control over your data

---

## Tips

1. Let it run to build history
2. Add rules early for better categorization
3. Review reports regularly
4. Adjust categories as needed
5. Set realistic focus goals

---

## Next Steps

1. Launch `dashboard-wpf.ps1`
2. Click "Start Tracking"
3. Switch between applications
4. Categorize unknown activities
5. Check your first daily report

**Get started now!** Dashboard is fully functional and ready to use.

For full documentation, see: `Readme.md`
$Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\AFOTRA.lnk")
$Shortcut.TargetPath = "C:\AFOTRA - Awema Focus Tracker\run-dashboard.vbs"
$Shortcut.Save()
```

**Launch Dashboard:**
```powershell
cd "C:\AFOTRA - Awema Focus Tracker"
.\dashboard.ps1
```

Or: Double-click `run-dashboard.vbs`

## ✅ Test Tracking (2 minutes)

1. Click **[Start] Tracking** button
   - Status changes to green: "Status: Running ACTIVE"
   - [Start] button disables, [Stop] button enables

2. Switch between applications (open browser, code editor, etc.)
   - Watch current process change in status bar
   - Categories should update based on rules

3. Click **[Report] Generate Report** 
   - Message shows today's focus score
   - Report saved to `logs/reports/summary-YYYY-MM-DD.json`

4. Click **[Stop] Tracking**
   - Status returns to red: "Status: Stopped"

## ✅ Verify Data Files (1 minute)

- [ ] Click **[Logs] Open Folder** in dashboard
- [ ] Verify `logs/activity-2026-03-30.csv` exists and has data
- [ ] Open CSV in Excel - verify columns and rows
- [ ] Verify `logs/reports/summary-2026-03-30.json` file exists

## ✅ Customize Rules (Optional - 5 minutes)

**Add a new category example:**

Edit `rules.json`:
```json
{
  "categories": [
    "travail",
    "etude", 
    "communication",
    "distraction",
    "personal",
    "inconnu"
  ],
  "processRules": [
    { "process": "Code", "category": "travail" },
    { "process": "Slack", "category": "communication" },
    { "process": "spotify", "category": "personal" }
  ],
  "titleRules": [
    { "contains": "Netflix", "category": "personal" },
    { "contains": "LinkedIn", "category": "travail" }
  ]
}
```

Then restart tracker for changes to take effect.

## ✅ Daily Usage (Every Day)

**Morning:**
```powershell
.\dashboard.ps1
# Click [Start] Tracking
```

**Evening:**
```powershell
# In dashboard:
# 1. Click [Report] Generate Report
# 2. Review your focus score
# 3. Click [Stop] Tracking
```

**Weekly (Optional):**
```powershell
# Backup your logs
Copy-Item "logs" "logs.backup-$(Get-Date -Format 'yyyy-MM-dd')"
```

## ✅ Troubleshooting Quick Links

**Problem: Dashboard won't launch**
```powershell
.\dashboard.ps1
# Check for error message in console
# See README.md Troubleshooting section
```

**Problem: Tracker not logging**
```powershell
.\tracker.ps1 -Check
# Should show: "✓ Tracker is running"
```

**Problem: Application not classified**
- Add rule to `rules.json` for that app/title
- See README.md section "Configuration" > "rules.json"

## Next Steps

1. **Read full README**: `README.md` - comprehensive guide
2. **Check test plan**: `TEST_PLAN.md` - validation procedures
3. **Monitor for week**: Let AFOTRA track your normal activity
4. **Create reports**: Analyze your productivity patterns
5. **Adjust rules**: Refine categories based on actual usage

---

## Support

If something doesn't work:

1. Check **README.md** - Troubleshooting section
2. Review **logs/** folder for error patterns
3. Verify files are writable: `Test-Path -PathType Container "C:\AFOTRA - Awema Focus Tracker\logs"`
4. Restart dashboard/tracker

---

**Version:** 1.0  
**Author:** CodeScooper  
**Project:** AFOTRA - Awema Focus Tracker

---

**Quick Command Reference:**

```powershell
# Dashboard
.\dashboard.ps1                         # Launch GUI

# Tracker
.\tracker.ps1                           # Start tracking
.\tracker.ps1 -Check                    # Check status
.\tracker.ps1 -Stop                     # Stop tracking

# Reports  
.\daily-report.ps1                      # Generate daily report

# Files
dir                                     # List all files
explorer logs                           # Open logs folder
Get-Content config.json | ConvertFrom-Json  # View configuration
```
