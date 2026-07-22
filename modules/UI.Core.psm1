# UI.Core.psm1 - Legacy Windows Forms interface helpers for AFOTRA
# Author: CodeScooper
# Project: AFOTRA - Awema Focus Tracker
#
# The main application is dashboard-wpf.ps1. This module remains as a small,
# parse-safe legacy helper for older tests/scripts that import UI.Core.

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
    $form.Text = "AFOTRA - Legacy Dashboard"
    $form.Size = New-Object System.Drawing.Size(900, 700)
    $form.StartPosition = "CenterScreen"

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Dock = [System.Windows.Forms.DockStyle]::Fill

    $liveTab = New-Object System.Windows.Forms.TabPage
    $liveTab.Text = "Live"

    $startBtn = New-Object System.Windows.Forms.Button
    $startBtn.Text = "Start Tracking"
    $startBtn.Location = New-Object System.Drawing.Point(10, 10)
    $startBtn.Size = New-Object System.Drawing.Size(120, 30)

    $stopBtn = New-Object System.Windows.Forms.Button
    $stopBtn.Text = "Stop Tracking"
    $stopBtn.Location = New-Object System.Drawing.Point(140, 10)
    $stopBtn.Size = New-Object System.Drawing.Size(120, 30)
    $stopBtn.Enabled = $false

    $reportBtn = New-Object System.Windows.Forms.Button
    $reportBtn.Text = "Generate Report"
    $reportBtn.Location = New-Object System.Drawing.Point(270, 10)
    $reportBtn.Size = New-Object System.Drawing.Size(130, 30)

    $logsBtn = New-Object System.Windows.Forms.Button
    $logsBtn.Text = "Open Logs"
    $logsBtn.Location = New-Object System.Drawing.Point(410, 10)
    $logsBtn.Size = New-Object System.Drawing.Size(100, 30)

    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Text = "Status: Stopped"
    $statusLabel.Location = New-Object System.Drawing.Point(10, 55)
    $statusLabel.Size = New-Object System.Drawing.Size(250, 25)
    $statusLabel.ForeColor = [System.Drawing.Color]::Red
    $statusLabel.Font = New-Object System.Drawing.Font("Arial", 11, [System.Drawing.FontStyle]::Bold)

    $infoLabel = New-Object System.Windows.Forms.Label
    $infoLabel.Text = "Process: N/A`r`nTitle: N/A`r`nCategory: N/A"
    $infoLabel.Location = New-Object System.Drawing.Point(10, 95)
    $infoLabel.Size = New-Object System.Drawing.Size(840, 100)
    $infoLabel.Font = New-Object System.Drawing.Font("Consolas", 10)

    $startBtn.Add_Click({
        if (-not $global:TrackerState.IsRunning) {
            if ($OnStartTracking) { & $OnStartTracking }
            $global:TrackerState.IsRunning = $true
            $startBtn.Enabled = $false
            $stopBtn.Enabled = $true
            $statusLabel.Text = "Status: Running"
            $statusLabel.ForeColor = [System.Drawing.Color]::Green
        }
    }.GetNewClosure())

    $stopBtn.Add_Click({
        if ($global:TrackerState.IsRunning) {
            if ($OnStopTracking) { & $OnStopTracking }
            $global:TrackerState.IsRunning = $false
            $startBtn.Enabled = $true
            $stopBtn.Enabled = $false
            $statusLabel.Text = "Status: Stopped"
            $statusLabel.ForeColor = [System.Drawing.Color]::Red
        }
    }.GetNewClosure())

    $reportBtn.Add_Click({ if ($OnGenerateReport) { & $OnGenerateReport } }.GetNewClosure())
    $logsBtn.Add_Click({ if ($LogFolder -and (Test-Path $LogFolder)) { Start-Process explorer.exe -ArgumentList $LogFolder } }.GetNewClosure())

    $liveTab.Controls.AddRange(@($startBtn, $stopBtn, $reportBtn, $logsBtn, $statusLabel, $infoLabel))

    foreach ($name in @("Settings", "About")) {
        $tab = New-Object System.Windows.Forms.TabPage
        $tab.Text = $name
        $label = New-Object System.Windows.Forms.Label
        $label.Text = "$name view is maintained in dashboard-wpf.ps1."
        $label.Location = New-Object System.Drawing.Point(10, 10)
        $label.Size = New-Object System.Drawing.Size(500, 25)
        $tab.Controls.Add($label)
        $tabs.TabPages.Add($tab) | Out-Null
    }

    $tabs.TabPages.Insert(0, $liveTab)
    $form.Controls.Add($tabs)
    return $form
}

Export-ModuleMember -Function New-DashboardForm
