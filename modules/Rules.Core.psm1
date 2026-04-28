# Rules.Core.psm1 - Core functions for rules management and activity classification
# Author: CodeScooper
# Project: AFOTRA - Awema Focus Tracker

function Load-Rules {
    param (
        [string]$RulesPath
    )
    if (Test-Path $RulesPath) {
        try {
            $rules = Get-Content $RulesPath -Encoding UTF8 | ConvertFrom-Json
            return $rules
        }
        catch {
            Write-Warning "Failed to load rules from $RulesPath. Using default rules."
            return Get-DefaultRules
        }
    }
    else {
        Write-Warning "Rules file not found at $RulesPath. Using default rules."
        return Get-DefaultRules
    }
}

function Get-DefaultRules {
    return @{
        categories = @("travail", "etude", "communication", "distraction", "inconnu")
        processRules = @()
        titleRules = @()
    }
}

function Classify-Activity {
    param (
        [string]$ProcessName,
        [string]$WindowTitle,
        [object]$Rules
    )

    # For browsers, title rules have priority (a YouTube tab must beat "chrome → travail")
    $browserProcesses = @("chrome", "msedge", "firefox", "brave", "opera", "vivaldi", "iexplore")
    $isBrowser = $false
    foreach ($b in $browserProcesses) {
        if ($ProcessName -like "*$b*") { $isBrowser = $true; break }
    }

    if (-not $isBrowser) {
        # Non-browser apps: process name is the most reliable signal → check first
        foreach ($rule in $Rules.processRules) {
            if ($ProcessName -like "*$($rule.process)*") { return $rule.category }
        }
    }

    # Title rules (checked for everyone; for browsers these take priority)
    foreach ($rule in $Rules.titleRules) {
        if ($WindowTitle -like "*$($rule.contains)*") { return $rule.category }
    }

    # Fallback: process rule (catches browsers with no matching title rule)
    foreach ($rule in $Rules.processRules) {
        if ($ProcessName -like "*$($rule.process)*") { return $rule.category }
    }

    return "inconnu"
}

function Get-ChromeTopDomains {
    param ([int]$Top = 50)

    $histPath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\History"
    if (-not (Test-Path $histPath)) { return @() }

    $tmpPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "afotra_chrome_$(Get-Date -Format 'yyyyMMddHHmmss').db")
    try {
        # Copy the file to avoid Chrome's lock
        [System.IO.File]::Copy($histPath, $tmpPath, $true)

        # SQLite stores text as UTF-8 – extract all URL-like strings from the binary
        $bytes  = [System.IO.File]::ReadAllBytes($tmpPath)
        $text   = [System.Text.Encoding]::UTF8.GetString($bytes)

        $pattern = 'https?://([a-zA-Z0-9][a-zA-Z0-9\-]{0,61}(?:\.[a-zA-Z0-9][a-zA-Z0-9\-]{0,61})*\.[a-zA-Z]{2,})'
        $allMatches = [regex]::Matches($text, $pattern)

        $domains = $allMatches |
            ForEach-Object { $_.Groups[1].Value.ToLower() } |
            Where-Object   { $_ -match '\.' -and $_.Length -lt 80 } |
            Group-Object   |
            Sort-Object    Count -Descending |
            Select-Object  -First $Top |
            ForEach-Object { [PSCustomObject]@{ Domain = $_.Name; Count = $_.Count; Category = "" } }

        return $domains
    }
    catch { return @() }
    finally { Remove-Item $tmpPath -ErrorAction SilentlyContinue }
}

function Save-Rules {
    param (
        [object]$Rules,
        [string]$RulesPath
    )
    try {
        $Rules | ConvertTo-Json -Depth 10 | Set-Content -Path $RulesPath -Encoding UTF8 -Force
    }
    catch {
        Write-Error "Failed to save rules to $RulesPath."
    }
}

function Get-Categories {
    param (
        [object]$Rules
    )
    return $Rules.categories
}

function Add-Category {
    param (
        [object]$Rules,
        [string]$Category
    )
    if ($Rules.categories -notcontains $Category) {
        $Rules.categories += $Category
        return $true
    }
    return $false
}

function Add-ProcessRule {
    param (
        [object]$Rules,
        [string]$Process,
        [string]$Category
    )
    $Rules.processRules += @{ process = $Process; category = $Category }
}

function Add-TitleRule {
    param (
        [object]$Rules,
        [string]$Contains,
        [string]$Category
    )
    $Rules.titleRules += @{ contains = $Contains; category = $Category }
}

Export-ModuleMember -Function Load-Rules, Get-DefaultRules, Classify-Activity, Save-Rules, Get-Categories, Add-Category, Add-ProcessRule, Add-TitleRule, Get-ChromeTopDomains