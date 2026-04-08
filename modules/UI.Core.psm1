# UI.Core.psm1 - Windows Forms interface for AFOTRA - Awema Focus Tracker
# Author: CodeScooper
# Project: AFOTRA - Awema Focus Tracker

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$global:TrackerState = @{
    IsRunning = $false
    Timer = $null
    CurrentInfo = @{ ProcessName = "N/A"; WindowTitle = "N/A"; Category = "N/A" }
    LastUpdateTime = Get-Date
}

function New-DashboardForm {
    param (
        [string]$ConfigPath,
        [string]$RulesPath,
        [string]$LogFolder,
        [scriptblock]$OnStartTracking,
        [scriptblock]$OnStopTracking,
        [scriptblock]$OnGenerateReport
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "AFOTRA - Awema Focus Tracker"
    $form.Size = New-Object System.Drawing.Size(900, 700)
    $form.StartPosition = "CenterScreen"
    $form.Icon = $null

    # Tab Control
    $tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Size = New-Object System.Drawing.Size(880, 630)
    $tabControl.Location = New-Object System.Drawing.Point(5, 40)

    # ===== TAB 1: LIVE =====
    $liveTab = New-Object System.Windows.Forms.TabPage
    $liveTab.Text = "Live"
    $liveTab.BackColor = [System.Drawing.Color]::White

    $startBtn = New-Object System.Windows.Forms.Button
    $startBtn.Text = "▶ Start Tracking"
    $startBtn.Location = New-Object System.Drawing.Point(10, 10)
    $startBtn.Size = New-Object System.Drawing.Size(120, 30)
    $startBtn.Add_Click({ 
        if (!$global:TrackerState.IsRunning) {
            & $OnStartTracking
            $startBtn.Enabled = $false
            $stopBtn.Enabled = $true
            $statusLabel.Text = "Status: Running ⏱️"
            $statusLabel.ForeColor = [System.Drawing.Color]::Green
        }
    })

    $stopBtn = New-Object System.Windows.Forms.Button
    $stopBtn.Text = "⏹ Stop Tracking"
    $stopBtn.Location = New-Object System.Drawing.Point(140, 10)
    $stopBtn.Size = New-Object System.Drawing.Size(120, 30)
    $stopBtn.Enabled = $false
    $stopBtn.Add_Click({
        if ($global:TrackerState.IsRunning) {
            & $OnStopTracking
            $startBtn.Enabled = $true
            $stopBtn.Enabled = $false
            $statusLabel.Text = "Status: Stopped"
            $statusLabel.ForeColor = [System.Drawing.Color]::Red
        }
    })

    $reportBtn = New-Object System.Windows.Forms.Button
    $reportBtn.Text = "📊 Generate Report"
    $reportBtn.Location = New-Object System.Drawing.Point(270, 10)
    $reportBtn.Size = New-Object System.Drawing.Size(120, 30)
    $reportBtn.Add_Click({ & $OnGenerateReport })

    $logsBtn = New-Object System.Windows.Forms.Button
    $logsBtn.Text = "📁 Open Logs"
    $logsBtn.Location = New-Object System.Drawing.Point(400, 10)
    $logsBtn.Size = New-Object System.Drawing.Size(100, 30)
    $logsBtn.Add_Click({ Start-Process explorer.exe -ArgumentList $LogFolder })

    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Text = "Status: Stopped"
    $statusLabel.Location = New-Object System.Drawing.Point(10, 50)
    $statusLabel.Size = New-Object System.Drawing.Size(200, 25)
    $statusLabel.ForeColor = [System.Drawing.Color]::Red
    $statusLabel.Font = New-Object System.Drawing.Font("Arial", 11, [System.Drawing.FontStyle]::Bold)

    # Current activity display
    $infoGroupBox = New-Object System.Windows.Forms.GroupBox
    $infoGroupBox.Text = "Current Activity"
    $infoGroupBox.Location = New-Object System.Drawing.Point(10, 85)
    $infoGroupBox.Size = New-Object System.Drawing.Size(850, 130)

    $processLabel = New-Object System.Windows.Forms.Label
    $processLabel.Text = "Process: N/A"
    $processLabel.Location = New-Object System.Drawing.Point(10, 20)
    $processLabel.Size = New-Object System.Drawing.Size(400, 25)

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "Title: N/A"
    $titleLabel.Location = New-Object System.Drawing.Point(10, 50)
    $titleLabel.Size = New-Object System.Drawing.Size(820, 25)

    $categoryLabel = New-Object System.Windows.Forms.Label
    $categoryLabel.Text = "Category: N/A"
    $categoryLabel.Location = New-Object System.Drawing.Point(10, 80)
    $categoryLabel.Size = New-Object System.Drawing.Size(400, 25)

    $infoGroupBox.Controls.AddRange(@($processLabel, $titleLabel, $categoryLabel))

    # Statistics
    $statsGroupBox = New-Object System.Windows.Forms.GroupBox
    $statsGroupBox.Text = "Today's Statistics"
    $statsGroupBox.Location = New-Object System.Drawing.Point(10, 225)
    $statsGroupBox.Size = New-Object System.Drawing.Size(850, 250)

    $statsLabel = New-Object System.Windows.Forms.Label
    $statsLabel.Text = "Total Time: 0 min`nFocus: 0 min`nDistraction: 0 min`nFocus Score: 0%"
    $statsLabel.Location = New-Object System.Drawing.Point(10, 20)
    $statsLabel.Size = New-Object System.Drawing.Size(830, 220)
    $statsLabel.AutoSize = $true
    $statsLabel.Font = New-Object System.Drawing.Font("Arial", 10)

    $statsGroupBox.Controls.Add($statsLabel)

    $liveTab.Controls.AddRange(@($startBtn, $stopBtn, $reportBtn, $logsBtn, $statusLabel, $infoGroupBox, $statsGroupBox))

    # ===== TAB 2: UNKNOWNS =====
    $unknownsTab = New-Object System.Windows.Forms.TabPage
    $unknownsTab.Text = "Unknown Items"
    $unknownsTab.BackColor = [System.Drawing.Color]::White

    $unknownGrid = New-Object System.Windows.Forms.DataGridView
    $unknownGrid.Location = New-Object System.Drawing.Point(10, 10)
    $unknownGrid.Size = New-Object System.Drawing.Size(850, 300)
    $unknownGrid.AllowUserToAddRows = $false
    $unknownGrid.ReadOnly = $true

    $unknownsTab.Controls.Add($unknownGrid)

    # ===== TAB 3: ANALYTICS =====
    $analyticsTab = New-Object System.Windows.Forms.TabPage
    $analyticsTab.Text = "Analytics"
    $analyticsTab.BackColor = [System.Drawing.Color]::White

    $analyticsRichText = New-Object System.Windows.Forms.RichTextBox
    $analyticsRichText.Location = New-Object System.Drawing.Point(10, 10)
    $analyticsRichText.Size = New-Object System.Drawing.Size(850, 480)
    $analyticsRichText.ReadOnly = $true
    $analyticsRichText.Text = "Top Applications: Loading...`nTime by Category: Loading...`nContext Switches: Loading..."

    $analyticsTab.Controls.Add($analyticsRichText)

    # ===== TAB 4: SETTINGS =====
    $settingsTab = New-Object System.Windows.Forms.TabPage
    $settingsTab.Text = "Settings"
    $settingsTab.BackColor = [System.Drawing.Color]::White

    $config = Get-Content $ConfigPath -Encoding UTF8 | ConvertFrom-Json

    $sampleLabel = New-Object System.Windows.Forms.Label
    $sampleLabel.Text = "Sample Interval (seconds):"
    $sampleLabel.Location = New-Object System.Drawing.Point(10, 10)
    $sampleLabel.Size = New-Object System.Drawing.Size(200, 25)

    $sampleInput = New-Object System.Windows.Forms.TextBox
    $sampleInput.Text = $config.sampleIntervalSeconds
    $sampleInput.Location = New-Object System.Drawing.Point(220, 10)
    $sampleInput.Size = New-Object System.Drawing.Size(100, 25)

    $focusLabel = New-Object System.Windows.Forms.Label
    $focusLabel.Text = "Focus Target (min/day):"
    $focusLabel.Location = New-Object System.Drawing.Point(10, 50)
    $focusLabel.Size = New-Object System.Drawing.Size(200, 25)

    $focusInput = New-Object System.Windows.Forms.TextBox
    $focusInput.Text = $config.focusMinPerDay
    $focusInput.Location = New-Object System.Drawing.Point(220, 50)
    $focusInput.Size = New-Object System.Drawing.Size(100, 25)

    $btnSaveSettings = New-Object System.Windows.Forms.Button
    $btnSaveSettings.Text = "Save Settings"
    $btnSaveSettings.Location = New-Object System.Drawing.Point(10, 100)
    $btnSaveSettings.Size = New-Object System.Drawing.Size(100, 30)
    $btnSaveSettings.Add_Click({
        try {
            $config.sampleIntervalSeconds = [int]$sampleInput.Text
            $config.focusMinPerDay = [int]$focusInput.Text
            $config | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigPath -Encoding UTF8
            [System.Windows.Forms.MessageBox]::Show("Settings saved successfully!", "AFOTRA - Awema Focus Tracker")
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show("Error saving settings: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })

    $settingsTab.Controls.AddRange(@($sampleLabel, $sampleInput, $focusLabel, $focusInput, $btnSaveSettings))

    # Add all tabs
    $tabControl.TabPages.Add($liveTab)
    $tabControl.TabPages.Add($unknownsTab)
    $tabControl.TabPages.Add($analyticsTab)
    $tabControl.TabPages.Add($settingsTab)

    $form.Controls.Add($tabControl)

    return $form
}

Export-ModuleMember -Function New-DashboardForm