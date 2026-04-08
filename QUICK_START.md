# AFOTRA - Post-Installation Checklist

Quick reference checklist to get AFOTRA running after installation.

## ✅ Pre-Flight Checklist (5 minutes)

- [ ] Extract AFOTRA to `C:\AFOTRA - Awema Focus Tracker`
- [ ] Verify all files present: `dir` shows config.json, rules.json, tracker.ps1, etc.
- [ ] Check PowerShell version: `$PSVersionTable.PSVersion` shows 5.0 or higher
- [ ] Set execution policy: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

## ✅ Initial Configuration (2 minutes)

- [ ] Open and review `config.json`
  - [ ] Sample interval: 10 seconds (good default)
  - [ ] Focus target: 480 minutes (8 hours) - adjust to your goal
  - [ ] Max distraction: 120 minutes (2 hours) - adjust your threshold

- [ ] Open and review `rules.json`
  - [ ] Review default categories: travail, etude, communication, distraction, inconnu
  - [ ] Check process rules: Code → travail, powershell → travail, etc.
  - [ ] Check title rules: YouTube → distraction, GitHub → travail, etc.
  - [ ] Add custom rules for your applications

## ✅ First Run (3 minutes)

**Desktop Shortcut (Optional):**
```powershell
# Create shortcut to dashboard
$WshShell = New-Object -ComObject WScript.Shell
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
