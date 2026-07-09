# Tasks.Core.psm1 - Task management data + logic layer for AFOTRA
# Author: CodeScooper | Project: AFOTRA - Awema Focus Tracker
#
# UI-free. Persists a JSON array of tasks (French field names, per the data model)
# to <repo>\tasks.json with ATOMIC writes (temp file + File.Replace/Move).
# All functions accept an explicit -Path so tests can inject a temp store and
# leave the real tasks.json untouched.

$script:ValidStatuts   = @('A_faire', 'En_cours', 'En_attente', 'Termine', 'Archive')
$script:ClosedStatuts  = @('Termine', 'Archive')

# ---- Private date helpers (nullable-safe ISO 8601) -------------------------
function ConvertTo-IsoDate {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value.ToString('s') }
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    return $s
}

function ConvertFrom-IsoDate {
    param($Value)
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return $null }
    try { return [datetime]::Parse($s, [System.Globalization.CultureInfo]::InvariantCulture) }
    catch { return $null }
}

# ---- Store location --------------------------------------------------------
function Get-TaskStorePath {
    # Override for tests / custom locations via env var.
    if ($env:AFOTRA_TASK_STORE) { return $env:AFOTRA_TASK_STORE }
    $root = Split-Path -Parent $PSScriptRoot   # modules\ -> repo root
    return (Join-Path $root 'tasks.json')
}

# ---- Load / Save (atomic) --------------------------------------------------
function Get-Tasks {
    param([string]$Path = (Get-TaskStorePath))

    if (-not (Test-Path $Path)) { return @() }
    try {
        $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
        $data = $raw | ConvertFrom-Json
        return @($data)
    }
    catch {
        # Corrupt JSON: preserve the bad file as a timestamped .bak, never crash.
        try {
            $bak = "$Path.$(Get-Date -Format 'yyyyMMddHHmmss').bak"
            Copy-Item -Path $Path -Destination $bak -Force -ErrorAction SilentlyContinue
        } catch { }
        return @()
    }
}

function Save-Tasks {
    param(
        [object[]]$Tasks,
        [string]$Path = (Get-TaskStorePath)
    )

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    # PowerShell 5.1 unwraps single-element arrays, so build the JSON array by hand
    # to guarantee tasks.json is ALWAYS a JSON array (never a bare object).
    $arr = @($Tasks)
    if ($arr.Count -eq 0) {
        $json = '[]'
    }
    elseif ($arr.Count -eq 1) {
        $json = "[`r`n" + (ConvertTo-Json -InputObject $arr[0] -Depth 10) + "`r`n]"
    }
    else {
        $json = ConvertTo-Json -InputObject $arr -Depth 10
    }

    $tmp = "$Path.tmp"
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($tmp, $json, $utf8Bom)

    if (Test-Path $Path) {
        # Atomic swap. File.Replace needs a real backup path (a null backup throws
        # ArgumentException on .NET Framework); we delete the backup right after.
        $bak = "$Path.repl"
        [System.IO.File]::Replace($tmp, $Path, $bak, $true)
        Remove-Item $bak -ErrorAction SilentlyContinue
    }
    else {
        [System.IO.File]::Move($tmp, $Path)
    }
}

# ---- Factory ---------------------------------------------------------------
function New-Task {
    param(
        [Parameter(Mandatory = $true)][string]$Titre,
        [string]$Description = '',
        [string]$Categorie   = '',
        [string]$Projet      = '',
        [string]$Contact     = '',
        [ValidateSet('Basse', 'Normale', 'Haute', 'Urgente')][string]$Priorite = 'Normale',
        [ValidateSet('A_faire', 'En_cours', 'En_attente', 'Termine', 'Archive')][string]$Statut = 'A_faire',
        [Nullable[datetime]]$DateEcheance = $null,
        [Nullable[datetime]]$RappelSoir   = $null,
        [string]$Bloquee_par = '',
        [string]$Notes       = '',
        [Nullable[int]]$EstimeMinutes = $null
    )

    return [PSCustomObject]([ordered]@{
        Id                   = [string](New-Guid)
        Titre                = $Titre
        Description          = $Description
        Categorie            = $Categorie
        Projet               = $Projet
        Contact              = $Contact
        Priorite             = $Priorite
        Statut               = $Statut
        DateEcheance         = (ConvertTo-IsoDate $DateEcheance)
        RappelSoir           = (ConvertTo-IsoDate $RappelSoir)
        Bloquee_par          = $Bloquee_par
        CreeLe               = (Get-Date).ToString('s')
        TermineLe            = $null
        Notes                = $Notes
        NotifieLe            = $null   # internal: last date (yyyy-MM-dd) a reminder fired
        EstimeMinutes        = $(if ($null -ne $EstimeMinutes) { [int]$EstimeMinutes } else { $null })
        TempsTravailSecondes = 0       # accumulated active work across sessions
        TempsGlobalSecondes  = 0       # accumulated wall-clock across sessions (incl. pauses)
        Sessions             = @()     # per-session log: {Debut,Fin,TravailSecondes,GlobalSecondes,PauseSecondes,PomodorosFait}
        OutilsTache          = @()     # focus-guard allow-list: process names deemed on-task
        DigressionsCount     = 0       # times the user answered "Non" to the guard
    })
}

# ---- Mutations (operate on the store, return the affected task) ------------
function Add-Task {
    param([Parameter(Mandatory = $true)][object]$Task, [string]$Path = (Get-TaskStorePath))
    $tasks = @(Get-Tasks -Path $Path)
    $tasks += $Task
    Save-Tasks -Tasks $tasks -Path $Path
    return $Task
}

function Update-Task {
    param([Parameter(Mandatory = $true)][object]$Task, [string]$Path = (Get-TaskStorePath))
    $tasks = @(Get-Tasks -Path $Path)
    $out = @()
    $replaced = $false
    foreach ($t in $tasks) {
        if ($t.Id -eq $Task.Id) { $out += $Task; $replaced = $true }
        else { $out += $t }
    }
    if (-not $replaced) { $out += $Task }
    Save-Tasks -Tasks $out -Path $Path
    return $Task
}

function Complete-Task {
    param([Parameter(Mandatory = $true)][string]$Id, [string]$Path = (Get-TaskStorePath), [datetime]$Now = (Get-Date))
    $tasks = @(Get-Tasks -Path $Path)
    $found = $null
    foreach ($t in $tasks) {
        if ($t.Id -eq $Id) { $t.Statut = 'Termine'; $t.TermineLe = $Now.ToString('s'); $found = $t }
    }
    Save-Tasks -Tasks $tasks -Path $Path
    return $found
}

function Archive-Task {
    param([Parameter(Mandatory = $true)][string]$Id, [string]$Path = (Get-TaskStorePath))
    $tasks = @(Get-Tasks -Path $Path)
    $found = $null
    foreach ($t in $tasks) { if ($t.Id -eq $Id) { $t.Statut = 'Archive'; $found = $t } }
    Save-Tasks -Tasks $tasks -Path $Path
    return $found
}

function Remove-Task {
    param([Parameter(Mandatory = $true)][string]$Id, [string]$Path = (Get-TaskStorePath))
    $tasks = @(Get-Tasks -Path $Path)
    $out = @($tasks | Where-Object { $_.Id -ne $Id })
    Save-Tasks -Tasks $out -Path $Path
}

function Set-TaskNotified {
    param([Parameter(Mandatory = $true)][string]$Id, [string]$Path = (Get-TaskStorePath), [datetime]$Now = (Get-Date))
    $tasks = @(Get-Tasks -Path $Path)
    foreach ($t in $tasks) { if ($t.Id -eq $Id) { $t.NotifieLe = $Now.ToString('yyyy-MM-dd') } }
    Save-Tasks -Tasks $tasks -Path $Path
}

function Set-TaskEstimate {
    param([Parameter(Mandatory = $true)][string]$Id, [int]$Minutes, [string]$Path = (Get-TaskStorePath))
    $tasks = @(Get-Tasks -Path $Path)
    foreach ($t in $tasks) {
        if ($t.Id -eq $Id) { $t | Add-Member -NotePropertyName EstimeMinutes -NotePropertyValue $Minutes -Force }
    }
    Save-Tasks -Tasks $tasks -Path $Path
}

function Add-TaskSession {
    # Persist a finished work-session result (from Session.Core\Get-SessionResult):
    # appends a session record and increments the task's cumulative time totals.
    # Tolerant of tasks created before this feature (missing fields coalesce to 0/@()).
    param([Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)][object]$Result, [string]$Path = (Get-TaskStorePath))
    $tasks = @(Get-Tasks -Path $Path)
    $found = $null
    foreach ($t in $tasks) {
        if ($t.Id -eq $Id) {
            $work = [int]$t.TempsTravailSecondes + [int]$Result.TravailSecondes   # [int]$null -> 0
            $glob = [int]$t.TempsGlobalSecondes  + [int]$Result.GlobalSecondes
            # Direct @() assignment (NOT via an if-block, whose output would unwrap a
            # single-element array back to a scalar and break the += below).
            $sessions = @()
            if ($t.Sessions) { $sessions = @($t.Sessions) }
            $sessions += [PSCustomObject]@{
                Debut           = $Result.Debut
                Fin             = $Result.Fin
                TravailSecondes = [int]$Result.TravailSecondes
                GlobalSecondes  = [int]$Result.GlobalSecondes
                PauseSecondes   = [int]$Result.PauseSecondes
                PomodorosFait   = [int]$Result.PomodorosFait
            }
            $t | Add-Member -NotePropertyName TempsTravailSecondes -NotePropertyValue $work     -Force
            $t | Add-Member -NotePropertyName TempsGlobalSecondes  -NotePropertyValue $glob     -Force
            $t | Add-Member -NotePropertyName Sessions             -NotePropertyValue $sessions -Force
            $found = $t
        }
    }
    Save-Tasks -Tasks $tasks -Path $Path
    return $found
}

function Get-TaskTools {
    # Pure: the allow-list of process names for a task (tolerant of missing field).
    param([object]$Task)
    if ($Task.OutilsTache) { return @($Task.OutilsTache) }
    return @()
}

function Test-TaskToolAllowed {
    # Pure: is a process already on the task's allow-list? (case-insensitive)
    param([object]$Task, [string]$Process)
    if ([string]::IsNullOrWhiteSpace($Process)) { return $true }
    $p = $Process.ToLowerInvariant()
    foreach ($a in (Get-TaskTools -Task $Task)) {
        if ([string]$a -and ($p -eq ([string]$a).ToLowerInvariant())) { return $true }
    }
    return $false
}

function Add-TaskTool {
    # Append a process to the task's allow-list (dedup, case-insensitive). Tolerant of
    # tasks created before this feature.
    param([Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)][string]$Process, [string]$Path = (Get-TaskStorePath))
    $tasks = @(Get-Tasks -Path $Path)
    $found = $null
    foreach ($t in $tasks) {
        if ($t.Id -eq $Id) {
            # Direct @() assignment (NOT via an if-block, which would unwrap a single
            # element and break += ), mirroring Add-TaskSession.
            $tools = @()
            if ($t.OutilsTache) { $tools = @($t.OutilsTache) }
            $exists = $false
            foreach ($x in $tools) { if ([string]$x -and (([string]$x).ToLowerInvariant() -eq $Process.ToLowerInvariant())) { $exists = $true } }
            if (-not $exists) { $tools += $Process }
            $t | Add-Member -NotePropertyName OutilsTache -NotePropertyValue $tools -Force
            $found = $t
        }
    }
    Save-Tasks -Tasks $tasks -Path $Path
    return $found
}

function Add-TaskDigression {
    # Increment the task's digression counter (user answered "Non" to the focus guard).
    param([Parameter(Mandatory = $true)][string]$Id, [string]$Path = (Get-TaskStorePath))
    $tasks = @(Get-Tasks -Path $Path)
    foreach ($t in $tasks) {
        if ($t.Id -eq $Id) {
            $t | Add-Member -NotePropertyName DigressionsCount -NotePropertyValue ([int]$t.DigressionsCount + 1) -Force
        }
    }
    Save-Tasks -Tasks $tasks -Path $Path
}

function Get-TaskEfficiency {
    # Pure: compare actual work time against the estimate. Ratio > 1 = under budget.
    param([object]$Task)
    $estMin  = [int]$Task.EstimeMinutes
    $workMin = [math]::Round(([int]$Task.TempsTravailSecondes) / 60, 1)
    $ecart   = [math]::Round($workMin - $estMin, 1)
    $ratio   = if ($workMin -gt 0 -and $estMin -gt 0) { [math]::Round($estMin / $workMin, 2) } else { $null }
    return [ordered]@{
        EstimeMin   = $estMin
        TravailMin  = $workMin
        EcartMin    = $ecart
        Ratio       = $ratio
        HasEstimate = ($estMin -gt 0)
    }
}

# ---- Queries (pure: operate on an in-memory task array) --------------------
function Get-DueReminders {
    param([object[]]$Tasks, [datetime]$Now = (Get-Date))
    $today = $Now.ToString('yyyy-MM-dd')
    $due = @()
    foreach ($t in @($Tasks)) {
        if ($t.Statut -in $script:ClosedStatuts) { continue }
        $rs = ConvertFrom-IsoDate $t.RappelSoir
        if ($null -eq $rs) { continue }
        # The reminder's start datetime must have passed (respects future-dated reminders)...
        if ($rs -gt $Now) { continue }
        # ...and it must be past the reminder's time-of-day TODAY, so the daily recurrence
        # fires in the evening (at RappelSoir's hour) rather than at midnight rollover.
        if ($Now.TimeOfDay -lt $rs.TimeOfDay) { continue }
        if ([string]$t.NotifieLe -eq $today) { continue }   # already fired today -> daily recurrence
        $due += $t
    }
    return @($due)
}

function Get-TaskSummary {
    param([object[]]$Tasks, [datetime]$Now = (Get-Date))
    $today = $Now.ToString('yyyy-MM-dd')
    $all = @($Tasks)

    $afaire    = @($all | Where-Object { $_.Statut -eq 'A_faire' }).Count
    $encours   = @($all | Where-Object { $_.Statut -eq 'En_cours' }).Count
    $enattente = @($all | Where-Object { $_.Statut -eq 'En_attente' }).Count
    $termAuj   = @($all | Where-Object {
            $_.Statut -eq 'Termine' -and $_.TermineLe -and
            ((ConvertFrom-IsoDate $_.TermineLe).ToString('yyyy-MM-dd') -eq $today)
        }).Count
    $retard = @($all | Where-Object {
            ($_.Statut -notin $script:ClosedStatuts) -and $_.DateEcheance -and
            ((ConvertFrom-IsoDate $_.DateEcheance) -lt $Now)
        })

    # Session-aware metrics: work done today + tasks that ran over their estimate.
    $workTodaySec = 0
    foreach ($t in $all) {
        if ($t.Sessions) {
            foreach ($s in @($t.Sessions)) {
                $fin = ConvertFrom-IsoDate $s.Fin
                if ($fin -and ($fin.ToString('yyyy-MM-dd') -eq $today)) { $workTodaySec += [int]$s.TravailSecondes }
            }
        }
    }
    $depassement = @($all | Where-Object {
            ([int]$_.EstimeMinutes) -gt 0 -and ((([int]$_.TempsTravailSecondes) / 60.0) -gt [int]$_.EstimeMinutes)
        }).Count

    return [ordered]@{
        AFaire              = $afaire
        EnCours             = $encours
        EnAttente           = $enattente
        TermineesAujourdhui = $termAuj
        EnRetard            = $retard.Count
        EnRetardTitres      = @($retard | ForEach-Object { $_.Titre })
        TempsTravailJourMin = [math]::Round($workTodaySec / 60, 1)
        EnDepassement       = $depassement
    }
}

# ---- Seed ------------------------------------------------------------------
function Initialize-TaskSeed {
    param([string]$Path = (Get-TaskStorePath), [datetime]$Now = (Get-Date))

    $existing = @(Get-Tasks -Path $Path)
    if ($existing.Count -gt 0) { return 0 }

    # "RappelSoir": "20:00" from the seed spec -> today at 20:00 local.
    $eve = [datetime]::new($Now.Year, $Now.Month, $Now.Day, 20, 0, 0)

    $seed = @(
        New-Task -Titre 'Appeler aide ménagère (Sikensi)' `
            -Description 'De la part de Kobenan. Fixer un RDV et connaître son tarif mensuel.' `
            -Categorie 'Appels' -Contact '07 00 74 99 71' -Priorite Normale -Statut A_faire -RappelSoir $eve

        New-Task -Titre 'Coach Hassan - charançons vivants' `
            -Description "Clodile Dokolé veut 1 kg de charançons vivants. Vérifier si c'est possible." `
            -Categorie 'Appels' -Contact 'Coach Hassan - 07 78 39 88 02' -Priorite Normale -Statut A_faire -RappelSoir $eve

        New-Task -Titre 'Répondre à M. Konan' `
            -Description 'Message déjà rédigé (voir Notes).' `
            -Categorie 'AWEMA/Clients' -Contact 'M. Konan (docteur)' -Priorite Normale -Statut En_attente `
            -Bloquee_par 'MAJ du site + vérification via checklist' `
            -Notes "Bonsoir Docteur, j'espère que vous allez bien. Nous avons essayé, mais la charge de travail que cela représente nous a découragés face à l'investissement que les organisations sont prêtes à faire. Il est difficile de trouver un équilibre, et je me retrouve donc à devoir assumer seul une grande partie de cette charge. Pour l'instant, j'ai arrêté de le proposer, le temps de trouver la bonne formule. Concernant les mises à jour, je vous invite à visiter le site pour voir si cela vous convient."

        New-Task -Titre 'Devis installation Windows (restaurant)' `
            -Description 'Produire le devis pour l''installation de Windows dans un restaurant. Joindre le devis caméras de sécurité déjà produit.' `
            -Categorie 'AWEMA/Clients' -Priorite Haute -Statut A_faire

        New-Task -Titre 'Branding e-shop pour Daniel' `
            -Description 'Travail de branding pour le e-shop de Daniel.' `
            -Categorie 'AWEMA/Clients' -Contact 'Daniel' -Priorite Normale -Statut A_faire

        New-Task -Titre 'Retours Malaika - resto Mama Rose' `
            -Description 'Prendre les retours de Malaika concernant le restaurant chez Mama Rose.' `
            -Categorie 'AWEMA/Clients' -Projet 'Mama Rose' -Contact 'Malaika' -Priorite Normale -Statut A_faire

        New-Task -Titre 'Planification tournages - La Grande Vision' `
            -Description 'Terminer la planification des tournages.' `
            -Categorie 'Ciné Light Studio' -Projet 'La Grande Vision' -Priorite Haute -Statut En_cours

        New-Task -Titre 'Sujets réunion HOLYGOD TV' `
            -Description 'Planifier les sujets à aborder pour la réunion.' `
            -Categorie 'HOLYGOD TV' -Priorite Normale -Statut A_faire
    )

    Save-Tasks -Tasks $seed -Path $Path
    return $seed.Count
}

Export-ModuleMember -Function `
    Get-TaskStorePath, Get-Tasks, Save-Tasks, New-Task, `
    Add-Task, Update-Task, Complete-Task, Archive-Task, Remove-Task, `
    Set-TaskNotified, Get-DueReminders, Get-TaskSummary, Initialize-TaskSeed, `
    Set-TaskEstimate, Add-TaskSession, Get-TaskEfficiency, `
    Get-TaskTools, Test-TaskToolAllowed, Add-TaskTool, Add-TaskDigression, `
    ConvertTo-IsoDate, ConvertFrom-IsoDate
