# SessionReport.Core.psm1 - Session & task reporting for AFOTRA
# Author: CodeScooper | Project: AFOTRA - Awema Focus Tracker
#
# Pure aggregation + formatting over the data already persisted on each task
# (Sessions[], TempsTravail/GlobalSecondes, EstimeMinutes, DigressionsCount).
# Reuses ConvertFrom-IsoDate + Get-TaskEfficiency from Tasks.Core.

if (-not (Get-Command Get-TaskEfficiency -ErrorAction SilentlyContinue)) {
    Import-Module (Join-Path $PSScriptRoot 'Tasks.Core.psm1') -Force -DisableNameChecking
}

function Get-SessionReport {
    # Bilan of ONE session (+ where the task stands after it).
    param([Parameter(Mandatory = $true)][object]$Task, [Parameter(Mandatory = $true)][object]$Session)
    $work  = [int]$Session.TravailSecondes
    $glob  = [int]$Session.GlobalSecondes
    $pause = [int]$Session.PauseSecondes
    $totalWork = [int]$Task.TempsTravailSecondes
    $est = [int]$Task.EstimeMinutes
    return [ordered]@{
        Titre                = [string]$Task.Titre
        Debut                = [string]$Session.Debut
        Fin                  = [string]$Session.Fin
        TravailMin           = [math]::Round($work / 60, 1)
        GlobalMin            = [math]::Round($glob / 60, 1)
        PauseMin             = [math]::Round($pause / 60, 1)
        PauseRatio           = if ($glob -gt 0) { [math]::Round($pause / $glob, 2) } else { 0 }
        Pomodoros            = [int]$Session.PomodorosFait
        TotalTravailTacheMin = [math]::Round($totalWork / 60, 1)
        EstimeMin            = $est
        AvancementPct        = if ($est -gt 0) { [math]::Round(($totalWork / 60) / $est * 100, 0) } else { $null }
    }
}

function Get-TaskReport {
    # Aggregate of ALL sessions that make up a task (+ chronological timeline).
    param([Parameter(Mandatory = $true)][object]$Task, [datetime]$Now = (Get-Date))
    $sessions = @()
    if ($Task.Sessions) { $sessions = @($Task.Sessions) }

    $work = 0; $glob = 0; $pause = 0; $pomo = 0
    foreach ($s in $sessions) {
        $work  += [int]$s.TravailSecondes
        $glob  += [int]$s.GlobalSecondes
        $pause += [int]$s.PauseSecondes
        $pomo  += [int]$s.PomodorosFait
    }

    $sorted = @($sessions | Sort-Object { [string]$_.Debut })
    $lines = @()
    $n = 0
    foreach ($s in $sorted) {
        $n++
        $lines += [ordered]@{
            N          = $n
            Debut      = [string]$s.Debut
            Fin        = [string]$s.Fin
            TravailMin = [math]::Round([int]$s.TravailSecondes / 60, 1)
            GlobalMin  = [math]::Round([int]$s.GlobalSecondes / 60, 1)
            PauseMin   = [math]::Round([int]$s.PauseSecondes / 60, 1)
            Pomodoros  = [int]$s.PomodorosFait
        }
    }

    $eff = Get-TaskEfficiency -Task $Task
    $first = if ($sorted.Count -gt 0) { [string]$sorted[0].Debut } else { $null }
    $last  = if ($sorted.Count -gt 0) { [string]$sorted[$sorted.Count - 1].Fin } else { $null }

    return [ordered]@{
        Titre       = [string]$Task.Titre
        Categorie   = [string]$Task.Categorie
        Projet      = [string]$Task.Projet
        Statut      = [string]$Task.Statut
        EstimeMin   = [int]$Task.EstimeMinutes
        NbSessions  = $sorted.Count
        TravailMin  = [math]::Round($work / 60, 1)
        GlobalMin   = [math]::Round($glob / 60, 1)
        PauseMin    = [math]::Round($pause / 60, 1)
        PauseRatio  = if ($glob -gt 0) { [math]::Round($pause / $glob, 2) } else { 0 }
        Pomodoros   = $pomo
        Digressions = [int]$Task.DigressionsCount
        EcartMin    = $eff.EcartMin
        Ratio       = $eff.Ratio
        Premiere    = $first
        Derniere    = $last
        Sessions    = $lines
    }
}

function Format-SessionReportText {
    param([Parameter(Mandatory = $true)][object]$Report)
    $r = $Report
    $L = @()
    $L += "Session terminée — $($r.Titre)"
    $L += "Début : $($r.Debut)"
    $L += "Fin   : $($r.Fin)"
    $L += ""
    $L += "Travail : $($r.TravailMin) min"
    $L += "Global  : $($r.GlobalMin) min"
    $L += "Pause   : $($r.PauseMin) min  (ratio $([int]($r.PauseRatio * 100)) %)"
    $L += "Pomodoros : $($r.Pomodoros)"
    if ($null -ne $r.AvancementPct) {
        $L += ""
        $L += "Tâche : $($r.TotalTravailTacheMin) / $($r.EstimeMin) min estimés  ($($r.AvancementPct) %)"
    }
    return ($L -join "`r`n")
}

function Format-TaskReportText {
    param([Parameter(Mandatory = $true)][object]$Report)
    $r = $Report
    $L = @()
    $L += "RAPPORT DE TÂCHE"
    $L += "================"
    $L += "$($r.Titre)"
    $meta = @()
    if ($r.Categorie) { $meta += $r.Categorie }
    if ($r.Projet)    { $meta += $r.Projet }
    if ($meta.Count -gt 0) { $L += ($meta -join "  ·  ") }
    $L += "Statut : $($r.Statut)"
    $L += ""
    $L += "Sessions  : $($r.NbSessions)"
    $L += "Travail   : $($r.TravailMin) min"
    $L += "Global    : $($r.GlobalMin) min"
    $L += "Pause     : $($r.PauseMin) min  (ratio $([int]($r.PauseRatio * 100)) %)"
    $L += "Pomodoros : $($r.Pomodoros)     Digressions : $($r.Digressions)"
    if ($r.EstimeMin -gt 0) {
        $sign = if ($r.EcartMin -gt 0) { "+" } else { "" }
        $L += "Estimé    : $($r.EstimeMin) min     Écart : $sign$($r.EcartMin) min  (ratio $($r.Ratio))"
    }
    if ($r.NbSessions -gt 0) {
        $L += ""
        $L += "Timeline :"
        foreach ($s in $r.Sessions) {
            $L += "  #$($s.N)  $($s.Debut) -> $($s.Fin)   travail $($s.TravailMin)m / pause $($s.PauseMin)m   $($s.Pomodoros) pomo"
        }
    }
    return ($L -join "`r`n")
}

function Get-TaskReportMarkdown {
    param([Parameter(Mandatory = $true)][object]$Report)
    $r = $Report
    $L = @()
    $L += "# Rapport de tâche — $($r.Titre)"
    $L += ""
    $sub = @()
    if ($r.Categorie) { $sub += "**Catégorie :** $($r.Categorie)" }
    if ($r.Projet)    { $sub += "**Projet :** $($r.Projet)" }
    $sub += "**Statut :** $($r.Statut)"
    $L += ($sub -join "  ·  ")
    $L += ""
    $L += "## Bilan"
    $L += ""
    $L += "| Métrique | Valeur |"
    $L += "|---|---|"
    $L += "| Sessions | $($r.NbSessions) |"
    $L += "| Travail | $($r.TravailMin) min |"
    $L += "| Global | $($r.GlobalMin) min |"
    $L += "| Pause | $($r.PauseMin) min ($([int]($r.PauseRatio * 100)) %) |"
    $L += "| Pomodoros | $($r.Pomodoros) |"
    $L += "| Digressions | $($r.Digressions) |"
    if ($r.EstimeMin -gt 0) {
        $sign = if ($r.EcartMin -gt 0) { "+" } else { "" }
        $L += "| Estimé | $($r.EstimeMin) min |"
        $L += "| Écart | $sign$($r.EcartMin) min (ratio $($r.Ratio)) |"
    }
    $L += ""
    if ($r.NbSessions -gt 0) {
        $L += "## Sessions"
        $L += ""
        $L += "| # | Début | Fin | Travail | Pause | Pomo |"
        $L += "|---|---|---|---|---|---|"
        foreach ($s in $r.Sessions) {
            $L += "| $($s.N) | $($s.Debut) | $($s.Fin) | $($s.TravailMin)m | $($s.PauseMin)m | $($s.Pomodoros) |"
        }
        $L += ""
    }
    return ($L -join "`r`n")
}

function Export-TaskReport {
    # Write the task report to logs/reports as JSON + readable Markdown. Returns the paths.
    param([Parameter(Mandatory = $true)][object]$Task, [Parameter(Mandatory = $true)][string]$Folder)
    if (-not (Test-Path $Folder)) { New-Item -ItemType Directory -Path $Folder -Force | Out-Null }
    $report = Get-TaskReport -Task $Task
    $idShort = ([string]$Task.Id) -replace '[^0-9A-Za-z]', ''
    if ($idShort.Length -gt 8) { $idShort = $idShort.Substring(0, 8) }
    $base = "task-$idShort-$(Get-Date -Format 'yyyy-MM-dd')"
    $jsonPath = Join-Path $Folder "$base.json"
    $mdPath   = Join-Path $Folder "$base.md"
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($jsonPath, (ConvertTo-Json -InputObject $report -Depth 10), $utf8Bom)
    [System.IO.File]::WriteAllText($mdPath, (Get-TaskReportMarkdown -Report $report), $utf8Bom)
    return [PSCustomObject]@{ Json = $jsonPath; Markdown = $mdPath }
}

Export-ModuleMember -Function `
    Get-SessionReport, Get-TaskReport, Format-SessionReportText, Format-TaskReportText, `
    Get-TaskReportMarkdown, Export-TaskReport
