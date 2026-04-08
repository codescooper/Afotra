# dashboard-wpf.ps1 - Modern WPF Dashboard for AFOTRA - Awema Focus Tracker
# Author: CodeScooper
# Project: AFOTRA - Awema Focus Tracker

param(
    [switch]$Debug
)

$ErrorActionPreference = "Stop"

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

Import-Module (Join-Path $scriptRoot "modules\Tracker.Core.psm1") -Force
Import-Module (Join-Path $scriptRoot "modules\Rules.Core.psm1") -Force
Import-Module (Join-Path $scriptRoot "modules\Report.Core.psm1") -Force

# Load configuration
$config = Get-Content $configPath -Encoding UTF8 | ConvertFrom-Json
$rules = Load-Rules -RulesPath $rulesPath

# Make configuration global for timer access
$global:config = $config
$global:rules = $rules
$global:logFolder = $logFolder

# Global state
$global:TrackerRunning = $false
$global:TrackerTimer = $null
$global:CurrentView = "Dashboard"
$global:CurrentActivityStart = $null
$global:CurrentActivityInfo = $null
$global:CurrentLogFile = $null

# XAML for the main window
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AFOTRA - Awema Focus Tracker" Height="800" Width="1200"
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
            <Setter Property="Background" Value="{StaticResource CardBackground}"/>
            <Setter Property="CornerRadius" Value="12"/>
            <Setter Property="BorderBrush" Value="#E5E7EB"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Effect">
                <Setter.Value>
                    <DropShadowEffect BlurRadius="8" ShadowDepth="2" Color="#000000" Opacity="0.1"/>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="PrimaryButtonStyle" TargetType="Button">
            <Setter Property="Background" Value="{StaticResource PrimaryBrush}"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Padding" Value="16,8"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" CornerRadius="8" BorderThickness="0">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#1D4ED8"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#1E40AF"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid>
        <!-- Sidebar Navigation -->
        <Border Background="{StaticResource PrimaryBrush}" Width="250" HorizontalAlignment="Left">
            <StackPanel Margin="20">
                <TextBlock Text="AFOTRA" FontSize="24" FontWeight="Bold" Foreground="White" Margin="0,0,0,30"/>
                <Button x:Name="NavDashboard" Content="📊 Dashboard" Style="{StaticResource PrimaryButtonStyle}" Margin="0,0,0,10" Background="Transparent"/>
                <Button x:Name="NavLiveTracking" Content="🎯 Live Tracking" Style="{StaticResource PrimaryButtonStyle}" Margin="0,0,0,10" Background="Transparent"/>
                <Button x:Name="NavUnknownActivities" Content="❓ Unknown Activities" Style="{StaticResource PrimaryButtonStyle}" Margin="0,0,0,10" Background="Transparent"/>
                <Button x:Name="NavRulesCategories" Content="⚙️ Rules &amp; Categories" Style="{StaticResource PrimaryButtonStyle}" Margin="0,0,0,10" Background="Transparent"/>
                <Button x:Name="NavAnalytics" Content="📈 Analytics" Style="{StaticResource PrimaryButtonStyle}" Margin="0,0,0,10" Background="Transparent"/>
                <Button x:Name="NavSettings" Content="🔧 Settings" Style="{StaticResource PrimaryButtonStyle}" Margin="0,0,0,30" Background="Transparent"/>
                <Separator Background="#4B5563"/>
                <Button x:Name="BtnStartStop" Content="▶ Start Tracking" Style="{StaticResource PrimaryButtonStyle}" Margin="0,20,0,0" Background="#10B981"/>
                <TextBlock x:Name="StatusText" Text="Status: Stopped" Foreground="White" Margin="0,10,0,0" FontSize="12"/>
            </StackPanel>
        </Border>

        <!-- Main Content Area -->
        <ScrollViewer Margin="270,20,20,20" VerticalScrollBarVisibility="Auto">
            <StackPanel x:Name="MainContent" Margin="0,0,0,20">
                <!-- Dashboard View -->
                <StackPanel x:Name="DashboardView" Visibility="Visible">
                    <TextBlock Text="Dashboard" FontSize="32" FontWeight="Bold" Foreground="{StaticResource TextPrimary}" Margin="0,0,0,20"/>
                    
                    <!-- Stats Cards Row 1 -->
                    <WrapPanel Margin="0,0,0,20">
                        <Border Style="{StaticResource CardStyle}" Width="280" Height="120" Margin="0,0,20,0">
                            <StackPanel Margin="20">
                                <TextBlock Text="Total Time" FontSize="14" Foreground="{StaticResource TextSecondary}"/>
                                <TextBlock x:Name="TotalTimeText" Text="00:00:00" FontSize="28" FontWeight="Bold" Foreground="{StaticResource TextPrimary}" Margin="0,5,0,0"/>
                            </StackPanel>
                        </Border>
                        <Border Style="{StaticResource CardStyle}" Width="280" Height="120" Margin="0,0,20,0">
                            <StackPanel Margin="20">
                                <TextBlock Text="Focus Time" FontSize="14" Foreground="{StaticResource TextSecondary}"/>
                                <TextBlock x:Name="FocusTimeText" Text="00:00:00" FontSize="28" FontWeight="Bold" Foreground="{StaticResource SuccessBrush}" Margin="0,5,0,0"/>
                            </StackPanel>
                        </Border>
                        <Border Style="{StaticResource CardStyle}" Width="280" Height="120">
                            <StackPanel Margin="20">
                                <TextBlock Text="Focus Score" FontSize="14" Foreground="{StaticResource TextSecondary}"/>
                                <TextBlock x:Name="FocusScoreText" Text="0%" FontSize="28" FontWeight="Bold" Foreground="{StaticResource PrimaryBrush}" Margin="0,5,0,0"/>
                            </StackPanel>
                        </Border>
                    </WrapPanel>

                    <!-- Stats Cards Row 2 -->
                    <WrapPanel Margin="0,0,0,20">
                        <Border Style="{StaticResource CardStyle}" Width="280" Height="120" Margin="0,0,20,0">
                            <StackPanel Margin="20">
                                <TextBlock Text="Distraction Time" FontSize="14" Foreground="{StaticResource TextSecondary}"/>
                                <TextBlock x:Name="DistractionTimeText" Text="00:00:00" FontSize="28" FontWeight="Bold" Foreground="{StaticResource DangerBrush}" Margin="0,5,0,0"/>
                            </StackPanel>
                        </Border>
                        <Border Style="{StaticResource CardStyle}" Width="280" Height="120" Margin="0,0,20,0">
                            <StackPanel Margin="20">
                                <TextBlock Text="Context Switches" FontSize="14" Foreground="{StaticResource TextSecondary}"/>
                                <TextBlock x:Name="ContextSwitchesText" Text="0" FontSize="28" FontWeight="Bold" Foreground="{StaticResource TextPrimary}" Margin="0,5,0,0"/>
                            </StackPanel>
                        </Border>
                        <Border Style="{StaticResource CardStyle}" Width="280" Height="120">
                            <StackPanel Margin="20">
                                <TextBlock Text="Current Activity" FontSize="14" Foreground="{StaticResource TextSecondary}"/>
                                <TextBlock x:Name="CurrentActivityText" Text="None" FontSize="16" FontWeight="Bold" Foreground="{StaticResource TextPrimary}" Margin="0,5,0,0" TextWrapping="Wrap"/>
                            </StackPanel>
                        </Border>
                    </WrapPanel>

                    <!-- Charts Section -->
                    <Border Style="{StaticResource CardStyle}" Margin="0,0,0,20">
                        <StackPanel Margin="20">
                            <TextBlock Text="Activity Distribution" FontSize="20" FontWeight="Bold" Foreground="{StaticResource TextPrimary}" Margin="0,0,0,15"/>
                            <Canvas x:Name="ActivityChartCanvas" Width="800" Height="300" Background="#F9FAFB"/>
                        </StackPanel>
                    </Border>
                </StackPanel>

                <!-- Live Tracking View -->
                <StackPanel x:Name="LiveTrackingView" Visibility="Collapsed">
                    <TextBlock Text="Live Tracking" FontSize="32" FontWeight="Bold" Foreground="{StaticResource TextPrimary}" Margin="0,0,0,20"/>
                    
                    <Border Style="{StaticResource CardStyle}" Margin="0,0,0,20">
                        <StackPanel Margin="20">
                            <TextBlock Text="Current Session" FontSize="20" FontWeight="Bold" Foreground="{StaticResource TextPrimary}" Margin="0,0,0,15"/>
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <StackPanel Grid.Column="0" Margin="0,0,20,0">
                                    <TextBlock Text="Process:" FontWeight="SemiBold" Foreground="{StaticResource TextSecondary}"/>
                                    <TextBlock x:Name="LiveProcessText" Text="--" FontSize="16" Margin="0,5,0,10"/>
                                    <TextBlock Text="Window Title:" FontWeight="SemiBold" Foreground="{StaticResource TextSecondary}"/>
                                    <TextBlock x:Name="LiveWindowText" Text="--" FontSize="14" Margin="0,5,0,10" TextWrapping="Wrap"/>
                                </StackPanel>
                                <StackPanel Grid.Column="1">
                                    <TextBlock Text="Category:" FontWeight="SemiBold" Foreground="{StaticResource TextSecondary}"/>
                                    <TextBlock x:Name="LiveCategoryText" Text="--" FontSize="16" Margin="0,5,0,10"/>
                                    <TextBlock Text="Time on Current:" FontWeight="SemiBold" Foreground="{StaticResource TextSecondary}"/>
                                    <TextBlock x:Name="LiveCurrentTimeText" Text="00:00:00" FontSize="16" Margin="0,5,0,10"/>
                                </StackPanel>
                            </Grid>
                        </StackPanel>
                    </Border>
                </StackPanel>

                <!-- Unknown Activities View -->
                <StackPanel x:Name="UnknownActivitiesView" Visibility="Collapsed">
                    <TextBlock Text="Unknown Activities" FontSize="32" FontWeight="Bold" Foreground="{StaticResource TextPrimary}" Margin="0,0,0,20"/>
                    
                    <Border Style="{StaticResource CardStyle}" Margin="0,0,0,20">
                        <StackPanel Margin="20">
                            <TextBlock Text="Activities marked as 'inconnu'" FontSize="16" Foreground="{StaticResource TextSecondary}" Margin="0,0,0,15"/>
                            <DataGrid x:Name="UnknownActivitiesGrid" Height="300" AutoGenerateColumns="False" IsReadOnly="True">
                                <DataGrid.Columns>
                                    <DataGridTextColumn Header="Process" Binding="{Binding ProcessName}" Width="*"/>
                                    <DataGridTextColumn Header="Window Title" Binding="{Binding WindowTitle}" Width="2*"/>
                                    <DataGridTextColumn Header="Occurrences" Binding="{Binding Count}" Width="100"/>
                                    <DataGridTextColumn Header="Total Time" Binding="{Binding TotalTime}" Width="100"/>
                                </DataGrid.Columns>
                            </DataGrid>
                            <StackPanel Orientation="Horizontal" Margin="0,15,0,0">
                                <Button x:Name="BtnCategorizeUnknown" Content="Categorize Selected" Style="{StaticResource PrimaryButtonStyle}" Margin="0,0,10,0"/>
                                <Button x:Name="BtnRefreshUnknown" Content="Refresh" Style="{StaticResource PrimaryButtonStyle}" Background="{StaticResource SecondaryBrush}"/>
                            </StackPanel>
                        </StackPanel>
                    </Border>
                </StackPanel>

                <!-- Rules & Categories View -->
                <StackPanel x:Name="RulesCategoriesView" Visibility="Collapsed">
                    <TextBlock Text="Rules &amp; Categories" FontSize="32" FontWeight="Bold" Foreground="{StaticResource TextPrimary}" Margin="0,0,0,20"/>
                    
                    <WrapPanel Margin="0,0,0,20">
                        <Border Style="{StaticResource CardStyle}" Width="400" Margin="0,0,20,0">
                            <StackPanel Margin="20">
                                <TextBlock Text="Categories" FontSize="20" FontWeight="Bold" Foreground="{StaticResource TextPrimary}" Margin="0,0,0,15"/>
                                <ListBox x:Name="CategoriesListBox" Height="200"/>
                                <StackPanel Orientation="Horizontal" Margin="0,15,0,0">
                                    <TextBox x:Name="NewCategoryTextBox" Width="200" Margin="0,0,10,0"/>
                                    <Button x:Name="BtnAddCategory" Content="Add" Style="{StaticResource PrimaryButtonStyle}"/>
                                </StackPanel>
                            </StackPanel>
                        </Border>
                        
                        <Border Style="{StaticResource CardStyle}" Width="400">
                            <StackPanel Margin="20">
                                <TextBlock Text="Rules" FontSize="20" FontWeight="Bold" Foreground="{StaticResource TextPrimary}" Margin="0,0,0,15"/>
                                <DataGrid x:Name="RulesGrid" Height="200" AutoGenerateColumns="False">
                                    <DataGrid.Columns>
                                        <DataGridTextColumn Header="Type" Binding="{Binding Type}" Width="80"/>
                                        <DataGridTextColumn Header="Pattern" Binding="{Binding Pattern}" Width="*"/>
                                        <DataGridTextColumn Header="Category" Binding="{Binding Category}" Width="100"/>
                                    </DataGrid.Columns>
                                </DataGrid>
                                <StackPanel Orientation="Horizontal" Margin="0,15,0,0">
                                    <Button x:Name="BtnAddRule" Content="Add Rule" Style="{StaticResource PrimaryButtonStyle}" Margin="0,0,10,0"/>
                                    <Button x:Name="BtnEditRule" Content="Edit" Style="{StaticResource PrimaryButtonStyle}" Background="{StaticResource SecondaryBrush}" Margin="0,0,10,0"/>
                                    <Button x:Name="BtnDeleteRule" Content="Delete" Style="{StaticResource PrimaryButtonStyle}" Background="{StaticResource DangerBrush}"/>
                                </StackPanel>
                            </StackPanel>
                        </Border>
                    </WrapPanel>
                </StackPanel>

                <!-- Analytics View -->
                <StackPanel x:Name="AnalyticsView" Visibility="Collapsed">
                    <TextBlock Text="Analytics" FontSize="32" FontWeight="Bold" Foreground="{StaticResource TextPrimary}" Margin="0,0,0,20"/>
                    
                    <Border Style="{StaticResource CardStyle}" Margin="0,0,0,20">
                        <StackPanel Margin="20">
                            <TextBlock Text="Top Applications" FontSize="20" FontWeight="Bold" Foreground="{StaticResource TextPrimary}" Margin="0,0,0,15"/>
                            <Canvas x:Name="TopAppsChartCanvas" Width="800" Height="300" Background="#F9FAFB"/>
                        </StackPanel>
                    </Border>

                    <Border Style="{StaticResource CardStyle}" Margin="0,0,0,20">
                        <StackPanel Margin="20">
                            <TextBlock Text="Daily Summary" FontSize="20" FontWeight="Bold" Foreground="{StaticResource TextPrimary}" Margin="0,0,0,15"/>
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <StackPanel Grid.Column="0" Margin="0,0,20,0">
                                    <TextBlock Text="Most Productive Hour:" FontWeight="SemiBold" Foreground="{StaticResource TextSecondary}"/>
                                    <TextBlock x:Name="MostProductiveHourText" Text="--" FontSize="16" Margin="0,5,0,10"/>
                                    <TextBlock Text="Longest Focus Session:" FontWeight="SemiBold" Foreground="{StaticResource TextSecondary}"/>
                                    <TextBlock x:Name="LongestFocusSessionText" Text="--" FontSize="16" Margin="0,5,0,10"/>
                                </StackPanel>
                                <StackPanel Grid.Column="1" Margin="0,0,20,0">
                                    <TextBlock Text="Total Context Switches:" FontWeight="SemiBold" Foreground="{StaticResource TextSecondary}"/>
                                    <TextBlock x:Name="TotalContextSwitchesText" Text="--" FontSize="16" Margin="0,5,0,10"/>
                                    <TextBlock Text="Average Session Length:" FontWeight="SemiBold" Foreground="{StaticResource TextSecondary}"/>
                                    <TextBlock x:Name="AverageSessionLengthText" Text="--" FontSize="16" Margin="0,5,0,10"/>
                                </StackPanel>
                                <StackPanel Grid.Column="2">
                                    <TextBlock Text="Peak Productivity:" FontWeight="SemiBold" Foreground="{StaticResource TextSecondary}"/>
                                    <TextBlock x:Name="PeakProductivityText" Text="--" FontSize="16" Margin="0,5,0,10"/>
                                    <Button x:Name="BtnGenerateDetailedReport" Content="Generate Detailed Report" Style="{StaticResource PrimaryButtonStyle}" Margin="0,10,0,0"/>
                                </StackPanel>
                            </Grid>
                        </StackPanel>
                    </Border>
                </StackPanel>

                <!-- Settings View -->
                <StackPanel x:Name="SettingsView" Visibility="Collapsed">
                    <TextBlock Text="Settings" FontSize="32" FontWeight="Bold" Foreground="{StaticResource TextPrimary}" Margin="0,0,0,20"/>
                    
                    <Border Style="{StaticResource CardStyle}">
                        <StackPanel Margin="20">
                            <TextBlock Text="Tracking Configuration" FontSize="20" FontWeight="Bold" Foreground="{StaticResource TextPrimary}" Margin="0,0,0,15"/>
                            <Grid Margin="0,0,0,15">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="200"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Grid.Column="0" Text="Sample Interval (seconds):" VerticalAlignment="Center"/>
                                <TextBox x:Name="SampleIntervalTextBox" Grid.Column="1" Text="10" Margin="10,0,0,0"/>
                            </Grid>
                            <Grid Margin="0,0,0,15">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="200"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Grid.Column="0" Text="Focus Goal (minutes/day):" VerticalAlignment="Center"/>
                                <TextBox x:Name="FocusGoalTextBox" Grid.Column="1" Text="480" Margin="10,0,0,0"/>
                            </Grid>
                            <Button x:Name="BtnSaveSettings" Content="Save Settings" Style="{StaticResource PrimaryButtonStyle}" HorizontalAlignment="Left"/>
                        </StackPanel>
                    </Border>
                </StackPanel>
            </StackPanel>
        </ScrollViewer>
    </Grid>
</Window>
"@

# Load XAML
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# Get UI elements
$navDashboard = $window.FindName("NavDashboard")
$navLiveTracking = $window.FindName("NavLiveTracking")
$navUnknownActivities = $window.FindName("NavUnknownActivities")
$navRulesCategories = $window.FindName("NavRulesCategories")
$navAnalytics = $window.FindName("NavAnalytics")
$navSettings = $window.FindName("NavSettings")
$btnStartStop = $window.FindName("BtnStartStop")
$statusText = $window.FindName("StatusText")

# Dashboard elements
$totalTimeText = $window.FindName("TotalTimeText")
$focusTimeText = $window.FindName("FocusTimeText")
$focusScoreText = $window.FindName("FocusScoreText")
$distractionTimeText = $window.FindName("DistractionTimeText")
$contextSwitchesText = $window.FindName("ContextSwitchesText")
$currentActivityText = $window.FindName("CurrentActivityText")
$activityChartCanvas = $window.FindName("ActivityChartCanvas")

# Live Tracking elements
$liveProcessText = $window.FindName("LiveProcessText")
$liveWindowText = $window.FindName("LiveWindowText")
$liveCategoryText = $window.FindName("LiveCategoryText")
$liveCurrentTimeText = $window.FindName("LiveCurrentTimeText")

# Unknown Activities elements
$unknownActivitiesGrid = $window.FindName("UnknownActivitiesGrid")
$btnCategorizeUnknown = $window.FindName("BtnCategorizeUnknown")
$btnRefreshUnknown = $window.FindName("BtnRefreshUnknown")

# Rules & Categories elements
$categoriesListBox = $window.FindName("CategoriesListBox")
$newCategoryTextBox = $window.FindName("NewCategoryTextBox")
$btnAddCategory = $window.FindName("BtnAddCategory")
$rulesGrid = $window.FindName("RulesGrid")
$btnAddRule = $window.FindName("BtnAddRule")
$btnEditRule = $window.FindName("BtnEditRule")
$btnDeleteRule = $window.FindName("BtnDeleteRule")

# Analytics elements
$topAppsChartCanvas = $window.FindName("TopAppsChartCanvas")
$mostProductiveHourText = $window.FindName("MostProductiveHourText")
$longestFocusSessionText = $window.FindName("LongestFocusSessionText")
$totalContextSwitchesText = $window.FindName("TotalContextSwitchesText")
$averageSessionLengthText = $window.FindName("AverageSessionLengthText")
$peakProductivityText = $window.FindName("PeakProductivityText")
$btnGenerateDetailedReport = $window.FindName("BtnGenerateDetailedReport")

# Settings elements
$sampleIntervalTextBox = $window.FindName("SampleIntervalTextBox")
$focusGoalTextBox = $window.FindName("FocusGoalTextBox")
$btnSaveSettings = $window.FindName("BtnSaveSettings")

# View management functions
function Show-View {
    param($viewName)
    
    $views = @("DashboardView", "LiveTrackingView", "UnknownActivitiesView", "RulesCategoriesView", "AnalyticsView", "SettingsView")
    foreach ($view in $views) {
        $viewElement = $window.FindName($view)
        if ($view -eq $viewName) {
            $viewElement.Visibility = "Visible"
            # Update view-specific data
            if ($view -eq "AnalyticsView") {
                Update-Analytics
            } elseif ($view -eq "UnknownActivitiesView") {
                Update-UnknownActivities
            }
        } else {
            $viewElement.Visibility = "Collapsed"
        }
    }
    $global:CurrentView = $viewName
}

# Navigation event handlers
$navDashboard.Add_Click({ Show-View "DashboardView" })
$navLiveTracking.Add_Click({ Show-View "LiveTrackingView" })
$navUnknownActivities.Add_Click({ Show-View "UnknownActivitiesView" })
$navRulesCategories.Add_Click({ Show-View "RulesCategoriesView" })
$navAnalytics.Add_Click({ Show-View "AnalyticsView" })
$navSettings.Add_Click({ Show-View "SettingsView" })

# Initialize UI with data
function Initialize-UI {
    # Load categories
    $categoriesListBox.Items.Clear()
    foreach ($category in $rules.categories) {
        $categoriesListBox.Items.Add($category)
    }
    
    # Load rules
    $rulesData = @()
    foreach ($rule in $rules.processRules) {
        $rulesData += [PSCustomObject]@{
            Type = "Process"
            Pattern = $rule.process
            Category = $rule.category
        }
    }
    foreach ($rule in $rules.titleRules) {
        $rulesData += [PSCustomObject]@{
            Type = "Title"
            Pattern = $rule.contains
            Category = $rule.category
        }
    }
    $rulesGrid.ItemsSource = $rulesData
    
    # Load settings
    $sampleIntervalTextBox.Text = $config.sampleIntervalSeconds
    $focusGoalTextBox.Text = $config.focusMinPerDay
    
    # Initial dashboard update
    Update-Dashboard
}

# Dashboard update function
function Update-Dashboard {
    $logFile = Get-TodayLogFile -LogFolder $logFolder
    if (!(Test-Path $logFile)) {
        return
    }
    
    try {
        $data = @(Import-Csv -Path $logFile -Encoding UTF8)
        if ($data.Count -eq 0) { return }
        
        $sampleSeconds = [int]$data[0].SampleSeconds
        $totalSeconds = $data.Count * $sampleSeconds
        
        $categories = @{}
        foreach ($row in $data) {
            if (!$categories[$row.Category]) {
                $categories[$row.Category] = 0
            }
            $categories[$row.Category] += $sampleSeconds
        }
        
        $focusSeconds = if ($categories["travail"]) { $categories["travail"] } else { 0 }
        $distractionSeconds = if ($categories["distraction"]) { $categories["distraction"] } else { 0 }
        $unknownSeconds = if ($categories["inconnu"]) { $categories["inconnu"] } else { 0 }
        
        $focusScore = if ($totalSeconds -gt 0) { [math]::Round(($focusSeconds / $totalSeconds) * 100, 1) } else { 0 }
        $contextSwitches = ($data | Group-Object WindowTitle).Count
        
        # Update UI
        $totalTimeText.Text = [TimeSpan]::FromSeconds($totalSeconds).ToString('hh\:mm\:ss')
        $focusTimeText.Text = [TimeSpan]::FromSeconds($focusSeconds).ToString('hh\:mm\:ss')
        $distractionTimeText.Text = [TimeSpan]::FromSeconds($distractionSeconds).ToString('hh\:mm\:ss')
        $focusScoreText.Text = "$focusScore%"
        $contextSwitchesText.Text = $contextSwitches
        
        # Update current activity display
        if ($global:TrackerRunning -and $global:CurrentActivityInfo) {
            $currentActivityText.Text = "$($global:CurrentActivityInfo.ProcessName) - $($global:CurrentActivityInfo.WindowTitle)"
            
            # Update live tracking if visible
            if ($global:CurrentView -eq "LiveTracking") {
                $liveProcessText.Text = $global:CurrentActivityInfo.ProcessName
                $liveWindowText.Text = $global:CurrentActivityInfo.WindowTitle
                $liveCategoryText.Text = $global:CurrentActivityInfo.Category
                if ($global:CurrentActivityStart) {
                    $elapsed = (Get-Date) - $global:CurrentActivityStart
                    $liveCurrentTimeText.Text = $elapsed.ToString('hh\:mm\:ss')
                }
            }
        } else {
            $currentActivityText.Text = "Tracking stopped"
            $liveCurrentTimeText.Text = "00:00:00"
        }
        
        # Update chart
        Update-ActivityChart -Categories $categories -TotalSeconds $totalSeconds
        
    } catch {
        if ($Debug) { Write-Host "Error updating dashboard: $_" }
    }
}

# Chart drawing functions
function Update-ActivityChart {
    param($Categories, $TotalSeconds)
    
    $activityChartCanvas.Children.Clear()
    
    if ($TotalSeconds -eq 0) { return }
    
    $colors = @{
        "travail" = "#10B981"
        "distraction" = "#EF4444"
        "communication" = "#3B82F6"
        "etude" = "#8B5CF6"
        "inconnu" = "#F59E0B"
    }
    
    $barWidth = 60
    $maxHeight = 200
    $x = 50
    $legendY = 250
    
    foreach ($category in $Categories.Keys) {
        $seconds = $Categories[$category]
        $percentage = $seconds / $TotalSeconds
        $barHeight = [math]::Round($percentage * $maxHeight)
        
        $color = if ($colors.ContainsKey($category)) { $colors[$category] } else { "#6B7280" }
        
        # Draw bar
        $rect = New-Object Windows.Shapes.Rectangle
        $rect.Width = $barWidth
        $rect.Height = $barHeight
        $rect.Fill = $color
        $rect.Stroke = "#374151"
        $rect.StrokeThickness = 1
        Canvas.SetLeft $rect $x
        Canvas.SetTop $rect (220 - $barHeight)
        $activityChartCanvas.Children.Add($rect)
        
        # Percentage text
        $textBlock = New-Object Windows.Controls.TextBlock
        $textBlock.Text = "$([math]::Round($percentage * 100, 1))%"
        $textBlock.FontSize = 10
        $textBlock.Foreground = "#374151"
        $textBlock.TextAlignment = "Center"
        $textBlock.Width = $barWidth
        Canvas.SetLeft $textBlock $x
        Canvas.SetTop $textBlock 225
        $activityChartCanvas.Children.Add($textBlock)
        
        # Legend
        $legendRect = New-Object Windows.Shapes.Rectangle
        $legendRect.Width = 15
        $legendRect.Height = 15
        $legendRect.Fill = $color
        Canvas.SetLeft $legendRect $x
        Canvas.SetTop $legendRect $legendY
        $activityChartCanvas.Children.Add($legendRect)
        
        $legendText = New-Object Windows.Controls.TextBlock
        $legendText.Text = $category
        $legendText.FontSize = 10
        $legendText.Foreground = "#374151"
        Canvas.SetLeft $legendText ($x + 20)
        Canvas.SetTop $legendText $legendY
        $activityChartCanvas.Children.Add($legendText)
        
        $x += $barWidth + 20
    }
}

function Update-UnknownActivities {
    $logFile = Get-TodayLogFile -LogFolder $logFolder
    if (Test-Path $logFile) {
        $data = Import-Csv -Path $logFile -Encoding UTF8
        $unknownActivities = $data | Where-Object { $_.Category -eq "inconnu" } | Group-Object ProcessName, WindowTitle | 
            Select-Object @{Name="ProcessName"; Expression={$_.Name.Split(',')[0]}}, 
                         @{Name="WindowTitle"; Expression={$_.Name.Split(',')[1]}}, 
                         @{Name="Count"; Expression={$_.Group.Count}}, 
                         @{Name="TotalTime"; Expression={[TimeSpan]::FromSeconds($_.Group.Count * [int]$data[0].SampleSeconds).ToString('hh\:mm\:ss')}}
        
        $unknownActivitiesGrid.ItemsSource = $unknownActivities
    }
}

# Analytics functions
function Update-Analytics {
    $logFile = Get-TodayLogFile -LogFolder $logFolder
    if (!(Test-Path $logFile)) {
        $mostProductiveHourText.Text = "--"
        $longestFocusSessionText.Text = "--"
        $totalContextSwitchesText.Text = "--"
        $averageSessionLengthText.Text = "--"
        $peakProductivityText.Text = "--"
        return
    }
    
    try {
        $data = @(Import-Csv -Path $logFile -Encoding UTF8)
        if ($data.Count -eq 0) { return }
        
        $sampleSeconds = [int]$data[0].SampleSeconds
        
        # Calculate top applications
        $appUsage = @{}
        foreach ($row in $data) {
            if (!$appUsage[$row.ProcessName]) {
                $appUsage[$row.ProcessName] = 0
            }
            $appUsage[$row.ProcessName] += $sampleSeconds
        }
        
        # Update top apps chart
        Update-TopAppsChart -AppUsage $appUsage
        
        # Calculate analytics
        $totalSeconds = $data.Count * $sampleSeconds
        $contextSwitches = ($data | Group-Object WindowTitle).Count
        
        # Most productive hour (simplified - hour with most "travail" time)
        $hourlyProductivity = @{}
        foreach ($row in $data) {
            $hour = [DateTime]::Parse($row.Time).Hour
            if (!$hourlyProductivity[$hour]) {
                $hourlyProductivity[$hour] = @{ Total = 0; Focus = 0 }
            }
            $hourlyProductivity[$hour].Total += $sampleSeconds
            if ($row.Category -eq "travail") {
                $hourlyProductivity[$hour].Focus += $sampleSeconds
            }
        }
        
        $mostProductiveHour = $hourlyProductivity.GetEnumerator() | 
            Sort-Object { $_.Value.Focus } -Descending | 
            Select-Object -First 1
        
        if ($mostProductiveHour) {
            $hour = $mostProductiveHour.Key
            $focusMinutes = [math]::Round($mostProductiveHour.Value.Focus / 60, 1)
            $mostProductiveHourText.Text = "${hour}:00 - ${focusMinutes} min focus"
        }
        
        # Longest focus session (simplified - consecutive "travail" entries)
        $longestSession = 0
        $currentSession = 0
        foreach ($row in $data) {
            if ($row.Category -eq "travail") {
                $currentSession += $sampleSeconds
                if ($currentSession -gt $longestSession) {
                    $longestSession = $currentSession
                }
            } else {
                $currentSession = 0
            }
        }
        
        $longestFocusSessionText.Text = [TimeSpan]::FromSeconds($longestSession).ToString('hh\:mm\:ss')
        $totalContextSwitchesText.Text = $contextSwitches
        
        # Average session length (simplified)
        $sessions = ($data | Group-Object WindowTitle).Count
        if ($sessions -gt 0) {
            $avgSessionSeconds = $totalSeconds / $sessions
            $averageSessionLengthText.Text = [TimeSpan]::FromSeconds($avgSessionSeconds).ToString('mm\:ss')
        }
        
        # Peak productivity (highest focus percentage in any hour)
        $peakProductivity = $hourlyProductivity.GetEnumerator() | 
            Where-Object { $_.Value.Total -gt 0 } | 
            ForEach-Object { [math]::Round(($_.Value.Focus / $_.Value.Total) * 100, 1) } | 
            Measure-Object -Maximum | 
            Select-Object -ExpandProperty Maximum
        
        $peakProductivityText.Text = "$peakProductivity%"
        
    } catch {
        if ($Debug) { Write-Host "Error updating analytics: $_" }
    }
}

function Update-TopAppsChart {
    param($AppUsage)
    
    $topAppsChartCanvas.Children.Clear()
    
    if ($AppUsage.Count -eq 0) { return }
    
    $topApps = $AppUsage.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5
    $maxTime = ($topApps | Measure-Object Value -Maximum).Maximum
    
    $barWidth = 80
    $maxHeight = 200
    $x = 50
    $legendY = 250
    
    $index = 0
    foreach ($app in $topApps) {
        $percentage = if ($maxTime -gt 0) { $app.Value / $maxTime } else { 0 }
        $barHeight = [math]::Round($percentage * $maxHeight)
        
        $colors = @("#10B981", "#3B82F6", "#F59E0B", "#EF4444", "#8B5CF6")
        $color = $colors[$index % $colors.Length]
        
        # Draw bar
        $rect = New-Object Windows.Shapes.Rectangle
        $rect.Width = $barWidth
        $rect.Height = $barHeight
        $rect.Fill = $color
        $rect.Stroke = "#374151"
        $rect.StrokeThickness = 1
        Canvas.SetLeft $rect $x
        Canvas.SetTop $rect (220 - $barHeight)
        $topAppsChartCanvas.Children.Add($rect)
        
        # Time text
        $timeText = [TimeSpan]::FromSeconds($app.Value).ToString('hh\:mm\:ss')
        $textBlock = New-Object Windows.Controls.TextBlock
        $textBlock.Text = $timeText
        $textBlock.FontSize = 10
        $textBlock.Foreground = "#374151"
        $textBlock.TextAlignment = "Center"
        $textBlock.Width = $barWidth
        Canvas.SetLeft $textBlock $x
        Canvas.SetTop $textBlock 225
        $topAppsChartCanvas.Children.Add($textBlock)
        
        # App name
        $appText = New-Object Windows.Controls.TextBlock
        $appText.Text = $app.Key
        $appText.FontSize = 9
        $appText.Foreground = "#374151"
        $appText.TextAlignment = "Center"
        $appText.Width = $barWidth
        Canvas.SetLeft $appText $x
        Canvas.SetTop $appText 240
        $topAppsChartCanvas.Children.Add($appText)
        
        $x += $barWidth + 20
        $index++
    }
}

# Tracking functions
$btnStartStop.Add_Click({
    if (!$global:TrackerRunning) {
        # Start tracking
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
                    
                    # Track current activity time
                    $currentTime = Get-Date
                    if ($global:CurrentActivityInfo -and 
                        $global:CurrentActivityInfo.ProcessName -eq $info.ProcessName -and 
                        $global:CurrentActivityInfo.WindowTitle -eq $info.WindowTitle) {
                        # Same activity, update time
                        $elapsed = $currentTime - $global:CurrentActivityStart
                        $global:CurrentActivityDuration = $elapsed.ToString('hh\:mm\:ss')
                    } else {
                        # New activity
                        $global:CurrentActivityStart = $currentTime
                        $global:CurrentActivityInfo = $info
                        $global:CurrentActivityDuration = "00:00:00"
                    }
                }
            } catch {
                # Silently ignore errors in timer
            }
        }
        
        Register-ObjectEvent -InputObject $global:TrackerTimer -EventName Elapsed -Action $action | Out-Null
        $global:TrackerTimer.Start()
        
        $btnStartStop.Content = "⏹ Stop Tracking"
        $btnStartStop.Background = "#EF4444"
        
    } else {
        # Stop tracking
        $global:TrackerRunning = $false
        if ($global:TrackerTimer) {
            $global:TrackerTimer.Stop()
            $global:TrackerTimer.Dispose()
            $global:TrackerTimer = $null
        }
        
        $statusText.Text = "Status: Stopped"
        $btnStartStop.Content = "▶ Start Tracking"
        $btnStartStop.Background = "#10B981"
        
        # Final update
        Update-Dashboard
    }
})

# Unknown activities functions
$btnRefreshUnknown.Add_Click({
    $logFile = Get-TodayLogFile -LogFolder $logFolder
    if (Test-Path $logFile) {
        $data = Import-Csv -Path $logFile -Encoding UTF8
        $unknownActivities = $data | Where-Object { $_.Category -eq "inconnu" } | Group-Object ProcessName, WindowTitle | 
            Select-Object @{Name="ProcessName"; Expression={$_.Name.Split(',')[0]}}, 
                         @{Name="WindowTitle"; Expression={$_.Name.Split(',')[1]}}, 
                         @{Name="Count"; Expression={$_.Group.Count}}, 
                         @{Name="TotalTime"; Expression={[TimeSpan]::FromSeconds($_.Group.Count * [int]$data[0].SampleSeconds).ToString('hh\:mm\:ss')}}
        
        $unknownActivitiesGrid.ItemsSource = $unknownActivities
    }
})

$btnCategorizeUnknown.Add_Click({
    $selectedItem = $unknownActivitiesGrid.SelectedItem
    if ($selectedItem) {
        # Show categorization dialog
        $categorizeWindow = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]@"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Categorize Activity" Height="300" Width="400" WindowStartupLocation="CenterOwner">
    <StackPanel Margin="20">
        <TextBlock Text="Categorize Unknown Activity" FontSize="16" FontWeight="Bold" Margin="0,0,0,15"/>
        <TextBlock Text="Process:" FontWeight="SemiBold"/>
        <TextBlock Text="$($selectedItem.ProcessName)" Margin="0,5,0,10"/>
        <TextBlock Text="Window Title:" FontWeight="SemiBold"/>
        <TextBlock Text="$($selectedItem.WindowTitle)" Margin="0,5,0,15" TextWrapping="Wrap"/>
        <TextBlock Text="Assign to category:" FontWeight="SemiBold"/>
        <ComboBox x:Name="CategoryComboBox" Margin="0,5,0,15"/>
        <TextBlock Text="Create rule based on:" FontWeight="SemiBold"/>
        <StackPanel Orientation="Horizontal" Margin="0,5,0,15">
            <RadioButton x:Name="RuleByProcess" Content="Process Name" IsChecked="True"/>
            <RadioButton x:Name="RuleByTitle" Content="Window Title" Margin="20,0,0,0"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="BtnCancel" Content="Cancel" Margin="0,0,10,0" Padding="15,5"/>
            <Button x:Name="BtnSaveCategory" Content="Save" Padding="15,5" Background="#10B981" Foreground="White"/>
        </StackPanel>
    </StackPanel>
</Window>
"@)))
        
        $categoryComboBox = $categorizeWindow.FindName("CategoryComboBox")
        $ruleByProcess = $categorizeWindow.FindName("RuleByProcess")
        $ruleByTitle = $categorizeWindow.FindName("RuleByTitle")
        $btnCancel = $categorizeWindow.FindName("BtnCancel")
        $btnSaveCategory = $categorizeWindow.FindName("BtnSaveCategory")
        
        # Populate categories
        foreach ($category in $rules.categories) {
            $categoryComboBox.Items.Add($category)
        }
        $categoryComboBox.SelectedIndex = 0
        
        $btnCancel.Add_Click({ $categorizeWindow.Close() })
        
        $btnSaveCategory.Add_Click({
            $selectedCategory = $categoryComboBox.SelectedItem
            if ($ruleByProcess.IsChecked) {
                $rules.processRules += @{ process = $selectedItem.ProcessName; category = $selectedCategory }
            } else {
                $rules.titleRules += @{ contains = $selectedItem.WindowTitle; category = $selectedCategory }
            }
            
            # Save rules
            Save-Rules -Rules $rules -RulesPath $rulesPath
            
            # Refresh UI
            Initialize-UI
            $btnRefreshUnknown.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
            
            $categorizeWindow.Close()
        })
        
        $categorizeWindow.ShowDialog()
    }
})

# Categories functions
$btnAddCategory.Add_Click({
    $newCategory = $newCategoryTextBox.Text.Trim()
    if ($newCategory -and $rules.categories -notcontains $newCategory) {
        $rules.categories += $newCategory
        Save-Rules -Rules $rules -RulesPath $rulesPath
        Initialize-UI
        $newCategoryTextBox.Text = ""
    }
})

# Settings functions
$btnSaveSettings.Add_Click({
    $config.sampleIntervalSeconds = [int]$sampleIntervalTextBox.Text
    $config.focusMinPerDay = [int]$focusGoalTextBox.Text
    $config | ConvertTo-Json -Depth 10 | Set-Content -Path $configPath -Encoding UTF8
    [Windows.MessageBox]::Show("Settings saved!", "AFOTRA")
})

# Analytics functions
$btnGenerateDetailedReport.Add_Click({
    $logFile = Get-TodayLogFile -LogFolder $logFolder
    if (Test-Path $logFile) {
        $reportData = Get-ReportData -LogFile $logFile
        if ($reportData) {
            $date = Get-Date -Format "yyyy-MM-dd"
            $jsonFile = Join-Path (Join-Path $logFolder "reports") "detailed-$date.json"
            Export-ReportToJSON -ReportData $reportData -OutputFile $jsonFile
            [Windows.MessageBox]::Show("Detailed report generated!`n`nFile: $jsonFile", "AFOTRA")
        }
    }
})

# Initialize and show window
Initialize-UI
$window.ShowDialog() | Out-Null