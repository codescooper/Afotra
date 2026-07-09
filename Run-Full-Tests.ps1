# Run-Full-Tests.ps1 - Suite de tests COMPLETE couvrant tous les cas d'usage AFOTRA.
# Author: CodeScooper (+ verification)
#
# Couvre : config/rules, toute la logique de classification (categories +
# priorites navigateur/process/titre + casse), gestion des regles (round-trip),
# journalisation (idempotence/colonnes), reporting (math + cas limites) et
# bout-en-bout (CLI -Check, tracker live, daily-report, dashboard WPF, XAML).
#
# Produit un rapport Markdown : TEST_REPORT.md
# Exit code 0 = tout vert, 1 = au moins un echec.
# -SkipLive : saute les tests necessitant un bureau interactif (CI headless).

param([switch]$SkipLive)

$ErrorActionPreference = "Stop"
$root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

$script:Results = @()
$script:Group   = ""

function Assert($cond, $msg) { if (-not $cond) { throw $msg } }

# Marque un test comme saute (affiche, jamais silencieux ; ne compte pas en echec).
function Skip {
    param([string]$Name, [string]$Reason)
    $script:Results += [PSCustomObject]@{ Group=$script:Group; Status="SKIP"; Name=$Name; Detail=$Reason }
    Write-Host ("  [SKIP] {0,-52} {1}" -f $Name, $Reason) -ForegroundColor DarkYellow
}

function Check {
    param([string]$Name, [scriptblock]$Test)
    try {
        $detail = & $Test
        $script:Results += [PSCustomObject]@{ Group=$script:Group; Status="PASS"; Name=$Name; Detail=[string]$detail }
        Write-Host ("  [PASS] {0,-52} {1}" -f $Name, $detail) -ForegroundColor Green
    }
    catch {
        $script:Results += [PSCustomObject]@{ Group=$script:Group; Status="FAIL"; Name=$Name; Detail=$_.Exception.Message }
        Write-Host ("  [FAIL] {0,-52} {1}" -f $Name, $_.Exception.Message) -ForegroundColor Red
    }
}
# NB: ne PAS nommer cette fonction "Group" : c'est l'alias de Group-Object, qui
# a priorite sur les fonctions et l'aurait masquee (la section serait restee vide).
function Section($title) { $script:Group = $title; Write-Host "`n[$title]" -ForegroundColor Yellow }

Write-Host "`n=== AFOTRA - Suite de tests COMPLETE ===" -ForegroundColor Cyan
Write-Host "Root: $root" -ForegroundColor DarkGray

Import-Module (Join-Path $root "modules\Tracker.Core.psm1") -Force
Import-Module (Join-Path $root "modules\Rules.Core.psm1")   -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $root "modules\Report.Core.psm1")  -Force
Import-Module (Join-Path $root "modules\Tasks.Core.psm1")   -Force -DisableNameChecking
Import-Module (Join-Path $root "modules\Notify.Core.psm1")  -Force -DisableNameChecking
Import-Module (Join-Path $root "modules\Session.Core.psm1") -Force -DisableNameChecking
Import-Module (Join-Path $root "modules\Orb.Core.psm1")     -Force -DisableNameChecking
$rules = Load-Rules -RulesPath (Join-Path $root "rules.json")

function New-TempStore { Join-Path $env:TEMP ("afotra_test_" + [guid]::NewGuid().ToString('N') + ".json") }

# ===================================================================
Section "A. Configuration & regles"
Check "config.json valide et coherent" {
    $c = Get-Content (Join-Path $root "config.json") -Encoding UTF8 | ConvertFrom-Json
    Assert ($c.sampleIntervalSeconds -ge 1) "intervalle invalide"
    Assert ($c.focusMinPerDay -gt 0) "focusMinPerDay invalide"
    Assert ($null -ne $c.logFolder) "logFolder manquant"
    "interval=$($c.sampleIntervalSeconds)s, focus=$($c.focusMinPerDay)min"
}
Check "rules.json : categories + regles presentes" {
    Assert ($rules.categories.Count -ge 5) "categories insuffisantes"
    Assert ($rules.processRules.Count -gt 0) "aucune regle process"
    Assert ($rules.titleRules.Count -gt 0) "aucune regle titre"
    "$($rules.categories.Count) cats / $($rules.processRules.Count) proc / $($rules.titleRules.Count) titre"
}
Check "toutes les regles referencent une categorie connue" {
    $cats = @($rules.categories)
    $bad = @()
    foreach ($r in $rules.processRules) { if ($cats -notcontains $r.category) { $bad += "proc:$($r.process)->$($r.category)" } }
    foreach ($r in $rules.titleRules)   { if ($cats -notcontains $r.category) { $bad += "title:$($r.contains)->$($r.category)" } }
    Assert ($bad.Count -eq 0) "categories inconnues: $($bad -join ', ')"
    "0 categorie orpheline"
}

# ===================================================================
Section "B. Classification - categories"
Check "process travail (Code) -> travail" {
    $c = Classify-Activity -ProcessName "Code" -WindowTitle "x.ps1 - Visual Studio Code" -Rules $rules
    Assert ($c -eq "travail") "got '$c'"; $c }
Check "process communication (Teams) -> communication" {
    $c = Classify-Activity -ProcessName "Teams" -WindowTitle "Reunion" -Rules $rules
    Assert ($c -eq "communication") "got '$c'"; $c }
Check "process communication (slack) -> communication" {
    $c = Classify-Activity -ProcessName "slack" -WindowTitle "general" -Rules $rules
    Assert ($c -eq "communication") "got '$c'"; $c }
Check "process distraction (Spotify) -> distraction" {
    $c = Classify-Activity -ProcessName "Spotify" -WindowTitle "Playlist" -Rules $rules
    Assert ($c -eq "distraction") "got '$c'"; $c }
Check "process non mappe + titre sans regle -> inconnu" {
    $c = Classify-Activity -ProcessName "zz_nomatch_999" -WindowTitle "qqzz_nomatch_999" -Rules $rules
    Assert ($c -eq "inconnu") "got '$c'"; $c }

Section "B. Classification - priorites (navigateur / process / titre)"
Check "navigateur : titre YouTube bat process chrome -> distraction" {
    $c = Classify-Activity -ProcessName "chrome" -WindowTitle "Une video - YouTube - Google Chrome" -Rules $rules
    Assert ($c -eq "distraction") "got '$c'"; $c }
Check "navigateur : titre Udemy -> etude" {
    $c = Classify-Activity -ProcessName "msedge" -WindowTitle "Cours - Udemy" -Rules $rules
    Assert ($c -eq "etude") "got '$c'"; $c }
Check "navigateur : titre Gmail -> communication" {
    $c = Classify-Activity -ProcessName "chrome" -WindowTitle "Boite de reception - Gmail" -Rules $rules
    Assert ($c -eq "communication") "got '$c'"; $c }
Check "navigateur : titre GitHub -> travail" {
    $c = Classify-Activity -ProcessName "chrome" -WindowTitle "repo - GitHub" -Rules $rules
    Assert ($c -eq "travail") "got '$c'"; $c }
Check "navigateur : aucun titre connu -> fallback process (travail)" {
    $c = Classify-Activity -ProcessName "chrome" -WindowTitle "Outil interne sans regle" -Rules $rules
    Assert ($c -eq "travail") "got '$c'"; $c }
Check "non-navigateur : process prioritaire sur titre (Code + 'YouTube' -> travail)" {
    $c = Classify-Activity -ProcessName "Code" -WindowTitle "watch YouTube" -Rules $rules
    Assert ($c -eq "travail") "got '$c'"; $c }
Check "non-navigateur non mappe : regle de titre s'applique (Udemy -> etude)" {
    $c = Classify-Activity -ProcessName "someApp_xyz" -WindowTitle "Lesson - Udemy" -Rules $rules
    Assert ($c -eq "etude") "got '$c'"; $c }
Check "correspondance titre insensible a la casse ('youtube' -> distraction)" {
    $c = Classify-Activity -ProcessName "chrome" -WindowTitle "regarder youtube maintenant" -Rules $rules
    Assert ($c -eq "distraction") "got '$c'"; $c }

# ===================================================================
Section "C. Gestion des regles (round-trip)"
Check "Get-Categories renvoie la liste" {
    $cats = Get-Categories -Rules $rules
    Assert ($cats.Count -ge 5) "trop peu de categories"; "$($cats.Count) categories" }
Check "Add-Category : nouvelle=true, doublon=false" {
    $r = Load-Rules -RulesPath (Join-Path $root "rules.json")
    $added = Add-Category -Rules $r -Category "sport_test"
    $dup   = Add-Category -Rules $r -Category "travail"
    Assert ($added -eq $true) "ajout nouvelle categorie a echoue"
    Assert ($dup -eq $false) "doublon aurait du renvoyer false"
    "ajout=$added, doublon=$dup" }
Check "Add-ProcessRule / Add-TitleRule augmentent les compteurs" {
    $r = Load-Rules -RulesPath (Join-Path $root "rules.json")
    $p0 = $r.processRules.Count; $t0 = $r.titleRules.Count
    Add-ProcessRule -Rules $r -Process "monApp_test" -Category "travail"
    Add-TitleRule   -Rules $r -Contains "MonSite_test" -Category "etude"
    Assert ($r.processRules.Count -eq $p0 + 1) "process rule non ajoutee"
    Assert ($r.titleRules.Count   -eq $t0 + 1) "title rule non ajoutee"
    "proc $p0->$($r.processRules.Count), title $t0->$($r.titleRules.Count)" }
Check "Save-Rules + Load-Rules : persistance fidele" {
    $r = Load-Rules -RulesPath (Join-Path $root "rules.json")
    Add-Category -Rules $r -Category "persist_test" | Out-Null
    Add-ProcessRule -Rules $r -Process "persist_proc" -Category "travail"
    $tmp = Join-Path $env:TEMP ("afotra_rules_{0}.json" -f (Get-Date -Format 'yyyyMMddHHmmssfff'))
    Save-Rules -Rules $r -RulesPath $tmp
    $back = Load-Rules -RulesPath $tmp
    Remove-Item $tmp -ErrorAction SilentlyContinue
    Assert ($back.categories -contains "persist_test") "categorie non persistee"
    # @() obligatoire : Where-Object peut renvoyer un scalaire, et .Count sur un
    # PSCustomObject unique renvoie vide en PowerShell 5.1.
    Assert ((@($back.processRules | Where-Object { $_.process -eq "persist_proc" })).Count -eq 1) "regle non persistee"
    # La regle rechargee doit aussi etre fonctionnelle
    $c = Classify-Activity -ProcessName "persist_proc" -WindowTitle "x" -Rules $back
    Assert ($c -eq "travail") "regle rechargee inactive (got '$c')"
    "round-trip OK + regle active" }

# ===================================================================
Section "D. Journalisation (logging)"
Check "Get-TodayLogFile : format activity-YYYY-MM-DD.csv" {
    $f = Get-TodayLogFile -LogFolder "logs"
    $expected = "activity-{0}.csv" -f (Get-Date -Format 'yyyy-MM-dd')
    Assert ((Split-Path $f -Leaf) -eq $expected) "got $(Split-Path $f -Leaf)"
    Split-Path $f -Leaf }
Check "Initialize-LogFile : entete ecrite une seule fois (idempotent)" {
    $tmp = Join-Path $env:TEMP ("afotra_init_{0}.csv" -f (Get-Date -Format 'yyyyMMddHHmmssfff'))
    Initialize-LogFile -LogFile $tmp
    Initialize-LogFile -LogFile $tmp   # 2e appel ne doit PAS dupliquer l'entete
    $lines = @(Get-Content $tmp)
    Remove-Item $tmp -ErrorAction SilentlyContinue
    Assert ($lines.Count -eq 1) "entete dupliquee: $($lines.Count) lignes"
    Assert ($lines[0] -like "Timestamp,*Category*") "entete incorrecte"
    "1 ligne d'entete" }
Check "Write-ActivityLog : 10 colonnes dans le bon ordre" {
    $tmp = Join-Path $env:TEMP ("afotra_w_{0}.csv" -f (Get-Date -Format 'yyyyMMddHHmmssfff'))
    Initialize-LogFile -LogFile $tmp
    Write-ActivityLog -LogFile $tmp -ActivityInfo ([PSCustomObject]@{ProcessName="UnitApp";ProcessId=42;WindowTitle="Titre";Category="travail"}) -SampleSeconds 5
    $row = @(Import-Csv $tmp -Encoding UTF8)[0]
    Remove-Item $tmp -ErrorAction SilentlyContinue
    Assert ($row.ProcessName -eq "UnitApp") "ProcessName errone"
    Assert ($row.ProcessId -eq "42") "ProcessId errone"
    Assert ($row.Category -eq "travail") "Category erronee"
    Assert ($row.SampleSeconds -eq "5") "SampleSeconds errone"
    Assert ($row.UserName -eq $env:USERNAME) "UserName errone"
    "colonnes & valeurs OK" }

# ===================================================================
Section "E. Reporting (math + cas limites)"
Check "Get-ReportData : focus score, total, switches, categories" {
    $tmp = Join-Path $env:TEMP ("afotra_rd_{0}.csv" -f (Get-Date -Format 'yyyyMMddHHmmssfff'))
    Initialize-LogFile -LogFile $tmp
    1..7 | ForEach-Object { Write-ActivityLog -LogFile $tmp -ActivityInfo ([PSCustomObject]@{ProcessName="Code";ProcessId=1;WindowTitle="w$_";Category="travail"}) -SampleSeconds 10 }
    1..3 | ForEach-Object { Write-ActivityLog -LogFile $tmp -ActivityInfo ([PSCustomObject]@{ProcessName="game";ProcessId=2;WindowTitle="g";Category="distraction"}) -SampleSeconds 10 }
    $rd = Get-ReportData -LogFile $tmp
    Remove-Item $tmp -ErrorAction SilentlyContinue
    Assert ($rd.TotalSeconds -eq 100) "total=$($rd.TotalSeconds)"
    Assert ($rd.FocusScore -eq 70) "focus=$($rd.FocusScore)"
    Assert ($rd.Categories["travail"] -eq 70) "travail=$($rd.Categories['travail'])"
    Assert ($rd.Categories["distraction"] -eq 30) "distraction=$($rd.Categories['distraction'])"
    # 7 transitions : w1..w7 (6 bascules) puis w7->g (1) ; g->g->g = 0.
    Assert ($rd.ContextSwitches -eq 7) "switches=$($rd.ContextSwitches) (attendu 7 transitions)"
    "total=100s focus=70% switches=7" }
Check "Get-ReportData : agrege les 'inconnu' (Unknowns)" {
    $tmp = Join-Path $env:TEMP ("afotra_uk_{0}.csv" -f (Get-Date -Format 'yyyyMMddHHmmssfff'))
    Initialize-LogFile -LogFile $tmp
    1..4 | ForEach-Object { Write-ActivityLog -LogFile $tmp -ActivityInfo ([PSCustomObject]@{ProcessName="mystery";ProcessId=9;WindowTitle="boite";Category="inconnu"}) -SampleSeconds 5 }
    $rd = Get-ReportData -LogFile $tmp
    Remove-Item $tmp -ErrorAction SilentlyContinue
    $k = "mystery|boite"
    Assert ($rd.Unknowns[$k].Count -eq 4) "count=$($rd.Unknowns[$k].Count)"
    Assert ($rd.Unknowns[$k].Seconds -eq 20) "sec=$($rd.Unknowns[$k].Seconds)"
    "inconnu agrege: 4 occ / 20s" }
Check "Get-ReportData : fichier inexistant -> null" {
    $rd = Get-ReportData -LogFile (Join-Path $env:TEMP "afotra_nope_zzz.csv")
    Assert ($null -eq $rd) "devrait etre null"; "null OK" }
Check "Get-ReportData : fichier vide (entete seule) -> null" {
    $tmp = Join-Path $env:TEMP ("afotra_empty_{0}.csv" -f (Get-Date -Format 'yyyyMMddHHmmssfff'))
    Initialize-LogFile -LogFile $tmp
    $rd = Get-ReportData -LogFile $tmp
    Remove-Item $tmp -ErrorAction SilentlyContinue
    Assert ($null -eq $rd) "devrait etre null"; "null OK" }
Check "Export-ReportToJSON : fichier + champs cles" {
    $tmp = Join-Path $env:TEMP ("afotra_ej_{0}.csv" -f (Get-Date -Format 'yyyyMMddHHmmssfff'))
    Initialize-LogFile -LogFile $tmp
    1..6 | ForEach-Object { Write-ActivityLog -LogFile $tmp -ActivityInfo ([PSCustomObject]@{ProcessName="Code";ProcessId=1;WindowTitle="w";Category="travail"}) -SampleSeconds 10 }
    1..2 | ForEach-Object { Write-ActivityLog -LogFile $tmp -ActivityInfo ([PSCustomObject]@{ProcessName="game";ProcessId=2;WindowTitle="g";Category="distraction"}) -SampleSeconds 10 }
    $rd = Get-ReportData -LogFile $tmp
    $json = Join-Path $env:TEMP ("afotra_sj_{0}.json" -f (Get-Date -Format 'yyyyMMddHHmmssfff'))
    Export-ReportToJSON -ReportData $rd -OutputFile $json
    $obj = Get-Content $json -Raw | ConvertFrom-Json
    Remove-Item $tmp,$json -ErrorAction SilentlyContinue
    Assert ($obj.TotalTrackedMinutes -gt 0) "TotalTrackedMinutes absent"
    Assert ($null -ne $obj.FocusScore) "FocusScore absent"
    Assert ($obj.DistractionMinutes -gt 0) "DistractionMinutes absent"
    Assert ($null -ne $obj.TopProcesses) "TopProcesses absent"
    "json: focus=$($obj.FocusScore)% distraction=$($obj.DistractionMinutes)min" }
Check "Export-ReportToJSON : TopProcesses limite a 5" {
    $tmp = Join-Path $env:TEMP ("afotra_tp_{0}.csv" -f (Get-Date -Format 'yyyyMMddHHmmssfff'))
    Initialize-LogFile -LogFile $tmp
    1..8 | ForEach-Object { Write-ActivityLog -LogFile $tmp -ActivityInfo ([PSCustomObject]@{ProcessName=("proc$_");ProcessId=$_;WindowTitle="w";Category="travail"}) -SampleSeconds 5 }
    $rd = Get-ReportData -LogFile $tmp
    $json = Join-Path $env:TEMP ("afotra_tp_{0}.json" -f (Get-Date -Format 'yyyyMMddHHmmssfff'))
    Export-ReportToJSON -ReportData $rd -OutputFile $json
    $obj = Get-Content $json -Raw | ConvertFrom-Json
    Remove-Item $tmp,$json -ErrorAction SilentlyContinue
    $count = ($obj.TopProcesses.PSObject.Properties | Measure-Object).Count
    Assert ($count -le 5) "TopProcesses=$count (>5)"
    "TopProcesses=$count (<=5 sur 8 process)" }
Check "Get-UnknownActivities : regroupe par process inconnu" {
    $tmp = Join-Path $env:TEMP ("afotra_ua_{0}.csv" -f (Get-Date -Format 'yyyyMMddHHmmssfff'))
    Initialize-LogFile -LogFile $tmp
    1..3 | ForEach-Object { Write-ActivityLog -LogFile $tmp -ActivityInfo ([PSCustomObject]@{ProcessName="weird";ProcessId=7;WindowTitle="t";Category="inconnu"}) -SampleSeconds 5 }
    Write-ActivityLog -LogFile $tmp -ActivityInfo ([PSCustomObject]@{ProcessName="Code";ProcessId=1;WindowTitle="w";Category="travail"}) -SampleSeconds 5
    $u = @(Get-UnknownActivities -LogFile $tmp)
    Remove-Item $tmp -ErrorAction SilentlyContinue
    $weird = $u | Where-Object { $_.ProcessName -eq "weird" }
    Assert ($null -ne $weird) "process inconnu absent"
    Assert ($weird.Count -eq 3) "count=$($weird.Count)"
    "weird x3 detecte, travail exclu" }

# ===================================================================
Section "F. Bout-en-bout (CLI / live / dashboard)"
Check "tracker.ps1 -Check : exit 1 quand non lance" {
    $p = Start-Process powershell -ArgumentList '-NoProfile','-File',"`"$(Join-Path $root 'tracker.ps1')`"",'-Check' -PassThru -Wait -WindowStyle Hidden
    Assert ($p.ExitCode -eq 1) "exit code=$($p.ExitCode) (attendu 1)"
    "exit=1 (correct : aucun tracker actif)" }
if ($SkipLive) {
    Skip "tracker.ps1 : ecrit reellement des lignes en cours d'execution" "requiert un bureau interactif (fenetre active)"
    Skip "daily-report.ps1 : genere le summary JSON du jour" "depend de donnees live du jour (saute avec tracker live)"
} else {
Check "tracker.ps1 : ecrit reellement des lignes en cours d'execution" {
    $logFile = Join-Path $root ("logs\activity-{0}.csv" -f (Get-Date -Format 'yyyy-MM-dd'))
    $before = if (Test-Path $logFile) { (@(Get-Content $logFile)).Count } else { 0 }
    $p = Start-Process powershell -ArgumentList '-NoProfile','-File',"`"$(Join-Path $root 'tracker.ps1')`"" -PassThru -RedirectStandardError (Join-Path $env:TEMP "afotra_trk_err.log") -RedirectStandardOutput (Join-Path $env:TEMP "afotra_trk_out.log") -WindowStyle Hidden
    Start-Sleep -Seconds 13
    $after = (@(Get-Content $logFile)).Count
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $root "tracker.lock") -ErrorAction SilentlyContinue  # finally non execute apres un kill
    Assert ($after -gt $before) "aucune ligne ajoutee (before=$before after=$after)"
    "ajout de $($after-$before) ligne(s) en 13s" }
Check "daily-report.ps1 : genere le summary JSON du jour" {
    $p = Start-Process powershell -ArgumentList '-NoProfile','-File',"`"$(Join-Path $root 'daily-report.ps1')`"" -PassThru -Wait -WindowStyle Hidden -RedirectStandardOutput (Join-Path $env:TEMP "afotra_rep_out.log") -RedirectStandardError (Join-Path $env:TEMP "afotra_rep_err.log")
    $json = Join-Path $root ("logs\reports\summary-{0}.json" -f (Get-Date -Format 'yyyy-MM-dd'))
    Assert ($p.ExitCode -eq 0) "exit=$($p.ExitCode)"
    Assert (Test-Path $json) "summary JSON non genere"
    $obj = Get-Content $json -Raw | ConvertFrom-Json
    Assert ($null -ne $obj.FocusScore) "FocusScore absent du rapport"
    "rapport genere (focus=$($obj.FocusScore)%)" }
}
Check "dashboard-wpf.ps1 : XAML (fenetre principale + overlay) parse" {
    Add-Type -AssemblyName PresentationFramework
    $src = Get-Content (Join-Path $root "dashboard-wpf.ps1") -Raw
    $n = 0
    foreach ($pat in @('\$xaml = @"\r?\n(.*?)\r?\n"@','\$overlayXaml = @"\r?\n(.*?)\r?\n"@')) {
        $mm = [regex]::Match($src, $pat, [System.Text.RegularExpressions.RegexOptions]::Singleline)
        Assert $mm.Success "bloc XAML introuvable"
        $rdr = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($mm.Groups[1].Value))
        $w = [Windows.Markup.XamlReader]::Load($rdr)
        Assert ($w -is [System.Windows.Window]) "n'a pas produit de Window"
        $w.Close(); $n++
    }
    Assert ($n -eq 2) "seulement $n/2 fenetres"
    "$n/2 fenetres XAML valides" }
if ($SkipLive) { Skip "dashboard-wpf.ps1 : se lance et affiche sa fenetre WPF" "requiert un bureau interactif (fenetre WPF)" } else {
Check "dashboard-wpf.ps1 : se lance et affiche sa fenetre WPF" {
    if (-not ([System.Management.Automation.PSTypeName]'AfotraWinScan').Type) {
        Add-Type -TypeDefinition @"
using System; using System.Text; using System.Runtime.InteropServices;
public class AfotraWinScan {
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr p);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", SetLastError=true)] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    delegate bool EnumProc(IntPtr h, IntPtr p);
    public static string FindTitle(uint targetPid, string needle) {
        string found = null;
        EnumWindows(delegate(IntPtr h, IntPtr p) {
            if (!IsWindowVisible(h)) return true;
            uint pid; GetWindowThreadProcessId(h, out pid);
            if (pid != targetPid) return true;
            StringBuilder sb = new StringBuilder(512); GetWindowText(h, sb, 512);
            string t = sb.ToString();
            if (t.IndexOf(needle, StringComparison.OrdinalIgnoreCase) >= 0) { found = t; return false; }
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
"@
    }
    $eo = Join-Path $env:TEMP "afotra_dashfull_err.log"; "" | Set-Content $eo
    $p = Start-Process powershell -ArgumentList '-NoProfile','-File',"`"$(Join-Path $root 'dashboard-wpf.ps1')`"" -PassThru -RedirectStandardError $eo -RedirectStandardOutput (Join-Path $env:TEMP "afotra_dashfull_out.log") -WindowStyle Hidden
    $title = $null
    for ($i = 0; $i -lt 15 -and -not $title; $i++) {
        Start-Sleep -Seconds 1
        if (-not (Get-Process -Id $p.Id -ErrorAction SilentlyContinue)) { break }
        $title = [AfotraWinScan]::FindTitle([uint32]$p.Id, "AFOTRA")
    }
    $alive = $null -ne (Get-Process -Id $p.Id -ErrorAction SilentlyContinue)
    $err = Get-Content $eo -Raw -ErrorAction SilentlyContinue
    if ($alive) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    Assert $alive "le processus est mort au demarrage. stderr: $err"
    Assert ($title -like "*AFOTRA*") "aucune fenetre AFOTRA visible (title='$title')"
    "fenetre: '$title'" }
}

# ===================================================================
Section "G. Ameliorations (AFK / verrou PID / focus configurable)"
Check "config.json : idleThresholdSeconds + focusCategories presents" {
    $c = Get-Content (Join-Path $root "config.json") -Encoding UTF8 | ConvertFrom-Json
    Assert ($c.idleThresholdSeconds -ge 1) "idleThresholdSeconds absent/invalide"
    Assert ($c.focusCategories.Count -ge 1) "focusCategories absent"
    "idle=$($c.idleThresholdSeconds)s, focus=[$($c.focusCategories -join ',')]" }
Check "rules.json : categorie 'inactif' presente" {
    Assert ($rules.categories -contains "inactif") "categorie inactif manquante"
    "inactif present" }
Check "Get-IdleSeconds renvoie un entier >= 0" {
    $s = Get-IdleSeconds
    Assert ($s -is [int] -and $s -ge 0) "valeur invalide: $s"
    "$s s d'inactivite" }
Check "Get-IsSessionLocked : LockApp -> verrouille, Code -> non" {
    Assert (Get-IsSessionLocked -ActivityInfo ([PSCustomObject]@{ProcessName="LockApp"})) "LockApp non detecte"
    Assert (-not (Get-IsSessionLocked -ActivityInfo ([PSCustomObject]@{ProcessName="Code"}))) "Code faux positif"
    "detection verrou OK" }
Check "Measure-ContextSwitches : compte les transitions (A,A,B,A -> 2)" {
    $r = @("A","A","B","A") | ForEach-Object { [PSCustomObject]@{ WindowTitle = $_ } }
    $n = Measure-ContextSwitches -Rows $r
    Assert ($n -eq 2) "got $n"
    "2 transitions" }
Check "Verrou PID : Set/Test/Remove (PID courant=actif, PID mort=inactif)" {
    $lock = Join-Path $env:TEMP ("afotra_lock_{0}.lock" -f (Get-Date -Format 'yyyyMMddHHmmssfff'))
    Remove-TrackerLock -LockFile $lock
    Assert (-not (Test-TrackerRunning -LockFile $lock)) "verrou absent devrait etre false"
    Set-TrackerLock -LockFile $lock -ProcessId $PID
    Assert (Test-TrackerRunning -LockFile $lock) "PID courant devrait etre actif"
    Set-TrackerLock -LockFile $lock -ProcessId 999999
    Assert (-not (Test-TrackerRunning -LockFile $lock)) "PID mort devrait etre inactif"
    Remove-TrackerLock -LockFile $lock
    Assert (-not (Test-Path $lock)) "verrou non supprime"
    "cycle verrou OK" }
Check "Reporting : focusCategories inclut 'etude'" {
    $tmp = Join-Path $env:TEMP ("afotra_fc_{0}.csv" -f (Get-Date -Format 'yyyyMMddHHmmssfff'))
    Initialize-LogFile -LogFile $tmp
    1..5 | ForEach-Object { Write-ActivityLog -LogFile $tmp -ActivityInfo ([PSCustomObject]@{ProcessName="Code";ProcessId=1;WindowTitle="t$_";Category="travail"}) -SampleSeconds 10 }
    1..5 | ForEach-Object { Write-ActivityLog -LogFile $tmp -ActivityInfo ([PSCustomObject]@{ProcessName="edge";ProcessId=2;WindowTitle="e$_";Category="etude"}) -SampleSeconds 10 }
    $rd = Get-ReportData -LogFile $tmp -FocusCategories @("travail","etude")
    Remove-Item $tmp -ErrorAction SilentlyContinue
    Assert ($rd.FocusScore -eq 100) "focus=$($rd.FocusScore) (attendu 100)"
    "travail+etude = 100% focus" }
Check "Reporting : 'inactif' exclu du temps actif (focus sur actif)" {
    $tmp = Join-Path $env:TEMP ("afotra_idle_{0}.csv" -f (Get-Date -Format 'yyyyMMddHHmmssfff'))
    Initialize-LogFile -LogFile $tmp
    1..5 | ForEach-Object { Write-ActivityLog -LogFile $tmp -ActivityInfo ([PSCustomObject]@{ProcessName="Code";ProcessId=1;WindowTitle="t$_";Category="travail"}) -SampleSeconds 10 }
    1..5 | ForEach-Object { Write-ActivityLog -LogFile $tmp -ActivityInfo ([PSCustomObject]@{ProcessName="idle";ProcessId=0;WindowTitle="afk";Category="inactif"}) -SampleSeconds 10 }
    $rd = Get-ReportData -LogFile $tmp
    Remove-Item $tmp -ErrorAction SilentlyContinue
    Assert ($rd.TotalSeconds -eq 100) "total=$($rd.TotalSeconds)"
    Assert ($rd.ActiveSeconds -eq 50) "actif=$($rd.ActiveSeconds) (attendu 50)"
    Assert ($rd.FocusScore -eq 100) "focus=$($rd.FocusScore) (attendu 100 sur temps actif)"
    "total=100s actif=50s focus=100%" }
if ($SkipLive) { Skip "tracker.ps1 -Check : exit 0 quand lance (via verrou PID)" "demarre un process tracker live" } else {
Check "tracker.ps1 -Check : exit 0 quand lance (via verrou PID)" {
    $lock = Join-Path $root "tracker.lock"
    Remove-Item $lock -ErrorAction SilentlyContinue   # ecarte un verrou orphelin
    $p = Start-Process powershell -ArgumentList '-NoProfile','-File',"`"$(Join-Path $root 'tracker.ps1')`"" -PassThru -RedirectStandardError (Join-Path $env:TEMP "afotra_lk_err.log") -RedirectStandardOutput (Join-Path $env:TEMP "afotra_lk_out.log") -WindowStyle Hidden
    # Attendre que le verrou contienne un PID VIVANT (pas seulement que le fichier existe).
    for ($i = 0; $i -lt 15 -and -not (Test-TrackerRunning -LockFile $lock); $i++) { Start-Sleep -Seconds 1 }
    $chk = Start-Process powershell -ArgumentList '-NoProfile','-File',"`"$(Join-Path $root 'tracker.ps1')`"",'-Check' -PassThru -Wait -WindowStyle Hidden
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    Remove-Item $lock -ErrorAction SilentlyContinue
    Assert ($chk.ExitCode -eq 0) "exit=$($chk.ExitCode) (attendu 0 quand lance)"
    "exit=0 (verrou detecte)" }
}

# ===================================================================
Section "H. Taches (module de gestion & suivi)"

Check "New-Task : GUID + defauts (Statut A_faire, Priorite Normale, CreeLe)" {
    $t = New-Task -Titre "Test"
    Assert ([guid]::TryParse($t.Id, [ref]([guid]::Empty))) "Id non-GUID: $($t.Id)"
    Assert ($t.Statut -eq "A_faire") "statut=$($t.Statut)"
    Assert ($t.Priorite -eq "Normale") "priorite=$($t.Priorite)"
    Assert ($t.CreeLe) "CreeLe manquant"
    Assert ($null -eq $t.TermineLe) "TermineLe devrait etre null"
    "Id=GUID statut=A_faire priorite=Normale" }

Check "Save/Get : ecriture atomique + round-trip fidele" {
    $store = New-TempStore
    $a = New-Task -Titre "Alpha" -Categorie "Appels" -Contact "0102"
    $b = New-Task -Titre "Beta" -Priorite Haute -Statut En_cours
    Save-Tasks -Tasks @($a, $b) -Path $store
    $back = @(Get-Tasks -Path $store)
    Remove-Item "$store*" -ErrorAction SilentlyContinue
    Assert ($back.Count -eq 2) "count=$($back.Count)"
    Assert (($back | Where-Object Titre -eq "Alpha").Contact -eq "0102") "contact perdu"
    Assert (($back | Where-Object Titre -eq "Beta").Priorite -eq "Haute") "priorite perdue"
    "2 taches, champs preserves" }

Check "Save-Tasks : 1 seule tache reste un TABLEAU JSON" {
    $store = New-TempStore
    Save-Tasks -Tasks @((New-Task -Titre "Solo")) -Path $store
    $raw = [System.IO.File]::ReadAllText($store, [System.Text.Encoding]::UTF8)
    Remove-Item "$store*" -ErrorAction SilentlyContinue
    Assert ($raw.TrimStart().StartsWith("[")) "pas un tableau JSON: $($raw.Substring(0,[Math]::Min(20,$raw.Length)))"
    "tableau JSON meme a 1 element" }

Check "Get-Tasks : fichier absent -> tableau vide" {
    $store = New-TempStore
    $r = @(Get-Tasks -Path $store)
    Assert ($r.Count -eq 0) "count=$($r.Count)"
    "absent -> @()" }

Check "Get-Tasks : JSON corrompu -> @() + sauvegarde .bak" {
    $store = New-TempStore
    Set-Content -Path $store -Value "{ ceci n'est pas : du json valide" -Encoding UTF8
    $r = @(Get-Tasks -Path $store)
    $bak = @(Get-ChildItem "$store.*.bak" -ErrorAction SilentlyContinue)
    Remove-Item "$store*" -ErrorAction SilentlyContinue
    Assert ($r.Count -eq 0) "count=$($r.Count)"
    Assert ($bak.Count -ge 1) "aucun .bak cree"
    "corrompu -> @() + .bak" }

Check "Complete-Task : Statut=Termine + TermineLe" {
    $store = New-TempStore
    $t = New-Task -Titre "AFinir"
    Save-Tasks -Tasks @($t) -Path $store
    $now = [datetime]"2026-07-08T15:00:00"
    Complete-Task -Id $t.Id -Path $store -Now $now | Out-Null
    $done = @(Get-Tasks -Path $store)[0]
    Remove-Item "$store*" -ErrorAction SilentlyContinue
    Assert ($done.Statut -eq "Termine") "statut=$($done.Statut)"
    Assert ($done.TermineLe) "TermineLe manquant"
    "Termine + TermineLe pose" }

Check "Archive-Task : Statut=Archive" {
    $store = New-TempStore
    $t = New-Task -Titre "AArchiver"
    Save-Tasks -Tasks @($t) -Path $store
    Archive-Task -Id $t.Id -Path $store | Out-Null
    $arc = @(Get-Tasks -Path $store)[0]
    Remove-Item "$store*" -ErrorAction SilentlyContinue
    Assert ($arc.Statut -eq "Archive") "statut=$($arc.Statut)"
    "Archive" }

Check "Get-DueReminders : due & non-termine inclus, termine exclu" {
    $now = [datetime]"2026-07-08T20:30:00"
    $due = New-Task -Titre "Due" -RappelSoir ([datetime]"2026-07-08T20:00:00")
    $done = New-Task -Titre "Done" -Statut Termine -RappelSoir ([datetime]"2026-07-08T20:00:00")
    $future = New-Task -Titre "Future" -RappelSoir ([datetime]"2026-07-08T23:00:00")
    $none = New-Task -Titre "NoReminder"
    $r = @(Get-DueReminders -Tasks @($due, $done, $future, $none) -Now $now)
    Assert ($r.Count -eq 1) "count=$($r.Count) (attendu 1)"
    Assert ($r[0].Titre -eq "Due") "mauvaise tache: $($r[0].Titre)"
    "1 due (termine/futur/sans rappel exclus)" }

Check "Get-DueReminders : recurrence quotidienne via garde NotifieLe" {
    $now = [datetime]"2026-07-08T20:30:00"
    $t = New-Task -Titre "Recur" -RappelSoir ([datetime]"2026-07-08T20:00:00")
    $t.NotifieLe = "2026-07-08"
    $today = @(Get-DueReminders -Tasks @($t) -Now $now)
    $t.NotifieLe = "2026-07-07"
    $tomorrow = @(Get-DueReminders -Tasks @($t) -Now $now)
    Assert ($today.Count -eq 0) "notifie aujourd'hui -> devrait etre exclu (count=$($today.Count))"
    Assert ($tomorrow.Count -eq 1) "notifie hier -> devrait re-declencher (count=$($tomorrow.Count))"
    "gate aujourd'hui=0, hier=1 (recurrence)" }

Check "Get-DueReminders : rappel date dans le futur ne se declenche pas avant" {
    $t = New-Task -Titre "Futur" -RappelSoir ([datetime]"2026-07-15T18:00:00")
    $before = @(Get-DueReminders -Tasks @($t) -Now ([datetime]"2026-07-08T20:30:00"))
    $onDay  = @(Get-DueReminders -Tasks @($t) -Now ([datetime]"2026-07-15T18:30:00"))
    Assert ($before.Count -eq 0) "declenche avant sa date (count=$($before.Count))"
    Assert ($onDay.Count -eq 1) "ne declenche pas le jour dit (count=$($onDay.Count))"
    "futur: 0 avant, 1 le jour J" }

Check "Get-DueReminders : recurrence le soir, pas au matin" {
    # Rappel pose hier a 20:00, jamais notifie -> ne doit PAS sonner ce matin a 8h,
    # mais doit sonner ce soir a 20:30.
    $t = New-Task -Titre "Soir" -RappelSoir ([datetime]"2026-07-07T20:00:00")
    $morning = @(Get-DueReminders -Tasks @($t) -Now ([datetime]"2026-07-08T08:00:00"))
    $evening = @(Get-DueReminders -Tasks @($t) -Now ([datetime]"2026-07-08T20:30:00"))
    Assert ($morning.Count -eq 0) "sonne le matin (count=$($morning.Count))"
    Assert ($evening.Count -eq 1) "ne sonne pas le soir (count=$($evening.Count))"
    "matin=0, soir=1 (timing du soir respecte)" }

Check "Get-TaskSummary : compte a faire / en cours / termine auj / retard" {
    $now = [datetime]"2026-07-08T12:00:00"
    $tasks = @(
        (New-Task -Titre "t1" -Statut A_faire),
        (New-Task -Titre "t2" -Statut A_faire),
        (New-Task -Titre "t3" -Statut En_cours),
        (New-Task -Titre "t4" -Statut Termine),
        (New-Task -Titre "t5" -DateEcheance ([datetime]"2026-07-01T10:00:00"))  # en retard
    )
    $tasks[3].TermineLe = "2026-07-08T09:00:00"
    $s = Get-TaskSummary -Tasks $tasks -Now $now
    Assert ($s.AFaire -eq 3) "AFaire=$($s.AFaire) (t1,t2,t5 sont A_faire)"
    Assert ($s.EnCours -eq 1) "EnCours=$($s.EnCours)"
    Assert ($s.TermineesAujourdhui -eq 1) "TermAuj=$($s.TermineesAujourdhui)"
    Assert ($s.EnRetard -eq 1) "Retard=$($s.EnRetard)"
    "AFaire=3 EnCours=1 TermAuj=1 Retard=1" }

Check "Get-TaskSummary : DateEcheance null ne plante pas" {
    $s = Get-TaskSummary -Tasks @((New-Task -Titre "SansEcheance")) -Now (Get-Date)
    Assert ($s.EnRetard -eq 0) "retard=$($s.EnRetard)"
    "null echeance gere -> retard=0" }

Check "Initialize-TaskSeed : 8 taches + RappelSoir converti en datetime" {
    $store = New-TempStore
    $n = Initialize-TaskSeed -Path $store -Now ([datetime]"2026-07-08T09:00:00")
    $tasks = @(Get-Tasks -Path $store)
    $withReminder = @($tasks | Where-Object { $_.RappelSoir })
    Remove-Item "$store*" -ErrorAction SilentlyContinue
    Assert ($n -eq 8) "seed count=$n (attendu 8)"
    Assert ($tasks.Count -eq 8) "loaded=$($tasks.Count)"
    Assert ($withReminder.Count -eq 2) "taches avec rappel=$($withReminder.Count) (attendu 2)"
    Assert ((ConvertFrom-IsoDate $withReminder[0].RappelSoir).Hour -eq 20) "rappel pas a 20h"
    "8 taches, 2 rappels a 20:00" }

Check "Initialize-TaskSeed : idempotent (ne re-seed pas)" {
    $store = New-TempStore
    Initialize-TaskSeed -Path $store | Out-Null
    $second = Initialize-TaskSeed -Path $store
    $count = @(Get-Tasks -Path $store).Count
    Remove-Item "$store*" -ErrorAction SilentlyContinue
    Assert ($second -eq 0) "2e seed a cree $second tache(s)"
    Assert ($count -eq 8) "count apres 2 seeds=$count"
    "2e appel = no-op" }

Check "Notify : Test-BurntToast renvoie un booleen (sans exception)" {
    $b = Test-BurntToast
    Assert ($b -is [bool]) "type=$($b.GetType().Name)"
    "bool=$b" }

Check "Notify : Show-AfotraNotification -NoShow renvoie le backend" {
    $backend = Show-AfotraNotification -Title "T" -Message "M" -NoShow
    Assert ($backend -in @("BurntToast", "NotifyIcon")) "backend=$backend"
    "backend=$backend (aucune UI affichee)" }

Check "Report : Export-ReportToJSON inclut la section Tasks quand fournie" {
    $csv = Join-Path $env:TEMP ("afotra_rep_" + [guid]::NewGuid().ToString('N') + ".csv")
    Initialize-LogFile -LogFile $csv
    1..3 | ForEach-Object { Write-ActivityLog -LogFile $csv -ActivityInfo ([PSCustomObject]@{ProcessName="Code";ProcessId=1;WindowTitle="x";Category="travail"}) -SampleSeconds 10 }
    $rd = Get-ReportData -LogFile $csv
    $out = Join-Path $env:TEMP ("afotra_rep_" + [guid]::NewGuid().ToString('N') + ".json")
    $summary = Get-TaskSummary -Tasks @((New-Task -Titre "x" -Statut A_faire))
    Export-ReportToJSON -ReportData $rd -OutputFile $out -TaskSummary $summary
    $json = Get-Content $out -Encoding UTF8 | ConvertFrom-Json
    Remove-Item $csv, $out -ErrorAction SilentlyContinue
    Assert ($null -ne $json.Tasks) "section Tasks absente"
    Assert ($json.Tasks.AFaire -eq 1) "Tasks.AFaire=$($json.Tasks.AFaire)"
    "section Tasks presente (AFaire=1)" }

# ===================================================================
Section "I. Sessions & Pomodoro"

$pcfg = @{ workMinutes = 1; shortBreakMinutes = 5; longBreakMinutes = 15; longBreakEvery = 4; autoStartNext = $false }
$t0 = [datetime]"2026-07-08T10:00:00"

Check "Get-CountdownState : sous budget, depassement, sans cible" {
    $under = Get-CountdownState -EstimateSec 300 -WorkSec 120
    $over  = Get-CountdownState -EstimateSec 300 -WorkSec 360
    $none  = Get-CountdownState -EstimateSec 0   -WorkSec 120
    Assert (-not $under.IsOverrun -and $under.RemainingSec -eq 180) "sous budget: reste=$($under.RemainingSec)"
    Assert ($over.IsOverrun -and $over.OverrunSec -eq 60) "depassement: over=$($over.OverrunSec)"
    Assert (-not $none.HasTarget) "sans estimation -> pas de cible"
    "reste 180 / +60 / sans cible" }

Check "Get-PomodoroBreakType : longue toutes les 4, courte sinon" {
    $b1 = Get-PomodoroBreakType -PomCompleted 1 -Config $pcfg
    $b4 = Get-PomodoroBreakType -PomCompleted 4 -Config $pcfg
    $b8 = Get-PomodoroBreakType -PomCompleted 8 -Config $pcfg
    Assert ($b1.Type -eq 'Short' -and $b1.Minutes -eq 5) "cycle1: $($b1.Type)"
    Assert ($b4.Type -eq 'Long'  -and $b4.Minutes -eq 15) "cycle4: $($b4.Type)"
    Assert ($b8.Type -eq 'Long') "cycle8: $($b8.Type)"
    "1=Short(5), 4=Long(15), 8=Long" }

Check "Get-PomodoroConfig : defauts + surcharge partielle" {
    $d = Get-PomodoroConfig $null
    $o = Get-PomodoroConfig @{ workMinutes = 50 }
    Assert ($d.workMinutes -eq 25 -and $d.longBreakEvery -eq 4) "defauts KO: $($d.workMinutes)"
    Assert ($o.workMinutes -eq 50 -and $o.shortBreakMinutes -eq 5) "surcharge KO: $($o.workMinutes)/$($o.shortBreakMinutes)"
    "defauts=25, surcharge=50 (repli conserve le reste)" }

Check "Step-Session : accumulation travail + BreakDue au bout de workMinutes" {
    $s = Start-Session -TaskId "a" -EstimateSec 120 -Config $pcfg -Now $t0
    $r30 = Step-Session -State $s -Now $t0.AddSeconds(30)
    $r60 = Step-Session -State $s -Now $t0.AddSeconds(60)
    Assert ($r30.WorkSec -eq 30 -and -not $r30.BreakDue) "t30: work=$($r30.WorkSec) breakDue=$($r30.BreakDue)"
    Assert ($r60.BreakDue) "t60: BreakDue devrait etre vrai (workMinutes=1)"
    "work=30 a t30, BreakDue a t60" }

Check "Suspend/Resume : temps travail gele, temps global continue" {
    $s = Start-Session -TaskId "b" -EstimateSec 0 -Config $pcfg -Now $t0
    Suspend-Session -State $s -Now $t0.AddSeconds(30) | Out-Null   # 30s travail
    Resume-Session  -State $s -Now $t0.AddSeconds(50) | Out-Null   # 20s pause
    $r = Step-Session -State $s -Now $t0.AddSeconds(80)            # +30s travail
    Assert ($r.WorkSec -eq 60) "travail=$($r.WorkSec) (attendu 60)"
    Assert ($r.GlobalSec -eq 80) "global=$($r.GlobalSec) (attendu 80)"
    Assert ($r.PauseSec -eq 20) "pause=$($r.PauseSec) (attendu 20)"
    "travail=60, global=80, pause=20 (double comptage)" }

Check "Cycle complet : travail hors pause vs global mur (Get-SessionResult)" {
    $s = Start-Session -TaskId "c" -EstimateSec 120 -Config $pcfg -Now $t0
    Step-Session -State $s -Now $t0.AddSeconds(60) | Out-Null
    Start-SessionBreak -State $s -Now $t0.AddSeconds(60) | Out-Null   # 60s travail, puis pause
    Stop-SessionBreak  -State $s -Now $t0.AddSeconds(360) | Out-Null  # 300s de pause
    $res = Get-SessionResult -State $s -Now $t0.AddSeconds(420)       # +60s travail
    Assert ($res.TravailSecondes -eq 120) "travail=$($res.TravailSecondes) (attendu 120)"
    Assert ($res.GlobalSecondes -eq 420) "global=$($res.GlobalSecondes) (attendu 420)"
    Assert ($res.PauseSecondes -eq 300) "pause=$($res.PauseSecondes) (attendu 300)"
    Assert ($res.PomodorosFait -eq 1) "pomodoros=$($res.PomodorosFait)"
    "travail=120, global=420, pause=300, 1 pomodoro" }

Check "Add-TaskSession : accumule les totaux + journal + round-trip" {
    $store = New-TempStore
    $t = New-Task -Titre "S" -EstimeMinutes 30
    Save-Tasks -Tasks @($t) -Path $store
    $res = [PSCustomObject]@{ Debut="2026-07-08T10:00:00"; Fin="2026-07-08T10:50:00"; TravailSecondes=2700; GlobalSecondes=3000; PauseSecondes=300; PomodorosFait=1 }
    Add-TaskSession -Id $t.Id -Result $res -Path $store | Out-Null
    Add-TaskSession -Id $t.Id -Result $res -Path $store | Out-Null
    $back = @(Get-Tasks -Path $store)[0]
    Remove-Item "$store*" -ErrorAction SilentlyContinue
    Assert ($back.TempsTravailSecondes -eq 5400) "travail cumule=$($back.TempsTravailSecondes)"
    Assert (@($back.Sessions).Count -eq 2) "sessions=$(@($back.Sessions).Count)"
    "2 sessions, travail cumule=5400s" }

Check "Get-TaskEfficiency : sous budget (ratio>1) et depassement (ratio<1)" {
    $under = New-Task -Titre "U" -EstimeMinutes 60; $under.TempsTravailSecondes = 1800   # 30min sur 60 -> efficace
    $over  = New-Task -Titre "O" -EstimeMinutes 30; $over.TempsTravailSecondes  = 2700   # 45min sur 30 -> depasse
    $eu = Get-TaskEfficiency -Task $under
    $eo = Get-TaskEfficiency -Task $over
    Assert ($eu.Ratio -gt 1 -and $eu.EcartMin -lt 0) "sous budget: ratio=$($eu.Ratio) ecart=$($eu.EcartMin)"
    Assert ($eo.Ratio -lt 1 -and $eo.EcartMin -gt 0) "depassement: ratio=$($eo.Ratio) ecart=$($eo.EcartMin)"
    "sous budget ratio=$($eu.Ratio) / depassement ratio=$($eo.Ratio)" }

Check "Get-TaskSummary : temps travaille du jour + nb depassements" {
    $store = New-TempStore
    $a = New-Task -Titre "A" -EstimeMinutes 10   # depassement (12min > 10)
    $a.TempsTravailSecondes = 720
    $a.Sessions = @([PSCustomObject]@{ Debut="2026-07-08T09:00:00"; Fin="2026-07-08T09:12:00"; TravailSecondes=720; GlobalSecondes=720; PauseSecondes=0; PomodorosFait=0 })
    $b = New-Task -Titre "B" -EstimeMinutes 60   # pas depassement (30min < 60), session hier
    $b.Sessions = @([PSCustomObject]@{ Debut="2026-07-07T09:00:00"; Fin="2026-07-07T09:30:00"; TravailSecondes=1800; GlobalSecondes=1800; PauseSecondes=0; PomodorosFait=0 })
    $b.TempsTravailSecondes = 1800
    Save-Tasks -Tasks @($a, $b) -Path $store
    $sum = Get-TaskSummary -Tasks @(Get-Tasks -Path $store) -Now ([datetime]"2026-07-08T18:00:00")
    Remove-Item "$store*" -ErrorAction SilentlyContinue
    Assert ($sum.TempsTravailJourMin -eq 12) "temps jour=$($sum.TempsTravailJourMin) (attendu 12: seule session du jour)"
    Assert ($sum.EnDepassement -eq 1) "depassements=$($sum.EnDepassement) (attendu 1)"
    "12 min aujourd'hui, 1 depassement" }

Check "Retro-compat : tache sans champs de session toleree" {
    $store = New-TempStore
    $old = [PSCustomObject]@{ Id=[guid]::NewGuid().ToString(); Titre="Vieux"; Statut="A_faire" }
    Save-Tasks -Tasks @($old) -Path $store
    $res = [PSCustomObject]@{ Debut="2026-07-08T10:00:00"; Fin="2026-07-08T10:30:00"; TravailSecondes=1800; GlobalSecondes=1800; PauseSecondes=0; PomodorosFait=0 }
    Add-TaskSession -Id $old.Id -Result $res -Path $store | Out-Null
    $back = @(Get-Tasks -Path $store)[0]
    $eff = Get-TaskEfficiency -Task $back
    Remove-Item "$store*" -ErrorAction SilentlyContinue
    Assert ($back.TempsTravailSecondes -eq 1800) "travail=$($back.TempsTravailSecondes)"
    Assert (-not $eff.HasEstimate) "sans estimation -> HasEstimate false"
    "vieille tache: session ajoutee sans crash" }

# ===================================================================
Section "J. Assistant orbe & garde-focus"

Check "Get-OrbMood : humeur selon session + garde" {
    Assert ((Get-OrbMood -HasSession $false) -eq 'Idle') "no session -> Idle"
    Assert ((Get-OrbMood -HasSession $true -Mode Running) -eq 'Focus') "running -> Focus"
    Assert ((Get-OrbMood -HasSession $true -Mode Running -IsOverrun $true) -eq 'Overrun') "overrun -> Overrun"
    Assert ((Get-OrbMood -HasSession $true -Mode Break) -eq 'Break') "break -> Break"
    Assert ((Get-OrbMood -HasSession $true -Mode Running -Guard $true) -eq 'Ask') "garde -> Ask"
    Assert ((Get-OrbMood -HasSession $true -Mode Paused -AwaitingResume $true) -eq 'Resume') "fin de pause -> Resume"
    "Idle/Focus/Overrun/Break/Ask/Resume OK" }

Check "Get-OrbVisual : humeur Resume distincte (appelle a reprendre)" {
    $resume = Get-OrbVisual Resume
    $break  = Get-OrbVisual Break
    Assert ($resume.SizePx -gt $break.SizePx) "Resume plus gros que Break: $($resume.SizePx) vs $($break.SizePx)"
    Assert ($resume.Edge -eq '#10B981') "Resume en vert (focus qui revient)"
    Assert ($resume.PulsePeriodMs -lt $break.PulsePeriodMs) "Resume pulse plus vite (attire l'oeil)"
    "Resume: vert, plus gros, pulse rapide" }

Check "Get-OrbVisual : tailles Ask > Overrun > Focus > Idle + recentrage Ask" {
    $idle = Get-OrbVisual Idle
    $focus = Get-OrbVisual Focus
    $over = Get-OrbVisual Overrun
    $ask = Get-OrbVisual Ask 1.0
    Assert ($ask.SizePx -gt $over.SizePx -and $over.SizePx -gt $focus.SizePx -and $focus.SizePx -gt $idle.SizePx) "ordre tailles KO: $($idle.SizePx)/$($focus.SizePx)/$($over.SizePx)/$($ask.SizePx)"
    Assert ($ask.MoveToCenter -and -not $focus.MoveToCenter) "recentrage seulement en Ask"
    Assert ($idle.Edge -eq '#14B8A6' -and $focus.Edge -eq '#10B981' -and $ask.Edge -eq '#EF4444') "couleurs KO"
    "idle=$($idle.SizePx) focus=$($focus.SizePx) over=$($over.SizePx) ask=$($ask.SizePx), recentre Ask" }

Check "Get-OrbVisual : Ask grossit avec l'intensite" {
    $a0 = Get-OrbVisual Ask 0.0
    $a1 = Get-OrbVisual Ask 1.0
    Assert ($a1.SizePx -gt $a0.SizePx) "intensite: $($a0.SizePx) -> $($a1.SizePx)"
    "$($a0.SizePx) -> $($a1.SizePx)" }

Check "Test-ProcessAllowed : liste, casse, AFOTRA tolere" {
    Assert (-not (Test-ProcessAllowed -ProcessName 'chrome' -AllowList @('Code'))) "chrome non liste"
    Assert (Test-ProcessAllowed -ProcessName 'CODE' -AllowList @('code')) "casse insensible"
    Assert (Test-ProcessAllowed -ProcessName 'AFOTRA' -AllowList @()) "afotra toujours ok"
    Assert (Test-ProcessAllowed -ProcessName 'powershell' -AllowList @()) "powershell (AFOTRA) tolere"
    "non-liste bloque, casse OK, AFOTRA/powershell tolere" }

Check "Add-TaskTool : ajout + dedup (casse) + round-trip" {
    $store = New-TempStore
    $t = New-Task -Titre "Dev"
    Assert (@($t.OutilsTache).Count -eq 0) "OutilsTache vide au depart"
    Save-Tasks -Tasks @($t) -Path $store
    Add-TaskTool -Id $t.Id -Process "Code" -Path $store | Out-Null
    Add-TaskTool -Id $t.Id -Process "code" -Path $store | Out-Null   # dedup
    Add-TaskTool -Id $t.Id -Process "figma" -Path $store | Out-Null
    $back = @(Get-Tasks -Path $store)[0]
    Remove-Item "$store*" -ErrorAction SilentlyContinue
    Assert (@($back.OutilsTache).Count -eq 2) "outils=$(@($back.OutilsTache).Count) (attendu 2, dedup)"
    Assert (Test-TaskToolAllowed -Task $back -Process 'FIGMA') "figma autorise (casse)"
    "2 outils (Code, figma), dedup casse OK" }

Check "Add-TaskDigression : incremente le compteur" {
    $store = New-TempStore
    $t = New-Task -Titre "D"
    Save-Tasks -Tasks @($t) -Path $store
    Add-TaskDigression -Id $t.Id -Path $store
    Add-TaskDigression -Id $t.Id -Path $store
    $back = @(Get-Tasks -Path $store)[0]
    Remove-Item "$store*" -ErrorAction SilentlyContinue
    Assert ([int]$back.DigressionsCount -eq 2) "digressions=$($back.DigressionsCount)"
    "digressions=2" }

Check "Add-TaskTool : tolere une tache sans le champ OutilsTache" {
    $store = New-TempStore
    $old = [PSCustomObject]@{ Id=[guid]::NewGuid().ToString(); Titre="V"; Statut="A_faire" }
    Save-Tasks -Tasks @($old) -Path $store
    Add-TaskTool -Id $old.Id -Process "Blender" -Path $store | Out-Null
    $back = @(Get-Tasks -Path $store)[0]
    Remove-Item "$store*" -ErrorAction SilentlyContinue
    Assert (@($back.OutilsTache).Count -eq 1 -and (Test-TaskToolAllowed -Task $back -Process 'blender')) "vieille tache: outil ajoute"
    "vieille tache toleree" }

# ===================================================================
# Rapport
# ===================================================================
$pass = @($script:Results | Where-Object Status -eq "PASS").Count
$fail = @($script:Results | Where-Object Status -eq "FAIL").Count
$skip = @($script:Results | Where-Object Status -eq "SKIP").Count
$total = $pass + $fail

Write-Host "`n=== RESUME ===" -ForegroundColor Cyan
Write-Host ("Reussis: {0}/{1}" -f $pass, $total) -ForegroundColor Green
if ($skip -gt 0) { Write-Host ("Sautes: {0} (live/bureau)" -f $skip) -ForegroundColor DarkYellow }
if ($fail -gt 0) { Write-Host ("Echecs: {0}/{1}" -f $fail, $total) -ForegroundColor Red }

# --- Genere TEST_REPORT.md ---
$now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$skipNote = if ($skip -gt 0) { " ($skip sautes : live/bureau)" } else { "" }
$verdict = if ($fail -eq 0) { "TOUS LES TESTS PASSENT$skipNote" } else { "$fail ECHEC(S)" }
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# AFOTRA - Rapport de tests complet")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("- **Date** : $now")
[void]$sb.AppendLine("- **Machine** : $env:COMPUTERNAME / utilisateur $env:USERNAME")
[void]$sb.AppendLine("- **Resultat** : **$verdict** ($pass/$total)")
[void]$sb.AppendLine("- **Couverture** : configuration, classification (categories + priorites + casse), gestion des regles (round-trip), journalisation, reporting (+ cas limites), bout-en-bout (CLI, tracker live, daily-report, dashboard WPF, XAML)")
[void]$sb.AppendLine("")
$lastGroup = ""
foreach ($r in $script:Results) {
    if ($r.Group -ne $lastGroup) {
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("## $($r.Group)")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("| Statut | Cas d'usage | Detail |")
        [void]$sb.AppendLine("|:------:|-------------|--------|")
        $lastGroup = $r.Group
    }
    $icon = switch ($r.Status) { "PASS" { "PASS" } "SKIP" { "SKIP" } default { "FAIL" } }
    $d = ($r.Detail -replace '\|','\|' -replace '[\r\n]+',' ')
    [void]$sb.AppendLine("| $icon | $($r.Name) | $d |")
}
[void]$sb.AppendLine("")
[void]$sb.AppendLine("---")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("**Total : $pass/$total reussis.** Genere par ``Run-Full-Tests.ps1``.")

$reportPath = Join-Path $root "TEST_REPORT.md"
$sb.ToString() | Set-Content -Path $reportPath -Encoding UTF8
Write-Host "Rapport ecrit : $reportPath" -ForegroundColor Green

if ($fail -gt 0) { exit 1 } else { exit 0 }
