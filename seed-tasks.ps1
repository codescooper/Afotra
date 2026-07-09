# seed-tasks.ps1 - Initialise tasks.json with the starter tasks (idempotent).
# Author: CodeScooper | Project: AFOTRA - Awema Focus Tracker
#
# Safe to run repeatedly: Initialize-TaskSeed does nothing if tasks already exist.

$ErrorActionPreference = "Stop"

try {
    $scriptRoot = $PSScriptRoot
    Import-Module (Join-Path $scriptRoot "modules\Tasks.Core.psm1") -Force -DisableNameChecking

    $storePath = Get-TaskStorePath
    $existing = @(Get-Tasks -Path $storePath)

    if ($existing.Count -gt 0) {
        Write-Host "tasks.json already has $($existing.Count) task(s) - seed skipped." -ForegroundColor Yellow
        Write-Host "Store: $storePath" -ForegroundColor Gray
        exit 0
    }

    $count = Initialize-TaskSeed -Path $storePath
    Write-Host "Seeded $count task(s) into: $storePath" -ForegroundColor Green
    exit 0
}
catch {
    Write-Error "Seed error: $_"
    exit 1
}
