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
    $lockPath = Join-Path $scriptRoot "tracker.lock"
    $idleThreshold = if ($config.idleThresholdSeconds) { [int]$config.idleThresholdSeconds } else { 180 }

    # Timer event actions run in a separate scope and do NOT capture script-local
    # variables. Expose what the action needs via $global: so it is reachable from
    # inside the Elapsed handler (otherwise the tracker silently logs nothing).
    $global:AfotraRules         = $rules
    $global:AfotraConfig        = $config
    $global:AfotraIdleThreshold = $idleThreshold

    if ($Check) {
        # Detection robuste via fichier de verrou PID (le titre de fenetre etait
        # peu fiable, notamment quand le tracker tourne en arriere-plan).
        if (Test-TrackerRunning -LockFile $lockPath) {
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
        if (Test-TrackerRunning -LockFile $lockPath) {
            $pidVal = Get-Content $lockPath -ErrorAction SilentlyContinue | Select-Object -First 1
            Stop-Process -Id ([int]$pidVal) -Force -ErrorAction SilentlyContinue
            Remove-TrackerLock -LockFile $lockPath
            Write-Host "Tracker stopped" -ForegroundColor Green
        }
        else {
            Remove-TrackerLock -LockFile $lockPath   # nettoie un verrou orphelin
            Write-Host "No tracker process found" -ForegroundColor Yellow
        }
        exit 0
    }

    # Check if already running
    if (Test-TrackerRunning -LockFile $lockPath) {
        Write-Host "Tracker is already running!" -ForegroundColor Yellow
        exit 1
    }

    Write-Host "AFOTRA - Awema Focus Tracker" -ForegroundColor Green
    Write-Host "Starting tracker with interval: $($config.sampleIntervalSeconds)s" -ForegroundColor Green

    $logFile = Get-TodayLogFile -LogFolder $logFolder
    Initialize-LogFile -LogFile $logFile
    $global:AfotraLogFile = $logFile
    Write-Host "Logging to: $logFile" -ForegroundColor Green

    $timer = New-Object System.Timers.Timer
    $timer.Interval = $config.sampleIntervalSeconds * 1000
    $timer.AutoReset = $true

    $action = {
        try {
            $info = Get-ActiveWindowInfo
            if ($info) {
                # AFK / ecran verrouille -> "inactif" (exclu du temps actif et du focus).
                $idle = Get-IdleSeconds
                if ((Get-IsSessionLocked -ActivityInfo $info) -or ($idle -ge $global:AfotraIdleThreshold)) {
                    $category = "inactif"
                }
                else {
                    $category = Classify-Activity -ProcessName $info.ProcessName -WindowTitle $info.WindowTitle -Rules $global:AfotraRules
                }
                $info | Add-Member -NotePropertyName "Category" -NotePropertyValue $category -Force
                Write-ActivityLog -LogFile $global:AfotraLogFile -ActivityInfo $info -SampleSeconds $global:AfotraConfig.sampleIntervalSeconds
                Write-Host "[$([datetime]::Now.ToString('HH:mm:ss'))] $($info.ProcessName) > $category" -ForegroundColor Cyan
            }
        }
        catch {
            Write-Host "[tracker] sample error: $_" -ForegroundColor Red
        }
    }

    Register-ObjectEvent -InputObject $timer -EventName Elapsed -Action $action | Out-Null
    $timer.Start()

    Set-TrackerLock -LockFile $lockPath
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
        Remove-TrackerLock -LockFile $lockPath
        Write-Host "Tracker stopped" -ForegroundColor Green
    }
}
catch {
    Write-Error "Error: $_"
    exit 1
}