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
    
    # Check process rules first (case-insensitive)
    foreach ($rule in $Rules.processRules) {
        if ($ProcessName -like "*$($rule.process)*") {
            return $rule.category
        }
    }
    
    # Check title rules
    foreach ($rule in $Rules.titleRules) {
        if ($WindowTitle -like "*$($rule.contains)*") {
            return $rule.category
        }
    }
    
    # Default to inconnu
    return "inconnu"
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

Export-ModuleMember -Function Load-Rules, Get-DefaultRules, Classify-Activity, Save-Rules, Get-Categories, Add-Category, Add-ProcessRule, Add-TitleRule