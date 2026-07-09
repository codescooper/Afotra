# daily-report.ps1 - Generate daily reports
# Author: CodeScooper
# Project: AFOTRA - Awema Focus Tracker

$ErrorActionPreference = "Stop"

try {
    $scriptRoot = $PSScriptRoot
    $configPath = Join-Path $scriptRoot "config.json"

    # Import modules
    Import-Module (Join-Path $scriptRoot "modules\Tracker.Core.psm1") -Force
    Import-Module (Join-Path $scriptRoot "modules\Report.Core.psm1") -Force
    Import-Module (Join-Path $scriptRoot "modules\Tasks.Core.psm1") -Force -DisableNameChecking

    $config = Get-Content $configPath -Encoding UTF8 | ConvertFrom-Json
    $logFolder = Join-Path $scriptRoot $config.logFolder
    $reportFolder = Join-Path $logFolder "reports"

    Write-Host "AFOTRA - Awema Focus Tracker - Report Generator" -ForegroundColor Green
    Write-Host "Generating daily report..." -ForegroundColor Green

    $logFile = Get-TodayLogFile -LogFolder $logFolder

    if (!(Test-Path $logFile)) {
        Write-Host "No tracking data for today" -ForegroundColor Yellow
        exit 1
    }

    $focusCats = if ($config.focusCategories) { $config.focusCategories } else { @("travail") }
    $reportData = Get-ReportData -LogFile $logFile -FocusCategories $focusCats

    if (!$reportData) {
        Write-Host "Unable to process tracking data" -ForegroundColor Red
        exit 1
    }

    $date = Get-Date -Format "yyyy-MM-dd"
    $jsonFile = Join-Path $reportFolder "summary-$date.json"

    $taskSummary = $null
    try { $taskSummary = Get-TaskSummary -Tasks @(Get-Tasks) } catch { }

    Export-ReportToJSON -ReportData $reportData -OutputFile $jsonFile -TaskSummary $taskSummary

    Write-Host "Report saved: $jsonFile" -ForegroundColor Green
    if ($taskSummary) {
        Write-Host "  Tasks: $($taskSummary.AFaire) a faire / $($taskSummary.EnCours) en cours / $($taskSummary.TermineesAujourdhui) terminees auj. / $($taskSummary.EnRetard) en retard" -ForegroundColor White
    }
    Write-Host "`nSummary:" -ForegroundColor Cyan
    Write-Host "  Total Tracked: $([math]::Round($reportData.TotalSeconds / 60, 2)) minutes" -ForegroundColor White
    Write-Host "  Focus Score: $($reportData.FocusScore)%" -ForegroundColor White
    Write-Host "  Context Switches: $($reportData.ContextSwitches)" -ForegroundColor White
    
    Write-Host "`nCategories:" -ForegroundColor Cyan
    foreach ($cat in $reportData.Categories.GetEnumerator()) {
        $minutes = [math]::Round($cat.Value / 60, 2)
        Write-Host "  $($cat.Key): $minutes min" -ForegroundColor White
    }

    exit 0
}
catch {
    Write-Error "Error: $_"
    exit 1
}