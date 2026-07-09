# Session.Core.psm1 - Pure timed-session + Pomodoro state machine for AFOTRA
# Author: CodeScooper | Project: AFOTRA - Awema Focus Tracker
#
# No UI, no real clock: every function takes an explicit -Now, so the whole state
# machine is unit-testable headless. The dashboard drives it from a 1s DispatcherTimer.
#
# Two clocks are tracked:
#   * work  = time actually spent working (excludes pauses and Pomodoro breaks)
#   * global = wall-clock from start to end (includes pauses/breaks)
#   * pause  = global - work  (so we can see breaks taken or skipped)

$script:DefaultPomodoro = @{
    workMinutes       = 25
    shortBreakMinutes = 5
    longBreakMinutes  = 15
    longBreakEvery    = 4
    autoStartNext     = $false
}

function Get-PomodoroConfig {
    # Merge a caller-provided config (hashtable or JSON PSObject) over the defaults.
    param([object]$Config)
    $c = $script:DefaultPomodoro.Clone()
    if ($Config) {
        foreach ($k in @('workMinutes', 'shortBreakMinutes', 'longBreakMinutes', 'longBreakEvery', 'autoStartNext')) {
            $v = $null
            if ($Config -is [hashtable]) {
                if ($Config.ContainsKey($k)) { $v = $Config[$k] }
            }
            else {
                $p = $Config.PSObject.Properties[$k]
                if ($p) { $v = $p.Value }
            }
            if ($null -ne $v -and "$v" -ne "") { $c[$k] = $v }
        }
    }
    return $c
}

function Get-PomodoroBreakType {
    # Long break every Nth completed work interval, short otherwise.
    param([int]$PomCompleted, [object]$Config)
    $c = Get-PomodoroConfig $Config
    $every = [int]$c.longBreakEvery
    if ($every -gt 0 -and $PomCompleted -gt 0 -and ($PomCompleted % $every) -eq 0) {
        return [PSCustomObject]@{ Type = 'Long'; Minutes = [int]$c.longBreakMinutes }
    }
    return [PSCustomObject]@{ Type = 'Short'; Minutes = [int]$c.shortBreakMinutes }
}

function Get-CountdownState {
    # Countdown from the estimate; once past it, report the overrun. No estimate -> count up.
    param([int]$EstimateSec, [int]$WorkSec)
    if ($EstimateSec -le 0) {
        return [PSCustomObject]@{ HasTarget = $false; RemainingSec = 0; IsOverrun = $false; OverrunSec = 0; ElapsedSec = $WorkSec }
    }
    $remaining = $EstimateSec - $WorkSec
    if ($remaining -ge 0) {
        return [PSCustomObject]@{ HasTarget = $true; RemainingSec = $remaining; IsOverrun = $false; OverrunSec = 0; ElapsedSec = $WorkSec }
    }
    return [PSCustomObject]@{ HasTarget = $true; RemainingSec = 0; IsOverrun = $true; OverrunSec = (-$remaining); ElapsedSec = $WorkSec }
}

# ---- internal: live seconds incl. the current running segment ---------------
function Get-LiveWorkSec {
    param([hashtable]$State, [datetime]$Now)
    $w = [int]$State.WorkAccumSec
    if ($State.Mode -eq 'Running' -and $State.LastResume) {
        $w += [int][math]::Floor(($Now - $State.LastResume).TotalSeconds)
    }
    return $w
}
function Get-LivePomSec {
    param([hashtable]$State, [datetime]$Now)
    $p = [int]$State.PomWorkSec
    if ($State.Mode -eq 'Running' -and $State.LastResume) {
        $p += [int][math]::Floor(($Now - $State.LastResume).TotalSeconds)
    }
    return $p
}

function Start-Session {
    param([string]$TaskId, [int]$EstimateSec = 0, [object]$Config, [datetime]$Now = (Get-Date))
    return @{
        TaskId       = $TaskId
        EstimateSec  = [int]$EstimateSec
        StartWall    = $Now
        WorkAccumSec = 0
        LastResume   = $Now
        Mode         = 'Running'   # Running | Paused | Break
        PomWorkSec   = 0
        PomCompleted = 0
        Config       = (Get-PomodoroConfig $Config)
        BreakType    = $null
        BreakEndsAt  = $null
    }
}

function Step-Session {
    # Non-mutating: computes a live readout from LastResume (no per-tick accumulation
    # so there is no rounding drift over long sessions).
    param([hashtable]$State, [datetime]$Now = (Get-Date))
    $workSec   = Get-LiveWorkSec -State $State -Now $Now
    $globalSec = [int][math]::Floor(($Now - $State.StartWall).TotalSeconds)
    $pomSec    = Get-LivePomSec -State $State -Now $Now
    $pomTarget = [int]$State.Config.workMinutes * 60
    $cd        = Get-CountdownState -EstimateSec ([int]$State.EstimateSec) -WorkSec $workSec

    $breakRemaining = 0
    $breakEnded = $false
    if ($State.Mode -eq 'Break' -and $State.BreakEndsAt) {
        $breakRemaining = [math]::Max(0, [int][math]::Ceiling(($State.BreakEndsAt - $Now).TotalSeconds))
        $breakEnded = ($Now -ge $State.BreakEndsAt)
    }

    return [PSCustomObject]@{
        Mode            = $State.Mode
        WorkSec         = $workSec
        GlobalSec       = $globalSec
        PauseSec        = [math]::Max(0, $globalSec - $workSec)
        RemainingSec    = $cd.RemainingSec
        IsOverrun       = $cd.IsOverrun
        OverrunSec      = $cd.OverrunSec
        HasTarget       = $cd.HasTarget
        PomSec          = $pomSec
        PomRemainingSec = [math]::Max(0, $pomTarget - $pomSec)
        PomCompleted    = $State.PomCompleted
        BreakDue        = (($State.Mode -eq 'Running') -and ($pomSec -ge $pomTarget))
        BreakType       = $State.BreakType
        BreakRemaining  = $breakRemaining
        BreakEnded      = $breakEnded
    }
}

function Suspend-Session {
    param([hashtable]$State, [datetime]$Now = (Get-Date))
    if ($State.Mode -eq 'Running' -and $State.LastResume) {
        $seg = [int][math]::Floor(($Now - $State.LastResume).TotalSeconds)
        $State.WorkAccumSec += $seg
        $State.PomWorkSec   += $seg
    }
    $State.Mode = 'Paused'
    $State.LastResume = $null
    return $State
}

function Resume-Session {
    param([hashtable]$State, [datetime]$Now = (Get-Date))
    $State.Mode = 'Running'
    $State.LastResume = $Now
    $State.BreakType = $null
    $State.BreakEndsAt = $null
    return $State
}

function Start-SessionBreak {
    param([hashtable]$State, [datetime]$Now = (Get-Date))
    if ($State.Mode -eq 'Running' -and $State.LastResume) {
        $seg = [int][math]::Floor(($Now - $State.LastResume).TotalSeconds)
        $State.WorkAccumSec += $seg
        $State.PomWorkSec   += $seg
    }
    $State.PomCompleted += 1
    $State.PomWorkSec = 0
    $bt = Get-PomodoroBreakType -PomCompleted $State.PomCompleted -Config $State.Config
    $State.BreakType = $bt.Type
    $State.BreakEndsAt = $Now.AddMinutes([int]$bt.Minutes)
    $State.Mode = 'Break'
    $State.LastResume = $null   # work frozen during the break; global keeps counting
    return $State
}

function Stop-SessionBreak {
    param([hashtable]$State, [datetime]$Now = (Get-Date))
    return (Resume-Session -State $State -Now $Now)
}

function Get-SessionResult {
    param([hashtable]$State, [datetime]$Now = (Get-Date))
    $workSec = Get-LiveWorkSec -State $State -Now $Now
    $globalSec = [int][math]::Floor(($Now - $State.StartWall).TotalSeconds)
    return [PSCustomObject]@{
        TaskId          = $State.TaskId
        Debut           = $State.StartWall.ToString('s')
        Fin             = $Now.ToString('s')
        TravailSecondes = $workSec
        GlobalSecondes  = $globalSec
        PauseSecondes   = [math]::Max(0, $globalSec - $workSec)
        PomodorosFait   = $State.PomCompleted
    }
}

Export-ModuleMember -Function `
    Get-PomodoroConfig, Get-PomodoroBreakType, Get-CountdownState, `
    Start-Session, Step-Session, Suspend-Session, Resume-Session, `
    Start-SessionBreak, Stop-SessionBreak, Get-SessionResult
