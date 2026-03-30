param(
    [string]$ConfigPath = "C:\AFOTRA - Awema Focus Tracker\config.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path $ConfigPath)) {
    throw "Config introuvable : $ConfigPath"
}

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

$sampleInterval = [int]$config.sampleIntervalSeconds
$logRoot = $config.logRoot

if (-not (Test-Path $logRoot)) {
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
}

$today = Get-Date -Format "yyyy-MM-dd"
$logPath = Join-Path $logRoot "activity-$today.csv"

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class Win32Focus
{
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
}
"@

function Get-Category {
    param(
        [string]$ProcessName,
        [string]$WindowTitle,
        $Config
    )

    foreach ($rule in $Config.titleRules) {
        if ($WindowTitle -like "*$($rule.contains)*") {
            return $rule.category
        }
    }

    foreach ($catProp in $Config.categories.PSObject.Properties) {
        $catName = $catProp.Name
        foreach ($app in $catProp.Value) {
            if ($ProcessName -ieq $app) {
                return $catName
            }
        }
    }

    return "inconnu"
}

function Get-ActiveWindowSnapshot {
    param($Config)

    $hWnd = [Win32Focus]::GetForegroundWindow()
    if ($hWnd -eq [IntPtr]::Zero) {
        return $null
    }

    $buffer = New-Object System.Text.StringBuilder 1024
    [void][Win32Focus]::GetWindowText($hWnd, $buffer, $buffer.Capacity)

    $processId = 0
    [void][Win32Focus]::GetWindowThreadProcessId($hWnd, [ref]$processId)

    if ($processId -eq 0) {
        return $null
    }

    try {
        $proc = Get-Process -Id $processId -ErrorAction Stop
    }
    catch {
        return $null
    }

    $title = $buffer.ToString().Trim()
    $processName = $proc.ProcessName
    $category = Get-Category -ProcessName $processName -WindowTitle $title -Config $Config

    [PSCustomObject]@{
        Timestamp      = (Get-Date).ToString("s")
        Date           = (Get-Date).ToString("yyyy-MM-dd")
        Time           = (Get-Date).ToString("HH:mm:ss")
        ProcessName    = $processName
        ProcessId      = $processId
        WindowTitle    = $title
        Category       = $category
        SampleSeconds  = $sampleInterval
        UserName       = $env:USERNAME
        MachineName    = $env:COMPUTERNAME
    }
}

Write-Host "Tracking lancé. Log : $logPath"
Write-Host "Arrêt : Ctrl+C"

while ($true) {
    $snapshot = Get-ActiveWindowSnapshot -Config $config
    if ($null -ne $snapshot) {
        if (-not (Test-Path $logPath)) {
            $snapshot | Export-Csv -Path $logPath -NoTypeInformation
        }
        else {
            $snapshot | Export-Csv -Path $logPath -NoTypeInformation -Append
        }
    }
    Start-Sleep -Seconds $sampleInterval
}