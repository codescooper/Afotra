# dashboard-wpf.ps1 - Modern WPF Dashboard for AFOTRA - Awema Focus Tracker
# Author: CodeScooper | Version: 2.0 (Improved)
# Project: AFOTRA - Awema Focus Tracker

param(
    [switch]$Debug
)

$ErrorActionPreference = "Stop"

trap {
    try {
        $root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
        $dir = Join-Path $root "logs"
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $log = Join-Path $dir "dashboard-error.log"
        $msg = @(
            "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Fatal dashboard error"
            $_.Exception.ToString()
            "Invocation: $($_.InvocationInfo.PositionMessage)"
            ""
        ) -join [Environment]::NewLine
        Add-Content -Path $log -Value $msg -Encoding UTF8
        Write-Host ""
        Write-Host "AFOTRA dashboard error. Details written to: $log" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Read-Host "Press Enter to close"
    } catch { }
    break
}

# This dashboard requires Windows + Desktop .NET (WPF)
# $IsWindows only exists in PowerShell 6+; on Windows PowerShell 5.x we are always on Windows
$isWindowsOS = if ($PSVersionTable.PSVersion.Major -ge 6) { $IsWindows } else { $true }
if (-not $isWindowsOS) {
# This dashboard requires Windows + Desktop .NET (WPF)
# NOTE: $IsWindows does not exist in Windows PowerShell 5.1, so we need a compatible check.
$isRunningOnWindows = $false
if (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) {
    $isRunningOnWindows = [bool]$IsWindows
} else {
    $isRunningOnWindows = ($env:OS -eq "Windows_NT")
}

if (-not $isRunningOnWindows) {
    throw "AFOTRA dashboard-wpf.ps1 requires Windows (WPF is not available on this OS)."
}

# Add WPF assemblies
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

# Import required modules
$scriptRoot = $PSScriptRoot
$configPath = Join-Path $scriptRoot "config.json"
$rulesPath = Join-Path $scriptRoot "rules.json"
$logFolder = Join-Path $scriptRoot "logs"
$dashboardLogPath = Join-Path $logFolder "dashboard-runtime.log"

# Ensure logs folder exists
if (!(Test-Path $logFolder)) {
    New-Item -ItemType Directory -Path $logFolder -Force | Out-Null
}
if (!(Test-Path (Join-Path $logFolder "reports"))) {
    New-Item -ItemType Directory -Path (Join-Path $logFolder "reports") -Force | Out-Null
}

# Import modules with error handling
try {
    Import-Module (Join-Path $scriptRoot "modules\Tracker.Core.psm1") -Force
    Import-Module (Join-Path $scriptRoot "modules\Rules.Core.psm1") -Force
    Import-Module (Join-Path $scriptRoot "modules\Report.Core.psm1") -Force
    Import-Module (Join-Path $scriptRoot "modules\Tasks.Core.psm1") -Force -DisableNameChecking
    Import-Module (Join-Path $scriptRoot "modules\Notify.Core.psm1") -Force -DisableNameChecking
    Import-Module (Join-Path $scriptRoot "modules\Session.Core.psm1") -Force -DisableNameChecking
    Import-Module (Join-Path $scriptRoot "modules\Orb.Core.psm1") -Force -DisableNameChecking
    Import-Module (Join-Path $scriptRoot "modules\SessionReport.Core.psm1") -Force -DisableNameChecking
} catch {
    [Windows.MessageBox]::Show("Error loading modules: $_", "AFOTRA Error") | Out-Null
    exit 1
function Write-DashboardLog {
    param(
        [string]$Message,
        [AllowNull()]
        [object]$ErrorObject = $null
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $details = ""
    if ($null -ne $ErrorObject) {
        $exception = if ($ErrorObject -is [System.Management.Automation.ErrorRecord]) {
            $ErrorObject.Exception
        } elseif ($ErrorObject -is [System.Exception]) {
            $ErrorObject
        } else {
            $null
        }
        $details = "`r`n$([string]$ErrorObject)"
        if ($exception) { $details += "`r`n$($exception.ToString())" }
        if ($ErrorObject -is [System.Management.Automation.ErrorRecord] -and $ErrorObject.ScriptStackTrace) {
            $details += "`r`nPowerShell stack:`r`n$($ErrorObject.ScriptStackTrace)"
        }
    }
    "[$timestamp] $Message$details" | Out-File -FilePath $dashboardLogPath -Append -Encoding UTF8
}

function Show-DashboardError {
    param(
        [string]$Message,
        [AllowNull()]
        [object]$ErrorObject = $null
    )

    Write-DashboardLog -Message $Message -ErrorObject $ErrorObject
    [Windows.MessageBox]::Show("$Message`n`nDetails saved to:`n$dashboardLogPath", "AFOTRA Error") | Out-Null
}

[AppDomain]::CurrentDomain.add_UnhandledException({
    param($sender, $eventArgs)
    Write-DashboardLog -Message "Unhandled AppDomain exception" -ErrorObject $eventArgs.ExceptionObject
})

[System.Windows.Threading.Dispatcher]::CurrentDispatcher.add_UnhandledException({
    param($sender, $eventArgs)
    Write-DashboardLog -Message "Unhandled WPF dispatcher exception" -ErrorObject $eventArgs.Exception
    [Windows.MessageBox]::Show("An unexpected dashboard error was handled.`n`nDetails saved to:`n$dashboardLogPath", "AFOTRA Error") | Out-Null
    $eventArgs.Handled = $true
})

# Import modules
Import-Module (Join-Path $scriptRoot "modules\Tracker.Core.psm1") -Force
Import-Module (Join-Path $scriptRoot "modules\Rules.Core.psm1") -Force
Import-Module (Join-Path $scriptRoot "modules\Report.Core.psm1") -Force

# Load configuration with fallback
$config = $null
if (Test-Path $configPath) {
    $config = Get-Content $configPath -Encoding UTF8 | ConvertFrom-Json
} else {
    $config = @{
        sampleIntervalSeconds = 10
        focusMinPerDay = 480
        maxDistractionMinPerDay = 120
        logFolder = "logs"
    }
}

$rules = Load-Rules -RulesPath $rulesPath

# Make configuration global for timer access
$global:config = $config
$global:rules = $rules
$global:logFolder = $logFolder
$global:SessionCheckpointFile = Join-Path $global:logFolder "session-current.json"
$global:rulesPath = $rulesPath
$global:configPath = $configPath

function Get-DashboardFocusCategories {
    if ($global:config -and $global:config.focusCategories) {
        return @($global:config.focusCategories)
    }
    return @("travail")
}

function Get-DashboardReportData {
    $logFile = Get-TodayLogFile -LogFolder $global:logFolder
    if (!(Test-Path $logFile)) { return $null }
    return Get-ReportData -LogFile $logFile -FocusCategories (Get-DashboardFocusCategories)
}

# Global state
$global:TrackerRunning = $false
$global:TrackerTimer = $null
$global:CurrentView = "DashboardView"
$global:CurrentActivityStart = $null
$global:CurrentActivityInfo = $null
$global:CurrentLogFile = $null
$global:LastSampleAt = $null
$global:LoggedRowsToday = 0
$global:SelectedTaskId = $null
$global:DashboardUpdateTimer = $null
$global:LastActivityGroup = $null
$global:TrackerTimerEventSub = $null
$global:DashboardTimerEventSub = $null
$global:TrackerBusy = $false
$global:OverlayWindow = $null
$global:OverlayDispTimer = $null
$global:DistractionStreakStart = $null
$global:ShakeActive = $false
$global:ShakeBaseLeft = 20.0
$global:ShakeStep = 0
$global:OverlayMinimized = $false
$global:AlarmActive = $false
$global:AlarmThread = $null
# Tasks module state
$global:taskStorePath = Get-TaskStorePath
$global:TaskReminderTimer = $null
$global:TaskFilter = "Tous"      # Tous | AFaire | EnCours | Aujourdhui | Retard
$global:TaskSearch = ""
# Work-session (Pomodoro) state
$global:PomodoroConfig = Get-PomodoroConfig ($config.pomodoro)
$global:PomodoroSound  = if ($config.pomodoro -and $null -ne $config.pomodoro.sound) { [bool]$config.pomodoro.sound } else { $true }
$global:SessionState = $null     # Session.Core state hashtable, or $null when idle
$global:SessionTimer = $null     # 1s DispatcherTimer driving the live session
$global:SessionReadout = $null   # last 1s readout; dashboard/overlay/orb share it
$global:SessionDisplayText = "--:--"
$global:SessionDisplayBrush = "#9CA3AF"
$global:SessionMilestonesFired = @{}
$global:SessionPomodoroSuggestionsFired = @{}
$global:OrbMilestonePopup = $null
$global:OrbMilestoneText = $null
$global:OrbMilestoneTimer = $null
# Assistant orb + focus-guard state
$asst = $config.assistant
$global:AsstOrbEnabled  = if ($asst -and $null -ne $asst.orbEnabled)  { [bool]$asst.orbEnabled }  else { $true }
$global:AsstFocusGuard  = if ($asst -and $null -ne $asst.focusGuard)  { [bool]$asst.focusGuard }  else { $true }
$global:AsstGuardSound  = if ($asst -and $null -ne $asst.guardSound)  { [bool]$asst.guardSound }  else { $false }
$global:AsstOrbMinSize  = if ($asst -and $asst.orbMinSize) { [int]$asst.orbMinSize } else { 90 }
$global:AsstOrbMaxSize  = if ($asst -and $asst.orbMaxSize) { [int]$asst.orbMaxSize } else { 420 }
$global:OrbAnimTimer = $null
$global:OrbPhase = 0.0            # pulse phase accumulator
$global:OrbCurSize = 90.0        # current interpolated orb diameter
$global:OrbCenter = $null        # current window centre (screen coords)
$global:OrbHome = $null          # resting window centre
$global:OrbHover = $false
$global:GuardAllow = @()         # per-session allow-list (process names)
$global:GuardSnooze = @()        # per-session "Ignorer" set
$global:GuardAsking = $null      # process currently being questioned
$global:GuardAskStart = $null
$global:GuardCooldownUntil = $null
$global:GuardOffTaskSince = $null  # start of the current off-task streak (drives escalation)
$global:GuardNonCount = 0          # times "Non" was pressed this streak (bumps escalation + sound)
$global:GuardReaskAt = $null       # after "Non", when to pop the question again

# XAML for the main window
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AFOTRA - Awema Focus Tracker v2.0" Height="760" Width="1180" MinHeight="620" MinWidth="960" SizeToContent="Manual"
        WindowStartupLocation="CenterScreen" Background="#222222">
    <Window.Resources>
        <SolidColorBrush x:Key="PrimaryBrush" Color="#FFC107"/>
        <SolidColorBrush x:Key="SecondaryBrush" Color="#3A3A3A"/>
        <SolidColorBrush x:Key="SuccessBrush" Color="#10B981"/>
        <SolidColorBrush x:Key="WarningBrush" Color="#F59E0B"/>
        <SolidColorBrush x:Key="DangerBrush" Color="#EF4444"/>
        <SolidColorBrush x:Key="CardBackground" Color="#2B2B2B"/>
        <SolidColorBrush x:Key="TextPrimary" Color="#F5F5F5"/>
        <SolidColorBrush x:Key="TextSecondary" Color="#9A9A9A"/>
        <Style TargetType="Button">
            <Setter Property="Foreground" Value="#F5F5F5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="ButtonChrome" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" Padding="{TemplateBinding Padding}" CornerRadius="3">
                            <ContentPresenter x:Name="ButtonContent" HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}" RecognizesAccessKey="True" TextElement.Foreground="{TemplateBinding Foreground}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ButtonChrome" Property="Opacity" Value="0.88"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="ButtonChrome" Property="Opacity" Value="0.74"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="ButtonChrome" Property="Background" Value="#3A3A3A"/>
                                <Setter TargetName="ButtonChrome" Property="BorderBrush" Value="#4A4A4A"/>
                                <Setter TargetName="ButtonContent" Property="TextElement.Foreground" Value="#8F8F8F"/>
                                <Setter TargetName="ButtonChrome" Property="Opacity" Value="1"/>
                                <Setter Property="Cursor" Value="Arrow"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="ScrollBar">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Width" Value="8"/>
            <Setter Property="MinWidth" Value="8"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ScrollBar">
                        <Grid x:Name="Root" Width="8" Background="Transparent">
                            <Track x:Name="PART_Track" IsDirectionReversed="True">
                                <Track.DecreaseRepeatButton>
                                    <RepeatButton Command="ScrollBar.PageUpCommand" Opacity="0" IsHitTestVisible="False"/>
                                </Track.DecreaseRepeatButton>
                                <Track.Thumb>
                                    <Thumb x:Name="Thumb" Background="#6B5B2A" MinHeight="38">
                                        <Thumb.Template>
                                            <ControlTemplate TargetType="Thumb">
                                                <Border x:Name="ThumbChrome" Width="6" Margin="1,3" CornerRadius="3" Background="{TemplateBinding Background}"/>
                                                <ControlTemplate.Triggers>
                                                    <Trigger Property="IsMouseOver" Value="True">
                                                        <Setter TargetName="ThumbChrome" Property="Background" Value="#FFC107"/>
                                                    </Trigger>
                                                    <Trigger Property="IsDragging" Value="True">
                                                        <Setter TargetName="ThumbChrome" Property="Background" Value="#FFD54F"/>
                                                    </Trigger>
                                                </ControlTemplate.Triggers>
                                            </ControlTemplate>
                                        </Thumb.Template>
                                    </Thumb>
                                </Track.Thumb>
                                <Track.IncreaseRepeatButton>
                                    <RepeatButton Command="ScrollBar.PageDownCommand" Opacity="0" IsHitTestVisible="False"/>
                                </Track.IncreaseRepeatButton>
                            </Track>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="Orientation" Value="Horizontal">
                                <Setter TargetName="Root" Property="Width" Value="Auto"/>
                                <Setter TargetName="Root" Property="Height" Value="8"/>
                                <Setter Property="Height" Value="8"/>
                                <Setter Property="MinHeight" Value="8"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="DataGrid">
            <Setter Property="Background" Value="#2B2B2B"/>
            <Setter Property="Foreground" Value="#F5F5F5"/>
            <Setter Property="BorderBrush" Value="#383838"/>
            <Setter Property="RowBackground" Value="#2B2B2B"/>
            <Setter Property="AlternatingRowBackground" Value="#262626"/>
            <Setter Property="GridLinesVisibility" Value="None"/>
            <Setter Property="HeadersVisibility" Value="Column"/>
            <Setter Property="SelectionMode" Value="Single"/>
            <Setter Property="SelectionUnit" Value="FullRow"/>
        </Style>
        <Style TargetType="DataGridColumnHeader">
            <Setter Property="Background" Value="#1F1F1F"/>
            <Setter Property="Foreground" Value="#FFC107"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="BorderThickness" Value="0"/>
        </Style>
        <Style TargetType="DataGridCell">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#F5F5F5"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="6,4"/>
            <Style.Triggers>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="Transparent"/>
                    <Setter Property="Foreground" Value="#1A1A1A"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="DataGridRow">
            <Setter Property="Background" Value="#2B2B2B"/>
            <Setter Property="Foreground" Value="#F5F5F5"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#353535"/>
                </Trigger>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="#FFC107"/>
                    <Setter Property="Foreground" Value="#1A1A1A"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#333333"/>
            <Setter Property="Foreground" Value="#F5F5F5"/>
            <Setter Property="BorderBrush" Value="#4A4A4A"/>
            <Setter Property="CaretBrush" Value="#FFC107"/>
            <Setter Property="BorderThickness" Value="1"/>
        </Style>
        <Style TargetType="ListBox">
            <Setter Property="Background" Value="#2B2B2B"/>
            <Setter Property="Foreground" Value="#F5F5F5"/>
            <Setter Property="BorderBrush" Value="#383838"/>
        </Style>
    </Window.Resources>
    <Grid>
        <!-- Sidebar Navigation -->
        <Border Background="#1A1A1A" Width="260" HorizontalAlignment="Left">
            <StackPanel Margin="18">
                <!-- Bee logo + wordmark -->
                <StackPanel Orientation="Horizontal" Margin="0,4,0,4">
                    <Viewbox Width="46" Height="42" VerticalAlignment="Center">
                        <Grid Width="46" Height="42">
                            <Ellipse Width="18" Height="14" Fill="#66FFFFFF" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="3,2,0,0"/>
                            <Ellipse Width="18" Height="14" Fill="#66FFFFFF" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,2,3,0"/>
                            <Ellipse Width="16" Height="14" Fill="#141414" HorizontalAlignment="Center" VerticalAlignment="Top" Margin="0,0,0,0"/>
                            <Border Width="26" Height="30" CornerRadius="13" Background="#FFC107" VerticalAlignment="Bottom" HorizontalAlignment="Center" ClipToBounds="True">
                                <StackPanel VerticalAlignment="Center">
                                    <Rectangle Height="4" Fill="#141414" Margin="0,2,0,0"/>
                                    <Rectangle Height="4" Fill="#141414" Margin="0,3,0,0"/>
                                    <Rectangle Height="4" Fill="#141414" Margin="0,3,0,0"/>
                                </StackPanel>
                            </Border>
                        </Grid>
                    </Viewbox>
                    <StackPanel VerticalAlignment="Center" Margin="10,0,0,0">
                        <TextBlock Text="AFOTRA" FontSize="22" FontWeight="Bold" Foreground="#FFC107"/>
                        <TextBlock Text="Focus Tracker" FontSize="10" Foreground="#8A8A8A"/>
                    </StackPanel>
                </StackPanel>
                <Separator Background="#2E2E2E" Margin="0,16,0,16"/>

                <Button x:Name="NavDashboard" Content="Dashboard" Background="#1A1A1A" Foreground="#CFCFCF" FontWeight="SemiBold" FontSize="13" Padding="12,9" BorderThickness="0" Cursor="Hand" Margin="0,0,0,6" HorizontalContentAlignment="Left"/>
                <Button x:Name="NavLiveTracking" Content="Live Tracking" Background="#1A1A1A" Foreground="#CFCFCF" FontWeight="SemiBold" FontSize="13" Padding="12,9" BorderThickness="0" Cursor="Hand" Margin="0,0,0,6" HorizontalContentAlignment="Left"/>
                <Button x:Name="NavUnknownActivities" Content="Unknown" Background="#1A1A1A" Foreground="#CFCFCF" FontWeight="SemiBold" FontSize="13" Padding="12,9" BorderThickness="0" Cursor="Hand" Margin="0,0,0,6" HorizontalContentAlignment="Left"/>
                <Button x:Name="NavRulesCategories" Content="Rules" Background="#1A1A1A" Foreground="#CFCFCF" FontWeight="SemiBold" FontSize="13" Padding="12,9" BorderThickness="0" Cursor="Hand" Margin="0,0,0,6" HorizontalContentAlignment="Left"/>
                <Button x:Name="NavTasks" Content="Tâches" Background="#1A1A1A" Foreground="#CFCFCF" FontWeight="SemiBold" FontSize="13" Padding="12,9" BorderThickness="0" Cursor="Hand" Margin="0,0,0,24" HorizontalContentAlignment="Left"/>

                <Separator Background="#2E2E2E" Margin="0,0,0,18"/>

                <Button x:Name="BtnStartStop" Content="Start Tracking" Background="#FFC107" Foreground="#1A1A1A" FontWeight="Bold" FontSize="14" Padding="12,8" BorderThickness="0" Cursor="Hand" Margin="0,0,0,12" Height="42"/>
                <TextBlock x:Name="StatusText" Text="Status: Stopped" Foreground="#CFCFCF" Margin="0,6,0,0" FontSize="11" TextAlignment="Center" FontWeight="SemiBold"/>
                <TextBlock x:Name="CurrentProcessText" Text="Process: --" Foreground="#8A8A8A" Margin="0,12,0,0" FontSize="10" TextWrapping="Wrap"/>
                <Button x:Name="BtnToggleOverlay" Content="Afficher Overlay" Background="#333333" Foreground="#E5E5E5" FontWeight="SemiBold" FontSize="11" Padding="12,6" BorderThickness="0" Cursor="Hand" Margin="0,12,0,0"/>
            </StackPanel>
        </Border>

        <!-- Main Content Area -->
        <Grid Margin="260,0,0,0">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <!-- Top bar -->
            <Border Grid.Row="0" Background="#222222" Padding="24,16,24,10">
                <Grid>
                    <TextBlock Text="🐝 Awema Focus Tracker" FontSize="14" FontWeight="SemiBold" Foreground="#8A8A8A" VerticalAlignment="Center"/>
                    <Border HorizontalAlignment="Right" Background="#333333" CornerRadius="18" Padding="14,7" Width="280">
                        <Grid>
                            <TextBlock Text="🔍  Rechercher une tâche..." Foreground="#7A7A7A" FontSize="12" VerticalAlignment="Center" x:Name="SearchPlaceholder"/>
                            <TextBox x:Name="GlobalSearchBox" Background="Transparent" BorderThickness="0" Foreground="#F5F5F5" FontSize="12" VerticalAlignment="Center"/>
                        </Grid>
                    </Border>
                </Grid>
            </Border>
            <ScrollViewer Grid.Row="1" Margin="24,4,24,20" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                <StackPanel x:Name="MainContent" Margin="0,0,0,20">
                
                <!-- Dashboard View -->
                <StackPanel x:Name="DashboardView" Visibility="Visible">
                    <TextBlock Text="Dashboard" FontSize="30" FontWeight="Bold" Foreground="#F5F5F5" Margin="0,4,0,20"/>

                    <!-- Metric tiles -->
                    <Grid Margin="0,0,0,20">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="1*"/><ColumnDefinition Width="1*"/><ColumnDefinition Width="1*"/><ColumnDefinition Width="1*"/>
                        </Grid.ColumnDefinitions>
                        <Border Grid.Column="0" Background="#2B2B2B" CornerRadius="10" BorderBrush="#383838" BorderThickness="1" Margin="0,0,12,0">
                            <StackPanel Margin="16">
                                <TextBlock Text="⏱  Temps total" FontSize="12" Foreground="#9A9A9A"/>
                                <TextBlock x:Name="TotalTimeText" Text="00:00:00" FontSize="26" FontWeight="Bold" Foreground="#F5F5F5" Margin="0,8,0,10"/>
                                <Border Height="4" CornerRadius="2" Background="#FFC107"/>
                            </StackPanel>
                        </Border>
                        <Border Grid.Column="1" Background="#2B2B2B" CornerRadius="10" BorderBrush="#383838" BorderThickness="1" Margin="0,0,12,0">
                            <StackPanel Margin="16">
                                <TextBlock Text="🍯  Focus" FontSize="12" Foreground="#9A9A9A"/>
                                <TextBlock x:Name="FocusTimeText" Text="00:00:00" FontSize="26" FontWeight="Bold" Foreground="#34D399" Margin="0,8,0,10"/>
                                <Border Height="4" CornerRadius="2" Background="#34D399"/>
                            </StackPanel>
                        </Border>
                        <Border Grid.Column="2" Background="#2B2B2B" CornerRadius="10" BorderBrush="#383838" BorderThickness="1" Margin="0,0,12,0">
                            <StackPanel Margin="16">
                                <TextBlock Text="🎯  Score focus" FontSize="12" Foreground="#9A9A9A"/>
                                <TextBlock x:Name="FocusScoreText" Text="0%" FontSize="26" FontWeight="Bold" Foreground="#FFC107" Margin="0,8,0,10"/>
                                <Border Height="4" CornerRadius="2" Background="#FFC107"/>
                            </StackPanel>
                        </Border>
                        <Border Grid.Column="3" Background="#2B2B2B" CornerRadius="10" BorderBrush="#383838" BorderThickness="1">
                            <StackPanel Margin="16">
                                <TextBlock Text="⚠  Distractions" FontSize="12" Foreground="#9A9A9A"/>
                                <TextBlock x:Name="DistractionTimeText" Text="00:00:00" FontSize="26" FontWeight="Bold" Foreground="#F87171" Margin="0,8,0,10"/>
                                <Border Height="4" CornerRadius="2" Background="#EF4444"/>
                            </StackPanel>
                        </Border>
                    </Grid>

                    <!-- Charts Section -->
                    <Border Background="#2B2B2B" CornerRadius="10" BorderBrush="#383838" BorderThickness="1" Margin="0,0,0,20">
                        <StackPanel Margin="20">
                            <TextBlock Text="Répartition de l'activité" FontSize="18" FontWeight="Bold" Foreground="#F5F5F5" Margin="0,0,0,15"/>
                            <Canvas x:Name="ActivityChartCanvas" Height="260" MinWidth="620" Background="#232323" HorizontalAlignment="Stretch"/>
                        </StackPanel>
                    </Border>

                    <!-- Tasks summary card -->
                    <Border Background="#2B2B2B" CornerRadius="10" BorderBrush="#383838" BorderThickness="1" Margin="0,0,0,20">
                        <StackPanel Margin="20">
                            <TextBlock Text="🐝 Tâches" FontSize="16" FontWeight="Bold" Foreground="#FFC107" Margin="0,0,0,12"/>
                            <WrapPanel>
                                <StackPanel Margin="0,0,40,0"><TextBlock Text="À faire" FontSize="11" Foreground="#9A9A9A"/><TextBlock x:Name="TaskCountAFaire" Text="0" FontSize="22" FontWeight="Bold" Foreground="#FFC107"/></StackPanel>
                                <StackPanel Margin="0,0,40,0"><TextBlock Text="En cours" FontSize="11" Foreground="#9A9A9A"/><TextBlock x:Name="TaskCountEnCours" Text="0" FontSize="22" FontWeight="Bold" Foreground="#F59E0B"/></StackPanel>
                                <StackPanel Margin="0,0,40,0"><TextBlock Text="Terminées auj." FontSize="11" Foreground="#9A9A9A"/><TextBlock x:Name="TaskCountTermine" Text="0" FontSize="22" FontWeight="Bold" Foreground="#34D399"/></StackPanel>
                                <StackPanel Margin="0,0,40,0"><TextBlock Text="En retard" FontSize="11" Foreground="#9A9A9A"/><TextBlock x:Name="TaskCountRetard" Text="0" FontSize="22" FontWeight="Bold" Foreground="#F87171"/></StackPanel>
                            </WrapPanel>
                        </StackPanel>
                    </Border>

                    <StackPanel Orientation="Horizontal" Margin="0,0,0,20">
                        <Button x:Name="BtnGenerateReport" Content="Générer un rapport" Background="#FFC107" Foreground="#1A1A1A" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand" Margin="0,0,10,0"/>
                        <Button x:Name="BtnOpenLogs" Content="Ouvrir les logs" Background="#3A3A3A" Foreground="#E5E5E5" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand"/>
                    </StackPanel>
                </StackPanel>

                <!-- Live Tracking View -->
                <StackPanel x:Name="LiveTrackingView" Visibility="Collapsed">
                    <TextBlock Text="Live Tracking" FontSize="32" FontWeight="Bold" Foreground="#F5F5F5" Margin="0,0,0,20"/>
                    
                    <Border Background="#2B2B2B" CornerRadius="10" BorderBrush="#383838" BorderThickness="1" Margin="0,0,0,20">
                        <StackPanel Margin="20">
                            <TextBlock Text="Current Activity" FontSize="18" FontWeight="Bold" Foreground="#F5F5F5" Margin="0,0,0,15"/>
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <StackPanel Grid.Column="0" Margin="0,0,20,0">
                                    <TextBlock Text="Process:" FontWeight="SemiBold" Foreground="#9A9A9A"/>
                                    <TextBlock x:Name="LiveProcessText" Text="--" FontSize="16" Margin="0,5,0,10" Foreground="#F5F5F5" FontFamily="Consolas"/>
                                    <TextBlock Text="Window Title:" FontWeight="SemiBold" Foreground="#9A9A9A"/>
                                    <TextBlock x:Name="LiveWindowText" Text="--" FontSize="13" Margin="0,5,0,10" TextWrapping="Wrap" Foreground="#F5F5F5"/>
                                </StackPanel>
                                <StackPanel Grid.Column="1">
                                    <TextBlock Text="Category:" FontWeight="SemiBold" Foreground="#9A9A9A"/>
                                    <TextBlock x:Name="LiveCategoryText" Text="--" FontSize="16" Margin="0,5,0,10" Foreground="#10B981" FontWeight="Bold"/>
                                    <TextBlock Text="Duration:" FontWeight="SemiBold" Foreground="#9A9A9A"/>
                                    <TextBlock x:Name="LiveCurrentTimeText" Text="00:00:00" FontSize="16" Margin="0,5,0,10" Foreground="#F5F5F5" FontFamily="Consolas" FontWeight="Bold"/>
                                    <TextBlock Text="Dernier échantillon:" FontWeight="SemiBold" Foreground="#9A9A9A"/>
                                    <TextBlock x:Name="LiveSampleText" Text="--" FontSize="13" Margin="0,5,0,10" Foreground="#FFC107" FontFamily="Consolas"/>
                                    <TextBlock Text="Échantillons aujourd'hui:" FontWeight="SemiBold" Foreground="#9A9A9A"/>
                                    <TextBlock x:Name="LiveLogCountText" Text="0" FontSize="13" Margin="0,5,0,0" Foreground="#F5F5F5" FontFamily="Consolas"/>
                                </StackPanel>
                            </Grid>
                            <TextBlock x:Name="LiveLogFileText" Text="Log: --" FontSize="11" Foreground="#9A9A9A" TextWrapping="Wrap" Margin="0,12,0,0"/>
                        </StackPanel>
                    </Border>
                    
                    <Border Background="#2B2B2B" CornerRadius="10" BorderBrush="#383838" BorderThickness="1">
                        <StackPanel Margin="20">
                            <TextBlock Text="Last 10 Activities" FontSize="18" FontWeight="Bold" Foreground="#F5F5F5" Margin="0,0,0,15"/>
                            <DataGrid x:Name="RecentActivitiesGrid" Height="280" AutoGenerateColumns="False" IsReadOnly="True" Background="#2B2B2B">
                                <DataGrid.Columns>
                                    <DataGridTextColumn Header="Time" Binding="{Binding Time}" Width="70"/>
                                    <DataGridTextColumn Header="Process" Binding="{Binding Process}" Width="100"/>
                                    <DataGridTextColumn Header="Window Title" Binding="{Binding Title}" Width="*"/>
                                    <DataGridTextColumn Header="Category" Binding="{Binding Category}" Width="100"/>
                                </DataGrid.Columns>
                            </DataGrid>
                        </StackPanel>
                    </Border>
                </StackPanel>

                <!-- Unknown Activities View -->
                <StackPanel x:Name="UnknownActivitiesView" Visibility="Collapsed">
                    <TextBlock Text="Unknown Activities" FontSize="32" FontWeight="Bold" Foreground="#F5F5F5" Margin="0,0,0,20"/>
                    
                    <Border Background="#2B2B2B" CornerRadius="10" BorderBrush="#383838" BorderThickness="1">
                        <StackPanel Margin="20">
                            <TextBlock Text="Categorize unclassified activities to improve tracking" FontSize="14" Foreground="#9A9A9A" Margin="0,0,0,15"/>
                            <DataGrid x:Name="UnknownActivitiesGrid" Height="350" AutoGenerateColumns="False" IsReadOnly="True" Background="#2B2B2B" CanUserAddRows="False">
                                <DataGrid.Columns>
                                    <DataGridTextColumn Header="Process" Binding="{Binding ProcessName}" Width="150"/>
                                    <DataGridTextColumn Header="Window Title" Binding="{Binding WindowTitle}" Width="*"/>
                                    <DataGridTextColumn Header="Count" Binding="{Binding Count}" Width="80"/>
                                    <DataGridTextColumn Header="Total Time" Binding="{Binding TotalTime}" Width="100"/>
                                </DataGrid.Columns>
                            </DataGrid>
                            <WrapPanel Margin="0,15,0,0">
                                <Button x:Name="BtnCategorizeUnknown" Content="Categorize Selected" Background="#10B981" Foreground="White" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand" Margin="0,0,10,0"/>
                                <Button x:Name="BtnRefreshUnknown" Content="Refresh" Background="#64748B" Foreground="White" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand"/>
                            </WrapPanel>
                        </StackPanel>
                    </Border>
                </StackPanel>

                <!-- Rules & Categories View -->
                <StackPanel x:Name="RulesCategoriesView" Visibility="Collapsed">
                    <TextBlock Text="Rules &amp; Categories" FontSize="32" FontWeight="Bold" Foreground="#F5F5F5" Margin="0,0,0,20"/>
                    
                    <Grid Margin="0,0,0,20">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="1*"/><ColumnDefinition Width="1*"/>
                        </Grid.ColumnDefinitions>
                        
                        <Border Grid.Column="0" Background="#2B2B2B" CornerRadius="10" BorderBrush="#383838" BorderThickness="1" Margin="0,0,10,0">
                            <StackPanel Margin="20">
                                <TextBlock Text="Categories" FontSize="16" FontWeight="Bold" Foreground="#F5F5F5" Margin="0,0,0,15"/>
                                <ListBox x:Name="CategoriesListBox" Height="150" Background="#2B2B2B" FontSize="13"/>
                                <StackPanel Orientation="Horizontal" Margin="0,15,0,0">
                                    <TextBox x:Name="NewCategoryTextBox" Width="240" Padding="8" Margin="0,0,10,0" Background="#2B2B2B"/>
                                    <Button x:Name="BtnAddCategory" Content="Add" Background="#2563EB" Foreground="White" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand" Width="90"/>
                                </StackPanel>
                            </StackPanel>
                        </Border>
                        
                        <Border Grid.Column="1" Background="#2B2B2B" CornerRadius="10" BorderBrush="#383838" BorderThickness="1">
                            <StackPanel Margin="20">
                                <TextBlock Text="Process Rules" FontSize="16" FontWeight="Bold" Foreground="#F5F5F5" Margin="0,0,0,15"/>
                                <DataGrid x:Name="ProcessRulesGrid" Height="150" AutoGenerateColumns="False" Background="#2B2B2B" CanUserAddRows="False">
                                    <DataGrid.Columns>
                                        <DataGridTextColumn Header="Process" Binding="{Binding Process}" Width="*"/>
                                        <DataGridTextColumn Header="Category" Binding="{Binding Category}" Width="120"/>
                                    </DataGrid.Columns>
                                </DataGrid>
                                <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                                    <Button x:Name="BtnAddProcessRule" Content="Add Rule" Background="#2563EB" Foreground="White" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand" Margin="0,0,10,0" Width="120"/>
                                    <Button x:Name="BtnDeleteProcessRule" Content="Delete" Background="#EF4444" Foreground="White" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand" Width="100"/>
                                </StackPanel>
                            </StackPanel>
                        </Border>
                    </Grid>

                    <!-- Chrome History Analysis -->
                    <Border Background="#2B2B2B" CornerRadius="10" BorderBrush="#383838" BorderThickness="1" Margin="0,0,0,20">
                        <StackPanel Margin="20">
                            <TextBlock Text="Analyse Historique Chrome" FontSize="16" FontWeight="Bold" Foreground="#F5F5F5" Margin="0,0,0,8"/>
                            <TextBlock Text="Détecte les domaines les plus visités et crée des règles automatiquement." FontSize="12" Foreground="#9A9A9A" Margin="0,0,0,12"/>
                            <StackPanel Orientation="Horizontal">
                                <Button x:Name="BtnAnalyzeChrome" Content="Analyser Chrome" Background="#EA580C" Foreground="White" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand"/>
                                <TextBlock x:Name="ChromeStatusText" Text="" Foreground="#9A9A9A" FontSize="12" Margin="15,0,0,0" VerticalAlignment="Center"/>
                            </StackPanel>
                        </StackPanel>
                    </Border>
                </StackPanel>

                <!-- ===== TASKS VIEW ===== -->
                <StackPanel x:Name="TasksView" Visibility="Collapsed">
                    <TextBlock Text="Tâches" FontSize="32" FontWeight="Bold" Foreground="#F5F5F5" Margin="0,0,0,20"/>

                    <!-- Session panel (Pomodoro) -->
                    <Border Background="#2B2B2B" CornerRadius="10" BorderBrush="#383838" BorderThickness="1" Margin="0,0,0,15">
                        <Grid Margin="20">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel Grid.Column="0" Margin="0,0,30,0" VerticalAlignment="Center">
                                <TextBlock Text="SESSION" FontSize="12" FontWeight="Bold" Foreground="#9A9A9A"/>
                                <TextBlock x:Name="SessionCountdown" Text="--:--" FontSize="46" FontWeight="Bold" Foreground="#9CA3AF" FontFamily="Consolas"/>
                                <TextBlock x:Name="SessionPomText" Text="" FontSize="12" Foreground="#9A9A9A"/>
                            </StackPanel>
                            <StackPanel Grid.Column="1" VerticalAlignment="Center">
                                <TextBlock x:Name="SessionTaskText" Text="Aucune session active" FontSize="15" FontWeight="SemiBold" Foreground="#F5F5F5" TextWrapping="Wrap" Margin="0,0,0,8"/>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                                    <TextBlock Text="Travail " FontSize="12" Foreground="#9A9A9A"/><TextBlock x:Name="SessionWorkText" Text="00:00:00" FontSize="12" Foreground="#F5F5F5" FontFamily="Consolas" Margin="0,0,16,0"/>
                                    <TextBlock Text="Global " FontSize="12" Foreground="#9A9A9A"/><TextBlock x:Name="SessionGlobalText" Text="00:00:00" FontSize="12" Foreground="#F5F5F5" FontFamily="Consolas" Margin="0,0,16,0"/>
                                    <TextBlock Text="Pause " FontSize="12" Foreground="#9A9A9A"/><TextBlock x:Name="SessionPauseText" Text="00:00:00" FontSize="12" Foreground="#F5F5F5" FontFamily="Consolas"/>
                                </StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                                    <TextBlock Text="Estimé (min):" FontSize="12" Foreground="#9A9A9A" VerticalAlignment="Center" Margin="0,0,6,0"/>
                                    <TextBox x:Name="SessionEstimeInput" Width="60" Padding="4,3" Text="25" Background="#2B2B2B"/>
                                </StackPanel>
                                <WrapPanel>
                                    <Button x:Name="BtnSessStart" Content="Démarrer" Background="#10B981" Foreground="White" FontWeight="SemiBold" FontSize="12" Padding="10,6" BorderThickness="0" Cursor="Hand" Margin="0,0,6,0"/>
                                    <Button x:Name="BtnSessPause" Content="Pause" Background="#64748B" Foreground="White" FontWeight="SemiBold" FontSize="12" Padding="10,6" BorderThickness="0" Cursor="Hand" Margin="0,0,6,0"/>
                                    <Button x:Name="BtnSessResume" Content="Reprendre" Background="#64748B" Foreground="White" FontWeight="SemiBold" FontSize="12" Padding="10,6" BorderThickness="0" Cursor="Hand" Margin="0,0,6,0"/>
                                    <Button x:Name="BtnSessBreak" Content="Pause Pomodoro" Background="#8B5CF6" Foreground="White" FontWeight="SemiBold" FontSize="12" Padding="10,6" BorderThickness="0" Cursor="Hand" Margin="0,0,6,0"/>
                                    <Button x:Name="BtnSessComplete" Content="Terminer la tâche" Background="#2563EB" Foreground="White" FontWeight="SemiBold" FontSize="12" Padding="10,6" BorderThickness="0" Cursor="Hand" Margin="0,0,6,0"/>
                                    <Button x:Name="BtnSessStop" Content="Arrêter" Background="#EF4444" Foreground="White" FontWeight="SemiBold" FontSize="12" Padding="10,6" BorderThickness="0" Cursor="Hand"/>
                                </WrapPanel>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <!-- Toolbar: search + quick filters -->
                    <Border Background="#2B2B2B" CornerRadius="10" BorderBrush="#383838" BorderThickness="1" Margin="0,0,0,15">
                        <StackPanel Margin="20">
                            <StackPanel Orientation="Horizontal" Margin="0,0,0,12">
                                <TextBox x:Name="TaskSearchBox" Width="320" Padding="8" Margin="0,0,10,0" Background="#2B2B2B"/>
                                <Button x:Name="BtnTaskSearch" Content="Rechercher" Background="#2563EB" Foreground="White" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand" Margin="0,0,6,0"/>
                                <Button x:Name="BtnTaskSearchClear" Content="Effacer" Background="#64748B" Foreground="White" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand"/>
                            </StackPanel>
                            <StackPanel Orientation="Horizontal">
                                <Button x:Name="BtnFilterTous" Content="Tous" Background="#2563EB" Foreground="White" FontWeight="SemiBold" FontSize="12" Padding="10,6" BorderThickness="0" Cursor="Hand" Margin="0,0,6,0"/>
                                <Button x:Name="BtnFilterAFaire" Content="À faire" Background="#64748B" Foreground="White" FontWeight="SemiBold" FontSize="12" Padding="10,6" BorderThickness="0" Cursor="Hand" Margin="0,0,6,0"/>
                                <Button x:Name="BtnFilterEnCours" Content="En cours" Background="#64748B" Foreground="White" FontWeight="SemiBold" FontSize="12" Padding="10,6" BorderThickness="0" Cursor="Hand" Margin="0,0,6,0"/>
                                <Button x:Name="BtnFilterAujourdhui" Content="Dues aujourd'hui" Background="#64748B" Foreground="White" FontWeight="SemiBold" FontSize="12" Padding="10,6" BorderThickness="0" Cursor="Hand" Margin="0,0,6,0"/>
                                <Button x:Name="BtnFilterRetard" Content="En retard" Background="#64748B" Foreground="White" FontWeight="SemiBold" FontSize="12" Padding="10,6" BorderThickness="0" Cursor="Hand"/>
                            </StackPanel>
                        </StackPanel>
                    </Border>

                    <!-- Task list + actions -->
                    <Border Background="#2B2B2B" CornerRadius="10" BorderBrush="#383838" BorderThickness="1">
                        <StackPanel Margin="20">
                            <DataGrid x:Name="TasksGrid" Height="360" AutoGenerateColumns="False" IsReadOnly="True" Background="#2B2B2B" CanUserAddRows="False" SelectionMode="Single" GridLinesVisibility="Horizontal" HeadersVisibility="Column">
                                <DataGrid.Columns>
                                    <DataGridTextColumn Header="Titre" Binding="{Binding Titre}" Width="*" SortMemberPath="Titre"/>
                                    <DataGridTextColumn Header="Catégorie" Binding="{Binding Categorie}" Width="140" SortMemberPath="Categorie"/>
                                    <DataGridTextColumn Header="Priorité" Binding="{Binding Priorite}" Width="90" SortMemberPath="PrioriteRank"/>
                                    <DataGridTextColumn Header="Échéance" Binding="{Binding Echeance}" Width="110" SortMemberPath="EcheanceSort"/>
                                    <DataGridTextColumn Header="Statut" Binding="{Binding Statut}" Width="100" SortMemberPath="Statut"/>
                                    <DataGridTextColumn Header="Estimé" Binding="{Binding Estime}" Width="70" SortMemberPath="EstimeSort"/>
                                    <DataGridTextColumn Header="Passé" Binding="{Binding Passe}" Width="80" SortMemberPath="PasseSort"/>
                                    <DataGridTextColumn Header="Contact" Binding="{Binding Contact}" Width="140"/>
                                </DataGrid.Columns>
                            </DataGrid>
                            <StackPanel Orientation="Horizontal" Margin="0,15,0,0">
                                <Button x:Name="BtnTaskAdd" Content="Ajouter" Background="#2563EB" Foreground="White" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand" Margin="0,0,8,0"/>
                                <Button x:Name="BtnTaskEdit" Content="Éditer" Background="#64748B" Foreground="White" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand" Margin="0,0,8,0"/>
                                <Button x:Name="BtnTaskComplete" Content="Terminer" Background="#10B981" Foreground="White" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand" Margin="0,0,8,0"/>
                                <Button x:Name="BtnTaskArchive" Content="Archiver" Background="#F59E0B" Foreground="White" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand" Margin="0,0,8,0"/>
                                <Button x:Name="BtnTaskReport" Content="Rapport" Background="#8B5CF6" Foreground="White" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand" Margin="0,0,8,0"/>
                                <Button x:Name="BtnTaskRefresh" Content="Rafraîchir" Background="#64748B" Foreground="White" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand"/>
                            </StackPanel>
                            <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                                <TextBlock Text="●" Foreground="#EF4444" FontSize="13" Margin="0,0,4,0"/><TextBlock Text="en retard" FontSize="11" Foreground="#9A9A9A" Margin="0,0,16,0"/>
                                <TextBlock Text="●" Foreground="#F59E0B" FontSize="13" Margin="0,0,4,0"/><TextBlock Text="due aujourd'hui" FontSize="11" Foreground="#9A9A9A" Margin="0,0,16,0"/>
                                <TextBlock Text="●" Foreground="#9CA3AF" FontSize="13" Margin="0,0,4,0"/><TextBlock Text="terminé / archivé" FontSize="11" Foreground="#9A9A9A"/>
                            </StackPanel>
                        </StackPanel>
                    </Border>
                </StackPanel>
            </StackPanel>
            </ScrollViewer>
        </Grid>
    </Grid>
</Window>
"@

# Load XAML
try {
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($xaml))
    $window = [Windows.Markup.XamlReader]::Load($reader)
}
catch {
    $base = "XAML parse error while loading dashboard UI."
    if ($_.Exception -and $_.Exception.InnerException) {
        throw "$base $($_.Exception.InnerException.Message)"
    }
        Show-DashboardError -Message $base -ErrorObject $_.Exception.InnerException
        throw "$base $($_.Exception.InnerException.Message)"
    }
    Show-DashboardError -Message $base -ErrorObject $_.Exception
    throw "$base $($_.Exception.Message)"
}

# Get UI elements
$navDashboard = $window.FindName("NavDashboard")
$navLiveTracking = $window.FindName("NavLiveTracking")
$navUnknownActivities = $window.FindName("NavUnknownActivities")
$navRulesCategories = $window.FindName("NavRulesCategories")
$btnStartStop = $window.FindName("BtnStartStop")
$statusText = $window.FindName("StatusText")
$currentProcessText = $window.FindName("CurrentProcessText")

# Dashboard elements
$totalTimeText = $window.FindName("TotalTimeText")
$focusTimeText = $window.FindName("FocusTimeText")
$focusScoreText = $window.FindName("FocusScoreText")
$distractionTimeText = $window.FindName("DistractionTimeText")
$activityChartCanvas = $window.FindName("ActivityChartCanvas")
$btnGenerateReport = $window.FindName("BtnGenerateReport")
$btnOpenLogs = $window.FindName("BtnOpenLogs")

# Live Tracking elements
$liveProcessText = $window.FindName("LiveProcessText")
$liveWindowText = $window.FindName("LiveWindowText")
$liveCategoryText = $window.FindName("LiveCategoryText")
$liveCurrentTimeText = $window.FindName("LiveCurrentTimeText")
$liveSampleText = $window.FindName("LiveSampleText")
$liveLogCountText = $window.FindName("LiveLogCountText")
$liveLogFileText = $window.FindName("LiveLogFileText")
$recentActivitiesGrid = $window.FindName("RecentActivitiesGrid")

# Unknown Activities elements
$unknownActivitiesGrid = $window.FindName("UnknownActivitiesGrid")
$btnCategorizeUnknown = $window.FindName("BtnCategorizeUnknown")
$btnRefreshUnknown = $window.FindName("BtnRefreshUnknown")

# Rules & Categories elements
$categoriesListBox = $window.FindName("CategoriesListBox")
$newCategoryTextBox = $window.FindName("NewCategoryTextBox")
$btnAddCategory = $window.FindName("BtnAddCategory")
$processRulesGrid = $window.FindName("ProcessRulesGrid")
$btnAddProcessRule = $window.FindName("BtnAddProcessRule")
$btnDeleteProcessRule = $window.FindName("BtnDeleteProcessRule")
$btnAnalyzeChrome = $window.FindName("BtnAnalyzeChrome")
$chromeStatusText = $window.FindName("ChromeStatusText")
$btnToggleOverlay = $window.FindName("BtnToggleOverlay")

# Tasks elements
$navTasks = $window.FindName("NavTasks")
$tasksGrid = $window.FindName("TasksGrid")
$taskSearchBox = $window.FindName("TaskSearchBox")
$btnTaskSearch = $window.FindName("BtnTaskSearch")
$btnTaskSearchClear = $window.FindName("BtnTaskSearchClear")
$btnFilterTous = $window.FindName("BtnFilterTous")
$btnFilterAFaire = $window.FindName("BtnFilterAFaire")
$btnFilterEnCours = $window.FindName("BtnFilterEnCours")
$btnFilterAujourdhui = $window.FindName("BtnFilterAujourdhui")
$btnFilterRetard = $window.FindName("BtnFilterRetard")
$btnTaskAdd = $window.FindName("BtnTaskAdd")
$btnTaskEdit = $window.FindName("BtnTaskEdit")
$btnTaskComplete = $window.FindName("BtnTaskComplete")
$btnTaskArchive = $window.FindName("BtnTaskArchive")
$btnTaskReport = $window.FindName("BtnTaskReport")
$btnTaskRefresh = $window.FindName("BtnTaskRefresh")
# Top bar global search
$globalSearchBox = $window.FindName("GlobalSearchBox")
$searchPlaceholder = $window.FindName("SearchPlaceholder")
# Dashboard task summary labels
$taskCountAFaire = $window.FindName("TaskCountAFaire")
$taskCountEnCours = $window.FindName("TaskCountEnCours")
$taskCountTermine = $window.FindName("TaskCountTermine")
$taskCountRetard = $window.FindName("TaskCountRetard")
# Session panel elements
$sessionCountdown = $window.FindName("SessionCountdown")
$sessionPomText = $window.FindName("SessionPomText")
$sessionTaskText = $window.FindName("SessionTaskText")
$sessionWorkText = $window.FindName("SessionWorkText")
$sessionGlobalText = $window.FindName("SessionGlobalText")
$sessionPauseText = $window.FindName("SessionPauseText")
$sessionEstimeInput = $window.FindName("SessionEstimeInput")
$btnSessStart = $window.FindName("BtnSessStart")
$btnSessPause = $window.FindName("BtnSessPause")
$btnSessResume = $window.FindName("BtnSessResume")
$btnSessBreak = $window.FindName("BtnSessBreak")
$btnSessComplete = $window.FindName("BtnSessComplete")
$btnSessStop = $window.FindName("BtnSessStop")

# Keep the main window inside the usable desktop area and start at a practical size.
try {
    $workArea = [System.Windows.SystemParameters]::WorkArea
    $window.MaxWidth = [math]::Max(960, $workArea.Width)
    $window.MaxHeight = [math]::Max(620, $workArea.Height)
    $window.Width = [math]::Min([double]$window.Width, [double]($workArea.Width * 0.94))
    $window.Height = [math]::Min([double]$window.Height, [double]($workArea.Height * 0.92))
    $window.Left = $workArea.Left + [math]::Max(0, ($workArea.Width - $window.Width) / 2)
    $window.Top = $workArea.Top + [math]::Max(0, ($workArea.Height - $window.Height) / 2)
} catch { }

# View management
function Show-View {
    param($viewName)
    $views = @("DashboardView", "LiveTrackingView", "UnknownActivitiesView", "RulesCategoriesView", "TasksView")
    foreach ($view in $views) {
        $element = $window.FindName($view)
        if ($view -eq $viewName) {
            $element.Visibility = "Visible"
            if ($view -eq "UnknownActivitiesView") { Update-UnknownActivities }
            elseif ($view -eq "RulesCategoriesView") { Update-Rules-UI }
            elseif ($view -eq "TasksView") { Update-Tasks-UI }
        } else {
            $element.Visibility = "Collapsed"
        }
    }
    $global:CurrentView = $viewName
    Set-NavActive $viewName
}

function Set-NavActive {
    param($viewName)
    $map = @{
        DashboardView         = $navDashboard
        LiveTrackingView      = $navLiveTracking
        UnknownActivitiesView = $navUnknownActivities
        RulesCategoriesView   = $navRulesCategories
        TasksView             = $navTasks
    }
    foreach ($k in $map.Keys) {
        $btn = $map[$k]
        if (-not $btn) { continue }
        if ($k -eq $viewName) { $btn.Background = "#FFC107"; $btn.Foreground = "#1A1A1A" }
        else { $btn.Background = "#1A1A1A"; $btn.Foreground = "#CFCFCF" }
    }
}

function Invoke-OnUIThread {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    if ($window.Dispatcher.CheckAccess()) {
        & $Action
    } else {
        $window.Dispatcher.Invoke($Action)
    }
}

function Invoke-OnUIThread {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    if ($window.Dispatcher.CheckAccess()) {
        & $Action
    } else {
        $window.Dispatcher.Invoke($Action)
    }
}

function Invoke-OnUIThread {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    if ($window.Dispatcher.CheckAccess()) {
        & $Action
    } else {
        $window.Dispatcher.Invoke($Action)
    }
}

function Invoke-OnUIThread {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    if ($window.Dispatcher.CheckAccess()) {
        & $Action
    } else {
        $window.Dispatcher.Invoke($Action)
    }
}

function ConvertTo-DisplayText {
    param(
        [AllowNull()]
        [object]$Value,
        [int]$MaxLength = 0
    )

    $text = if ($null -eq $Value) { "" } else { [string]$Value }
    $text = $text -replace "(\r\n|\r|\n)", " "

    if ($MaxLength -gt 3 -and $text.Length -gt $MaxLength) {
        return $text.Substring(0, $MaxLength - 3) + "..."
    }

    return $text
}

function Invoke-OnUIThread {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    if ($window.Dispatcher.CheckAccess()) {
        & $Action
    } else {
        $window.Dispatcher.Invoke($Action)
    }
}

function ConvertTo-DisplayText {
    param(
        [AllowNull()]
        [object]$Value,
        [int]$MaxLength = 0
    )

    $text = if ($null -eq $Value) { "" } else { [string]$Value }
    $text = $text -replace "(\r\n|\r|\n)", " "

    if ($MaxLength -gt 3 -and $text.Length -gt $MaxLength) {
        return $text.Substring(0, $MaxLength - 3) + "..."
    }

    return $text
}

function Invoke-OnUIThread {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    if ($window.Dispatcher.CheckAccess()) {
        & $Action
    } else {
        $window.Dispatcher.Invoke($Action)
    }
}

function ConvertTo-DisplayText {
    param(
        [AllowNull()]
        [object]$Value,
        [int]$MaxLength = 0
    )

    $text = if ($null -eq $Value) { "" } else { [string]$Value }
    $text = $text -replace "(\r\n|\r|\n)", " "

    if ($MaxLength -gt 3 -and $text.Length -gt $MaxLength) {
        return $text.Substring(0, $MaxLength - 3) + "..."
    }

    return $text
}

$navDashboard.Add_Click({ Show-View "DashboardView" })
$navLiveTracking.Add_Click({ Show-View "LiveTrackingView" })
$navUnknownActivities.Add_Click({ Show-View "UnknownActivitiesView" })
$navRulesCategories.Add_Click({ Show-View "RulesCategoriesView" })
$navTasks.Add_Click({ Show-View "TasksView" })

# Top-bar global search: routes to the Tâches tab and applies the text filter.
$globalSearchBox.Add_TextChanged({
    if ($searchPlaceholder) {
        $searchPlaceholder.Visibility = if ([string]::IsNullOrEmpty($globalSearchBox.Text)) { "Visible" } else { "Collapsed" }
    }
})
$globalSearchBox.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq "Return") {
        $q = $globalSearchBox.Text.Trim()
        $global:TaskSearch = $q
        if ($taskSearchBox) { $taskSearchBox.Text = $q }
        Show-View "TasksView"
        Update-Tasks-UI
    }
})

# Initialize UI
function Initialize-UI {
    $categoriesListBox.Items.Clear()
    foreach ($category in $global:rules.categories) {
        $categoriesListBox.Items.Add($category) | Out-Null
    }
    Update-Rules-UI
    # Seed starter tasks on first launch (no-op if tasks.json already has data).
    try { Initialize-TaskSeed -Path $global:taskStorePath | Out-Null } catch { if ($Debug) { Write-Warning "Seed failed: $_" } }
    Restore-InterruptedSession
    Update-Tasks-UI
    Set-TaskFilterButtons $global:TaskFilter
    Update-SessionUI
    Update-SessionButtons
    Set-NavActive "DashboardView"
    Update-Dashboard
}

# Update functions
function Update-Dashboard {
    Update-TaskSummaryCard   # independent of tracking data

    try {
        $reportData = Get-DashboardReportData
        if (-not $reportData) {
            $totalTimeText.Text = "00:00:00"
            $focusTimeText.Text = "00:00:00"
            $distractionTimeText.Text = "00:00:00"
            $focusScoreText.Text = "0%"
            $activityChartCanvas.Children.Clear()
            if ($global:CurrentView -eq "LiveTrackingView") {
                $recentActivitiesGrid.ItemsSource = @()
            }
            return
        }

        $totalSeconds = [int]$reportData.TotalSeconds
        $focusSeconds = [int]$reportData.FocusSeconds
        $distractionSeconds = if ($reportData.Categories["distraction"]) { [int]$reportData.Categories["distraction"] } else { 0 }
        $focusScore = $reportData.FocusScore
        $global:LoggedRowsToday = @($reportData.DataRows).Count

        $totalTimeText.Text = [TimeSpan]::FromSeconds($totalSeconds).ToString('hh\:mm\:ss')
        $focusTimeText.Text = [TimeSpan]::FromSeconds($focusSeconds).ToString('hh\:mm\:ss')
        $distractionTimeText.Text = [TimeSpan]::FromSeconds($distractionSeconds).ToString('hh\:mm\:ss')
        $focusScoreText.Text = "$focusScore%"
        if ($liveLogCountText) { $liveLogCountText.Text = [string]$global:LoggedRowsToday }
        if ($liveLogFileText) { $liveLogFileText.Text = "Log: $(Get-TodayLogFile -LogFolder $global:logFolder)" }
        if ($liveSampleText -and $global:LastSampleAt) { $liveSampleText.Text = $global:LastSampleAt.ToString("HH:mm:ss") }
        
        if ($global:CurrentActivityInfo) {
            $currentProcessText.Text = "Process: $($global:CurrentActivityInfo.ProcessName)"
        }
        
        Update-ActivityChart -Categories $reportData.Categories -TotalSeconds $totalSeconds

        if ($global:CurrentView -eq "LiveTrackingView") {
            if ($global:CurrentActivityInfo) {
                $liveProcessText.Text = $global:CurrentActivityInfo.ProcessName
                $liveWindowText.Text = $global:CurrentActivityInfo.WindowTitle
                $liveCategoryText.Text = $global:CurrentActivityInfo.Category
            } else {
                $liveProcessText.Text = "--"
                $liveWindowText.Text = "--"
                $liveCategoryText.Text = "--"
            }
            if ($global:CurrentActivityStart) {
                $elapsed = (Get-Date) - $global:CurrentActivityStart
                $liveCurrentTimeText.Text = $elapsed.ToString('hh\:mm\:ss')
            } else {
                $liveCurrentTimeText.Text = "00:00:00"
            }
            $recentActivities = @($reportData.DataRows | Select-Object -Last 10 | ForEach-Object {
                [PSCustomObject]@{
                    Time = $_.Time; Process = $_.ProcessName; Title = ConvertTo-DisplayText -Value $_.WindowTitle -MaxLength 45; Category = $_.Category
                }
            })
            $recentActivitiesGrid.ItemsSource = @($recentActivities | Sort-Object Time -Descending)
        }
    } catch {
        if ($Debug) {
            Write-Warning "Update-Dashboard failed: $_"
        }
    }
}

function Update-ActivityChart {
    param($Categories, $TotalSeconds)
    $activityChartCanvas.Children.Clear()
    if ($TotalSeconds -eq 0) { return }
    
    $colors = @{ "travail" = "#10B981"; "distraction" = "#EF4444"; "communication" = "#3B82F6"; "etude" = "#8B5CF6"; "inconnu" = "#F59E0B" }
    $barWidth = 70; $maxHeight = 180; $x = 60; $legendY = 220
    
    foreach ($category in ($Categories.Keys | Sort-Object)) {
        $seconds = $Categories[$category]
        $percentage = $seconds / $TotalSeconds
        $barHeight = [math]::Round($percentage * $maxHeight)
        $color = if ($colors.ContainsKey($category)) { $colors[$category] } else { "#6B7280" }
        
        $rect = New-Object Windows.Shapes.Rectangle
        $rect.Width = $barWidth; $rect.Height = $barHeight; $rect.Fill = $color; $rect.Stroke = "#374151"; $rect.StrokeThickness = 1
        [Windows.Controls.Canvas]::SetLeft($rect, $x); [Windows.Controls.Canvas]::SetTop($rect, 200 - $barHeight)
        $activityChartCanvas.Children.Add($rect) | Out-Null
        
        $textBlock = New-Object Windows.Controls.TextBlock
        $textBlock.Text = "$([math]::Round($percentage * 100, 1))%"; $textBlock.FontSize = 10; $textBlock.Foreground = "#CFCFCF"; $textBlock.TextAlignment = "Center"; $textBlock.Width = $barWidth
        [Windows.Controls.Canvas]::SetLeft($textBlock, $x); [Windows.Controls.Canvas]::SetTop($textBlock, 205)
        $activityChartCanvas.Children.Add($textBlock) | Out-Null
        
        $legendText = New-Object Windows.Controls.TextBlock
        $legendText.Text = "$category"; $legendText.FontSize = 11; $legendText.Foreground = "#CFCFCF"; $legendText.FontWeight = "Bold"
        [Windows.Controls.Canvas]::SetLeft($legendText, $x - 10); [Windows.Controls.Canvas]::SetTop($legendText, $legendY)
        $activityChartCanvas.Children.Add($legendText) | Out-Null
        
        $x += $barWidth + 25
    }
}

function Update-UnknownActivities {
    $logFile = Get-TodayLogFile -LogFolder $global:logFolder
    if (!(Test-Path $logFile)) { $unknownActivitiesGrid.ItemsSource = @(); return }

    try {
        $data = @(Import-Csv -Path $logFile -Encoding UTF8 -ErrorAction SilentlyContinue)
        if ($data.Count -eq 0) { $unknownActivitiesGrid.ItemsSource = @(); return }

        $sampleSeconds = [int]$data[0].SampleSeconds
        $unknownActivities = @()
        $groupSeparator = [char]31
        $grouped = $data | Where-Object { $_.Category -eq "inconnu" } | Group-Object { "$($_.ProcessName)$groupSeparator$($_.WindowTitle)" }

        foreach ($group in $grouped) {
            $parts = $group.Name -split [regex]::Escape([string]$groupSeparator), 2
            $processName = if ($parts.Count -gt 0) { $parts[0] } else { "" }
            $windowTitle = if ($parts.Count -gt 1) { $parts[1] } else { "" }
            $unknownActivities += [PSCustomObject]@{
                ProcessName = $processName
                WindowTitle = $windowTitle
                Count       = $group.Count
                TotalTime   = [TimeSpan]::FromSeconds($group.Count * $sampleSeconds).ToString('hh\:mm\:ss')
            }
        }
        $unknownActivitiesGrid.ItemsSource = @($unknownActivities)
    } catch {
        if ($Debug) {
            Write-Warning "Update-UnknownActivities failed: $_"
        }
    }
}

function Update-Rules-UI {
    try {
        $global:rules = Load-Rules -RulesPath $global:rulesPath
        $rulesData = @()
        foreach ($rule in $global:rules.processRules) {
            $rulesData += [PSCustomObject]@{ Process = $rule.process; Category = $rule.category }
        }
        $processRulesGrid.ItemsSource = @($rulesData)
    } catch {
        if ($Debug) {
            Write-Warning "Update-Rules-UI failed: $_"
        }
    }
}

function Stop-TrackingTimer {
    if ($global:TrackerTimer) {
        $global:TrackerTimer.Stop()
        try { $global:TrackerTimer.Dispose() } catch { }
        $global:TrackerTimer = $null
    }
    if ($global:TrackerTimerEventSub) {
        Unregister-Event -SubscriptionId $global:TrackerTimerEventSub.Id -ErrorAction SilentlyContinue
        $global:TrackerTimerEventSub = $null
    }
}

function Stop-DashboardTimer {
    if ($global:DashboardUpdateTimer) {
        $global:DashboardUpdateTimer.Stop()
        $global:DashboardUpdateTimer = $null
    }
}

function Write-DashboardRuntimeError {
    param([string]$Message)
    try {
        $log = Join-Path $global:logFolder "dashboard-runtime.log"
        Add-Content -Path $log -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -Encoding UTF8
    } catch { }
        $global:DashboardUpdateTimer.Dispose()
        $global:DashboardUpdateTimer = $null
    }
    if ($global:DashboardTimerEventSub) {
        Unregister-Event -SubscriptionId $global:DashboardTimerEventSub.Id -ErrorAction SilentlyContinue
        $global:DashboardTimerEventSub = $null
    }
}

Write-DashboardRuntimeError "Dashboard script initialized. pid=$PID"

function Save-SessionCheckpoint {
    param($Readout = $null, [datetime]$Now = (Get-Date))
    if (-not $global:SessionState) { return }
    try {
        if (-not $Readout) { $Readout = Step-Session -State $global:SessionState -Now $Now }
        $data = [ordered]@{
            SavedAt         = $Now.ToString('s')
            TaskId          = [string]$global:SessionState.TaskId
            TaskTitle       = [string]$global:SessionState.TaskTitle
            EstimateSec     = [int]$global:SessionState.EstimateSec
            Debut           = ([datetime]$global:SessionState.StartWall).ToString('s')
            TravailSecondes = [int]$Readout.WorkSec
            GlobalSecondes  = [int]$Readout.GlobalSec
            PauseSecondes   = [int]$Readout.PauseSec
            PomodorosFait   = [int]$Readout.PomCompleted
            Mode            = [string]$global:SessionState.Mode
        }
        $json = $data | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($global:SessionCheckpointFile, $json, [System.Text.UTF8Encoding]::new($true))
    } catch {
        Write-DashboardRuntimeError "Save-SessionCheckpoint failed: $_"
    }
}

function Clear-SessionCheckpoint {
    try {
        if (Test-Path $global:SessionCheckpointFile) {
            Remove-Item $global:SessionCheckpointFile -Force
        }
    } catch {
        Write-DashboardRuntimeError "Clear-SessionCheckpoint failed: $_"
    }
}

function Restore-InterruptedSession {
    try {
        if (-not (Test-Path $global:SessionCheckpointFile)) { return }
        $cp = Get-Content $global:SessionCheckpointFile -Raw | ConvertFrom-Json
        if (-not $cp.TaskId -or [int]$cp.TravailSecondes -lt 30) {
            Clear-SessionCheckpoint
            return
        }

        $res = [PSCustomObject]@{
            TaskId          = [string]$cp.TaskId
            Debut           = [string]$cp.Debut
            Fin             = [string]$cp.SavedAt
            TravailSecondes = [int]$cp.TravailSecondes
            GlobalSecondes  = [int]$cp.GlobalSecondes
            PauseSecondes   = [int]$cp.PauseSecondes
            PomodorosFait   = [int]$cp.PomodorosFait
        }
        Add-TaskSession -Id ([string]$cp.TaskId) -Result $res -Path $global:taskStorePath | Out-Null
        Write-DashboardRuntimeError "Recovered interrupted session. task=$($cp.TaskId) workSec=$($cp.TravailSecondes)"
        Clear-SessionCheckpoint
    } catch {
        Write-DashboardRuntimeError "Restore-InterruptedSession failed: $_"
    }
}

function Get-RealTaskSessions {
    param([object]$Task)
    if (-not $Task -or -not $Task.Sessions) { return @() }
    return @($Task.Sessions | Where-Object {
        $_ -and (
            $_.Debut -or
            $_.Fin -or
            ([int]$_.TravailSecondes -gt 0) -or
            ([int]$_.GlobalSecondes -gt 0)
        )
    })
}

function Get-LiveSessionResult {
    param([datetime]$Now = (Get-Date))
    if (-not $global:SessionState) { return $null }
    try {
        $r = if ($global:SessionReadout) { $global:SessionReadout } else { Step-Session -State $global:SessionState -Now $Now }
        return [PSCustomObject]@{
            TaskId          = [string]$global:SessionState.TaskId
            Debut           = ([datetime]$global:SessionState.StartWall).ToString('s')
            Fin             = $Now.ToString('s')
            TravailSecondes = [int]$r.WorkSec
            GlobalSecondes  = [int]$r.GlobalSec
            PauseSecondes   = [int]$r.PauseSec
            PomodorosFait   = [int]$r.PomCompleted
        }
    } catch {
        Write-DashboardRuntimeError "Get-LiveSessionResult failed: $_"
        return $null
    }
}

function Get-TasksForReporting {
    param([switch]$IncludeLiveSession)
    $tasks = @(Get-Tasks -Path $global:taskStorePath)
    if (-not $IncludeLiveSession -or -not $global:SessionState) { return $tasks }

    $live = Get-LiveSessionResult
    if (-not $live -or [int]$live.TravailSecondes -le 0) { return $tasks }

    foreach ($t in $tasks) {
        if ($t.Id -eq $live.TaskId) {
            $sessions = @(Get-RealTaskSessions -Task $t)
            $sessions += [PSCustomObject]@{
                Debut           = $live.Debut
                Fin             = $live.Fin
                TravailSecondes = [int]$live.TravailSecondes
                GlobalSecondes  = [int]$live.GlobalSecondes
                PauseSecondes   = [int]$live.PauseSecondes
                PomodorosFait   = [int]$live.PomodorosFait
            }
            $t | Add-Member -NotePropertyName Sessions -NotePropertyValue $sessions -Force
            $t | Add-Member -NotePropertyName TempsTravailSecondes -NotePropertyValue ([int]$t.TempsTravailSecondes + [int]$live.TravailSecondes) -Force
            $t | Add-Member -NotePropertyName TempsGlobalSecondes -NotePropertyValue ([int]$t.TempsGlobalSecondes + [int]$live.GlobalSecondes) -Force
            $t | Add-Member -NotePropertyName Statut -NotePropertyValue "En_cours" -Force
            break
        }
    }
    return $tasks
}

function Invoke-TrackingSample {
    try {
        if (-not $global:CurrentLogFile) {
            $global:CurrentLogFile = Get-TodayLogFile -LogFolder $global:logFolder
            Initialize-LogFile -LogFile $global:CurrentLogFile
        }

        $info = Get-ActiveWindowInfo
        if (-not $info) {
            Write-DashboardRuntimeError "Get-ActiveWindowInfo returned null"
            return
        }

        $isAfotraWindow = ($info.ProcessName -in @("powershell", "pwsh") -and $info.WindowTitle -like "*AFOTRA*")
        if ($isAfotraWindow) {
            $display = $global:CurrentActivityInfo
            if ($display) {
                $liveProcessText.Text = $display.ProcessName
                $liveWindowText.Text = $display.WindowTitle
                $liveCategoryText.Text = $display.Category
                $statusText.Text = "Status: Running - AFOTRA ignoré"
            } else {
                $liveProcessText.Text = "AFOTRA"
                $liveWindowText.Text = "Fenêtre AFOTRA ignorée : passe sur une autre application pour enregistrer l'activité."
                $liveCategoryText.Text = "--"
                $statusText.Text = "Status: Running - en attente d'une autre appli"
            }
            return
        }

        $idleThreshold = if ($global:config.idleThresholdSeconds) { [int]$global:config.idleThresholdSeconds } else { 180 }
        $category = if ((Get-IsSessionLocked -ActivityInfo $info) -or (Get-IdleSeconds -ge $idleThreshold)) {
            "inactif"
        } else {
            Classify-Activity -ProcessName $info.ProcessName -WindowTitle $info.WindowTitle -Rules $global:rules
        }
        $info | Add-Member -NotePropertyName "Category" -NotePropertyValue $category -Force
        Write-ActivityLog -LogFile $global:CurrentLogFile -ActivityInfo $info -SampleSeconds $global:config.sampleIntervalSeconds
        $global:LastSampleAt = Get-Date
        $global:LoggedRowsToday = [int]$global:LoggedRowsToday + 1

        if (-not ($global:CurrentActivityInfo -and
                  $global:CurrentActivityInfo.ProcessName -eq $info.ProcessName -and
                  $global:CurrentActivityInfo.WindowTitle  -eq $info.WindowTitle)) {
            $global:CurrentActivityStart = Get-Date
        }
        $global:CurrentActivityInfo = $info
        $currentProcessText.Text = "Process: $($info.ProcessName)"
        $liveProcessText.Text = $info.ProcessName
        $liveWindowText.Text = $info.WindowTitle
        $liveCategoryText.Text = $info.Category
        if ($liveSampleText) { $liveSampleText.Text = $global:LastSampleAt.ToString("HH:mm:ss") }
        if ($liveLogCountText) { $liveLogCountText.Text = [string]$global:LoggedRowsToday }
        if ($liveLogFileText) { $liveLogFileText.Text = "Log: $($global:CurrentLogFile)" }
        $statusText.Text = "Status: Running - $($info.ProcessName) > $category"
        Update-Dashboard
    } catch {
        Write-DashboardRuntimeError "Tracking sample failed: $_"
        if ($Debug) { Write-Warning "Tracking sample failed: $_" }
    }
}

function Update-TrackingButtons {
    try {
        $isRunning = [bool]$global:TrackerRunning
        if ($btnStartStop) {
            $btnStartStop.Content = if ($isRunning) { "Stop Tracking" } else { "Start Tracking" }
            $btnStartStop.Background = if ($isRunning) { "#EF4444" } else { "#FFC107" }
            $btnStartStop.Foreground = if ($isRunning) { "White" } else { "#1A1A1A" }
        }
        if ($btnOverlayStartStop) {
            $btnOverlayStartStop.Content = if ($isRunning) { "Live ON" } else { "Live OFF" }
            $btnOverlayStartStop.Background = if ($isRunning) { "#EF4444" } else { "#10B981" }
            $btnOverlayStartStop.Foreground = "White"
        }
        if ($ovStatusDot) {
            $ovStatusDot.Fill = if ($isRunning) { "#10B981" } else { "#6B7280" }
        }
    } catch {
        Write-DashboardRuntimeError "Update-TrackingButtons failed: $_"
    }
}

function Start-AfotraTracking {
    if ($global:TrackerRunning) {
        Update-TrackingButtons
        return
    }
    Write-DashboardRuntimeError "Live tracking start requested."
    $global:TrackerRunning = $true
    $global:CurrentLogFile = Get-TodayLogFile -LogFolder $global:logFolder
    Initialize-LogFile -LogFile $global:CurrentLogFile

    $global:TrackerTimer = New-Object System.Windows.Threading.DispatcherTimer
    $global:TrackerTimer.Interval = [TimeSpan]::FromSeconds($global:config.sampleIntervalSeconds)
    $global:TrackerTimer.Add_Tick({ Invoke-TrackingSample })
    $global:TrackerTimer.Start()

    $btnStartStop.Content = "Stop Tracking"
    $btnStartStop.Background = "#EF4444"
    $btnStartStop.Foreground = "White"
    Update-TrackingButtons
    $statusText.Text = "Status: Running..."
    Invoke-TrackingSample
}

function Stop-AfotraTracking {
    if (-not $global:TrackerRunning) { return }
    Write-DashboardRuntimeError "Live tracking stop requested."
    $global:TrackerRunning = $false
    Stop-TrackingTimer
    $statusText.Text = "Status: Stopped"
    $btnStartStop.Content = "Start Tracking"
    $btnStartStop.Background = "#FFC107"
    $btnStartStop.Foreground = "#1A1A1A"
    Update-TrackingButtons
    Update-Dashboard
}

# Tracking button
$btnStartStop.Add_Click({
    if (!$global:TrackerRunning) { Start-AfotraTracking }
    else { Stop-AfotraTracking }
})

# Actions
$btnRefreshUnknown.Add_Click({ Update-UnknownActivities })
$btnCategorizeUnknown.Add_Click({
    $selectedItem = $unknownActivitiesGrid.SelectedItem
    if (!$selectedItem) { [Windows.MessageBox]::Show("Select an activity first.", "AFOTRA") | Out-Null; return }
    
    Add-Type -AssemblyName System.Windows.Forms; $form = New-Object System.Windows.Forms.Form
    $form.Text = "Categorize Activity"; $form.Width = 450; $form.Height = 300; $form.StartPosition = "CenterParent"
    
    $label = New-Object System.Windows.Forms.Label; $label.Text = "Process: $($selectedItem.ProcessName)"; $label.Location = New-Object System.Drawing.Point(10, 20); $label.AutoSize = $true; $form.Controls.Add($label)
    $combo = New-Object System.Windows.Forms.ComboBox; $combo.Location = New-Object System.Drawing.Point(10, 80); $combo.Width = 400
    foreach ($cat in $global:rules.categories) { $combo.Items.Add($cat) | Out-Null }
    $combo.SelectedIndex = 0; $form.Controls.Add($combo)
    
    $radio1 = New-Object System.Windows.Forms.RadioButton; $radio1.Text = "Process Name"; $radio1.Location = New-Object System.Drawing.Point(10, 140); $radio1.Checked = $true; $form.Controls.Add($radio1)
    $radio2 = New-Object System.Windows.Forms.RadioButton; $radio2.Text = "Window Title"; $radio2.Location = New-Object System.Drawing.Point(200, 140); $form.Controls.Add($radio2)
    
    $btnOk = New-Object System.Windows.Forms.Button; $btnOk.Text = "OK"; $btnOk.Location = New-Object System.Drawing.Point(280, 210); $btnOk.DialogResult = "OK"; $form.Controls.Add($btnOk)
    $btnCancel = New-Object System.Windows.Forms.Button; $btnCancel.Text = "Cancel"; $btnCancel.Location = New-Object System.Drawing.Point(360, 210); $btnCancel.DialogResult = "Cancel"; $form.Controls.Add($btnCancel)
    
    Set-DarkTheme -Control $form; if ($form.ShowDialog() -eq "OK") {
        if ($radio1.Checked) { Add-ProcessRule -Rules $global:rules -Process $selectedItem.ProcessName -Category $combo.SelectedItem }
        else { Add-TitleRule -Rules $global:rules -Contains $selectedItem.WindowTitle -Category $combo.SelectedItem }
        Save-Rules -Rules $global:rules -RulesPath $global:rulesPath
        Update-Rules-UI; Update-UnknownActivities
        [Windows.MessageBox]::Show("Rule created!", "AFOTRA") | Out-Null
    }
    $form.Dispose()
})

$btnAddCategory.Add_Click({
    $newCategory = $newCategoryTextBox.Text.Trim()
    if ($newCategory -and $global:rules.categories -notcontains $newCategory) {
        Add-Category -Rules $global:rules -Category $newCategory | Out-Null
        Save-Rules -Rules $global:rules -RulesPath $global:rulesPath
        Initialize-UI; $newCategoryTextBox.Text = ""
    }
})

$btnAddProcessRule.Add_Click({
    Add-Type -AssemblyName System.Windows.Forms; $form = New-Object System.Windows.Forms.Form
    $form.Text = "Add Process Rule"; $form.Width = 400; $form.Height = 250; $form.StartPosition = "CenterParent"
    
    $label1 = New-Object System.Windows.Forms.Label; $label1.Text = "Process Name:"; $label1.Location = New-Object System.Drawing.Point(10, 20); $label1.AutoSize = $true; $form.Controls.Add($label1)
    $text = New-Object System.Windows.Forms.TextBox; $text.Location = New-Object System.Drawing.Point(10, 45); $text.Width = 370; $form.Controls.Add($text)
    
    $label2 = New-Object System.Windows.Forms.Label; $label2.Text = "Category:"; $label2.Location = New-Object System.Drawing.Point(10, 80); $label2.AutoSize = $true; $form.Controls.Add($label2)
    $combo = New-Object System.Windows.Forms.ComboBox; $combo.Location = New-Object System.Drawing.Point(10, 105); $combo.Width = 370
    foreach ($cat in $global:rules.categories) { $combo.Items.Add($cat) | Out-Null }
    $combo.SelectedIndex = 0; $form.Controls.Add($combo)
    
    $btnOk = New-Object System.Windows.Forms.Button; $btnOk.Text = "OK"; $btnOk.Location = New-Object System.Drawing.Point(240, 170); $btnOk.DialogResult = "OK"; $form.Controls.Add($btnOk)
    $btnCancel = New-Object System.Windows.Forms.Button; $btnCancel.Text = "Cancel"; $btnCancel.Location = New-Object System.Drawing.Point(320, 170); $btnCancel.DialogResult = "Cancel"; $form.Controls.Add($btnCancel)
    
    Set-DarkTheme -Control $form; if ($form.ShowDialog() -eq "OK" -and $text.Text.Trim()) {
        Add-ProcessRule -Rules $global:rules -Process $text.Text.Trim() -Category $combo.SelectedItem
        Save-Rules -Rules $global:rules -RulesPath $global:rulesPath
        Update-Rules-UI
    }
    $form.Dispose()
})

$btnDeleteProcessRule.Add_Click({
    $selectedItem = $processRulesGrid.SelectedItem
    if ($selectedItem) {
        $global:rules.processRules = $global:rules.processRules | Where-Object { $_.process -ne $selectedItem.Process }
        Save-Rules -Rules $global:rules -RulesPath $global:rulesPath
        Update-Rules-UI
    }
})

$btnAnalyzeChrome.Add_Click({
    $chromeStatusText.Text = "Analyse en cours..."
    $btnAnalyzeChrome.IsEnabled = $false

    $domains = Get-ChromeTopDomains -Top 60

    $btnAnalyzeChrome.IsEnabled = $true

    if (-not $domains -or $domains.Count -eq 0) {
        $chromeStatusText.Text = "Historique Chrome introuvable ou vide."
        return
    }

    # Filter out already-ruled domains
    $existingRules = @($global:rules.titleRules | ForEach-Object { $_.contains.ToLower() })
    $newDomains = @($domains | Where-Object {
        $d = $_.Domain
        -not ($existingRules | Where-Object { $_ -like "*$d*" })
    })

    if ($newDomains.Count -eq 0) {
        $chromeStatusText.Text = "Tous les domaines ont déjà une règle."
        return
    }

    # Build a WinForms dialog listing all new domains with a ComboBox per row
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Catégoriser les domaines Chrome"
    $form.Width = 680; $form.Height = 600
    $form.StartPosition = "CenterParent"
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Dock = "Fill"; $panel.AutoScroll = $true
    $form.Controls.Add($panel)

    $categories = @($global:rules.categories)

    $y = 10
    $controls = @()

    # Header
    $hDomain  = New-Object System.Windows.Forms.Label; $hDomain.Text = "Domaine"; $hDomain.Location = New-Object System.Drawing.Point(10, $y); $hDomain.Width = 300; $hDomain.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold); $panel.Controls.Add($hDomain)
    $hCount   = New-Object System.Windows.Forms.Label; $hCount.Text = "Visites"; $hCount.Location = New-Object System.Drawing.Point(315, $y); $hCount.Width = 60; $hCount.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold); $panel.Controls.Add($hCount)
    $hCat     = New-Object System.Windows.Forms.Label; $hCat.Text = "Catégorie"; $hCat.Location = New-Object System.Drawing.Point(380, $y); $hCat.Width = 180; $hCat.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold); $panel.Controls.Add($hCat)
    $y += 28

    foreach ($domain in $newDomains) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $domain.Domain; $lbl.Location = New-Object System.Drawing.Point(10, $y); $lbl.Width = 300; $lbl.AutoEllipsis = $true
        $panel.Controls.Add($lbl)

        $cnt = New-Object System.Windows.Forms.Label
        $cnt.Text = "$($domain.Count)"; $cnt.Location = New-Object System.Drawing.Point(315, $y); $cnt.Width = 60; $cnt.ForeColor = [System.Drawing.Color]::Gray
        $panel.Controls.Add($cnt)

        $combo = New-Object System.Windows.Forms.ComboBox
        $combo.Location = New-Object System.Drawing.Point(380, ($y - 2)); $combo.Width = 180; $combo.DropDownStyle = "DropDownList"
        $combo.Items.Add("(ignorer)") | Out-Null
        foreach ($cat in $categories) { $combo.Items.Add($cat) | Out-Null }
        $combo.SelectedIndex = 0
        $panel.Controls.Add($combo)

        $controls += [PSCustomObject]@{ Domain = $domain.Domain; Combo = $combo }
        $y += 30
    }

    # Bottom buttons
    $btnPanel = New-Object System.Windows.Forms.Panel
    $btnPanel.Dock = "Bottom"; $btnPanel.Height = 50
    $form.Controls.Add($btnPanel)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Appliquer les règles"; $btnOk.Location = New-Object System.Drawing.Point(430, 12); $btnOk.Width = 160; $btnOk.DialogResult = "OK"
    $btnPanel.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Annuler"; $btnCancel.Location = New-Object System.Drawing.Point(598, 12); $btnCancel.Width = 70; $btnCancel.DialogResult = "Cancel"
    $btnPanel.Controls.Add($btnCancel)

    Set-DarkTheme -Control $form; if ($form.ShowDialog() -eq "OK") {
        $added = 0
        foreach ($row in $controls) {
            if ($row.Combo.SelectedIndex -gt 0) {
                $cat = $row.Combo.SelectedItem.ToString()
                Add-TitleRule -Rules $global:rules -Contains $row.Domain -Category $cat
                $added++
            }
        }
        if ($added -gt 0) {
            Save-Rules -Rules $global:rules -RulesPath $global:rulesPath
            Update-Rules-UI
            $chromeStatusText.Text = "$added règle(s) ajoutée(s) !"
        } else {
            $chromeStatusText.Text = "Aucune règle ajoutée."
        }
    } else {
        $chromeStatusText.Text = ""
    }
    $form.Dispose()
})

$btnGenerateReport.Add_Click({
    $logFile = Get-TodayLogFile -LogFolder $global:logFolder
    if (!(Test-Path $logFile)) {
        [Windows.MessageBox]::Show("Aucune donnée de suivi pour aujourd'hui.`n`nClique d'abord sur Start Tracking, travaille quelques minutes, puis regénère le rapport.", "AFOTRA") | Out-Null
        return
    }

    try {
        $reportData = Get-DashboardReportData
        if (-not $reportData) {
            [Windows.MessageBox]::Show("Impossible de traiter le journal du jour.`n`nFichier : $logFile", "AFOTRA") | Out-Null
            return
        }
        $date = Get-Date -Format "yyyy-MM-dd"
        $reportFolder = Join-Path $global:logFolder "reports"
        if (!(Test-Path $reportFolder)) { New-Item -ItemType Directory -Path $reportFolder -Force | Out-Null }
        $jsonFile = Join-Path $reportFolder "summary-$date.json"
        $taskSummary = $null
        $taskDetail = $null
        try {
            $allTasks = @(Get-TasksForReporting -IncludeLiveSession)
            $taskSummary = Get-TaskSummary -Tasks $allTasks
            $taskDetail = @($allTasks | Where-Object { @(Get-RealTaskSessions -Task $_).Count -gt 0 } | ForEach-Object { Get-TaskReport -Task $_ })
        } catch { if ($Debug) { Write-Warning "Task report section failed: $_" } }
        Export-ReportToJSON -ReportData $reportData -OutputFile $jsonFile -TaskSummary $taskSummary -TaskDetail $taskDetail
        Update-Dashboard
        [Windows.MessageBox]::Show("Rapport généré !`n`n$jsonFile", "AFOTRA") | Out-Null
        Start-Process explorer.exe -ArgumentList "/select,`"$jsonFile`""
    } catch {
        [Windows.MessageBox]::Show("Erreur génération rapport : $_", "AFOTRA") | Out-Null
    }
})

$btnOpenLogs.Add_Click({
    if (Test-Path $global:logFolder) { Explorer.exe $global:logFolder }
})

# ===================================================================
# TASKS — helpers, list rendering, dialog, handlers, reminder timer
# ===================================================================
$global:TasksCache = @()
$global:DashboardUpdateTimer.Start()

# ===================================================================
# OVERLAY WINDOW — toujours visible, non-modal, always-on-top
# ===================================================================
$overlayXaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="AFOTRA Assistant"
    Width="120" Height="120"
    WindowStyle="None"
    AllowsTransparency="True"
    Background="Transparent"
    Topmost="True"
    ShowInTaskbar="False"
    ShowActivated="False"
    Left="40" Top="80">
  <Grid x:Name="OrbRoot" Background="Transparent">
    <!-- The living bee -->
    <Viewbox x:Name="OrbViewbox" Width="92" Height="92" HorizontalAlignment="Center" VerticalAlignment="Center" RenderTransformOrigin="0.5,0.5" Cursor="Hand">
      <Viewbox.RenderTransform>
        <ScaleTransform x:Name="OrbScale" ScaleX="1" ScaleY="1"/>
      </Viewbox.RenderTransform>
      <Grid Width="100" Height="100">
        <!-- wings -->
        <Ellipse x:Name="OrbWingL" Width="42" Height="30" Fill="#59FFFFFF" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="4,8,0,0" RenderTransformOrigin="1,0.5">
          <Ellipse.RenderTransform><RotateTransform x:Name="OrbWingLRot" Angle="-8"/></Ellipse.RenderTransform>
        </Ellipse>
        <Ellipse x:Name="OrbWingR" Width="42" Height="30" Fill="#59FFFFFF" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,8,4,0" RenderTransformOrigin="0,0.5">
          <Ellipse.RenderTransform><RotateTransform x:Name="OrbWingRRot" Angle="8"/></Ellipse.RenderTransform>
        </Ellipse>
        <!-- body -->
        <Ellipse x:Name="OrbBody" Width="66" Height="80" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,12,0,0">
          <Ellipse.Fill>
            <RadialGradientBrush x:Name="OrbBrush" GradientOrigin="0.4,0.3" Center="0.5,0.5" RadiusX="0.62" RadiusY="0.62">
              <GradientStop x:Name="OrbStopCore" Color="#FFD54F" Offset="0.0"/>
              <GradientStop x:Name="OrbStopMid"  Color="#FFB300" Offset="0.7"/>
              <GradientStop x:Name="OrbStopEdge" Color="#00FFB300" Offset="1.0"/>
            </RadialGradientBrush>
          </Ellipse.Fill>
          <Ellipse.Effect>
            <DropShadowEffect x:Name="OrbGlow" Color="#FFB300" BlurRadius="18" ShadowDepth="0" Opacity="0.85"/>
          </Ellipse.Effect>
        </Ellipse>
        <!-- stripes, clipped to the body -->
        <Grid Width="66" Height="80" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,12,0,0" IsHitTestVisible="False">
          <Grid.Clip><EllipseGeometry Center="33,40" RadiusX="33" RadiusY="40"/></Grid.Clip>
          <StackPanel VerticalAlignment="Center">
            <Rectangle Height="8" Fill="#1A1A1A" Margin="0,3,0,0"/>
            <Rectangle Height="8" Fill="#1A1A1A" Margin="0,8,0,0"/>
            <Rectangle Height="8" Fill="#1A1A1A" Margin="0,8,0,0"/>
          </StackPanel>
        </Grid>
        <!-- head -->
        <Ellipse Width="30" Height="24" Fill="#1A1A1A" HorizontalAlignment="Center" VerticalAlignment="Top" Margin="0,2,0,0" IsHitTestVisible="False"/>
        <Ellipse Width="5" Height="5" Fill="#FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Top" Margin="-9,8,0,0" IsHitTestVisible="False"/>
        <Ellipse Width="5" Height="5" Fill="#FFFFFF" HorizontalAlignment="Center" VerticalAlignment="Top" Margin="9,8,0,0" IsHitTestVisible="False"/>
      </Grid>
    </Viewbox>

    <!-- Hover reveal: full session/activity panel -->
    <Popup x:Name="OrbDetailPopup" PlacementTarget="{Binding ElementName=OrbViewbox}" Placement="Right" AllowsTransparency="True" StaysOpen="True" HorizontalOffset="6">
      <Border Background="#F21F2937" CornerRadius="10" Padding="12" Margin="8">
        <Border.Effect><DropShadowEffect Color="Black" Opacity="0.55" BlurRadius="12" ShadowDepth="2"/></Border.Effect>
        <StackPanel Width="248">
          <Grid Margin="0,0,0,8">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <Ellipse x:Name="OvStatusDot" Width="7" Height="7" Fill="#6B7280" VerticalAlignment="Center" Margin="0,0,6,0"/>
              <TextBlock Text="AFOTRA LIVE" FontSize="9" FontWeight="Bold" Foreground="#9CA3AF"/>
            </StackPanel>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
              <Button x:Name="BtnOverlayStartStop" Content="Live OFF" Background="#10B981" Foreground="White" FontWeight="Bold" FontSize="10" Padding="8,3" BorderThickness="0" Cursor="Hand" Margin="0,0,5,0"/>
              <Button x:Name="BtnCloseOverlay" Content="Masquer" Background="Transparent" Foreground="#9CA3AF" BorderThickness="0" FontSize="10" Cursor="Hand" Padding="4,0"/>
            </StackPanel>
          </Grid>
          <Separator Background="#2D3748" Margin="0,0,0,8"/>
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0">
              <TextBlock x:Name="OvProcess" Text="--" FontSize="15" FontWeight="Bold" Foreground="White" TextTrimming="CharacterEllipsis"/>
              <TextBlock x:Name="OvTitle" Text="--" FontSize="10" Foreground="#9CA3AF" TextTrimming="CharacterEllipsis"/>
            </StackPanel>
            <StackPanel Grid.Column="1" HorizontalAlignment="Right" Margin="8,0,0,0">
              <Border x:Name="OvCatBadge" CornerRadius="4" Padding="7,3" HorizontalAlignment="Right" Background="#374151">
                <TextBlock x:Name="OvCategory" Text="--" FontSize="10" FontWeight="Bold" Foreground="White"/>
              </Border>
              <TextBlock x:Name="OvDuration" Text="00:00:00" FontSize="12" Foreground="#E5E7EB" TextAlignment="Right" Margin="0,4,0,0" FontFamily="Consolas"/>
            </StackPanel>
          </Grid>
          <Grid Margin="0,8,0,0">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="Focus:" FontSize="10" Foreground="#9A9A9A" VerticalAlignment="Center"/>
              <TextBlock x:Name="OvFocusScore" Text="0%" FontSize="10" FontWeight="Bold" Foreground="#10B981" Margin="4,0,10,0" VerticalAlignment="Center"/>
              <TextBlock Text="Tracké:" FontSize="10" Foreground="#9A9A9A" VerticalAlignment="Center"/>
              <TextBlock x:Name="OvTotalTime" Text="0m" FontSize="10" Foreground="#D1D5DB" Margin="4,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <TextBlock x:Name="OvAlertText" Text="" FontSize="10" FontWeight="Bold" Foreground="#FCA5A5" HorizontalAlignment="Right" VerticalAlignment="Center"/>
          </Grid>
          <TextBlock x:Name="OvSessionText" Text="" FontSize="11" FontWeight="Bold" Foreground="#FCD34D" Margin="0,6,0,0" TextTrimming="CharacterEllipsis" Visibility="Collapsed"/>
        </StackPanel>
      </Border>
    </Popup>

    <!-- Session milestone bubble -->
    <Popup x:Name="OrbMilestonePopup" PlacementTarget="{Binding ElementName=OrbViewbox}" Placement="Top" AllowsTransparency="True" StaysOpen="True" HorizontalOffset="8" VerticalOffset="-6">
      <Border Background="#F21A1A1A" CornerRadius="10" Padding="12,9" Margin="8" BorderBrush="#FFC107" BorderThickness="1">
        <Border.Effect><DropShadowEffect Color="Black" Opacity="0.45" BlurRadius="14" ShadowDepth="2"/></Border.Effect>
        <TextBlock x:Name="OrbMilestoneText" Text="" Foreground="#FFF7CC" FontSize="12" FontWeight="SemiBold" TextWrapping="Wrap" MaxWidth="260"/>
      </Border>
    </Popup>

    <!-- Focus-guard question -->
    <Popup x:Name="OrbAskPopup" PlacementTarget="{Binding ElementName=OrbViewbox}" Placement="Bottom" AllowsTransparency="True" StaysOpen="True">
      <Border Background="#F2111827" CornerRadius="10" Padding="14" Margin="8" BorderBrush="#EF4444" BorderThickness="2">
        <Border.Effect><DropShadowEffect Color="Black" Opacity="0.6" BlurRadius="14" ShadowDepth="2"/></Border.Effect>
        <StackPanel Width="300">
          <TextBlock x:Name="OrbAskText" Text="En rapport avec la tâche ?" Foreground="White" FontSize="13" FontWeight="Bold" TextWrapping="Wrap" Margin="0,0,0,12"/>
          <StackPanel Orientation="Horizontal">
            <Button x:Name="BtnAskYes" Content="Oui, pour la tâche" Background="#10B981" Foreground="White" FontWeight="SemiBold" FontSize="12" Padding="10,6" BorderThickness="0" Cursor="Hand" Margin="0,0,6,0"/>
            <Button x:Name="BtnAskNo" Content="Non" Background="#EF4444" Foreground="White" FontWeight="SemiBold" FontSize="12" Padding="12,6" BorderThickness="0" Cursor="Hand" Margin="0,0,6,0"/>
            <Button x:Name="BtnAskIgnore" Content="Ignorer" Background="#64748B" Foreground="White" FontWeight="SemiBold" FontSize="12" Padding="10,6" BorderThickness="0" Cursor="Hand"/>
          </StackPanel>
        </StackPanel>
      </Border>
    </Popup>
  </Grid>
</Window>
"@

try {
    $ovReader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($overlayXaml))
    $global:OverlayWindow = [Windows.Markup.XamlReader]::Load($ovReader)
} catch {
    [Windows.MessageBox]::Show("Overlay XAML error: $_", "AFOTRA") | Out-Null
}

if ($global:OverlayWindow) {
    $ovProcess           = $global:OverlayWindow.FindName("OvProcess")
    $ovTitle             = $global:OverlayWindow.FindName("OvTitle")
    $ovCategory          = $global:OverlayWindow.FindName("OvCategory")
    $ovCatBadge          = $global:OverlayWindow.FindName("OvCatBadge")
    $ovDuration          = $global:OverlayWindow.FindName("OvDuration")
    $ovFocusScore        = $global:OverlayWindow.FindName("OvFocusScore")
    $ovTotalTime         = $global:OverlayWindow.FindName("OvTotalTime")
    $ovAlertText         = $global:OverlayWindow.FindName("OvAlertText")
    $ovStatusDot         = $global:OverlayWindow.FindName("OvStatusDot")
    $global:OvSessionText = $global:OverlayWindow.FindName("OvSessionText")
    $btnOverlayStartStop = $global:OverlayWindow.FindName("BtnOverlayStartStop")
    $btnCloseOverlay     = $global:OverlayWindow.FindName("BtnCloseOverlay")
    # Orb elements
    $orbViewbox   = $global:OverlayWindow.FindName("OrbViewbox")
    $orbScale     = $global:OverlayWindow.FindName("OrbScale")
    $orbGlow      = $global:OverlayWindow.FindName("OrbGlow")
    $orbStopCore  = $global:OverlayWindow.FindName("OrbStopCore")
    $orbStopMid   = $global:OverlayWindow.FindName("OrbStopMid")
    $orbStopEdge  = $global:OverlayWindow.FindName("OrbStopEdge")
    $orbWingLRot  = $global:OverlayWindow.FindName("OrbWingLRot")
    $orbWingRRot  = $global:OverlayWindow.FindName("OrbWingRRot")
    $global:OrbDetailPopup = $global:OverlayWindow.FindName("OrbDetailPopup")
    $global:OrbMilestonePopup = $global:OverlayWindow.FindName("OrbMilestonePopup")
    $global:OrbMilestoneText  = $global:OverlayWindow.FindName("OrbMilestoneText")
    $global:OrbAskPopup    = $global:OverlayWindow.FindName("OrbAskPopup")
    $orbAskText   = $global:OverlayWindow.FindName("OrbAskText")
    $btnAskYes    = $global:OverlayWindow.FindName("BtnAskYes")
    $btnAskNo     = $global:OverlayWindow.FindName("BtnAskNo")
    $btnAskIgnore = $global:OverlayWindow.FindName("BtnAskIgnore")
    Update-TrackingButtons

    $global:OrbMilestoneTimer = New-Object System.Windows.Threading.DispatcherTimer
    $global:OrbMilestoneTimer.Interval = [TimeSpan]::FromSeconds(7)
    $global:OrbMilestoneTimer.Add_Tick({
        try {
            $global:OrbMilestoneTimer.Stop()
            if ($global:OrbMilestonePopup) { $global:OrbMilestonePopup.IsOpen = $false }
        } catch { }
    })

    # Drag sur la fenêtre entière, mais annulé si le clic vient d'un bouton
    $global:OverlayWindow.Add_MouseLeftButtonDown({
        param($s, $e)
        # Remonter l'arbre visuel depuis la source — si on croise un Button, ne pas dragger
        $el = $e.OriginalSource
        while ($null -ne $el) {
            if ($el -is [System.Windows.Controls.Primitives.ButtonBase]) { return }
            $el = try { [System.Windows.Media.VisualTreeHelper]::GetParent($el) } catch { $null }
        }
        try { $global:OverlayWindow.DragMove() } catch { }
        # The animation timer owns the window rect, so adopt the dragged position as home.
        $cx = $global:OverlayWindow.Left + $global:OverlayWindow.Width / 2
        $cy = $global:OverlayWindow.Top + $global:OverlayWindow.Height / 2
        $global:OrbCenter = @{ X = $cx; Y = $cy }
        $global:OrbHome   = @{ X = $cx; Y = $cy }
    })

    # --- Bouton ✕ : masquer ---
    $btnCloseOverlay.Add_Click({
        $global:OverlayWindow.Hide()
        $btnToggleOverlay.Content = "Afficher Overlay"
    })

    # --- Survol de la sphère : révèle le panneau de détails ---
    $global:OrbHideTimer = New-Object System.Windows.Threading.DispatcherTimer
    $global:OrbHideTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $global:OrbHideTimer.Add_Tick({
        $global:OrbHideTimer.Stop()
        if (-not $global:OrbOverWindow -and -not $global:OrbOverPopup) {
            if ($global:OrbDetailPopup) { $global:OrbDetailPopup.IsOpen = $false }
            $global:OrbHover = $false
        }
    })
    function Show-OrbDetail {
        if ($global:OrbAskPopup -and $global:OrbAskPopup.IsOpen) { return }   # la question a priorité
        if ($global:OrbDetailPopup) { $global:OrbDetailPopup.IsOpen = $true }
        $global:OrbHover = $true
    }
    $global:OverlayWindow.Add_MouseEnter({ $global:OrbOverWindow = $true; Show-OrbDetail })
    $global:OverlayWindow.Add_MouseLeave({ $global:OrbOverWindow = $false; $global:OrbHideTimer.Start() })
    if ($global:OrbDetailPopup -and $global:OrbDetailPopup.Child) {
        $global:OrbDetailPopup.Child.Add_MouseEnter({ $global:OrbOverPopup = $true })
        $global:OrbDetailPopup.Child.Add_MouseLeave({ $global:OrbOverPopup = $false; $global:OrbHideTimer.Start() })
    }

    # --- Bouton Start/Stop overlay : déclenche le bouton principal ---
    $btnOverlayStartStop.Add_Click({
        $btnStartStop.RaiseEvent(
            [System.Windows.RoutedEventArgs]::new(
                [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent
            )
        )
    })

    $categoryColors = @{
        "travail"       = "#10B981"
        "distraction"   = "#EF4444"
        "communication" = "#3B82F6"
        "etude"         = "#8B5CF6"
        "inconnu"       = "#F59E0B"
    }

    # --- Shake : pattern de positions X relatives ---
    $shakePattern = @(0,12,-12,12,-12,12,-12,10,-10,8,-8,5,-5,2,-2,0,0,0,0,0)

    $global:ShakeWobbleTimer = New-Object System.Windows.Threading.DispatcherTimer
    $global:ShakeWobbleTimer.Interval = [TimeSpan]::FromMilliseconds(55)
    $global:ShakeWobbleTimer.Add_Tick({
        if ($global:ShakeStep -ge $shakePattern.Count) {
            $global:ShakeWobbleTimer.Stop()
            $global:OverlayWindow.Left = $global:ShakeBaseLeft
            $global:ShakeStep = 0
            return
        }
        $global:OverlayWindow.Left = $global:ShakeBaseLeft + $shakePattern[$global:ShakeStep]
        $global:ShakeStep++
    })

    # Déclencheur périodique : secoue toutes les 7s si ShakeActive
    $global:ShakeTriggerTimer = New-Object System.Windows.Threading.DispatcherTimer
    $global:ShakeTriggerTimer.Interval = [TimeSpan]::FromSeconds(7)
    $global:ShakeTriggerTimer.Add_Tick({
        if (-not $global:ShakeActive) { $global:ShakeTriggerTimer.Stop(); return }
        $global:ShakeBaseLeft = $global:OverlayWindow.Left
        $global:ShakeStep = 0
        $global:ShakeWobbleTimer.Start()
    })

    # --- Alarme sonore sur thread séparé (Console.Beep ne bloque pas l'UI) ---
    function Start-Alarm {
        if ($global:AlarmActive) { return }
        $global:AlarmActive = $true
        $t = New-Object System.Threading.Thread({
            while ($global:AlarmActive) {
                try {
                    # Séquence agaçante : montée rapide + pause courte
                    [System.Console]::Beep(880,  180)
                    [System.Threading.Thread]::Sleep(60)
                    [System.Console]::Beep(1100, 180)
                    [System.Threading.Thread]::Sleep(60)
                    [System.Console]::Beep(1320, 180)
                    [System.Threading.Thread]::Sleep(60)
                    [System.Console]::Beep(1100, 180)
                    [System.Threading.Thread]::Sleep(60)
                    [System.Console]::Beep(880,  350)
                    [System.Threading.Thread]::Sleep(700)   # pause avant répétition
                } catch { break }
            }
        })
        $t.IsBackground = $true
        $t.Start()
        $global:AlarmThread = $t
    }

    function Stop-Alarm {
        $global:AlarmActive = $false   # le thread s'arrête au prochain test du while
    }

    # The orb itself now conveys agitation (colour/size/pulse via the animation timer),
    # so shake-mode no longer moves the window — it just raises a flag (+ optional alarm).
    function Start-ShakeMode {
        param([switch]$Silent)
        if ($global:ShakeActive) { return }
        $global:ShakeActive = $true
        if ($ovAlertText) { $ovAlertText.Text = "!! Recentre-toi" }
        if (-not $Silent) { Start-Alarm }
    }

    function Stop-ShakeMode {
        if (-not $global:ShakeActive) { return }
        $global:ShakeActive = $false
        if ($ovAlertText) { $ovAlertText.Text = "" }
        Stop-Alarm
    }

    # --- Update-Overlay ---
    function Update-Overlay {
        if (-not $global:OverlayWindow.IsVisible) { return }

        # Activité à afficher
        $info     = Get-ActiveWindowInfo
        $isAfotra = $info -and $info.ProcessName -eq "powershell" -and $info.WindowTitle -like "*AFOTRA*"
        $display  = if ($isAfotra -and $global:CurrentActivityInfo) { $global:CurrentActivityInfo } else { $info }

        $cat = "inconnu"
        if ($display) {
            $ovProcess.Text = $display.ProcessName
            $t = $display.WindowTitle
            $ovTitle.Text = if ($t.Length -gt 46) { $t.Substring(0,43) + "..." } else { $t }

            $cat = if ($display.PSObject.Properties["Category"] -and $display.Category) {
                $display.Category
            } else {
                Classify-Activity -ProcessName $display.ProcessName -WindowTitle $display.WindowTitle -Rules $global:rules
            }
            $ovCategory.Text = $cat
            $col = if ($categoryColors.ContainsKey($cat)) { $categoryColors[$cat] } else { "#6B7280" }
            $ovCatBadge.Background = $col
        }

        # Indicateur running + bouton overlay
        Update-TrackingButtons

        # Durée sur la fenêtre courante
        $ovDuration.Text = if ($global:CurrentActivityStart) {
            ((Get-Date) - $global:CurrentActivityStart).ToString('hh\:mm\:ss')
        } else { "00:00:00" }

        # Score focus du jour (lecture CSV légère)
        try {
            $rd = Get-DashboardReportData
            if ($rd) {
                $ovFocusScore.Text = "$($rd.FocusScore)%"
                $ovTotalTime.Text  = "$([math]::Round($rd.TotalSeconds / 60, 0))m"
            } else {
                $ovFocusScore.Text = "0%"
                $ovTotalTime.Text  = "0m"
            }
        } catch {}

        $sessionRunning = ($global:SessionState -and $global:SessionState.Mode -eq 'Running')

        # --- Focus guard : escalade tant qu'on reste hors-tâche ; "Non" ne calme pas ---
        # IMPORTANT: use $info (the REAL foreground), not $display (which is substituted with the
        # last tracked activity while AFOTRA is in front — that would trigger the guard spuriously
        # the moment you start a session and balloon the orb over the whole screen).
        if ($global:AsstFocusGuard -and $sessionRunning -and $info) {
            $proc = [string]$info.ProcessName
            $isAfotraWin = ($proc -eq 'powershell' -and $info.WindowTitle -like '*AFOTRA*')
            $allow = @($global:GuardAllow) + @($global:GuardSnooze)
            $onTask = $isAfotraWin -or (Test-ProcessAllowed -ProcessName $proc -AllowList $allow)

            if ($onTask) {
                # Back on the right track -> everything calms and the escalation resets.
                if ($global:GuardAsking -or $global:GuardOffTaskSince) { Clear-Guard }
            }
            else {
                # Off-task: start/continue the streak. Intensity (in Update-Orb) grows with
                # the streak duration + the number of "Non", so it gets more harassing.
                if (-not $global:GuardOffTaskSince) { $global:GuardOffTaskSince = Get-Date }
                if (-not $global:GuardAskStart)     { $global:GuardAskStart = Get-Date }
                if ($global:GuardAsking -ne $proc)  { $global:GuardAsking = $proc }   # switched to another off-task app

                $task = [string]$global:SessionState.TaskTitle
                $askMsg = if ([int]$global:GuardNonCount -gt 0) { "Toujours hors-tâche — reviens sur « $task » !" }
                          else { "« $proc » — en rapport avec « $task » ?" }

                $popupOpen = ($global:OrbAskPopup -and $global:OrbAskPopup.IsOpen)
                if (-not $popupOpen -and (-not $global:GuardReaskAt -or (Get-Date) -ge $global:GuardReaskAt)) {
                    # (re)open the question — after "Non" this fires again once the short re-arm elapses.
                    if ($orbAskText) { $orbAskText.Text = $askMsg }
                    if ($global:OrbDetailPopup) { $global:OrbDetailPopup.IsOpen = $false }
                    if ($global:OrbAskPopup) { $global:OrbAskPopup.IsOpen = $true }
                    $global:GuardReaskAt = $null
                }
                elseif ($popupOpen -and $orbAskText) { $orbAskText.Text = $askMsg }

                # Sound escalation: on if configured, or once the user has refused twice and stayed.
                $wantSound = $global:AsstGuardSound -or ([int]$global:GuardNonCount -ge 2)
                if ($wantSound -and -not $global:AlarmActive) { Start-Alarm }
            }
        }
        elseif ($global:GuardAsking -or $global:GuardOffTaskSince) {
            Clear-Guard   # session finie/pause -> on arrête d'interpeller
        }

        # --- Logique distraction streak (hors session ; la garde la supplante en session) ---
        if ($isRunning -and -not $sessionRunning) {
            if ($cat -eq "distraction") {
                if (-not $global:DistractionStreakStart) {
                    $global:DistractionStreakStart = Get-Date
                }
                $streakMin = ((Get-Date) - $global:DistractionStreakStart).TotalMinutes
                if ($streakMin -ge 5) {
                    Start-ShakeMode -Silent:(-not $global:AsstGuardSound)
                }
            } else {
                $global:DistractionStreakStart = $null
                if ($cat -eq "travail" -and $global:ShakeActive) {
                    Stop-ShakeMode
                }
            }
        }
    }

    # Overlay refresh 800ms
    $global:OverlayDispTimer = New-Object System.Windows.Threading.DispatcherTimer
    $global:OverlayDispTimer.Interval = [TimeSpan]::FromMilliseconds(800)
    $global:OverlayDispTimer.Add_Tick({ try { Update-Overlay } catch { if ($Debug) { Write-Warning "Overlay tick: $_" } } })
    $global:OverlayDispTimer.Start()

    # ---- Assistant orb: colour helpers, guard clearing, animation, ask handlers ----
    function ConvertTo-OrbColor { param([string]$Hex) [System.Windows.Media.ColorConverter]::ConvertFromString($Hex) }
    function ConvertTo-EdgeColor {
        param([string]$Hex)
        $c = [System.Windows.Media.ColorConverter]::ConvertFromString($Hex)
        return [System.Windows.Media.Color]::FromArgb(0, $c.R, $c.G, $c.B)
    }

    function Clear-Guard {
        $global:GuardAsking = $null
        $global:GuardOffTaskSince = $null
        $global:GuardNonCount = 0
        $global:GuardReaskAt = $null
        $global:GuardAskStart = $null
        if ($global:OrbAskPopup) { $global:OrbAskPopup.IsOpen = $false }
        Stop-Alarm
        if ($global:ShakeActive) { Stop-ShakeMode }
    }

    function Update-Orb {
        try {
            $hasSession = [bool]$global:SessionState
            $mode = if ($hasSession) { [string]$global:SessionState.Mode } else { 'None' }
            $isOverrun = $false
            if ($hasSession -and $global:SessionReadout) { $isOverrun = [bool]$global:SessionReadout.IsOverrun }
            $guard = [bool]$global:GuardAsking
            $awaiting = [bool]($hasSession -and $global:SessionState.AwaitingResume)
            $mood = Get-OrbMood -HasSession $hasSession -Mode $mode -IsOverrun $isOverrun -Guard $guard -AwaitingResume $awaiting
            if ($mood -eq 'Idle' -and $global:ShakeActive) { $mood = 'Overrun' }

            $intensity = 0.0
            if ($mood -eq 'Ask' -and $global:GuardOffTaskSince) {
                # Grows with time spent off-task (~25 s to max) AND with each "Non" (+0.3 each).
                $secs = ((Get-Date) - $global:GuardOffTaskSince).TotalSeconds
                $intensity = [math]::Min(1.0, ($secs / 25.0) + ([int]$global:GuardNonCount * 0.3))
            }
            $vis = Get-OrbVisual -Mood $mood -Intensity $intensity

            $orbStopCore.Color = ConvertTo-OrbColor $vis.Core
            $orbStopMid.Color  = ConvertTo-OrbColor $vis.Edge
            $orbStopEdge.Color = ConvertTo-EdgeColor $vis.Edge
            $orbGlow.Color     = ConvertTo-OrbColor $vis.Glow

            $target = [double][math]::Max($global:AsstOrbMinSize, [math]::Min($global:AsstOrbMaxSize, $vis.SizePx))
            if ($global:OrbHover) { $target = [math]::Max($target, 100) }
            $global:OrbCurSize = $global:OrbCurSize + ($target - $global:OrbCurSize) * 0.18
            $sz = [double]$global:OrbCurSize
            $orbViewbox.Width = $sz; $orbViewbox.Height = $sz

            $global:OrbPhase += (50.0 / [double]$vis.PulsePeriodMs)
            $tau = 2 * [math]::PI
            $pulse = 1.0 + [double]$vis.PulseAmp * [math]::Sin($tau * $global:OrbPhase)
            $wob   = [double]$vis.WobbleAmp * [math]::Sin($tau * $global:OrbPhase * 1.6)
            $orbScale.ScaleX = $pulse + $wob
            $orbScale.ScaleY = $pulse - $wob
            # Wing flap — faster when agitated (shorter pulse period)
            if ($orbWingLRot -and $orbWingRRot) {
                $flap = [math]::Abs([math]::Sin($tau * $global:OrbPhase * 3.0)) * 18.0
                $orbWingLRot.Angle = -8.0 - $flap
                $orbWingRRot.Angle = 8.0 + $flap
            }
            $orbGlow.BlurRadius = [double]$vis.GlowRadius * (1.0 + 0.35 * [math]::Sin($tau * $global:OrbPhase))
            $orbGlow.Opacity = 0.7 + 0.25 * (0.5 + 0.5 * [math]::Sin($tau * $global:OrbPhase))

            # Window rect (this timer is the SOLE owner of the overlay position/size)
            $margin = [double]($vis.GlowRadius * 2 + 24)
            $winSize = $sz * (1.0 + [double]$vis.PulseAmp) + $margin
            if (-not $global:OrbCenter) { $global:OrbCenter = @{ X = ($global:OverlayWindow.Left + $global:OverlayWindow.Width / 2); Y = ($global:OverlayWindow.Top + $global:OverlayWindow.Height / 2) } }
            if (-not $global:OrbHome)   { $global:OrbHome   = @{ X = $global:OrbCenter.X; Y = $global:OrbCenter.Y } }
            $tgtX = $global:OrbHome.X; $tgtY = $global:OrbHome.Y
            if ($vis.MoveToCenter -and -not $global:OrbHover) {
                $tgtX = [System.Windows.SystemParameters]::PrimaryScreenWidth / 2
                $tgtY = [System.Windows.SystemParameters]::PrimaryScreenHeight / 2
            }
            $global:OrbCenter.X = $global:OrbCenter.X + ($tgtX - $global:OrbCenter.X) * 0.10
            $global:OrbCenter.Y = $global:OrbCenter.Y + ($tgtY - $global:OrbCenter.Y) * 0.10
            $global:OverlayWindow.Width  = $winSize
            $global:OverlayWindow.Height = $winSize
            $global:OverlayWindow.Left = $global:OrbCenter.X - $winSize / 2
            $global:OverlayWindow.Top  = $global:OrbCenter.Y - $winSize / 2
        } catch { if ($Debug) { Write-Warning "Update-Orb: $_" } }
    }

    $global:OrbAnimTimer = New-Object System.Windows.Threading.DispatcherTimer
    $global:OrbAnimTimer.Interval = [TimeSpan]::FromMilliseconds(50)
    $global:OrbAnimTimer.Add_Tick({ Update-Orb })
    if ($global:AsstOrbEnabled) { $global:OrbAnimTimer.Start() }

    $btnAskYes.Add_Click({
        if ($global:GuardAsking -and $global:SessionState) {
            $proc = $global:GuardAsking
            Add-TaskTool -Id $global:SessionState.TaskId -Process $proc -Path $global:taskStorePath | Out-Null
            $global:GuardAllow += $proc
        }
        Clear-Guard
    })
    $btnAskNo.Add_Click({
        if ($global:GuardAsking -and $global:SessionState) {
            Add-TaskDigression -Id $global:SessionState.TaskId -Path $global:taskStorePath | Out-Null
        }
        # "Non" does NOT calm the orb: bump the escalation and re-arm the question. It keeps
        # harassing (bigger, redder, faster, then sound) until you actually go back on task.
        $global:GuardNonCount = [int]$global:GuardNonCount + 1
        if ($ovAlertText) { $ovAlertText.Text = "Reviens sur ta tâche" }
        if ($global:OrbAskPopup) { $global:OrbAskPopup.IsOpen = $false }
        $global:GuardReaskAt = (Get-Date).AddSeconds(5)   # brief window to actually close the app
        # Guard stays armed ($global:GuardAsking / GuardOffTaskSince unchanged) -> orb stays agitated.
    })
    $btnAskIgnore.Add_Click({
        if ($global:GuardAsking) { $global:GuardSnooze += $global:GuardAsking }   # snooze pour la session
        Clear-Guard
    })

    # Bouton toggle sidebar
    $btnToggleOverlay.Add_Click({
        if ($global:OverlayWindow.IsVisible) {
            $global:OverlayWindow.Hide()
            $btnToggleOverlay.Content = "Afficher Overlay"
        } else {
            $global:OverlayWindow.Show()
            $btnToggleOverlay.Content = "Masquer Overlay"
        }
    })
}

# ===================================================================
# Window cleanup
# ===================================================================

$window.Add_Closing({
    param($sender, $eventArgs)
    try {
        Write-DashboardRuntimeError "Main window closing. sessionActive=$([bool]$global:SessionState) overlayVisible=$([bool]($global:OverlayWindow -and $global:OverlayWindow.IsVisible))"
        Stop-TrackingTimer
        Stop-DashboardTimer
        if ($global:TaskReminderTimer)  { $global:TaskReminderTimer.Stop();  $global:TaskReminderTimer  = $null }
        if ($global:SessionState) {
            try { Stop-CurrentSession | Out-Null }
            catch { Write-DashboardRuntimeError "Persist session during closing failed: $_" }
        }
        if ($global:SessionTimer)       { $global:SessionTimer.Stop();       $global:SessionTimer       = $null }
        Close-AfotraNotifier
        if ($global:OverlayDispTimer)   { $global:OverlayDispTimer.Stop();   $global:OverlayDispTimer   = $null }
        if ($global:OrbAnimTimer)       { $global:OrbAnimTimer.Stop();       $global:OrbAnimTimer       = $null }
        if ($global:OrbMilestoneTimer)  { $global:OrbMilestoneTimer.Stop();  $global:OrbMilestoneTimer  = $null }
        if ($global:OrbHideTimer)       { $global:OrbHideTimer.Stop();       $global:OrbHideTimer       = $null }
        if ($global:ShakeWobbleTimer)   { $global:ShakeWobbleTimer.Stop();   $global:ShakeWobbleTimer   = $null }
        if ($global:ShakeTriggerTimer)  { $global:ShakeTriggerTimer.Stop();  $global:ShakeTriggerTimer  = $null }
        $global:AlarmActive = $false
        if ($global:OverlayWindow)      { $global:OverlayWindow.Close();     $global:OverlayWindow      = $null }
    } catch {
        Write-DashboardRuntimeError "Main window closing handler failed: $_"
    }
})

Initialize-UI

if ($global:OverlayWindow) {
    $global:OverlayWindow.Show()
    $btnToggleOverlay.Content = "Masquer Overlay"
}

# Run the WPF dispatcher with the main window as the lifetime owner.
$app = [System.Windows.Application]::Current
if (-not $app) {
    $app = New-Object System.Windows.Application
}
$app.MainWindow = $window
$app.Add_DispatcherUnhandledException({
    param($sender, $eventArgs)
    try { Write-DashboardRuntimeError "Dispatcher unhandled exception: $($eventArgs.Exception)" } catch { }
    $eventArgs.Handled = $true
})
$app.ShutdownMode = [System.Windows.ShutdownMode]::OnMainWindowClose
Write-DashboardRuntimeError "Application.Run starting. mainWindowTitle=$($app.MainWindow.Title)"
$app.Run($window) | Out-Null
Write-DashboardRuntimeError "Application.Run returned."

Stop-TrackingTimer
Stop-DashboardTimer
Write-DashboardRuntimeError "Dashboard script exited after Run."
