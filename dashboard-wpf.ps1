# dashboard-wpf.ps1 - Modern WPF Dashboard for AFOTRA - Awema Focus Tracker
# Author: CodeScooper | Version: 2.0 (Improved)
# Project: AFOTRA - Awema Focus Tracker

param(
    [switch]$Debug
)

$ErrorActionPreference = "Stop"

# This dashboard requires Windows + Desktop .NET (WPF)
# $IsWindows only exists in PowerShell 6+; on Windows PowerShell 5.x we are always on Windows
$isWindowsOS = if ($PSVersionTable.PSVersion.Major -ge 6) { $IsWindows } else { $true }
if (-not $isWindowsOS) {
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
} catch {
    [Windows.MessageBox]::Show("Error loading modules: $_", "AFOTRA Error") | Out-Null
    exit 1
}

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
$global:rulesPath = $rulesPath
$global:configPath = $configPath

# Global state
$global:TrackerRunning = $false
$global:TrackerTimer = $null
$global:CurrentView = "DashboardView"
$global:CurrentActivityStart = $null
$global:CurrentActivityInfo = $null
$global:CurrentLogFile = $null
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

# XAML for the main window
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AFOTRA - Awema Focus Tracker v2.0" Height="900" Width="1400"
        WindowStartupLocation="CenterScreen" Background="#F5F7FA">
    <Window.Resources>
        <SolidColorBrush x:Key="PrimaryBrush" Color="#2563EB"/>
        <SolidColorBrush x:Key="SecondaryBrush" Color="#64748B"/>
        <SolidColorBrush x:Key="SuccessBrush" Color="#10B981"/>
        <SolidColorBrush x:Key="WarningBrush" Color="#F59E0B"/>
        <SolidColorBrush x:Key="DangerBrush" Color="#EF4444"/>
        <SolidColorBrush x:Key="CardBackground" Color="#FFFFFF"/>
        <SolidColorBrush x:Key="TextPrimary" Color="#1F2937"/>
        <SolidColorBrush x:Key="TextSecondary" Color="#6B7280"/>
        <Style x:Key="CardStyle" TargetType="Border">
            <Setter Property="Background" Value="#FFFFFF"/>
            <Setter Property="CornerRadius" Value="8"/>
            <Setter Property="BorderBrush" Value="#E5E7EB"/>
            <Setter Property="BorderThickness" Value="1"/>
        </Style>
        <Style x:Key="PrimaryButtonStyle" TargetType="Button">
            <Setter Property="Background" Value="#2563EB"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Padding" Value="12,8"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
    </Window.Resources>
    <Grid>
        <!-- Sidebar Navigation -->
        <Border Background="#2563EB" Width="260" HorizontalAlignment="Left">
            <StackPanel Margin="20">
                <TextBlock Text="AFOTRA" FontSize="26" FontWeight="Bold" Foreground="White" Margin="0,0,0,10"/>
                <TextBlock Text="Focus Tracker" FontSize="12" Foreground="#E0EFFE" Margin="0,0,0,30" TextAlignment="Center"/>
                
                <Button x:Name="NavDashboard" Content="Dashboard" Background="#64748B" Foreground="White" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand" Margin="0,0,0,8"/>
                <Button x:Name="NavLiveTracking" Content="Live Tracking" Background="#64748B" Foreground="White" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand" Margin="0,0,0,8"/>
                <Button x:Name="NavUnknownActivities" Content="Unknown" Background="#64748B" Foreground="White" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand" Margin="0,0,0,8"/>
                <Button x:Name="NavRulesCategories" Content="Rules" Background="#64748B" Foreground="White" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand" Margin="0,0,0,8"/>
                <Button x:Name="NavTasks" Content="Tâches" Background="#64748B" Foreground="White" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand" Margin="0,0,0,30"/>
                
                <Separator Background="#4B5563" Margin="0,0,0,20"/>
                
                <Button x:Name="BtnStartStop" Content="Start Tracking" Background="#10B981" Foreground="White" FontWeight="Bold" FontSize="14" Padding="12,8" BorderThickness="0" Cursor="Hand" Margin="0,0,0,12" Height="42"/>
                <TextBlock x:Name="StatusText" Text="Status: Stopped" Foreground="White" Margin="0,10,0,0" FontSize="11" TextAlignment="Center" FontWeight="SemiBold"/>
                <TextBlock x:Name="CurrentProcessText" Text="Process: --" Foreground="#E0EFFE" Margin="0,15,0,0" FontSize="10" TextWrapping="Wrap"/>
                <Button x:Name="BtnToggleOverlay" Content="Afficher Overlay" Background="#374151" Foreground="White" FontWeight="SemiBold" FontSize="11" Padding="12,6" BorderThickness="0" Cursor="Hand" Margin="0,12,0,0"/>
            </StackPanel>
        </Border>

        <!-- Main Content Area -->
        <ScrollViewer Margin="280,20,20,20" VerticalScrollBarVisibility="Auto">
            <StackPanel x:Name="MainContent" Margin="0,0,0,20">
                
                <!-- Dashboard View -->
                <StackPanel x:Name="DashboardView" Visibility="Visible">
                    <TextBlock Text="Dashboard" FontSize="32" FontWeight="Bold" Foreground="#1F2937" Margin="0,0,0,20"/>
                    
                    <!-- Stats Cards Grid -->
                    <Grid Margin="0,0,0,20">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="1*"/><ColumnDefinition Width="1*"/><ColumnDefinition Width="1*"/><ColumnDefinition Width="1*"/>
                        </Grid.ColumnDefinitions>
                        <Border Grid.Column="0" Background="#FFFFFF" CornerRadius="8" BorderBrush="#E5E7EB" BorderThickness="1" Margin="0,0,10,0">
                            <StackPanel Margin="15">
                                <TextBlock Text="Total Time" FontSize="12" Foreground="#6B7280"/>
                                <TextBlock x:Name="TotalTimeText" Text="00:00:00" FontSize="26" FontWeight="Bold" Foreground="#1F2937" Margin="0,5,0,0"/>
                            </StackPanel>
                        </Border>
                        <Border Grid.Column="1" Background="#FFFFFF" CornerRadius="8" BorderBrush="#E5E7EB" BorderThickness="1" Margin="0,0,10,0">
                            <StackPanel Margin="15">
                                <TextBlock Text="Focus Time" FontSize="12" Foreground="#6B7280"/>
                                <TextBlock x:Name="FocusTimeText" Text="00:00:00" FontSize="26" FontWeight="Bold" Foreground="#10B981" Margin="0,5,0,0"/>
                            </StackPanel>
                        </Border>
                        <Border Grid.Column="2" Background="#FFFFFF" CornerRadius="8" BorderBrush="#E5E7EB" BorderThickness="1" Margin="0,0,10,0">
                            <StackPanel Margin="15">
                                <TextBlock Text="Focus Score" FontSize="12" Foreground="#6B7280"/>
                                <TextBlock x:Name="FocusScoreText" Text="0%" FontSize="26" FontWeight="Bold" Foreground="#2563EB" Margin="0,5,0,0"/>
                            </StackPanel>
                        </Border>
                        <Border Grid.Column="3" Background="#FFFFFF" CornerRadius="8" BorderBrush="#E5E7EB" BorderThickness="1">
                            <StackPanel Margin="15">
                                <TextBlock Text="Distractions" FontSize="12" Foreground="#6B7280"/>
                                <TextBlock x:Name="DistractionTimeText" Text="00:00:00" FontSize="26" FontWeight="Bold" Foreground="#EF4444" Margin="0,5,0,0"/>
                            </StackPanel>
                        </Border>
                    </Grid>

                    <!-- Charts Section -->
                    <Border Background="#FFFFFF" CornerRadius="8" BorderBrush="#E5E7EB" BorderThickness="1" Margin="0,0,0,20">
                        <StackPanel Margin="20">
                            <TextBlock Text="Activity Distribution" FontSize="18" FontWeight="Bold" Foreground="#1F2937" Margin="0,0,0,15"/>
                            <Canvas x:Name="ActivityChartCanvas" Width="1000" Height="280" Background="#F9FAFB"/>
                        </StackPanel>
                    </Border>
                    
                    <!-- Quick Actions -->
                    <!-- Tasks summary card -->
                    <Border Background="#FFFFFF" CornerRadius="8" BorderBrush="#E5E7EB" BorderThickness="1" Margin="0,0,0,20">
                        <StackPanel Margin="20">
                            <TextBlock Text="Tâches" FontSize="16" FontWeight="Bold" Foreground="#1F2937" Margin="0,0,0,12"/>
                            <StackPanel Orientation="Horizontal">
                                <StackPanel Margin="0,0,30,0"><TextBlock Text="À faire" FontSize="11" Foreground="#6B7280"/><TextBlock x:Name="TaskCountAFaire" Text="0" FontSize="22" FontWeight="Bold" Foreground="#2563EB"/></StackPanel>
                                <StackPanel Margin="0,0,30,0"><TextBlock Text="En cours" FontSize="11" Foreground="#6B7280"/><TextBlock x:Name="TaskCountEnCours" Text="0" FontSize="22" FontWeight="Bold" Foreground="#F59E0B"/></StackPanel>
                                <StackPanel Margin="0,0,30,0"><TextBlock Text="Terminées auj." FontSize="11" Foreground="#6B7280"/><TextBlock x:Name="TaskCountTermine" Text="0" FontSize="22" FontWeight="Bold" Foreground="#10B981"/></StackPanel>
                                <StackPanel Margin="0,0,30,0"><TextBlock Text="En retard" FontSize="11" Foreground="#6B7280"/><TextBlock x:Name="TaskCountRetard" Text="0" FontSize="22" FontWeight="Bold" Foreground="#EF4444"/></StackPanel>
                            </StackPanel>
                        </StackPanel>
                    </Border>

                    <StackPanel Orientation="Horizontal" Margin="0,0,0,20">
                        <Button x:Name="BtnGenerateReport" Content="Generate Report" Background="#3B82F6" Foreground="White" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand" Margin="0,0,10,0"/>
                        <Button x:Name="BtnOpenLogs" Content="Open Logs" Background="#64748B" Foreground="White" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand"/>
                    </StackPanel>
                </StackPanel>

                <!-- Live Tracking View -->
                <StackPanel x:Name="LiveTrackingView" Visibility="Collapsed">
                    <TextBlock Text="Live Tracking" FontSize="32" FontWeight="Bold" Foreground="#1F2937" Margin="0,0,0,20"/>
                    
                    <Border Background="#FFFFFF" CornerRadius="8" BorderBrush="#E5E7EB" BorderThickness="1" Margin="0,0,0,20">
                        <StackPanel Margin="20">
                            <TextBlock Text="Current Activity" FontSize="18" FontWeight="Bold" Foreground="#1F2937" Margin="0,0,0,15"/>
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <StackPanel Grid.Column="0" Margin="0,0,20,0">
                                    <TextBlock Text="Process:" FontWeight="SemiBold" Foreground="#6B7280"/>
                                    <TextBlock x:Name="LiveProcessText" Text="--" FontSize="16" Margin="0,5,0,10" Foreground="#1F2937" FontFamily="Consolas"/>
                                    <TextBlock Text="Window Title:" FontWeight="SemiBold" Foreground="#6B7280"/>
                                    <TextBlock x:Name="LiveWindowText" Text="--" FontSize="13" Margin="0,5,0,10" TextWrapping="Wrap" Foreground="#1F2937"/>
                                </StackPanel>
                                <StackPanel Grid.Column="1">
                                    <TextBlock Text="Category:" FontWeight="SemiBold" Foreground="#6B7280"/>
                                    <TextBlock x:Name="LiveCategoryText" Text="--" FontSize="16" Margin="0,5,0,10" Foreground="#10B981" FontWeight="Bold"/>
                                    <TextBlock Text="Duration:" FontWeight="SemiBold" Foreground="#6B7280"/>
                                    <TextBlock x:Name="LiveCurrentTimeText" Text="00:00:00" FontSize="16" Margin="0,5,0,10" Foreground="#1F2937" FontFamily="Consolas" FontWeight="Bold"/>
                                </StackPanel>
                            </Grid>
                        </StackPanel>
                    </Border>
                    
                    <Border Background="#FFFFFF" CornerRadius="8" BorderBrush="#E5E7EB" BorderThickness="1">
                        <StackPanel Margin="20">
                            <TextBlock Text="Last 10 Activities" FontSize="18" FontWeight="Bold" Foreground="#1F2937" Margin="0,0,0,15"/>
                            <DataGrid x:Name="RecentActivitiesGrid" Height="280" AutoGenerateColumns="False" IsReadOnly="True" Background="White">
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
                    <TextBlock Text="Unknown Activities" FontSize="32" FontWeight="Bold" Foreground="#1F2937" Margin="0,0,0,20"/>
                    
                    <Border Background="#FFFFFF" CornerRadius="8" BorderBrush="#E5E7EB" BorderThickness="1">
                        <StackPanel Margin="20">
                            <TextBlock Text="Categorize unclassified activities to improve tracking" FontSize="14" Foreground="#6B7280" Margin="0,0,0,15"/>
                            <DataGrid x:Name="UnknownActivitiesGrid" Height="350" AutoGenerateColumns="False" IsReadOnly="True" Background="White" CanUserAddRows="False">
                                <DataGrid.Columns>
                                    <DataGridTextColumn Header="Process" Binding="{Binding ProcessName}" Width="150"/>
                                    <DataGridTextColumn Header="Window Title" Binding="{Binding WindowTitle}" Width="*"/>
                                    <DataGridTextColumn Header="Count" Binding="{Binding Count}" Width="80"/>
                                    <DataGridTextColumn Header="Total Time" Binding="{Binding TotalTime}" Width="100"/>
                                </DataGrid.Columns>
                            </DataGrid>
                            <StackPanel Orientation="Horizontal" Margin="0,15,0,0">
                                <Button x:Name="BtnCategorizeUnknown" Content="Categorize Selected" Background="#10B981" Foreground="White" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand" Margin="0,0,10,0"/>
                                <Button x:Name="BtnRefreshUnknown" Content="Refresh" Background="#64748B" Foreground="White" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand"/>
                            </StackPanel>
                        </StackPanel>
                    </Border>
                </StackPanel>

                <!-- Rules & Categories View -->
                <StackPanel x:Name="RulesCategoriesView" Visibility="Collapsed">
                    <TextBlock Text="Rules &amp; Categories" FontSize="32" FontWeight="Bold" Foreground="#1F2937" Margin="0,0,0,20"/>
                    
                    <Grid Margin="0,0,0,20">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="1*"/><ColumnDefinition Width="1*"/>
                        </Grid.ColumnDefinitions>
                        
                        <Border Grid.Column="0" Background="#FFFFFF" CornerRadius="8" BorderBrush="#E5E7EB" BorderThickness="1" Margin="0,0,10,0">
                            <StackPanel Margin="20">
                                <TextBlock Text="Categories" FontSize="16" FontWeight="Bold" Foreground="#1F2937" Margin="0,0,0,15"/>
                                <ListBox x:Name="CategoriesListBox" Height="150" Background="White" FontSize="13"/>
                                <StackPanel Orientation="Horizontal" Margin="0,15,0,0">
                                    <TextBox x:Name="NewCategoryTextBox" Width="240" Padding="8" Margin="0,0,10,0" Background="White"/>
                                    <Button x:Name="BtnAddCategory" Content="Add" Background="#2563EB" Foreground="White" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand" Width="90"/>
                                </StackPanel>
                            </StackPanel>
                        </Border>
                        
                        <Border Grid.Column="1" Background="#FFFFFF" CornerRadius="8" BorderBrush="#E5E7EB" BorderThickness="1">
                            <StackPanel Margin="20">
                                <TextBlock Text="Process Rules" FontSize="16" FontWeight="Bold" Foreground="#1F2937" Margin="0,0,0,15"/>
                                <DataGrid x:Name="ProcessRulesGrid" Height="150" AutoGenerateColumns="False" Background="White" CanUserAddRows="False">
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
                    <Border Background="#FFFFFF" CornerRadius="8" BorderBrush="#E5E7EB" BorderThickness="1" Margin="0,0,0,20">
                        <StackPanel Margin="20">
                            <TextBlock Text="Analyse Historique Chrome" FontSize="16" FontWeight="Bold" Foreground="#1F2937" Margin="0,0,0,8"/>
                            <TextBlock Text="Détecte les domaines les plus visités et crée des règles automatiquement." FontSize="12" Foreground="#6B7280" Margin="0,0,0,12"/>
                            <StackPanel Orientation="Horizontal">
                                <Button x:Name="BtnAnalyzeChrome" Content="Analyser Chrome" Background="#EA580C" Foreground="White" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand"/>
                                <TextBlock x:Name="ChromeStatusText" Text="" Foreground="#6B7280" FontSize="12" Margin="15,0,0,0" VerticalAlignment="Center"/>
                            </StackPanel>
                        </StackPanel>
                    </Border>
                </StackPanel>

                <!-- ===== TASKS VIEW ===== -->
                <StackPanel x:Name="TasksView" Visibility="Collapsed">
                    <TextBlock Text="Tâches" FontSize="32" FontWeight="Bold" Foreground="#1F2937" Margin="0,0,0,20"/>

                    <!-- Session panel (Pomodoro) -->
                    <Border Background="#FFFFFF" CornerRadius="8" BorderBrush="#E5E7EB" BorderThickness="1" Margin="0,0,0,15">
                        <Grid Margin="20">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel Grid.Column="0" Margin="0,0,30,0" VerticalAlignment="Center">
                                <TextBlock Text="SESSION" FontSize="12" FontWeight="Bold" Foreground="#6B7280"/>
                                <TextBlock x:Name="SessionCountdown" Text="--:--" FontSize="46" FontWeight="Bold" Foreground="#9CA3AF" FontFamily="Consolas"/>
                                <TextBlock x:Name="SessionPomText" Text="" FontSize="12" Foreground="#6B7280"/>
                            </StackPanel>
                            <StackPanel Grid.Column="1" VerticalAlignment="Center">
                                <TextBlock x:Name="SessionTaskText" Text="Aucune session active" FontSize="15" FontWeight="SemiBold" Foreground="#1F2937" TextWrapping="Wrap" Margin="0,0,0,8"/>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                                    <TextBlock Text="Travail " FontSize="12" Foreground="#6B7280"/><TextBlock x:Name="SessionWorkText" Text="00:00:00" FontSize="12" Foreground="#1F2937" FontFamily="Consolas" Margin="0,0,16,0"/>
                                    <TextBlock Text="Global " FontSize="12" Foreground="#6B7280"/><TextBlock x:Name="SessionGlobalText" Text="00:00:00" FontSize="12" Foreground="#1F2937" FontFamily="Consolas" Margin="0,0,16,0"/>
                                    <TextBlock Text="Pause " FontSize="12" Foreground="#6B7280"/><TextBlock x:Name="SessionPauseText" Text="00:00:00" FontSize="12" Foreground="#1F2937" FontFamily="Consolas"/>
                                </StackPanel>
                                <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                                    <TextBlock Text="Estimé (min):" FontSize="12" Foreground="#6B7280" VerticalAlignment="Center" Margin="0,0,6,0"/>
                                    <TextBox x:Name="SessionEstimeInput" Width="60" Padding="4,3" Text="25" Background="White"/>
                                </StackPanel>
                                <StackPanel Orientation="Horizontal">
                                    <Button x:Name="BtnSessStart" Content="Démarrer" Background="#10B981" Foreground="White" FontWeight="SemiBold" FontSize="12" Padding="10,6" BorderThickness="0" Cursor="Hand" Margin="0,0,6,0"/>
                                    <Button x:Name="BtnSessPause" Content="Pause" Background="#64748B" Foreground="White" FontWeight="SemiBold" FontSize="12" Padding="10,6" BorderThickness="0" Cursor="Hand" Margin="0,0,6,0"/>
                                    <Button x:Name="BtnSessResume" Content="Reprendre" Background="#64748B" Foreground="White" FontWeight="SemiBold" FontSize="12" Padding="10,6" BorderThickness="0" Cursor="Hand" Margin="0,0,6,0"/>
                                    <Button x:Name="BtnSessBreak" Content="Pause Pomodoro" Background="#8B5CF6" Foreground="White" FontWeight="SemiBold" FontSize="12" Padding="10,6" BorderThickness="0" Cursor="Hand" Margin="0,0,6,0"/>
                                    <Button x:Name="BtnSessComplete" Content="Terminer la tâche" Background="#2563EB" Foreground="White" FontWeight="SemiBold" FontSize="12" Padding="10,6" BorderThickness="0" Cursor="Hand" Margin="0,0,6,0"/>
                                    <Button x:Name="BtnSessStop" Content="Arrêter" Background="#EF4444" Foreground="White" FontWeight="SemiBold" FontSize="12" Padding="10,6" BorderThickness="0" Cursor="Hand"/>
                                </StackPanel>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <!-- Toolbar: search + quick filters -->
                    <Border Background="#FFFFFF" CornerRadius="8" BorderBrush="#E5E7EB" BorderThickness="1" Margin="0,0,0,15">
                        <StackPanel Margin="20">
                            <StackPanel Orientation="Horizontal" Margin="0,0,0,12">
                                <TextBox x:Name="TaskSearchBox" Width="320" Padding="8" Margin="0,0,10,0" Background="White"/>
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
                    <Border Background="#FFFFFF" CornerRadius="8" BorderBrush="#E5E7EB" BorderThickness="1">
                        <StackPanel Margin="20">
                            <DataGrid x:Name="TasksGrid" Height="360" AutoGenerateColumns="False" IsReadOnly="True" Background="White" CanUserAddRows="False" SelectionMode="Single" GridLinesVisibility="Horizontal" HeadersVisibility="Column">
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
                                <Button x:Name="BtnTaskRefresh" Content="Rafraîchir" Background="#64748B" Foreground="White" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand"/>
                            </StackPanel>
                            <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                                <TextBlock Text="●" Foreground="#EF4444" FontSize="13" Margin="0,0,4,0"/><TextBlock Text="en retard" FontSize="11" Foreground="#6B7280" Margin="0,0,16,0"/>
                                <TextBlock Text="●" Foreground="#F59E0B" FontSize="13" Margin="0,0,4,0"/><TextBlock Text="due aujourd'hui" FontSize="11" Foreground="#6B7280" Margin="0,0,16,0"/>
                                <TextBlock Text="●" Foreground="#9CA3AF" FontSize="13" Margin="0,0,4,0"/><TextBlock Text="terminé / archivé" FontSize="11" Foreground="#6B7280"/>
                            </StackPanel>
                        </StackPanel>
                    </Border>
                </StackPanel>
            </StackPanel>
        </ScrollViewer>
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
$btnTaskRefresh = $window.FindName("BtnTaskRefresh")
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

$navDashboard.Add_Click({ Show-View "DashboardView" })
$navLiveTracking.Add_Click({ Show-View "LiveTrackingView" })
$navUnknownActivities.Add_Click({ Show-View "UnknownActivitiesView" })
$navRulesCategories.Add_Click({ Show-View "RulesCategoriesView" })
$navTasks.Add_Click({ Show-View "TasksView" })

# Initialize UI
function Initialize-UI {
    $categoriesListBox.Items.Clear()
    foreach ($category in $global:rules.categories) {
        $categoriesListBox.Items.Add($category) | Out-Null
    }
    Update-Rules-UI
    # Seed starter tasks on first launch (no-op if tasks.json already has data).
    try { Initialize-TaskSeed -Path $global:taskStorePath | Out-Null } catch { if ($Debug) { Write-Warning "Seed failed: $_" } }
    Update-Tasks-UI
    Update-SessionUI
    Update-SessionButtons
    Update-Dashboard
}

# Update functions
function Update-Dashboard {
    Update-TaskSummaryCard   # independent of tracking data
    $logFile = Get-TodayLogFile -LogFolder $global:logFolder
    if (!(Test-Path $logFile)) { return }
    
    try {
        $data = @(Import-Csv -Path $logFile -Encoding UTF8 -ErrorAction SilentlyContinue)
        if ($data.Count -eq 0) { return }
        
        $sampleSeconds = [int]$data[0].SampleSeconds
        $totalSeconds = $data.Count * $sampleSeconds
        $categories = @{}
        
        foreach ($row in $data) {
            if (!$categories[$row.Category]) { $categories[$row.Category] = 0 }
            $categories[$row.Category] += $sampleSeconds
        }
        
        $focusSeconds = if ($categories["travail"]) { $categories["travail"] } else { 0 }
        $distractionSeconds = if ($categories["distraction"]) { $categories["distraction"] } else { 0 }
        $focusScore = if ($totalSeconds -gt 0) { [math]::Round(($focusSeconds / $totalSeconds) * 100, 1) } else { 0 }
        
        $totalTimeText.Text = [TimeSpan]::FromSeconds($totalSeconds).ToString('hh\:mm\:ss')
        $focusTimeText.Text = [TimeSpan]::FromSeconds($focusSeconds).ToString('hh\:mm\:ss')
        $distractionTimeText.Text = [TimeSpan]::FromSeconds($distractionSeconds).ToString('hh\:mm\:ss')
        $focusScoreText.Text = "$focusScore%"
        
        if ($global:CurrentActivityInfo) {
            $title = $global:CurrentActivityInfo.WindowTitle
            if ($title.Length -gt 60) { $title = $title.Substring(0, 57) + "..." }
            $currentProcessText.Text = "Process: $($global:CurrentActivityInfo.ProcessName)"
        }
        
        Update-ActivityChart -Categories $categories -TotalSeconds $totalSeconds

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
            $recentActivities = @($data | Select-Object -Last 10 | ForEach-Object {
                [PSCustomObject]@{
                    Time = $_.Time; Process = $_.ProcessName; Title = if ($_.WindowTitle.Length -gt 45) { $_.WindowTitle.Substring(0, 42) + "..." } else { $_.WindowTitle }; Category = $_.Category
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
        $textBlock.Text = "$([math]::Round($percentage * 100, 1))%"; $textBlock.FontSize = 10; $textBlock.Foreground = "#374151"; $textBlock.TextAlignment = "Center"; $textBlock.Width = $barWidth
        [Windows.Controls.Canvas]::SetLeft($textBlock, $x); [Windows.Controls.Canvas]::SetTop($textBlock, 205)
        $activityChartCanvas.Children.Add($textBlock) | Out-Null
        
        $legendText = New-Object Windows.Controls.TextBlock
        $legendText.Text = "$category"; $legendText.FontSize = 11; $legendText.Foreground = "#374151"; $legendText.FontWeight = "Bold"
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
        $grouped = $data | Where-Object { $_.Category -eq "inconnu" } | Group-Object { "$($_.ProcessName)|$($_.WindowTitle)" }
        
        foreach ($group in $grouped) {
            $parts = $group.Name -split '\|'
            $unknownActivities += [PSCustomObject]@{
                ProcessName = $parts[0]; WindowTitle = $parts[1]; Count = $group.Count; TotalTime = [TimeSpan]::FromSeconds($group.Count * $sampleSeconds).ToString('hh\:mm\:ss')
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
        $global:TrackerTimer = $null
    }
}

function Stop-DashboardTimer {
    if ($global:DashboardUpdateTimer) {
        $global:DashboardUpdateTimer.Stop()
        $global:DashboardUpdateTimer = $null
    }
}

# Tracking button
$btnStartStop.Add_Click({
    if (!$global:TrackerRunning) {
        $global:TrackerRunning = $true
        $global:CurrentLogFile = Get-TodayLogFile -LogFolder $global:logFolder
        Initialize-LogFile -LogFile $global:CurrentLogFile
        
        # DispatcherTimer runs on the WPF UI thread — same runspace as imported modules
        $global:TrackerTimer = New-Object System.Windows.Threading.DispatcherTimer
        $global:TrackerTimer.Interval = [TimeSpan]::FromSeconds($global:config.sampleIntervalSeconds)

        $global:TrackerTimer.Add_Tick({
            $info = Get-ActiveWindowInfo
            if ($info) {
                $isAfotraWindow = ($info.ProcessName -eq "powershell" -and $info.WindowTitle -like "*AFOTRA*")
                if (-not $isAfotraWindow) {
                    $category = Classify-Activity -ProcessName $info.ProcessName -WindowTitle $info.WindowTitle -Rules $global:rules
                    $info | Add-Member -NotePropertyName "Category" -NotePropertyValue $category -Force
                    Write-ActivityLog -LogFile $global:CurrentLogFile -ActivityInfo $info -SampleSeconds $global:config.sampleIntervalSeconds

                    if (-not ($global:CurrentActivityInfo -and
                              $global:CurrentActivityInfo.ProcessName -eq $info.ProcessName -and
                              $global:CurrentActivityInfo.WindowTitle  -eq $info.WindowTitle)) {
                        $global:CurrentActivityStart = Get-Date
                        $global:CurrentActivityInfo  = $info
                    }
                }
            }
        })
        $global:TrackerTimer.Start()
        
        $btnStartStop.Content = "Stop Tracking"
        $btnStartStop.Background = "#EF4444"
        $statusText.Text = "Status: Running..."
        
    } else {
        $global:TrackerRunning = $false
        Stop-TrackingTimer
        $statusText.Text = "Status: Stopped"
        $btnStartStop.Content = "Start Tracking"
        $btnStartStop.Background = "#10B981"
        Update-Dashboard
    }
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
    
    if ($form.ShowDialog() -eq "OK") {
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
    
    if ($form.ShowDialog() -eq "OK" -and $text.Text.Trim()) {
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

    if ($form.ShowDialog() -eq "OK") {
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
    if (Test-Path $logFile) {
        try {
            $reportData = Get-ReportData -LogFile $logFile
            if ($reportData) {
                $date = Get-Date -Format "yyyy-MM-dd"
                $jsonFile = Join-Path (Join-Path $global:logFolder "reports") "summary-$date.json"
                $taskSummary = $null
                try { $taskSummary = Get-TaskSummary -Tasks @(Get-Tasks -Path $global:taskStorePath) } catch { }
                Export-ReportToJSON -ReportData $reportData -OutputFile $jsonFile -TaskSummary $taskSummary
                [Windows.MessageBox]::Show("Report generated!`n`n$jsonFile", "AFOTRA") | Out-Null
                Explorer.exe $jsonFile
            }
        } catch {
            [Windows.MessageBox]::Show("Error: $_", "AFOTRA") | Out-Null
        }
    }
})

$btnOpenLogs.Add_Click({
    if (Test-Path $global:logFolder) { Explorer.exe $global:logFolder }
})

# ===================================================================
# TASKS — helpers, list rendering, dialog, handlers, reminder timer
# ===================================================================
$global:TasksCache = @()

function Get-TaskPriorityRank {
    param([string]$Priorite)
    switch ($Priorite) {
        "Urgente" { 0 } "Haute" { 1 } "Normale" { 2 } "Basse" { 3 } default { 4 }
    }
}

function Update-TaskSummaryCard {
    try {
        $tasks = @(Get-Tasks -Path $global:taskStorePath)
        $sum = Get-TaskSummary -Tasks $tasks
        $taskCountAFaire.Text  = [string]$sum.AFaire
        $taskCountEnCours.Text = [string]$sum.EnCours
        $taskCountTermine.Text = [string]$sum.TermineesAujourdhui
        $taskCountRetard.Text  = [string]$sum.EnRetard
    } catch { if ($Debug) { Write-Warning "Update-TaskSummaryCard failed: $_" } }
}

function Update-Tasks-UI {
    try {
        $global:TasksCache = @(Get-Tasks -Path $global:taskStorePath)
        $now = Get-Date
        $todayStart = $now.Date
        $tomorrowStart = $todayStart.AddDays(1)

        $rows = @()
        foreach ($t in $global:TasksCache) {
            $closed = $t.Statut -in @("Termine", "Archive")
            $ech = ConvertFrom-IsoDate $t.DateEcheance

            # Row state for colour coding (échéance-based).
            $state = "Normal"
            if ($closed) { $state = "Termine" }
            elseif ($ech -and $ech -lt $todayStart) { $state = "Retard" }
            elseif ($ech -and $ech -ge $todayStart -and $ech -lt $tomorrowStart) { $state = "Aujourdhui" }

            # Quick filter
            $keep = switch ($global:TaskFilter) {
                "AFaire"     { $t.Statut -eq "A_faire" }
                "EnCours"    { $t.Statut -eq "En_cours" }
                "Aujourdhui" { (-not $closed) -and $state -eq "Aujourdhui" }
                "Retard"     { (-not $closed) -and $state -eq "Retard" }
                default      { $true }
            }
            if (-not $keep) { continue }

            # Text search across the meaningful fields
            if ($global:TaskSearch) {
                $hay = @($t.Titre, $t.Description, $t.Categorie, $t.Projet, $t.Contact, $t.Notes) -join " "
                if ($hay -notlike "*$($global:TaskSearch)*") { continue }
            }

            $estMin  = [int]$t.EstimeMinutes
            $passeSec = [int]$t.TempsTravailSecondes
            $rows += [PSCustomObject]@{
                Titre        = $t.Titre
                Categorie    = $t.Categorie
                Priorite     = $t.Priorite
                Echeance     = if ($ech) { $ech.ToString("yyyy-MM-dd") } else { "" }
                EcheanceSort = if ($ech) { $ech.ToString("yyyy-MM-ddTHH:mm:ss") } else { "9999-12-31" }
                PrioriteRank = Get-TaskPriorityRank $t.Priorite
                Statut       = $t.Statut
                Estime       = if ($estMin -gt 0) { "${estMin}m" } else { "" }
                EstimeSort   = $estMin
                Passe        = if ($passeSec -gt 0) { [TimeSpan]::FromSeconds($passeSec).ToString('hh\:mm') } else { "" }
                PasseSort    = $passeSec
                Contact      = $t.Contact
                Id           = $t.Id
                _State       = $state
            }
        }
        $tasksGrid.ItemsSource = @($rows)
    } catch { if ($Debug) { Write-Warning "Update-Tasks-UI failed: $_" } }
}

# Row colour coding (recycled rows: always set a background so stale colours clear).
$tasksGrid.Add_LoadingRow({
    param($sender, $e)
    $item = $e.Row.Item
    $white  = [System.Windows.Media.Brushes]::White
    $gray   = [System.Windows.Media.Brushes]::Gray
    $black  = [System.Windows.Media.Brushes]::Black
    $red    = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(254, 226, 226)) # rose
    $orange = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(254, 243, 199)) # amber
    $lgray  = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(243, 244, 246)) # gray-100
    $state = $null
    if ($item -and ($item.PSObject.Properties.Name -contains "_State")) { $state = $item._State }
    switch ($state) {
        "Retard"     { $e.Row.Background = $red;    $e.Row.Foreground = $black }
        "Aujourdhui" { $e.Row.Background = $orange; $e.Row.Foreground = $black }
        "Termine"    { $e.Row.Background = $lgray;  $e.Row.Foreground = $gray }
        default      { $e.Row.Background = $white;  $e.Row.Foreground = $black }
    }
})

function Get-SelectedTask {
    $sel = $tasksGrid.SelectedItem
    if (-not $sel) { return $null }
    return @($global:TasksCache | Where-Object { $_.Id -eq $sel.Id })[0]
}

# WinForms add/edit modal (consistent with the app's other dialogs). Returns a
# field-values object, or $null if cancelled.
function Show-TaskDialog {
    param([object]$Existing)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = if ($Existing) { "Éditer la tâche" } else { "Nouvelle tâche" }
    $form.Width = 560; $form.Height = 680; $form.StartPosition = "CenterScreen"
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form.AutoScroll = $true

    # Single script-scoped layout cursor so the nested Add-Label and the inline
    # control placement share the SAME counter (a plain local would not be visible
    # inside the nested function).
    $script:dlgY = 12
    function Add-Label($text) {
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $text; $l.Location = New-Object System.Drawing.Point(15, $script:dlgY); $l.AutoSize = $true
        $form.Controls.Add($l); $script:dlgY += 20
    }

    Add-Label "Titre *"
    $txtTitre = New-Object System.Windows.Forms.TextBox
    $txtTitre.Location = New-Object System.Drawing.Point(15, $script:dlgY); $txtTitre.Width = 505
    $form.Controls.Add($txtTitre); $script:dlgY += 30

    Add-Label "Description"
    $txtDesc = New-Object System.Windows.Forms.TextBox
    $txtDesc.Location = New-Object System.Drawing.Point(15, $script:dlgY); $txtDesc.Width = 505; $txtDesc.Height = 50
    $txtDesc.Multiline = $true; $txtDesc.ScrollBars = "Vertical"
    $form.Controls.Add($txtDesc); $script:dlgY += 60

    Add-Label "Catégorie"
    $cbCat = New-Object System.Windows.Forms.ComboBox
    $cbCat.Location = New-Object System.Drawing.Point(15, $script:dlgY); $cbCat.Width = 240; $cbCat.DropDownStyle = "DropDown"
    $catItems = @("Appels", "AWEMA/Clients", "Ciné Light Studio", "HOLYGOD TV")
    $catItems += @($global:rules.categories)
    $catItems += @($global:TasksCache | ForEach-Object { $_.Categorie })
    foreach ($c in ($catItems | Where-Object { $_ } | Select-Object -Unique)) { $cbCat.Items.Add($c) | Out-Null }
    $form.Controls.Add($cbCat)

    $lblProj = New-Object System.Windows.Forms.Label
    $lblProj.Text = "Projet"; $lblProj.Location = New-Object System.Drawing.Point(275, ($script:dlgY - 20)); $lblProj.AutoSize = $true
    $form.Controls.Add($lblProj)
    $txtProj = New-Object System.Windows.Forms.TextBox
    $txtProj.Location = New-Object System.Drawing.Point(280, $script:dlgY); $txtProj.Width = 240
    $form.Controls.Add($txtProj); $script:dlgY += 32

    Add-Label "Contact"
    $txtContact = New-Object System.Windows.Forms.TextBox
    $txtContact.Location = New-Object System.Drawing.Point(15, $script:dlgY); $txtContact.Width = 505
    $form.Controls.Add($txtContact); $script:dlgY += 32

    Add-Label "Priorité"
    $cbPrio = New-Object System.Windows.Forms.ComboBox
    $cbPrio.Location = New-Object System.Drawing.Point(15, $script:dlgY); $cbPrio.Width = 240; $cbPrio.DropDownStyle = "DropDownList"
    foreach ($p in @("Basse", "Normale", "Haute", "Urgente")) { $cbPrio.Items.Add($p) | Out-Null }

    $lblStat = New-Object System.Windows.Forms.Label
    $lblStat.Text = "Statut"; $lblStat.Location = New-Object System.Drawing.Point(275, ($script:dlgY - 20)); $lblStat.AutoSize = $true
    $form.Controls.Add($lblStat)
    $cbStat = New-Object System.Windows.Forms.ComboBox
    $cbStat.Location = New-Object System.Drawing.Point(280, $script:dlgY); $cbStat.Width = 240; $cbStat.DropDownStyle = "DropDownList"
    foreach ($s in @("A_faire", "En_cours", "En_attente", "Termine", "Archive")) { $cbStat.Items.Add($s) | Out-Null }
    $form.Controls.Add($cbPrio); $form.Controls.Add($cbStat); $script:dlgY += 34

    Add-Label "Estimé (minutes, 0 = aucun)"
    $numEst = New-Object System.Windows.Forms.NumericUpDown
    $numEst.Location = New-Object System.Drawing.Point(15, $script:dlgY); $numEst.Width = 120
    $numEst.Minimum = 0; $numEst.Maximum = 100000; $numEst.Increment = 5
    $form.Controls.Add($numEst); $script:dlgY += 34

    # Échéance (optional)
    $chkEch = New-Object System.Windows.Forms.CheckBox
    $chkEch.Text = "Échéance"; $chkEch.Location = New-Object System.Drawing.Point(15, $script:dlgY); $chkEch.AutoSize = $true
    $form.Controls.Add($chkEch)
    $dtEch = New-Object System.Windows.Forms.DateTimePicker
    $dtEch.Location = New-Object System.Drawing.Point(160, ($script:dlgY - 3)); $dtEch.Width = 200
    $dtEch.Format = "Custom"; $dtEch.CustomFormat = "yyyy-MM-dd HH:mm"; $dtEch.Enabled = $false
    $form.Controls.Add($dtEch)
    $chkEch.Add_CheckedChanged({ $dtEch.Enabled = $chkEch.Checked }.GetNewClosure())
    $script:dlgY += 32

    # Rappel du soir (optional)
    $chkRap = New-Object System.Windows.Forms.CheckBox
    $chkRap.Text = "Rappel du soir"; $chkRap.Location = New-Object System.Drawing.Point(15, $script:dlgY); $chkRap.AutoSize = $true
    $form.Controls.Add($chkRap)
    $dtRap = New-Object System.Windows.Forms.DateTimePicker
    $dtRap.Location = New-Object System.Drawing.Point(160, ($script:dlgY - 3)); $dtRap.Width = 200
    $dtRap.Format = "Custom"; $dtRap.CustomFormat = "yyyy-MM-dd HH:mm"; $dtRap.Enabled = $false
    $form.Controls.Add($dtRap)
    $chkRap.Add_CheckedChanged({ $dtRap.Enabled = $chkRap.Checked }.GetNewClosure())
    $script:dlgY += 32

    Add-Label "Bloquée par"
    $txtBloc = New-Object System.Windows.Forms.TextBox
    $txtBloc.Location = New-Object System.Drawing.Point(15, $script:dlgY); $txtBloc.Width = 505
    $form.Controls.Add($txtBloc); $script:dlgY += 32

    Add-Label "Notes"
    $txtNotes = New-Object System.Windows.Forms.TextBox
    $txtNotes.Location = New-Object System.Drawing.Point(15, $script:dlgY); $txtNotes.Width = 505; $txtNotes.Height = 70
    $txtNotes.Multiline = $true; $txtNotes.ScrollBars = "Vertical"
    $form.Controls.Add($txtNotes); $script:dlgY += 82

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Enregistrer"; $btnOk.Location = New-Object System.Drawing.Point(330, $script:dlgY); $btnOk.Width = 90; $btnOk.DialogResult = "OK"
    $form.Controls.Add($btnOk)
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Annuler"; $btnCancel.Location = New-Object System.Drawing.Point(430, $script:dlgY); $btnCancel.Width = 90; $btnCancel.DialogResult = "Cancel"
    $form.Controls.Add($btnCancel)
    $form.AcceptButton = $btnOk; $form.CancelButton = $btnCancel

    # Defaults / populate for edit
    $cbPrio.SelectedItem = "Normale"; $cbStat.SelectedItem = "A_faire"
    if ($Existing) {
        $txtTitre.Text = [string]$Existing.Titre
        $txtDesc.Text = [string]$Existing.Description
        $cbCat.Text = [string]$Existing.Categorie
        $txtProj.Text = [string]$Existing.Projet
        $txtContact.Text = [string]$Existing.Contact
        if ($Existing.Priorite) { $cbPrio.SelectedItem = [string]$Existing.Priorite }
        if ($Existing.Statut)   { $cbStat.SelectedItem = [string]$Existing.Statut }
        $txtBloc.Text = [string]$Existing.Bloquee_par
        $txtNotes.Text = [string]$Existing.Notes
        $eEch = ConvertFrom-IsoDate $Existing.DateEcheance
        if ($eEch) { $chkEch.Checked = $true; $dtEch.Enabled = $true; $dtEch.Value = $eEch }
        $eRap = ConvertFrom-IsoDate $Existing.RappelSoir
        if ($eRap) { $chkRap.Checked = $true; $dtRap.Enabled = $true; $dtRap.Value = $eRap }
        if ([int]$Existing.EstimeMinutes -gt 0) { $numEst.Value = [int]$Existing.EstimeMinutes }
    } else {
        $dtRap.Value = [datetime]::new((Get-Date).Year, (Get-Date).Month, (Get-Date).Day, 20, 0, 0)
    }

    $result = $form.ShowDialog()
    if ($result -ne "OK") { $form.Dispose(); return $null }
    if ([string]::IsNullOrWhiteSpace($txtTitre.Text)) {
        [System.Windows.Forms.MessageBox]::Show("Le titre est obligatoire.", "AFOTRA") | Out-Null
        $form.Dispose(); return $null
    }

    $vals = [PSCustomObject]@{
        Titre        = $txtTitre.Text.Trim()
        Description  = $txtDesc.Text
        Categorie    = $cbCat.Text.Trim()
        Projet       = $txtProj.Text.Trim()
        Contact      = $txtContact.Text.Trim()
        Priorite     = [string]$cbPrio.SelectedItem
        Statut       = [string]$cbStat.SelectedItem
        DateEcheance = if ($chkEch.Checked) { $dtEch.Value } else { $null }
        RappelSoir   = if ($chkRap.Checked) { $dtRap.Value } else { $null }
        Bloquee_par  = $txtBloc.Text.Trim()
        Notes        = $txtNotes.Text
        EstimeMinutes = [int]$numEst.Value
    }
    $form.Dispose()
    return $vals
}

$btnTaskAdd.Add_Click({
    $vals = Show-TaskDialog
    if ($vals) {
        $t = New-Task -Titre $vals.Titre -Description $vals.Description -Categorie $vals.Categorie `
            -Projet $vals.Projet -Contact $vals.Contact -Priorite $vals.Priorite -Statut $vals.Statut `
            -Bloquee_par $vals.Bloquee_par -Notes $vals.Notes -EstimeMinutes ([int]$vals.EstimeMinutes)
        $t.DateEcheance = ConvertTo-IsoDate $vals.DateEcheance
        $t.RappelSoir   = ConvertTo-IsoDate $vals.RappelSoir
        if ($vals.Statut -eq "Termine") { $t.TermineLe = (Get-Date).ToString("s") }
        Add-Task -Task $t -Path $global:taskStorePath | Out-Null
        Update-Tasks-UI
    }
})

$btnTaskEdit.Add_Click({
    $existing = Get-SelectedTask
    if (-not $existing) { [System.Windows.MessageBox]::Show("Sélectionnez une tâche.", "AFOTRA") | Out-Null; return }
    $vals = Show-TaskDialog -Existing $existing
    if ($vals) {
        $existing.Titre = $vals.Titre; $existing.Description = $vals.Description; $existing.Categorie = $vals.Categorie
        $existing.Projet = $vals.Projet; $existing.Contact = $vals.Contact; $existing.Priorite = $vals.Priorite
        $existing.Bloquee_par = $vals.Bloquee_par; $existing.Notes = $vals.Notes
        $existing | Add-Member -NotePropertyName EstimeMinutes -NotePropertyValue ([int]$vals.EstimeMinutes) -Force
        $existing.DateEcheance = ConvertTo-IsoDate $vals.DateEcheance
        $existing.RappelSoir   = ConvertTo-IsoDate $vals.RappelSoir
        if ($vals.Statut -eq "Termine" -and $existing.Statut -ne "Termine") { $existing.TermineLe = (Get-Date).ToString("s") }
        if ($vals.Statut -ne "Termine") { $existing.TermineLe = $null }
        $existing.Statut = $vals.Statut
        Update-Task -Task $existing -Path $global:taskStorePath | Out-Null
        Update-Tasks-UI
    }
})

$btnTaskComplete.Add_Click({
    $sel = $tasksGrid.SelectedItem
    if (-not $sel) { [System.Windows.MessageBox]::Show("Sélectionnez une tâche.", "AFOTRA") | Out-Null; return }
    # If a session is running on this task, persist its time before completing.
    if ($global:SessionState -and $global:SessionState.TaskId -eq $sel.Id) {
        Stop-CurrentSession | Out-Null
        Update-SessionUI; Update-SessionButtons
    }
    Complete-Task -Id $sel.Id -Path $global:taskStorePath | Out-Null
    Update-Tasks-UI
})

$btnTaskArchive.Add_Click({
    $sel = $tasksGrid.SelectedItem
    if (-not $sel) { [System.Windows.MessageBox]::Show("Sélectionnez une tâche.", "AFOTRA") | Out-Null; return }
    Archive-Task -Id $sel.Id -Path $global:taskStorePath | Out-Null
    Update-Tasks-UI
})

$btnTaskRefresh.Add_Click({ Update-Tasks-UI })

function Set-TaskFilterButtons {
    param([string]$Active)
    $map = @{
        "Tous" = $btnFilterTous; "AFaire" = $btnFilterAFaire; "EnCours" = $btnFilterEnCours
        "Aujourdhui" = $btnFilterAujourdhui; "Retard" = $btnFilterRetard
    }
    foreach ($k in $map.Keys) {
        $map[$k].Background = if ($k -eq $Active) { "#2563EB" } else { "#64748B" }
    }
}

$btnFilterTous.Add_Click({ $global:TaskFilter = "Tous"; Set-TaskFilterButtons "Tous"; Update-Tasks-UI })
$btnFilterAFaire.Add_Click({ $global:TaskFilter = "AFaire"; Set-TaskFilterButtons "AFaire"; Update-Tasks-UI })
$btnFilterEnCours.Add_Click({ $global:TaskFilter = "EnCours"; Set-TaskFilterButtons "EnCours"; Update-Tasks-UI })
$btnFilterAujourdhui.Add_Click({ $global:TaskFilter = "Aujourdhui"; Set-TaskFilterButtons "Aujourdhui"; Update-Tasks-UI })
$btnFilterRetard.Add_Click({ $global:TaskFilter = "Retard"; Set-TaskFilterButtons "Retard"; Update-Tasks-UI })

$btnTaskSearch.Add_Click({ $global:TaskSearch = $taskSearchBox.Text.Trim(); Update-Tasks-UI })
$btnTaskSearchClear.Add_Click({ $taskSearchBox.Text = ""; $global:TaskSearch = ""; Update-Tasks-UI })
$taskSearchBox.Add_KeyDown({ param($s, $e) if ($e.Key -eq "Return") { $global:TaskSearch = $taskSearchBox.Text.Trim(); Update-Tasks-UI } })

# ---- Work sessions (Pomodoro) ---------------------------------------------
function Format-Hms { param([int]$Sec) [TimeSpan]::FromSeconds([math]::Max(0, $Sec)).ToString('hh\:mm\:ss') }
function Format-Mmss {
    param([int]$Sec)
    $s = [math]::Max(0, $Sec)
    if ($s -ge 3600) { [TimeSpan]::FromSeconds($s).ToString('h\:mm\:ss') } else { [TimeSpan]::FromSeconds($s).ToString('mm\:ss') }
}

function Update-SessionButtons {
    $active = ($null -ne $global:SessionState)
    $mode = if ($active) { $global:SessionState.Mode } else { 'None' }
    $btnSessStart.IsEnabled       = (-not $active)
    $sessionEstimeInput.IsEnabled = (-not $active)
    $btnSessPause.IsEnabled       = ($mode -eq 'Running')
    $btnSessResume.IsEnabled      = ($mode -eq 'Paused' -or $mode -eq 'Break')
    $btnSessBreak.IsEnabled       = ($mode -eq 'Running')
    $btnSessComplete.IsEnabled    = $active
    $btnSessStop.IsEnabled        = $active
}

function Update-SessionUI {
    param($Readout = $null)
    if (-not $global:SessionState) {
        $sessionTaskText.Text = "Aucune session active"
        $sessionCountdown.Text = "--:--"; $sessionCountdown.Foreground = "#9CA3AF"
        $sessionPomText.Text = ""
        $sessionWorkText.Text = "00:00:00"; $sessionGlobalText.Text = "00:00:00"; $sessionPauseText.Text = "00:00:00"
        if ($global:OvSessionText) { $global:OvSessionText.Visibility = "Collapsed" }
        return
    }
    if (-not $Readout) { $Readout = Step-Session -State $global:SessionState -Now (Get-Date) }
    $sessionTaskText.Text = [string]$global:SessionState.TaskTitle

    if ($global:SessionState.AwaitingResume) {
        $sessionCountdown.Text = "Reprendre"; $sessionCountdown.Foreground = "#10B981"
    } elseif ($Readout.Mode -eq 'Break') {
        $sessionCountdown.Text = "Pause " + (Format-Mmss $Readout.BreakRemaining); $sessionCountdown.Foreground = "#8B5CF6"
    } elseif ($global:SessionState.Mode -eq 'Paused') {
        $sessionCountdown.Text = if ($Readout.HasTarget -and -not $Readout.IsOverrun) { Format-Mmss $Readout.RemainingSec } elseif ($Readout.IsOverrun) { "+" + (Format-Mmss $Readout.OverrunSec) } else { Format-Mmss $Readout.WorkSec }
        $sessionCountdown.Foreground = "#F59E0B"
    } elseif (-not $Readout.HasTarget) {
        $sessionCountdown.Text = Format-Mmss $Readout.WorkSec; $sessionCountdown.Foreground = "#2563EB"
    } elseif ($Readout.IsOverrun) {
        $sessionCountdown.Text = "+" + (Format-Mmss $Readout.OverrunSec); $sessionCountdown.Foreground = "#EF4444"
    } else {
        $sessionCountdown.Text = Format-Mmss $Readout.RemainingSec; $sessionCountdown.Foreground = "#10B981"
    }

    $sessionWorkText.Text = Format-Hms $Readout.WorkSec
    $sessionGlobalText.Text = Format-Hms $Readout.GlobalSec
    $sessionPauseText.Text = Format-Hms $Readout.PauseSec
    if ($global:SessionState.AwaitingResume) {
        $sessionPomText.Text = "Pause terminée — clique Reprendre"
    } elseif ($Readout.Mode -eq 'Break') {
        $sessionPomText.Text = "Pause $($global:SessionState.BreakType) · $($Readout.PomCompleted) pomodoro(s)"
    } else {
        $sessionPomText.Text = "Pomodoro " + (Format-Mmss $Readout.PomRemainingSec) + " · $($Readout.PomCompleted) fait(s)"
    }

    if ($global:OvSessionText) {
        $global:OvSessionText.Visibility = "Visible"
        $global:OvSessionText.Text = "⏱ " + $sessionCountdown.Text + "  " + [string]$global:SessionState.TaskTitle
    }
}

function Stop-CurrentSession {
    # Persist accumulated time to the task, clear the live session. Returns the TaskId (or $null).
    param([datetime]$Now = (Get-Date))
    if (-not $global:SessionState) { return $null }
    $taskId = $global:SessionState.TaskId
    $res = Get-SessionResult -State $global:SessionState -Now $Now
    try { Add-TaskSession -Id $taskId -Result $res -Path $global:taskStorePath | Out-Null } catch { if ($Debug) { Write-Warning "Add-TaskSession failed: $_" } }
    $global:SessionState = $null
    if ($global:SessionTimer) { $global:SessionTimer.Stop(); $global:SessionTimer = $null }
    # Drop any pending focus-guard question when the session ends.
    $global:GuardAsking = $null
    $global:GuardCooldownUntil = $null
    if ($global:OrbAskPopup) { $global:OrbAskPopup.IsOpen = $false }
    if ($global:AlarmActive) { $global:AlarmActive = $false }
    return $taskId
}

function Start-Chime {
    # Short, non-looping cue on a background thread (Console.Beep would freeze the UI thread).
    # 'Break' = a soft two-note fall; 'Resume' = a rising three-note "let's go".
    param([ValidateSet('Break', 'Resume')][string]$Kind = 'Resume')
    $global:ChimeNotes = if ($Kind -eq 'Break') { @(660, 150, 520, 220) } else { @(523, 130, 659, 130, 784, 240) }
    $th = New-Object System.Threading.Thread([System.Threading.ThreadStart] {
            try {
                for ($i = 0; $i -lt $global:ChimeNotes.Count; $i += 2) {
                    [System.Console]::Beep([int]$global:ChimeNotes[$i], [int]$global:ChimeNotes[$i + 1])
                }
            } catch { }
        })
    $th.IsBackground = $true
    $th.Start()
}

function Start-SessionTimer {
    if ($global:SessionTimer) { return }
    $global:SessionTimer = New-Object System.Windows.Threading.DispatcherTimer
    $global:SessionTimer.Interval = [TimeSpan]::FromSeconds(1)
    $global:SessionTimer.Add_Tick({
        if (-not $global:SessionState) { return }
        $now = Get-Date
        $r = Step-Session -State $global:SessionState -Now $now
        if ($r.BreakDue) {
            # Work interval finished -> start the break.
            Start-SessionBreak -State $global:SessionState -Now $now | Out-Null
            $mins = if ($global:SessionState.BreakType -eq 'Long') { [int]$global:PomodoroConfig.longBreakMinutes } else { [int]$global:PomodoroConfig.shortBreakMinutes }
            Show-AfotraNotification -Title "AFOTRA - Pomodoro" -Message "Cycle terminé — pause de $mins min ($($global:SessionState.BreakType))." | Out-Null
            if ($global:PomodoroSound) { Start-Chime -Kind Break }
            $r = Step-Session -State $global:SessionState -Now $now
        }
        elseif ($global:SessionState.Mode -eq 'Break' -and $global:SessionState.BreakEndsAt -and $now -ge $global:SessionState.BreakEndsAt) {
            # Break time is up.
            if ($global:PomodoroConfig.autoStartNext) {
                Stop-SessionBreak -State $global:SessionState -Now $now | Out-Null
                $global:SessionState.AwaitingResume = $false
                Show-AfotraNotification -Title "AFOTRA - Pomodoro" -Message "Pause terminée — c'est reparti, focus !" | Out-Null
                if ($global:PomodoroSound) { Start-Chime -Kind Resume }
            } else {
                # Wait for a manual Reprendre; a distinct "AwaitingResume" state makes the orb
                # call you back (and we only notify once, not every tick).
                $global:SessionState.Mode = 'Paused'; $global:SessionState.BreakType = $null; $global:SessionState.BreakEndsAt = $null
                $global:SessionState.AwaitingResume = $true
                Show-AfotraNotification -Title "AFOTRA - Pomodoro" -Message "Pause terminée — clique Reprendre pour repartir." | Out-Null
                if ($global:PomodoroSound) { Start-Chime -Kind Resume }
            }
            $r = Step-Session -State $global:SessionState -Now $now
        }
        Update-SessionUI -Readout $r
        Update-SessionButtons
    })
    $global:SessionTimer.Start()
}

$btnSessStart.Add_Click({
    if ($global:SessionState) { [System.Windows.MessageBox]::Show("Une session est déjà active.", "AFOTRA") | Out-Null; return }
    $sel = $tasksGrid.SelectedItem
    if (-not $sel) { [System.Windows.MessageBox]::Show("Sélectionnez d'abord une tâche.", "AFOTRA") | Out-Null; return }
    $estMin = 0; [int]::TryParse([string]$sessionEstimeInput.Text, [ref]$estMin) | Out-Null
    if ($estMin -gt 0) { Set-TaskEstimate -Id $sel.Id -Minutes $estMin -Path $global:taskStorePath }
    $global:SessionState = Start-Session -TaskId $sel.Id -EstimateSec ($estMin * 60) -Config $global:PomodoroConfig -Now (Get-Date)
    $global:SessionState.TaskTitle = [string]$sel.Titre
    $global:SessionState.AwaitingResume = $false
    # Seed the focus-guard allow-list from the task's saved tools.
    $fullTask = @($global:TasksCache | Where-Object { $_.Id -eq $sel.Id })[0]
    $global:GuardAllow = @(Get-TaskTools -Task $fullTask)
    $global:GuardSnooze = @()
    $global:GuardAsking = $null
    $global:GuardCooldownUntil = $null
    Start-SessionTimer
    Update-SessionUI
    Update-SessionButtons
    Update-Tasks-UI
})

$btnSessPause.Add_Click({
    if ($global:SessionState -and $global:SessionState.Mode -eq 'Running') {
        Suspend-Session -State $global:SessionState -Now (Get-Date) | Out-Null
        Update-SessionUI; Update-SessionButtons
    }
})

$btnSessResume.Add_Click({
    if ($global:SessionState -and $global:SessionState.Mode -in @('Paused', 'Break')) {
        $wasAwaiting = [bool]$global:SessionState.AwaitingResume
        Resume-Session -State $global:SessionState -Now (Get-Date) | Out-Null
        $global:SessionState.AwaitingResume = $false
        if ($wasAwaiting) {
            Show-AfotraNotification -Title "AFOTRA - Focus" -Message "Focus repris — au travail !" | Out-Null
            if ($global:PomodoroSound) { Start-Chime -Kind Resume }
        }
        Update-SessionUI; Update-SessionButtons
    }
})

$btnSessBreak.Add_Click({
    if ($global:SessionState -and $global:SessionState.Mode -eq 'Running') {
        Start-SessionBreak -State $global:SessionState -Now (Get-Date) | Out-Null
        Update-SessionUI; Update-SessionButtons
    }
})

$btnSessComplete.Add_Click({
    $id = Stop-CurrentSession
    if ($id) { Complete-Task -Id $id -Path $global:taskStorePath | Out-Null }
    Update-SessionUI; Update-SessionButtons; Update-Tasks-UI
})

$btnSessStop.Add_Click({
    Stop-CurrentSession | Out-Null
    Update-SessionUI; Update-SessionButtons; Update-Tasks-UI
})

# Evening reminder timer: fires due reminders (daily recurrence via NotifieLe guard).
$global:TaskReminderTimer = New-Object System.Windows.Threading.DispatcherTimer
$global:TaskReminderTimer.Interval = [TimeSpan]::FromSeconds(60)
$global:TaskReminderTimer.Add_Tick({
    try {
        $tasks = @(Get-Tasks -Path $global:taskStorePath)
        $due = @(Get-DueReminders -Tasks $tasks)
        foreach ($t in $due) {
            $body = $t.Titre
            if ($t.Contact) { $body += "  -  $($t.Contact)" }
            Show-AfotraNotification -Title "AFOTRA - Rappel du soir" -Message $body | Out-Null
            Set-TaskNotified -Id $t.Id -Path $global:taskStorePath
        }
        if ($due.Count -gt 0) { Update-TaskSummaryCard }
    } catch { if ($Debug) { Write-Warning "Reminder tick failed: $_" } }
})
$global:TaskReminderTimer.Start()

# Dashboard refresh timer — DispatcherTimer, UI thread, no Invoke-OnUIThread needed
$global:DashboardUpdateTimer = New-Object System.Windows.Threading.DispatcherTimer
$global:DashboardUpdateTimer.Interval = [TimeSpan]::FromMilliseconds(2000)
$global:DashboardUpdateTimer.Add_Tick({ Update-Dashboard })
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
    <!-- The living sphere -->
    <Ellipse x:Name="OrbEllipse" Width="90" Height="90" HorizontalAlignment="Center" VerticalAlignment="Center" RenderTransformOrigin="0.5,0.5" Cursor="Hand">
      <Ellipse.Fill>
        <RadialGradientBrush x:Name="OrbBrush" GradientOrigin="0.4,0.34" Center="0.5,0.5" RadiusX="0.62" RadiusY="0.62">
          <GradientStop x:Name="OrbStopCore" Color="#5EEAD4" Offset="0.0"/>
          <GradientStop x:Name="OrbStopMid"  Color="#14B8A6" Offset="0.65"/>
          <GradientStop x:Name="OrbStopEdge" Color="#0014B8A6" Offset="1.0"/>
        </RadialGradientBrush>
      </Ellipse.Fill>
      <Ellipse.Effect>
        <DropShadowEffect x:Name="OrbGlow" Color="#14B8A6" BlurRadius="18" ShadowDepth="0" Opacity="0.85"/>
      </Ellipse.Effect>
      <Ellipse.RenderTransform>
        <ScaleTransform x:Name="OrbScale" ScaleX="1" ScaleY="1"/>
      </Ellipse.RenderTransform>
    </Ellipse>
    <!-- Wet highlight for an organic feel -->
    <Ellipse x:Name="OrbHighlight" Width="26" Height="16" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,-22,0,0" Opacity="0.55" IsHitTestVisible="False">
      <Ellipse.Fill>
        <RadialGradientBrush>
          <GradientStop Color="#CCFFFFFF" Offset="0.0"/>
          <GradientStop Color="#00FFFFFF" Offset="1.0"/>
        </RadialGradientBrush>
      </Ellipse.Fill>
    </Ellipse>

    <!-- Hover reveal: full session/activity panel -->
    <Popup x:Name="OrbDetailPopup" PlacementTarget="{Binding ElementName=OrbEllipse}" Placement="Right" AllowsTransparency="True" StaysOpen="True" HorizontalOffset="6">
      <Border Background="#F21F2937" CornerRadius="10" Padding="12" Margin="8">
        <Border.Effect><DropShadowEffect Color="Black" Opacity="0.55" BlurRadius="12" ShadowDepth="2"/></Border.Effect>
        <StackPanel Width="248">
          <Grid Margin="0,0,0,8">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <Ellipse x:Name="OvStatusDot" Width="7" Height="7" Fill="#6B7280" VerticalAlignment="Center" Margin="0,0,6,0"/>
              <TextBlock Text="AFOTRA LIVE" FontSize="9" FontWeight="Bold" Foreground="#9CA3AF"/>
            </StackPanel>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
              <Button x:Name="BtnOverlayStartStop" Content="Start" Background="#10B981" Foreground="White" FontWeight="Bold" FontSize="10" Padding="8,3" BorderThickness="0" Cursor="Hand" Margin="0,0,5,0"/>
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
              <TextBlock Text="Focus:" FontSize="10" Foreground="#6B7280" VerticalAlignment="Center"/>
              <TextBlock x:Name="OvFocusScore" Text="0%" FontSize="10" FontWeight="Bold" Foreground="#10B981" Margin="4,0,10,0" VerticalAlignment="Center"/>
              <TextBlock Text="Tracké:" FontSize="10" Foreground="#6B7280" VerticalAlignment="Center"/>
              <TextBlock x:Name="OvTotalTime" Text="0m" FontSize="10" Foreground="#D1D5DB" Margin="4,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <TextBlock x:Name="OvAlertText" Text="" FontSize="10" FontWeight="Bold" Foreground="#FCA5A5" HorizontalAlignment="Right" VerticalAlignment="Center"/>
          </Grid>
          <TextBlock x:Name="OvSessionText" Text="" FontSize="11" FontWeight="Bold" Foreground="#FCD34D" Margin="0,6,0,0" TextTrimming="CharacterEllipsis" Visibility="Collapsed"/>
        </StackPanel>
      </Border>
    </Popup>

    <!-- Focus-guard question -->
    <Popup x:Name="OrbAskPopup" PlacementTarget="{Binding ElementName=OrbEllipse}" Placement="Bottom" AllowsTransparency="True" StaysOpen="True">
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
    $orbEllipse   = $global:OverlayWindow.FindName("OrbEllipse")
    $orbScale     = $global:OverlayWindow.FindName("OrbScale")
    $orbGlow      = $global:OverlayWindow.FindName("OrbGlow")
    $orbStopCore  = $global:OverlayWindow.FindName("OrbStopCore")
    $orbStopMid   = $global:OverlayWindow.FindName("OrbStopMid")
    $orbStopEdge  = $global:OverlayWindow.FindName("OrbStopEdge")
    $global:OrbDetailPopup = $global:OverlayWindow.FindName("OrbDetailPopup")
    $global:OrbAskPopup    = $global:OverlayWindow.FindName("OrbAskPopup")
    $orbAskText   = $global:OverlayWindow.FindName("OrbAskText")
    $btnAskYes    = $global:OverlayWindow.FindName("BtnAskYes")
    $btnAskNo     = $global:OverlayWindow.FindName("BtnAskNo")
    $btnAskIgnore = $global:OverlayWindow.FindName("BtnAskIgnore")

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
        $isRunning = $global:TrackerRunning
        $ovStatusDot.Fill = if ($isRunning) { "#10B981" } else { "#6B7280" }
        if ($isRunning) {
            $btnOverlayStartStop.Content    = "Stop"
            $btnOverlayStartStop.Background = "#EF4444"
        } else {
            $btnOverlayStartStop.Content    = "Start"
            $btnOverlayStartStop.Background = "#10B981"
        }

        # Durée sur la fenêtre courante
        $ovDuration.Text = if ($global:CurrentActivityStart) {
            ((Get-Date) - $global:CurrentActivityStart).ToString('hh\:mm\:ss')
        } else { "00:00:00" }

        # Score focus du jour (lecture CSV légère)
        $lf = Get-TodayLogFile -LogFolder $global:logFolder
        if (Test-Path $lf) {
            try {
                $rows = @(Import-Csv $lf -Encoding UTF8 -ErrorAction SilentlyContinue)
                if ($rows.Count -gt 0) {
                    $ss    = [int]$rows[0].SampleSeconds
                    $total = $rows.Count * $ss
                    $focus = ($rows | Where-Object Category -eq "travail" | Measure-Object).Count * $ss
                    $ovFocusScore.Text = "$(if($total -gt 0){[math]::Round($focus/$total*100,1)}else{0})%"
                    $ovTotalTime.Text  = "$([math]::Round($total/60,0))m"
                }
            } catch {}
        }

        $sessionRunning = ($global:SessionState -and $global:SessionState.Mode -eq 'Running')

        # --- Focus guard : pendant une session, interpelle sur tout process hors liste blanche ---
        if ($global:AsstFocusGuard -and $sessionRunning -and $display) {
            $proc = [string]$display.ProcessName
            $isAfotraWin = ($proc -eq 'powershell' -and $display.WindowTitle -like '*AFOTRA*')
            $allow = @($global:GuardAllow) + @($global:GuardSnooze)
            $onTask = $isAfotraWin -or (Test-ProcessAllowed -ProcessName $proc -AllowList $allow)
            $inCooldown = ($global:GuardCooldownUntil -and (Get-Date) -lt $global:GuardCooldownUntil)

            if ($onTask) {
                if ($global:GuardAsking) { Clear-Guard }   # revenu sur le droit chemin
            }
            elseif (-not $global:GuardAsking -and -not $inCooldown) {
                $global:GuardAsking = $proc
                $global:GuardAskStart = Get-Date
                $orbAskText.Text = "« $proc » — en rapport avec « $($global:SessionState.TaskTitle) » ?"
                if ($global:OrbDetailPopup) { $global:OrbDetailPopup.IsOpen = $false }
                if ($global:OrbAskPopup) { $global:OrbAskPopup.IsOpen = $true }
                if ($global:AsstGuardSound) { Start-Alarm }
            }
        }
        elseif ($global:GuardAsking) {
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
    $global:OverlayDispTimer.Add_Tick({ Update-Overlay })
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
        if ($global:OrbAskPopup) { $global:OrbAskPopup.IsOpen = $false }
        Stop-Alarm
        if ($global:ShakeActive) { Stop-ShakeMode }
    }

    function Update-Orb {
        try {
            $hasSession = [bool]$global:SessionState
            $mode = if ($hasSession) { [string]$global:SessionState.Mode } else { 'None' }
            $isOverrun = $false
            if ($hasSession) { $isOverrun = [bool](Step-Session -State $global:SessionState -Now (Get-Date)).IsOverrun }
            $guard = [bool]$global:GuardAsking
            $awaiting = [bool]($hasSession -and $global:SessionState.AwaitingResume)
            $mood = Get-OrbMood -HasSession $hasSession -Mode $mode -IsOverrun $isOverrun -Guard $guard -AwaitingResume $awaiting
            if ($mood -eq 'Idle' -and $global:ShakeActive) { $mood = 'Overrun' }

            $intensity = 0.0
            if ($mood -eq 'Ask' -and $global:GuardAskStart) {
                $intensity = [math]::Min(1.0, ((Get-Date) - $global:GuardAskStart).TotalSeconds / 8.0)
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
            $orbEllipse.Width = $sz; $orbEllipse.Height = $sz

            $global:OrbPhase += (50.0 / [double]$vis.PulsePeriodMs)
            $tau = 2 * [math]::PI
            $pulse = 1.0 + [double]$vis.PulseAmp * [math]::Sin($tau * $global:OrbPhase)
            $wob   = [double]$vis.WobbleAmp * [math]::Sin($tau * $global:OrbPhase * 1.6)
            $orbScale.ScaleX = $pulse + $wob
            $orbScale.ScaleY = $pulse - $wob
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
        $global:GuardCooldownUntil = (Get-Date).AddSeconds(12)   # laisse le temps de fermer l'app
        if ($ovAlertText) { $ovAlertText.Text = "Recentre-toi sur ta tâche" }
        Clear-Guard
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
# Window cleanup + arrêt du DispatcherFrame
# ===================================================================
$global:AppFrame = New-Object System.Windows.Threading.DispatcherFrame

$window.Add_Closing({
    try {
        Stop-TrackingTimer
        Stop-DashboardTimer
        if ($global:TaskReminderTimer)  { $global:TaskReminderTimer.Stop();  $global:TaskReminderTimer  = $null }
        if ($global:SessionState)       { Stop-CurrentSession | Out-Null }   # persist in-progress session time
        if ($global:SessionTimer)       { $global:SessionTimer.Stop();       $global:SessionTimer       = $null }
        Close-AfotraNotifier
        if ($global:OverlayDispTimer)   { $global:OverlayDispTimer.Stop();   $global:OverlayDispTimer   = $null }
        if ($global:OrbAnimTimer)       { $global:OrbAnimTimer.Stop();       $global:OrbAnimTimer       = $null }
        if ($global:OrbHideTimer)       { $global:OrbHideTimer.Stop();       $global:OrbHideTimer       = $null }
        if ($global:ShakeWobbleTimer)   { $global:ShakeWobbleTimer.Stop();   $global:ShakeWobbleTimer   = $null }
        if ($global:ShakeTriggerTimer)  { $global:ShakeTriggerTimer.Stop();  $global:ShakeTriggerTimer  = $null }
        $global:AlarmActive = $false
        if ($global:OverlayWindow)      { $global:OverlayWindow.Close();     $global:OverlayWindow      = $null }
    } catch { }
    # Arrêter la boucle dispatcher pour que le script se termine
    $global:AppFrame.Continue = $false
})

Initialize-UI

# Show() au lieu de ShowDialog() — évite le blocage modal des autres fenêtres
$window.Show()

if ($global:OverlayWindow) {
    $global:OverlayWindow.Show()
    $btnToggleOverlay.Content = "Masquer Overlay"
}

# Garde le script vivant sans créer de fenêtre modale bloquante
[System.Windows.Threading.Dispatcher]::PushFrame($global:AppFrame)

Stop-TrackingTimer
Stop-DashboardTimer
