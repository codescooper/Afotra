# Run-Tests.ps1 - Automated, measurable verification suite for AFOTRA
# Author: CodeScooper | Verifies the project is concretely functional.
#
# Usage:   powershell -NoProfile -ExecutionPolicy Bypass -File .\Run-Tests.ps1
# Exit code 0 = all tests passed, 1 = at least one failure.

$ErrorActionPreference = "Stop"
$root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

$script:Pass = 0
$script:Fail = 0
$script:Results = @()

function Check {
    param([string]$Name, [scriptblock]$Test)
    try {
        $detail = & $Test
        $script:Pass++
        $script:Results += [PSCustomObject]@{ Status = "PASS"; Name = $Name; Detail = $detail }
        Write-Host ("  [PASS] {0,-45} {1}" -f $Name, $detail) -ForegroundColor Green
    }
    catch {
        $script:Fail++
        $script:Results += [PSCustomObject]@{ Status = "FAIL"; Name = $Name; Detail = $_.Exception.Message }
        Write-Host ("  [FAIL] {0,-45} {1}" -f $Name, $_.Exception.Message) -ForegroundColor Red
    }
}

function Assert($cond, $msg) { if (-not $cond) { throw $msg } }

Write-Host "`n=== AFOTRA Automated Verification Suite ===" -ForegroundColor Cyan
Write-Host "Root: $root`n" -ForegroundColor DarkGray

# --- Group 1: Environment / files ---
Write-Host "[1] Environment & files" -ForegroundColor Yellow
Check "config.json exists & valid JSON" {
    $c = Get-Content (Join-Path $root "config.json") -Encoding UTF8 | ConvertFrom-Json
    Assert ($c.sampleIntervalSeconds -ge 1) "sampleIntervalSeconds invalid"
    "interval=$($c.sampleIntervalSeconds)s"
}
Check "rules.json exists & valid JSON" {
    $r = Get-Content (Join-Path $root "rules.json") -Encoding UTF8 | ConvertFrom-Json
    Assert ($r.categories.Count -gt 0) "no categories"
    "$($r.categories.Count) cats, $($r.processRules.Count) proc rules, $($r.titleRules.Count) title rules"
}
foreach ($m in @("Tracker.Core","Rules.Core","Report.Core","UI.Core")) {
    Check "module modules\$m.psm1 present" {
        Assert (Test-Path (Join-Path $root "modules\$m.psm1")) "missing"
        "ok"
    }.GetNewClosure()
}

# --- Group 2: Module loading ---
Write-Host "`n[2] Module loading" -ForegroundColor Yellow
Check "Import all core modules" {
    Import-Module (Join-Path $root "modules\Tracker.Core.psm1") -Force
    Import-Module (Join-Path $root "modules\Rules.Core.psm1") -Force -WarningAction SilentlyContinue
    Import-Module (Join-Path $root "modules\Report.Core.psm1") -Force
    foreach ($fn in @("Get-ActiveWindowInfo","Classify-Activity","Load-Rules","Get-ReportData","Write-ActivityLog")) {
        Assert (Get-Command $fn -ErrorAction SilentlyContinue) "function $fn not exported"
    }
    "5 key functions available"
}

$rules = Load-Rules -RulesPath (Join-Path $root "rules.json")

# --- Group 3: Classification logic ---
Write-Host "`n[3] Classification logic" -ForegroundColor Yellow
Check "Code editor -> travail" {
    $c = Classify-Activity -ProcessName "Code" -WindowTitle "x.ps1 - Visual Studio Code" -Rules $rules
    Assert ($c -eq "travail") "got '$c'"
    $c
}
Check "Browser YouTube title beats process -> distraction" {
    $c = Classify-Activity -ProcessName "chrome" -WindowTitle "Some Video - YouTube - Google Chrome" -Rules $rules
    Assert ($c -eq "distraction") "got '$c'"
    $c
}
Check "Unmatched -> inconnu" {
    $c = Classify-Activity -ProcessName "zzqq_nomatch_999" -WindowTitle "qqzz_nomatch_999" -Rules $rules
    Assert ($c -eq "inconnu") "got '$c'"
    $c
}

# --- Group 4: Live window capture ---
Write-Host "`n[4] Live window capture (Win32)" -ForegroundColor Yellow
Check "Get-ActiveWindowInfo returns a process" {
    $i = Get-ActiveWindowInfo
    Assert ($i -and $i.ProcessName) "no info returned"
    "$($i.ProcessName) (pid $($i.ProcessId))"
}

# --- Group 5: Logging roundtrip ---
Write-Host "`n[5] Logging roundtrip" -ForegroundColor Yellow
Check "Initialize + Write + read back a row" {
    $tmp = Join-Path $env:TEMP ("afotra_test_{0}.csv" -f (Get-Date -Format 'yyyyMMddHHmmss'))
    Initialize-LogFile -LogFile $tmp
    Write-ActivityLog -LogFile $tmp -ActivityInfo ([PSCustomObject]@{ ProcessName="UnitTest"; ProcessId=1; WindowTitle="T"; Category="travail" }) -SampleSeconds 5
    $rows = @(Import-Csv $tmp -Encoding UTF8)
    Remove-Item $tmp -ErrorAction SilentlyContinue
    Assert ($rows.Count -eq 1) "expected 1 data row, got $($rows.Count)"
    Assert ($rows[0].ProcessName -eq "UnitTest") "wrong process logged"
    "1 row written & parsed"
}

# --- Group 6: Report math ---
Write-Host "`n[6] Report generation & math" -ForegroundColor Yellow
Check "Get-ReportData computes correct focus score" {
    $tmp = Join-Path $env:TEMP ("afotra_rep_{0}.csv" -f (Get-Date -Format 'yyyyMMddHHmmss'))
    Initialize-LogFile -LogFile $tmp
    # 7 travail + 3 distraction = 70% focus
    1..7 | ForEach-Object { Write-ActivityLog -LogFile $tmp -ActivityInfo ([PSCustomObject]@{ProcessName="Code";ProcessId=1;WindowTitle="w";Category="travail"}) -SampleSeconds 10 }
    1..3 | ForEach-Object { Write-ActivityLog -LogFile $tmp -ActivityInfo ([PSCustomObject]@{ProcessName="game";ProcessId=2;WindowTitle="g";Category="distraction"}) -SampleSeconds 10 }
    $rd = Get-ReportData -LogFile $tmp
    Remove-Item $tmp -ErrorAction SilentlyContinue
    Assert ($rd.TotalSeconds -eq 100) "total=$($rd.TotalSeconds) expected 100"
    Assert ($rd.FocusScore -eq 70) "focus=$($rd.FocusScore) expected 70"
    "total=100s, focus=70% (verified)"
}
Check "Export-ReportToJSON writes a summary file" {
    $tmp = Join-Path $env:TEMP ("afotra_rep2_{0}.csv" -f (Get-Date -Format 'yyyyMMddHHmmss'))
    Initialize-LogFile -LogFile $tmp
    1..4 | ForEach-Object { Write-ActivityLog -LogFile $tmp -ActivityInfo ([PSCustomObject]@{ProcessName="Code";ProcessId=1;WindowTitle="w";Category="travail"}) -SampleSeconds 10 }
    $rd = Get-ReportData -LogFile $tmp
    $json = Join-Path $env:TEMP ("afotra_sum_{0}.json" -f (Get-Date -Format 'yyyyMMddHHmmss'))
    Export-ReportToJSON -ReportData $rd -OutputFile $json
    $ok = Test-Path $json
    $obj = if ($ok) { Get-Content $json -Raw | ConvertFrom-Json } else { $null }
    Remove-Item $tmp,$json -ErrorAction SilentlyContinue
    Assert $ok "json not created"
    Assert ($obj.FocusMinutes -eq 0.67 -or $obj.TotalTrackedMinutes -gt 0) "json content invalid"
    "summary json valid"
}

# --- Group 7: WPF UI parses ---
Write-Host "`n[7] WPF UI integrity" -ForegroundColor Yellow
Check "Both XAML blocks parse into Windows" {
    Add-Type -AssemblyName PresentationFramework
    $src = Get-Content (Join-Path $root "dashboard-wpf.ps1") -Raw
    $n = 0
    foreach ($pat in @('\$xaml = @"\r?\n(.*?)\r?\n"@','\$overlayXaml = @"\r?\n(.*?)\r?\n"@')) {
        $mm = [regex]::Match($src, $pat, [System.Text.RegularExpressions.RegexOptions]::Singleline)
        Assert $mm.Success "xaml block not found"
        $rdr = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($mm.Groups[1].Value))
        $w = [Windows.Markup.XamlReader]::Load($rdr)
        Assert ($w -is [System.Windows.Window]) "did not produce a Window"
        $w.Close(); $n++
    }
    "$n/2 windows parsed"
}

# --- Group 8: End-to-end live runs ---
Write-Host "`n[8] End-to-end live process runs" -ForegroundColor Yellow
Check "dashboard-wpf.ps1 launches & survives startup" {
    $eo = Join-Path $env:TEMP "afotra_dash_err.log"; "" | Set-Content $eo
    $p = Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$(Join-Path $root 'dashboard-wpf.ps1')`"" -PassThru -RedirectStandardError $eo -RedirectStandardOutput (Join-Path $env:TEMP "afotra_dash_out.log") -WindowStyle Hidden
    Start-Sleep -Seconds 8
    $alive = $null -ne (Get-Process -Id $p.Id -ErrorAction SilentlyContinue)
    $title = if ($alive) { (Get-Process -Id $p.Id).MainWindowTitle } else { "" }
    $err = (Get-Content $eo -Raw -ErrorAction SilentlyContinue)
    if ($alive) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    Assert $alive "process died during startup. stderr: $err"
    Assert ($title -like "*AFOTRA*") "window title not found: '$title'"
    "window: '$title'"
}
Check "tracker.ps1 actually appends rows when running" {
    $logFile = Join-Path $root ("logs\activity-{0}.csv" -f (Get-Date -Format 'yyyy-MM-dd'))
    $before = if (Test-Path $logFile) { (@(Get-Content $logFile)).Count } else { 0 }
    $p = Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$(Join-Path $root 'tracker.ps1')`"" -PassThru -RedirectStandardError (Join-Path $env:TEMP "afotra_trk_err.log") -RedirectStandardOutput (Join-Path $env:TEMP "afotra_trk_out.log") -WindowStyle Hidden
    Start-Sleep -Seconds 13
    $after = (@(Get-Content $logFile)).Count
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    Assert ($after -gt $before) "no rows appended (before=$before after=$after) - tracker is a no-op"
    "appended $($after-$before) row(s) in 13s"
}

# --- Summary ---
Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
$total = $script:Pass + $script:Fail
Write-Host ("Passed: {0}/{1}" -f $script:Pass, $total) -ForegroundColor Green
if ($script:Fail -gt 0) {
    Write-Host ("Failed: {0}/{1}" -f $script:Fail, $total) -ForegroundColor Red
    exit 1
} else {
    Write-Host "ALL TESTS PASSED - AFOTRA is functional." -ForegroundColor Green
    exit 0
}
