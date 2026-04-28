# Tracker.Core.psm1 - Core functions for tracking PC activity
# Author: CodeScooper
# Project: AFOTRA - Awema Focus Tracker

if (-not ([System.Management.Automation.PSTypeName]'Win32').Type) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class Win32 {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
}
"@
}

function Get-ActiveWindowInfo {
    try {
        $hwnd = [Win32]::GetForegroundWindow()
        if ($hwnd -eq [IntPtr]::Zero) { return $null }

        $title = New-Object System.Text.StringBuilder 256
        [Win32]::GetWindowText($hwnd, $title, 256) | Out-Null
        $windowTitle = $title.ToString()

        $processId = 0
        [Win32]::GetWindowThreadProcessId($hwnd, [ref]$processId) | Out-Null

        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        $processName = if ($process) { $process.ProcessName } else { "Unknown" }

        return @{
            ProcessName = $processName
            ProcessId = $processId
            WindowTitle = $windowTitle
        }
    }
    catch {
        return $null
    }
}

function Initialize-LogFile {
    param (
        [string]$LogFile
    )
    
    $folder = Split-Path -Parent $LogFile
    if (!(Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }

    if (!(Test-Path $LogFile)) {
        "Timestamp,Date,Time,ProcessName,ProcessId,WindowTitle,Category,SampleSeconds,UserName,MachineName" | Out-File -FilePath $LogFile -Encoding UTF8 -Force
    }
}

function Write-ActivityLog {
    param (
        [string]$LogFile,
        [object]$ActivityInfo,
        [int]$SampleSeconds
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $date = Get-Date -Format "yyyy-MM-dd"
    $time = Get-Date -Format "HH:mm:ss"
    $userName = $env:USERNAME
    $machineName = $env:COMPUTERNAME
    
    $line = "$timestamp,$date,$time,$($ActivityInfo.ProcessName),$($ActivityInfo.ProcessId),$($ActivityInfo.WindowTitle),$($ActivityInfo.Category),$SampleSeconds,$userName,$machineName"
    $line | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

function Get-TodayLogFile {
    param (
        [string]$LogFolder
    )
    $date = Get-Date -Format "yyyy-MM-dd"
    return Join-Path $LogFolder "activity-$date.csv"
}

Export-ModuleMember -Function Get-ActiveWindowInfo, Initialize-LogFile, Write-ActivityLog, Get-TodayLogFile