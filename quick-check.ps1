# quick-check.ps1 - Quick AFOTRA Environment Check
# Simple verification script

$scriptRoot = $PSScriptRoot

Write-Host "`nAFOTRA - Environment Check`n" -ForegroundColor Cyan
Write-Host ("=" * 50) -ForegroundColor Cyan

# Check directories
$dirs = @("\logs", "\logs\reports", "\modules")
Write-Host "`nDirectories:" -ForegroundColor Yellow
foreach ($dir in $dirs) {
    $path = $scriptRoot + $dir
    if (Test-Path $path) {
        Write-Host "  [OK] $dir" -ForegroundColor Green
    } else {
        Write-Host "  [CREATE] $dir" -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

# Check files
$files = @("config.json", "rules.json", "dashboard-wpf.ps1", "tracker.ps1", "daily-report.ps1", "modules\Tracker.Core.psm1", "modules\Rules.Core.psm1", "modules\Report.Core.psm1")
Write-Host "`nRequired Files:" -ForegroundColor Yellow
foreach ($file in $files) {
    $path = Join-Path $scriptRoot $file
    if (Test-Path $path) {
        Write-Host "  [OK] $file" -ForegroundColor Green
    } else {
        Write-Host "  [MISSING] $file" -ForegroundColor Red
    }
}

# Check config files
Write-Host "`nConfiguration Files:" -ForegroundColor Yellow
try {
    $config = Get-Content (Join-Path $scriptRoot "config.json") | ConvertFrom-Json
    Write-Host "  [OK] config.json" -ForegroundColor Green
} catch {
    Write-Host "  [ERROR] config.json - $_" -ForegroundColor Red
}

try {
    $rules = Get-Content (Join-Path $scriptRoot "rules.json") | ConvertFrom-Json  
    Write-Host "  [OK] rules.json" -ForegroundColor Green
} catch {
    Write-Host "  [ERROR] rules.json - $_" -ForegroundColor Red
}

Write-Host "`n" + ("=" * 50) -ForegroundColor Cyan
Write-Host "Environment check complete!" -ForegroundColor Green
Write-Host "Ready to launch: .\dashboard-wpf.ps1`n" -ForegroundColor Cyan
