# Notify.Core.psm1 - Windows notification abstraction for AFOTRA
# Author: CodeScooper | Project: AFOTRA - Awema Focus Tracker
#
# Prefers BurntToast (real Windows toasts) when the module is installed; otherwise
# falls back to System.Windows.Forms.NotifyIcon balloon tips (zero external deps).
# Show-AfotraNotification returns the backend it used ("BurntToast" / "NotifyIcon"),
# which also makes it testable via -NoShow (decide backend without popping any UI).

$script:AfotraNotifyIcon = $null

function Test-BurntToast {
    # True if the BurntToast module is available for import. Never throws.
    try { return [bool](Get-Module -ListAvailable -Name BurntToast) }
    catch { return $false }
}

function Show-BalloonNotification {
    param([string]$Title, [string]$Message, [switch]$NoShow)
    if ($NoShow) { return 'NotifyIcon' }
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        if (-not $script:AfotraNotifyIcon) {
            $script:AfotraNotifyIcon = New-Object System.Windows.Forms.NotifyIcon
            $script:AfotraNotifyIcon.Icon = [System.Drawing.SystemIcons]::Information
            $script:AfotraNotifyIcon.Text = 'AFOTRA'
            $script:AfotraNotifyIcon.Visible = $true
        }
        $script:AfotraNotifyIcon.BalloonTipTitle = $Title
        $script:AfotraNotifyIcon.BalloonTipText  = $Message
        $script:AfotraNotifyIcon.ShowBalloonTip(10000)
    }
    catch { }
    return 'NotifyIcon'
}

function Show-AfotraNotification {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Message,
        [switch]$NoShow
    )

    if (Test-BurntToast) {
        if ($NoShow) { return 'BurntToast' }
        try {
            Import-Module BurntToast -ErrorAction Stop
            New-BurntToastNotification -Text $Title, $Message | Out-Null
            return 'BurntToast'
        }
        catch {
            # BurntToast present but failed to fire -> graceful fallback.
            return (Show-BalloonNotification -Title $Title -Message $Message)
        }
    }

    return (Show-BalloonNotification -Title $Title -Message $Message -NoShow:$NoShow)
}

function Close-AfotraNotifier {
    if ($script:AfotraNotifyIcon) {
        try { $script:AfotraNotifyIcon.Visible = $false; $script:AfotraNotifyIcon.Dispose() } catch { }
        $script:AfotraNotifyIcon = $null
    }
}

Export-ModuleMember -Function Test-BurntToast, Show-AfotraNotification, Show-BalloonNotification, Close-AfotraNotifier
