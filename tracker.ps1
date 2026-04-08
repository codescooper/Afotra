# tracker.ps1 - Standalone tracker script
# Author: CodeScooper
# Project: AFOTRA - Awema Focus Tracker

param (
    [switch]$Stop,
    [switch]$Check
)

$ErrorActionPreference = "Stop"

try {
    $scriptRoot = $PSScriptRoot
    $configPath = Join-Path $scriptRoot "config.json"
    $rulesPath = Join-Path $scriptRoot "rules.json"

    # Import modules
    Import-Module (Join-Path $scriptRoot "modules\Tracker.Core.psm1") -Force
    Import-Module (Join-Path $scriptRoot "modules\Rules.Core.psm1") -Force

    $config = Get-Content $configPath -Encoding UTF8 | ConvertFrom-Json
    $rules = Load-Rules -RulesPath $rulesPath
    $logFolder = Join-Path $scriptRoot $config.logFolder

    if ($Check) {
        $psProcesses = Get-Process -Name powershell -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like "*AFOTRA*" }
        if ($psProcesses.Count -gt 0) {
            Write-Host "[OK] Tracker is running" -ForegroundColor Green
            exit 0
        }
        else {
            Write-Host "[NOT RUNNING] Tracker is not running" -ForegroundColor Red
            exit 1
        }
    }

    if ($Stop) {
        Write-Host "Stopping tracker..." -ForegroundColor Yellow
        $psProcesses = Get-Process -Name powershell -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like "*AFOTRA*" }
        if ($psProcesses.Count -gt 0) {
            $psProcesses | Stop-Process -Force
            Write-Host "Tracker stopped" -ForegroundColor Green
        }
        else {
            Write-Host "No tracker process found" -ForegroundColor Yellow
        }
        exit 0
    }

    # Check if already running
    $psProcesses = Get-Process -Name powershell -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like "*AFOTRA Tracker*" }
    if ($psProcesses.Count -gt 0) {
        Write-Host "Tracker is already running!" -ForegroundColor Yellow
        exit 1
    }

    Write-Host "AFOTRA - Awema Focus Tracker" -ForegroundColor Green
    Write-Host "Starting tracker with interval: $($config.sampleIntervalSeconds)s" -ForegroundColor Green

    $logFile = Get-TodayLogFile -LogFolder $logFolder
    Initialize-LogFile -LogFile $logFile
    Write-Host "Logging to: $logFile" -ForegroundColor Green

    $timer = New-Object System.Timers.Timer
    $timer.Interval = $config.sampleIntervalSeconds * 1000
    $timer.AutoReset = $true

    $action = {
        $info = Get-ActiveWindowInfo
        if ($info) {
            $category = Classify-Activity -ProcessName $info.ProcessName -WindowTitle $info.WindowTitle -Rules $rules
            $info | Add-Member -NotePropertyName "Category" -NotePropertyValue $category -Force
            Write-ActivityLog -LogFile $logFile -ActivityInfo $info -SampleSeconds $config.sampleIntervalSeconds
            Write-Host "[$([datetime]::Now.ToString('HH:mm:ss'))] $($info.ProcessName) > $category" -ForegroundColor Cyan
        }
    }

    Register-ObjectEvent -InputObject $timer -EventName Elapsed -Action $action | Out-Null
    $timer.Start()

    $host.UI.RawUI.WindowTitle = "AFOTRA Tracker - Running"

    Write-Host "Tracker running. Press Ctrl+C to stop." -ForegroundColor Yellow

    try {
        while ($true) {
            Start-Sleep 1
        }
    }
    finally {
        $timer.Stop()
        $timer.Dispose()
        Write-Host "Tracker stopped" -ForegroundColor Green
    }
}
catch {
    Write-Error "Error: $_"
    exit 1
}