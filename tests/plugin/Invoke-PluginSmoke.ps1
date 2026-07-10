#Requires -Version 7.0
[CmdletBinding()]
param(
    [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command copilot -ErrorAction SilentlyContinue)) {
    throw 'copilot CLI is required for the plugin smoke test.'
}

$plugin = Get-Content -LiteralPath (Join-Path $RepoRoot 'plugin.json') -Raw | ConvertFrom-Json
$marketplace = Get-Content -LiteralPath (Join-Path $RepoRoot '.github/plugin/marketplace.json') -Raw | ConvertFrom-Json
$marketplaceName = [string]$marketplace.name
$pluginSpecification = "$($plugin.name)@$marketplaceName"
$expectedSkills = @(Get-ChildItem (Join-Path $RepoRoot 'skills') -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') }).Count
$expectedAgents = @(Get-ChildItem (Join-Path $RepoRoot 'agents') -Filter '*.agent.md' -File).Count
$expectedMcpConfigs = 1

$temporaryHome = Join-Path ([System.IO.Path]::GetTempPath()) "copilot-plugin-smoke-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $temporaryHome | Out-Null

$environmentNames = @('HOME', 'USERPROFILE', 'APPDATA', 'LOCALAPPDATA', 'COPILOT_HOME', 'COPILOT_CACHE_HOME')
$savedEnvironment = @{}
foreach ($environmentName in $environmentNames) {
    $savedEnvironment[$environmentName] = [Environment]::GetEnvironmentVariable($environmentName, 'Process')
}

try {
    $env:HOME = $temporaryHome
    $env:USERPROFILE = $temporaryHome
    $env:APPDATA = Join-Path $temporaryHome 'AppData/Roaming'
    $env:LOCALAPPDATA = Join-Path $temporaryHome 'AppData/Local'
    $env:COPILOT_HOME = Join-Path $temporaryHome '.copilot'
    $env:COPILOT_CACHE_HOME = Join-Path $temporaryHome 'cache'

    $marketplaceOutput = & copilot plugin marketplace add $RepoRoot 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Marketplace registration failed:`n$marketplaceOutput" }

    $installOutput = & copilot plugin install $pluginSpecification 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Plugin install failed:`n$installOutput" }
    $installText = $installOutput -join "`n"
    if ($installText -notmatch "Installed\s+$expectedSkills\s+skills") {
        throw "Plugin install did not report $expectedSkills skills:`n$installText"
    }

    $listOutput = & copilot plugin list 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Plugin list failed:`n$listOutput" }
    if (($listOutput -join "`n") -notmatch [regex]::Escape($pluginSpecification)) {
        throw "Installed plugin list does not contain $pluginSpecification."
    }

    $installedPluginRoot = Join-Path $env:COPILOT_HOME "installed-plugins/$marketplaceName/$($plugin.name)"
    if (-not (Test-Path -LiteralPath $installedPluginRoot -PathType Container)) {
        throw "Installed plugin root not found: $installedPluginRoot`n$installText"
    }

    $installedSkills = @(Get-ChildItem (Join-Path $installedPluginRoot 'skills') -Filter 'SKILL.md' -File -Recurse -FollowSymlink).Count
    $installedAgents = @(Get-ChildItem (Join-Path $installedPluginRoot 'agents') -Filter '*.agent.md' -File -Recurse -FollowSymlink).Count
    $installedMcpConfigs = [int](Test-Path -LiteralPath (Join-Path $installedPluginRoot '.mcp.json') -PathType Leaf)

    if ($installedSkills -ne $expectedSkills) {
        throw "Plugin installed $installedSkills skills; expected $expectedSkills."
    }
    if ($installedAgents -ne $expectedAgents) {
        throw "Plugin installed $installedAgents agents; expected $expectedAgents."
    }
    if ($installedMcpConfigs -ne $expectedMcpConfigs) {
        throw "Plugin installed $installedMcpConfigs MCP configs; expected $expectedMcpConfigs."
    }

    Write-Host "Plugin smoke passed: $installedSkills skills, $installedAgents agents, $installedMcpConfigs MCP config."
}
finally {
    foreach ($environmentName in $environmentNames) {
        $savedValue = $savedEnvironment[$environmentName]
        if ($null -eq $savedValue) {
            Remove-Item "Env:$environmentName" -ErrorAction SilentlyContinue
        }
        else {
            [Environment]::SetEnvironmentVariable($environmentName, $savedValue, 'Process')
        }
    }
    Remove-Item $temporaryHome -Recurse -Force -ErrorAction SilentlyContinue
}