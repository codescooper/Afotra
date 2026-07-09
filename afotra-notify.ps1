# afotra-notify.ps1 - Silent evening-reminder mode for AFOTRA.
# Author: CodeScooper | Project: AFOTRA - Awema Focus Tracker
#
# Fires Windows notifications for every task whose RappelSoir is due and that hasn't
# been notified yet today, then marks them notified. No window, no dashboard.
# Designed to be run by Windows Task Scheduler at ~20:00 so reminders fire even when
# the dashboard is closed.
#
# Register the daily job (run once, in a normal PowerShell prompt):
#   schtasks /Create /SC DAILY /ST 20:00 /TN "AFOTRA Rappel du soir" /F ^
#     /TR "powershell -NoProfile -WindowStyle Hidden -File \"<REPO>\afotra-notify.ps1\""
# Replace <REPO> with this folder's full path. Remove with:
#   schtasks /Delete /TN "AFOTRA Rappel du soir" /F

$ErrorActionPreference = "Stop"

try {
    $scriptRoot = $PSScriptRoot
    Import-Module (Join-Path $scriptRoot "modules\Tasks.Core.psm1")  -Force -DisableNameChecking
    Import-Module (Join-Path $scriptRoot "modules\Notify.Core.psm1") -Force -DisableNameChecking

    $storePath = Get-TaskStorePath
    $tasks = @(Get-Tasks -Path $storePath)
    $due = @(Get-DueReminders -Tasks $tasks)

    if ($due.Count -eq 0) {
        Write-Host "No reminders due." -ForegroundColor Gray
        exit 0
    }

    foreach ($t in $due) {
        $body = $t.Titre
        if ($t.Contact) { $body += "  -  $($t.Contact)" }
        Show-AfotraNotification -Title "AFOTRA - Rappel du soir" -Message $body | Out-Null
        Set-TaskNotified -Id $t.Id -Path $storePath
    }

    Write-Host "Fired $($due.Count) reminder(s)." -ForegroundColor Green

    # Give the tray balloon a moment to display before the process exits.
    Start-Sleep -Seconds 8
    Close-AfotraNotifier
    exit 0
}
catch {
    Write-Error "Notify error: $_"
    exit 1
}
