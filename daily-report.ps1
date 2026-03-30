param(
    [string]$ConfigPath = "C:\AFOTRA - Awema Focus Tracker\config.json",
    [string]$Date = $(Get-Date -Format "yyyy-MM-dd")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path $ConfigPath)) {
    throw "Config introuvable : $ConfigPath"
}

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$logPath = Join-Path $config.logRoot "activity-$Date.csv"

if (-not (Test-Path $logPath)) {
    throw "Aucun log trouvé pour $Date : $logPath"
}

$rows = Import-Csv $logPath
if (-not $rows -or $rows.Count -eq 0) {
    throw "Le log est vide pour $Date"
}

$sampleSeconds = [int]($rows[0].SampleSeconds)

$appStats = $rows |
    Group-Object ProcessName |
    ForEach-Object {
        $seconds = $_.Count * $sampleSeconds
        [PSCustomObject]@{
            ProcessName = $_.Name
            Samples     = $_.Count
            Minutes     = [math]::Round($seconds / 60, 1)
            Hours       = [math]::Round($seconds / 3600, 2)
        }
    } |
    Sort-Object Minutes -Descending

$categoryStats = $rows |
    Group-Object Category |
    ForEach-Object {
        $seconds = $_.Count * $sampleSeconds
        [PSCustomObject]@{
            Category = $_.Name
            Samples  = $_.Count
            Minutes  = [math]::Round($seconds / 60, 1)
            Hours    = [math]::Round($seconds / 3600, 2)
        }
    } |
    Sort-Object Minutes -Descending

$contextSwitches = 0
for ($i = 1; $i -lt $rows.Count; $i++) {
    if ($rows[$i].ProcessName -ne $rows[$i - 1].ProcessName -or
        $rows[$i].WindowTitle -ne $rows[$i - 1].WindowTitle) {
        $contextSwitches++
    }
}

$focusRow = $categoryStats | Where-Object Category -eq "travail" | Select-Object -First 1
$focusMinutes = if ($focusRow) { [double]$focusRow.Minutes } else { 0 }

$distractionRow = $categoryStats | Where-Object Category -eq "distraction" | Select-Object -First 1
$distractionMinutes = if ($distractionRow) { [double]$distractionRow.Minutes } else { 0 }

$goalFocus = [int]$config.goals.focusMinPerDay
$goalMaxDistraction = [int]$config.goals.maxDistractionMinPerDay

$focusScore = 100

if ($goalFocus -gt 0 -and $focusMinutes -lt $goalFocus) {
    $focusPenalty = (($goalFocus - $focusMinutes) / $goalFocus) * 40
    $focusScore -= $focusPenalty
}

if ($goalMaxDistraction -gt 0 -and $distractionMinutes -gt $goalMaxDistraction) {
    $distractionPenalty = (($distractionMinutes - $goalMaxDistraction) / $goalMaxDistraction) * 60
    $focusScore -= $distractionPenalty
}

$focusScore = [math]::Round([math]::Max(0, [math]::Min(100, $focusScore)), 0)

$summary = [PSCustomObject]@{
    Date                    = $Date
    TotalSamples            = $rows.Count
    SampleIntervalSeconds   = $sampleSeconds
    TotalTrackedMinutes     = [math]::Round(($rows.Count * $sampleSeconds) / 60, 1)
    ContextSwitches         = $contextSwitches
    FocusMinutes            = $focusMinutes
    DistractionMinutes      = $distractionMinutes
    GoalFocusMinutes        = $goalFocus
    GoalMaxDistractionMin   = $goalMaxDistraction
    FocusScore              = $focusScore
}

$reportRoot = Join-Path $config.logRoot "reports"
if (-not (Test-Path $reportRoot)) {
    New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null
}

$summaryPath = Join-Path $reportRoot "summary-$Date.json"
$appPath = Join-Path $reportRoot "apps-$Date.csv"
$categoryPath = Join-Path $reportRoot "categories-$Date.csv"

$summary | ConvertTo-Json -Depth 5 | Set-Content -Path $summaryPath -Encoding UTF8
$appStats | Export-Csv -Path $appPath -NoTypeInformation
$categoryStats | Export-Csv -Path $categoryPath -NoTypeInformation

Write-Host ""
Write-Host "=== Résumé $Date ==="
Write-Host "Temps total suivi      : $($summary.TotalTrackedMinutes) min"
Write-Host "Changements contexte   : $($summary.ContextSwitches)"
Write-Host "Temps travail          : $($summary.FocusMinutes) min"
Write-Host "Temps distraction      : $($summary.DistractionMinutes) min"
Write-Host "Score focus            : $($summary.FocusScore)/100"
Write-Host ""

Write-Host "Top 10 apps :"
$appStats | Select-Object -First 10 | Format-Table -AutoSize

Write-Host ""
Write-Host "Par catégorie :"
$categoryStats | Format-Table -AutoSize

Write-Host ""
Write-Host "Fichiers générés :"
Write-Host $summaryPath
Write-Host $appPath
Write-Host $categoryPath