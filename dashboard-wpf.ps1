# dashboard-wpf.ps1 - Modern WPF Dashboard for AFOTRA - Awema Focus Tracker
# Author: CodeScooper | Version: 2.0 (Improved)
# Project: AFOTRA - Awema Focus Tracker

param(
    [switch]$Debug
)

$ErrorActionPreference = "Stop"

# This dashboard requires Windows + Desktop .NET (WPF)
if (-not $IsWindows) {
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
                <Button x:Name="NavRulesCategories" Content="Rules" Background="#64748B" Foreground="White" FontWeight="SemiBold" FontSize="13" Padding="12,8" BorderThickness="0" Cursor="Hand" Margin="0,0,0,30"/>
                
                <Separator Background="#4B5563" Margin="0,0,0,20"/>
                
                <Button x:Name="BtnStartStop" Content="Start Tracking" Background="#10B981" Foreground="White" FontWeight="Bold" FontSize="14" Padding="12,8" BorderThickness="0" Cursor="Hand" Margin="0,0,0,12" Height="42"/>
                <TextBlock x:Name="StatusText" Text="Status: Stopped ⏸️" Foreground="White" Margin="0,10,0,0" FontSize="11" TextAlignment="Center" FontWeight="SemiBold"/>
                <TextBlock x:Name="CurrentProcessText" Text="Process: --" Foreground="#E0EFFE" Margin="0,15,0,0" FontSize="10" TextWrapping="Wrap"/>
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

# View management
function Show-View {
    param($viewName)
    $views = @("DashboardView", "LiveTrackingView", "UnknownActivitiesView", "RulesCategoriesView")
    foreach ($view in $views) {
        $element = $window.FindName($view)
        if ($view -eq $viewName) {
            $element.Visibility = "Visible"
            if ($view -eq "UnknownActivitiesView") { Update-UnknownActivities }
            elseif ($view -eq "RulesCategoriesView") { Update-Rules-UI }
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

# Initialize UI
function Initialize-UI {
    $categoriesListBox.Items.Clear()
    foreach ($category in $global:rules.categories) {
        $categoriesListBox.Items.Add($category) | Out-Null
    }
    Update-Rules-UI
    Update-Dashboard
}

# Update functions
function Update-Dashboard {
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
        $global:TrackerTimer.Dispose()
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
        $global:DashboardUpdateTimer.Dispose()
        $global:DashboardUpdateTimer = $null
    }
    if ($global:DashboardTimerEventSub) {
        Unregister-Event -SubscriptionId $global:DashboardTimerEventSub.Id -ErrorAction SilentlyContinue
        $global:DashboardTimerEventSub = $null
    }
}

# Tracking button
$btnStartStop.Add_Click({
    if (!$global:TrackerRunning) {
        $global:TrackerRunning = $true
        $global:CurrentLogFile = Get-TodayLogFile -LogFolder $global:logFolder
        Initialize-LogFile -LogFile $global:CurrentLogFile
        
        $global:TrackerTimer = New-Object System.Timers.Timer
        $global:TrackerTimer.Interval = $global:config.sampleIntervalSeconds * 1000
        $global:TrackerTimer.AutoReset = $true
        
        $action = {
            try {
                $info = Get-ActiveWindowInfo
                if ($info) {
                    $category = Classify-Activity -ProcessName $info.ProcessName -WindowTitle $info.WindowTitle -Rules $global:rules
                    $info | Add-Member -NotePropertyName "Category" -NotePropertyValue $category -Force
                    Write-ActivityLog -LogFile $global:CurrentLogFile -ActivityInfo $info -SampleSeconds $global:config.sampleIntervalSeconds
                    
                    $currentTime = Get-Date
                    if ($global:CurrentActivityInfo -and $global:CurrentActivityInfo.ProcessName -eq $info.ProcessName -and $global:CurrentActivityInfo.WindowTitle -eq $info.WindowTitle) {
                        $elapsed = $currentTime - $global:CurrentActivityStart
                        $global:CurrentActivityDuration = $elapsed.ToString('hh\:mm\:ss')
                    } else {
                        $global:CurrentActivityStart = $currentTime
                        $global:CurrentActivityInfo = $info
                        $global:CurrentActivityDuration = "00:00:00"
                    }
                }
            } catch { }
        }
        
        $global:TrackerTimerEventSub = Register-ObjectEvent -InputObject $global:TrackerTimer -EventName Elapsed -Action $action -ErrorAction SilentlyContinue
        $global:TrackerTimer.Start()
        
        $btnStartStop.Content = "⏹ Stop Tracking"
        $btnStartStop.Background = "#EF4444"
        $statusText.Text = "Status: Running ⏱️"
        
    } else {
        $global:TrackerRunning = $false
        Stop-TrackingTimer
        $statusText.Text = "Status: Stopped ⏸️"
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

$btnGenerateReport.Add_Click({
    $logFile = Get-TodayLogFile -LogFolder $global:logFolder
    if (Test-Path $logFile) {
        try {
            $reportData = Get-ReportData -LogFile $logFile
            if ($reportData) {
                $date = Get-Date -Format "yyyy-MM-dd"
                $jsonFile = Join-Path (Join-Path $global:logFolder "reports") "summary-$date.json"
                Export-ReportToJSON -ReportData $reportData -OutputFile $jsonFile
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

# Update timer
$global:DashboardUpdateTimer = New-Object System.Timers.Timer
$global:DashboardUpdateTimer.Interval = 1500
$global:DashboardUpdateTimer.AutoReset = $true
$dashboardAction = {
    if ($global:TrackerRunning) {
        Invoke-OnUIThread { Update-Dashboard }
    }
}
$global:DashboardTimerEventSub = Register-ObjectEvent -InputObject $global:DashboardUpdateTimer -EventName Elapsed -Action $dashboardAction -ErrorAction SilentlyContinue
$global:DashboardUpdateTimer.Start()

# Window cleanup
$window.Add_Closing({
    try {
        Stop-TrackingTimer
        Stop-DashboardTimer
    } catch { }
})

Initialize-UI
$window.ShowDialog() | Out-Null

Stop-TrackingTimer
Stop-DashboardTimer
