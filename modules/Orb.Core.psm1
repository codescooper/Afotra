# Orb.Core.psm1 - Pure visual language + focus-guard logic for the AFOTRA assistant orb
# Author: CodeScooper | Project: AFOTRA - Awema Focus Tracker
#
# No UI. Maps assistant state -> a "mood", and a mood -> a visual spec (colour, glow,
# size, pulse, wobble). Keeping this pure makes the "at a glance" language unit-testable;
# the dashboard's animation timer just applies whatever these functions return.

function Get-OrbMood {
    # Decide the orb's mood from the session state + focus-guard flag.
    param(
        [bool]$HasSession     = $false,
        [string]$Mode         = 'None',   # Running | Paused | Break | None
        [bool]$IsOverrun      = $false,
        [bool]$Guard          = $false,   # an unknown process is foreground during a running session
        [bool]$AwaitingResume = $false    # a break just ended and is waiting for the user to resume
    )
    if ($Guard) { return 'Ask' }
    if (-not $HasSession) { return 'Idle' }
    if ($AwaitingResume) { return 'Resume' }   # "your turn — come back" (distinct from a plain pause)
    switch ($Mode) {
        'Break'   { 'Break' }
        'Paused'  { 'Break' }         # paused = resting -> same visual family
        'Running' { if ($IsOverrun) { 'Overrun' } else { 'Focus' } }
        default   { 'Idle' }
    }
}

function Get-OrbVisual {
    # Mood -> concrete look. Intensity (0..1) grows the "Ask" orb the longer it goes unanswered.
    param([string]$Mood = 'Idle', [double]$Intensity = 0.0)

    switch ($Mood) {
        'Focus' {
            $v = @{ Core = '#34D399'; Edge = '#10B981'; Glow = '#10B981'; GlowRadius = 26
                    SizePx = 112; PulseAmp = 0.05;  PulsePeriodMs = 2500; WobbleAmp = 0.03; MoveToCenter = $false }
        }
        'Break' {
            $v = @{ Core = '#A78BFA'; Edge = '#8B5CF6'; Glow = '#8B5CF6'; GlowRadius = 22
                    SizePx = 104; PulseAmp = 0.03;  PulsePeriodMs = 4200; WobbleAmp = 0.02; MoveToCenter = $false }
        }
        'Overrun' {
            $v = @{ Core = '#FB923C'; Edge = '#F97316'; Glow = '#F97316'; GlowRadius = 34
                    SizePx = 126; PulseAmp = 0.08;  PulsePeriodMs = 1200; WobbleAmp = 0.05; MoveToCenter = $false }
        }
        'Resume' {
            # Break is over: an inviting, attention-grabbing "come back to work" bloom.
            $v = @{ Core = '#6EE7B7'; Edge = '#10B981'; Glow = '#34D399'; GlowRadius = 42
                    SizePx = 150; PulseAmp = 0.11;  PulsePeriodMs = 900;  WobbleAmp = 0.04; MoveToCenter = $false }
        }
        'Ask' {
            $i = [math]::Max(0.0, [math]::Min(1.0, $Intensity))
            $v = @{ Core = '#F87171'; Edge = '#EF4444'; Glow = '#EF4444'; GlowRadius = 48
                    SizePx = [int](180 + 240 * $i); PulseAmp = 0.12; PulsePeriodMs = 650; WobbleAmp = 0.09; MoveToCenter = $true }
        }
        default {
            # Idle
            $v = @{ Core = '#5EEAD4'; Edge = '#14B8A6'; Glow = '#14B8A6'; GlowRadius = 18
                    SizePx = 92;  PulseAmp = 0.035; PulsePeriodMs = 4000; WobbleAmp = 0.02; MoveToCenter = $false }
        }
    }
    return [PSCustomObject]$v
}

function Test-ProcessAllowed {
    # Is this foreground process "on task"? AFOTRA itself and idle/lock markers always pass.
    param([string]$ProcessName, [string[]]$AllowList = @())
    if ([string]::IsNullOrWhiteSpace($ProcessName)) { return $true }
    $p = $ProcessName.ToLowerInvariant()
    $alwaysOk = @('afotra', 'powershell', 'pwsh', 'idle', 'inactif', 'lockapp', 'logonui')
    if ($alwaysOk -contains $p) { return $true }
    foreach ($a in @($AllowList)) {
        if (-not $a) { continue }
        if ($p -eq ([string]$a).ToLowerInvariant()) { return $true }
    }
    return $false
}

Export-ModuleMember -Function Get-OrbMood, Get-OrbVisual, Test-ProcessAllowed
