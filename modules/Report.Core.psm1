# Report.Core.psm1 - Core functions for generating reports
# Author: CodeScooper
# Project: AFOTRA - Awema Focus Tracker

function Measure-ContextSwitches {
    # Compte les VRAIES bascules : nombre de fois ou la fenetre active change
    # entre deux echantillons consecutifs (et non le nombre de titres distincts).
    param (
        [object[]]$Rows
    )
    if (-not $Rows -or $Rows.Count -lt 2) { return 0 }
    $switches = 0
    for ($i = 1; $i -lt $Rows.Count; $i++) {
        if ($Rows[$i].WindowTitle -ne $Rows[$i - 1].WindowTitle) { $switches++ }
    }
    return $switches
}

function Get-ReportData {
    param (
        [string]$LogFile,
        [string[]]$FocusCategories = @("travail")
    )
    
    if (!(Test-Path $LogFile)) {
        return $null
    }

    try {
        $data = @(Import-Csv -Path $LogFile -Encoding UTF8)
        if ($data.Count -eq 0) { return $null }

        $sampleSeconds = [int]$data[0].SampleSeconds
        $totalSeconds = $data.Count * $sampleSeconds

        $categories = @{}
        $processes = @{}
        $unknowns = @{}

        foreach ($row in $data) {
            # Categories
            if (!$categories[$row.Category]) {
                $categories[$row.Category] = 0
            }
            $categories[$row.Category] += $sampleSeconds

            # Processes
            if (!$processes[$row.ProcessName]) {
                $processes[$row.ProcessName] = 0
            }
            $processes[$row.ProcessName] += $sampleSeconds

            # Unknowns
            if ($row.Category -eq "inconnu") {
                $key = "$($row.ProcessName)|$($row.WindowTitle)"
                if (!$unknowns[$key]) {
                    $unknowns[$key] = @{
                        ProcessName = $row.ProcessName
                        WindowTitle = $row.WindowTitle
                        Count = 0
                        Seconds = 0
                    }
                }
                $unknowns[$key].Count++
                $unknowns[$key].Seconds += $sampleSeconds
            }
        }

        # Focus = somme des categories declarees "focus" (configurable).
        $focusSeconds = 0
        foreach ($fc in $FocusCategories) { if ($categories[$fc]) { $focusSeconds += $categories[$fc] } }

        # Le temps inactif (AFK / ecran verrouille) est exclu du denominateur :
        # le focus score mesure la concentration pendant le temps ACTIF.
        $inactiveSeconds = if ($categories["inactif"]) { $categories["inactif"] } else { 0 }
        $activeSeconds = $totalSeconds - $inactiveSeconds
        $focusScore = if ($activeSeconds -gt 0) { [math]::Round(($focusSeconds / $activeSeconds) * 100, 2) } else { 0 }

        $contextSwitches = Measure-ContextSwitches -Rows $data

        return @{
            TotalSeconds = $totalSeconds
            ActiveSeconds = $activeSeconds
            SampleSeconds = $sampleSeconds
            Categories = $categories
            Processes = $processes
            Unknowns = $unknowns
            FocusSeconds = $focusSeconds
            FocusScore = $focusScore
            ContextSwitches = $contextSwitches
            DataRows = $data
        }
    }
    catch {
        Write-Warning "Error processing report data: $_"
        return $null
    }
}

function Export-ReportToJSON {
    param (
        [object]$ReportData,
        [string]$OutputFile,
        [object]$TaskSummary = $null
    )
    
    $folder = Split-Path -Parent $OutputFile
    if (!(Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }

    $focusSeconds = if ($null -ne $ReportData.FocusSeconds) { $ReportData.FocusSeconds } elseif ($ReportData.Categories["travail"]) { $ReportData.Categories["travail"] } else { 0 }
    $distractionSeconds = if ($ReportData.Categories["distraction"]) { $ReportData.Categories["distraction"] } else { 0 }
    $activeSeconds = if ($null -ne $ReportData.ActiveSeconds) { $ReportData.ActiveSeconds } else { $ReportData.TotalSeconds }

    $topProcesses = @{}
    $ReportData.Processes.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5 | ForEach-Object {
        $topProcesses[$_.Key] = $_.Value
    }
    
    $summary = @{
        TotalTrackedMinutes = [math]::Round($ReportData.TotalSeconds / 60, 2)
        ActiveMinutes = [math]::Round($activeSeconds / 60, 2)
        FocusMinutes = [math]::Round($focusSeconds / 60, 2)
        DistractionMinutes = [math]::Round($distractionSeconds / 60, 2)
        FocusScore = $ReportData.FocusScore
        ContextSwitches = $ReportData.ContextSwitches
        Categories = $ReportData.Categories
        TopProcesses = $topProcesses
    }

    # Optional Tasks section (counts: a faire / en cours / terminees aujourd'hui / en retard)
    if ($null -ne $TaskSummary) {
        $summary["Tasks"] = $TaskSummary
    }

    $summary | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputFile -Encoding UTF8 -Force
}

function Get-UnknownActivities {
    param (
        [string]$LogFile
    )
    if (!(Test-Path $LogFile)) { return @() }
    
    try {
        $data = @(Import-Csv -Path $LogFile -Encoding UTF8)
        $unknown = $data | Where-Object Category -eq "inconnu" | Group-Object ProcessName | Select-Object @{Name="ProcessName"; Expression={ $_.Name }}, @{Name="Count"; Expression={ $_.Count }}
        return $unknown
    }
    catch {
        return @()
    }
}

Export-ModuleMember -Function Get-ReportData, Export-ReportToJSON, Get-UnknownActivities, Measure-ContextSwitches