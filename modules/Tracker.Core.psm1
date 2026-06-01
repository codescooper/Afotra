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

# Type separe pour la detection d'inactivite (ne pas toucher au type Win32 garde
# ci-dessus, qui ne serait pas mis a jour lors d'un re-import -Force).
if (-not ([System.Management.Automation.PSTypeName]'Win32Idle').Type) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32Idle {
    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    public static uint IdleMillis() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(lii);
        if (!GetLastInputInfo(ref lii)) return 0;
        return (uint)Environment.TickCount - lii.dwTime;
    }
}
"@
}

function Get-IdleSeconds {
    # Secondes ecoulees depuis la derniere activite clavier/souris (0 si erreur).
    try { return [int]([Win32Idle]::IdleMillis() / 1000) }
    catch { return 0 }
}

function Get-IsSessionLocked {
    # L'ecran de verrouillage Windows met LogonUI/LockApp au premier plan.
    param([object]$ActivityInfo)
    if (-not $ActivityInfo) { return $false }
    return ($ActivityInfo.ProcessName -in @("LockApp", "LogonUI"))
}

# ---- Verrou de processus (fichier PID) : fiabilise -Check / -Stop ----
function Set-TrackerLock {
    param([string]$LockFile, [int]$ProcessId = $PID)
    [string]$ProcessId | Set-Content -Path $LockFile -Encoding ASCII -Force
}

function Test-TrackerRunning {
    param([string]$LockFile)
    if (!(Test-Path $LockFile)) { return $false }
    $pidVal = Get-Content $LockFile -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $pidVal) { return $false }
    $proc = Get-Process -Id ([int]$pidVal) -ErrorAction SilentlyContinue
    return ($null -ne $proc -and $proc.ProcessName -match 'powershell|pwsh')
}

function Remove-TrackerLock {
    param([string]$LockFile)
    Remove-Item $LockFile -ErrorAction SilentlyContinue
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

Export-ModuleMember -Function Get-ActiveWindowInfo, Initialize-LogFile, Write-ActivityLog, Get-TodayLogFile, Get-IdleSeconds, Get-IsSessionLocked, Set-TrackerLock, Test-TrackerRunning, Remove-TrackerLock