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

$ErrorActionPreference = "Stop"
$root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

$script:Results = @()
$script:Group   = ""

function Assert($cond, $msg) { if (-not $cond) { throw $msg } }

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
$rules = Load-Rules -RulesPath (Join-Path $root "rules.json")

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
    Assert ($rd.ContextSwitches -eq 8) "switches=$($rd.ContextSwitches) (7 titres distincts + 1)"
    "total=100s focus=70% switches=8" }
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
Check "tracker.ps1 : ecrit reellement des lignes en cours d'execution" {
    $logFile = Join-Path $root ("logs\activity-{0}.csv" -f (Get-Date -Format 'yyyy-MM-dd'))
    $before = if (Test-Path $logFile) { (@(Get-Content $logFile)).Count } else { 0 }
    $p = Start-Process powershell -ArgumentList '-NoProfile','-File',"`"$(Join-Path $root 'tracker.ps1')`"" -PassThru -RedirectStandardError (Join-Path $env:TEMP "afotra_trk_err.log") -RedirectStandardOutput (Join-Path $env:TEMP "afotra_trk_out.log") -WindowStyle Hidden
    Start-Sleep -Seconds 13
    $after = (@(Get-Content $logFile)).Count
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
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

# ===================================================================
# Rapport
# ===================================================================
$pass = @($script:Results | Where-Object Status -eq "PASS").Count
$fail = @($script:Results | Where-Object Status -eq "FAIL").Count
$total = $pass + $fail

Write-Host "`n=== RESUME ===" -ForegroundColor Cyan
Write-Host ("Reussis: {0}/{1}" -f $pass, $total) -ForegroundColor Green
if ($fail -gt 0) { Write-Host ("Echecs: {0}/{1}" -f $fail, $total) -ForegroundColor Red }

# --- Genere TEST_REPORT.md ---
$now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$verdict = if ($fail -eq 0) { "TOUS LES TESTS PASSENT" } else { "$fail ECHEC(S)" }
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
    $icon = if ($r.Status -eq "PASS") { "PASS" } else { "FAIL" }
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
