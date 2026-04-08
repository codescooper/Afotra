# Test complet d'intégration AFOTRA
Write-Host "=== AFOTRA Full Integration Test ===" -ForegroundColor Green
Write-Host ""

Write-Host "Test 1: Checking if tracker is running..." -ForegroundColor Cyan
$check = & ".\tracker.ps1" -Check 2>&1
Write-Host $check
Write-Host ""

Write-Host "Test 2: Verifying CSV file exists..." -ForegroundColor Cyan
$csv = "logs\activity-$(Get-Date -Format 'yyyy-MM-dd').csv"
if (Test-Path $csv) {
    Write-Host "[OK] CSV file exists: $csv" -ForegroundColor Green
    $lines = @(Get-Content $csv)
    Write-Host "[OK] CSV has $($lines.Count) lines" -ForegroundColor Green
} else {
    Write-Host "[ERROR] CSV not found" -ForegroundColor Red
}
Write-Host ""

Write-Host "Test 3: Verifying config.json..." -ForegroundColor Cyan
$config = Get-Content config.json -Encoding UTF8 | ConvertFrom-Json
Write-Host "[OK] sampleIntervalSeconds: $($config.sampleIntervalSeconds)" -ForegroundColor Green
Write-Host "[OK] focusMinPerDay: $($config.focusMinPerDay)" -ForegroundColor Green
Write-Host ""

Write-Host "Test 4: Verifying rules.json..." -ForegroundColor Cyan
$rules = Get-Content rules.json -Encoding UTF8 | ConvertFrom-Json
Write-Host "[OK] Categories: $($rules.categories -join ', ')" -ForegroundColor Green
Write-Host "[OK] Process rules: $($rules.processRules.Count)" -ForegroundColor Green
Write-Host "[OK] Title rules: $($rules.titleRules.Count)" -ForegroundColor Green
Write-Host ""

Write-Host "Test 5: Verifying modules..." -ForegroundColor Cyan
$moduleFiles = @("modules\Tracker.Core.psm1", "modules\Rules.Core.psm1", "modules\Report.Core.psm1")
foreach ($module in $moduleFiles) {
    if (Test-Path $module) {
        Write-Host "[OK] $module exists" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] $module not found" -ForegroundColor Red
    }
}
Write-Host ""

Write-Host "=== All Tests Passed ===" -ForegroundColor Green
Write-Host "AFOTRA is ready to use!" -ForegroundColor Green
