#Requires -Version 7.0
[CmdletBinding()]
param(
    [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,

    [Parameter(Mandatory)]
    [string] $CopilotPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-NativeExecutable ([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    if (-not $IsWindows) {
        try { $mode = [System.IO.File]::GetUnixFileMode($Path) }
        catch { return $false }
        $executeBits = [int](
            [System.IO.UnixFileMode]::UserExecute -bor
            [System.IO.UnixFileMode]::GroupExecute -bor
            [System.IO.UnixFileMode]::OtherExecute)
        if (([int]$mode -band $executeBits) -eq 0) { return $false }
    }
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $header = [byte[]]::new(4)
        $read = $stream.Read($header, 0, $header.Length)
    }
    finally { $stream.Dispose() }

    if ($IsWindows) {
        return $read -ge 2 -and $header[0] -eq 0x4D -and $header[1] -eq 0x5A
    }
    if ($IsLinux) {
        return $read -eq 4 -and $header[0] -eq 0x7F -and
            $header[1] -eq 0x45 -and $header[2] -eq 0x4C -and $header[3] -eq 0x46
    }
    if ($IsMacOS) {
        $signature = @($header | ForEach-Object { $_.ToString('X2') }) -join ''
        return $read -eq 4 -and $signature -in @(
            'FEEDFACE', 'FEEDFACF', 'CEFAEDFE', 'CFFAEDFE',
            'CAFEBABE', 'BEBAFECA', 'CAFEBABF', 'BFBAFECA')
    }
    return $false
}

$resolvedCopilotPath = (Resolve-Path -LiteralPath $CopilotPath -ErrorAction Stop).Path
$expectedName = if ($IsWindows) { 'copilot.exe' } else { 'copilot' }
if ([System.IO.Path]::GetFileName($resolvedCopilotPath) -cne $expectedName) {
    throw "Copilot CLI path must name '$expectedName': $resolvedCopilotPath"
}
if (-not (Test-NativeExecutable $resolvedCopilotPath)) {
    throw "Copilot CLI path is not a native executable for this host: $resolvedCopilotPath"
}
$copilotExecutableSha256 = (Get-FileHash -LiteralPath $resolvedCopilotPath -Algorithm SHA256).Hash

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

$environmentNames = @('HOME', 'USERPROFILE', 'APPDATA', 'LOCALAPPDATA', 'COPILOT_HOME', 'COPILOT_CACHE_HOME', 'COPILOT_AUTO_UPDATE')
$savedEnvironment = @{}
foreach ($environmentName in $environmentNames) {
    $savedEnvironment[$environmentName] = [Environment]::GetEnvironmentVariable($environmentName, 'Process')
}

try {
    $env:HOME = $temporaryHome
    $env:USERPROFILE = $temporaryHome
    $appDataRoot = Join-Path $temporaryHome 'AppData'
    $env:APPDATA = Join-Path $appDataRoot 'Roaming'
    $env:LOCALAPPDATA = Join-Path $appDataRoot 'Local'
    $env:COPILOT_HOME = Join-Path $temporaryHome '.copilot'
    $env:COPILOT_CACHE_HOME = Join-Path $temporaryHome 'cache'
    $env:COPILOT_AUTO_UPDATE = 'false'

    $versionOutput = @(& $resolvedCopilotPath --version 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Copilot CLI version query failed:`n$($versionOutput -join [Environment]::NewLine)"
    }
    $copilotVersion = ($versionOutput -join [Environment]::NewLine).Trim()
    if ($copilotVersion -notmatch '^GitHub Copilot CLI \d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?(?:\.|\s|$)') {
        throw "Selected executable did not identify itself as GitHub Copilot CLI: $copilotVersion"
    }
    if ((Get-FileHash -LiteralPath $resolvedCopilotPath -Algorithm SHA256).Hash -cne
        $copilotExecutableSha256) {
        throw 'The selected Copilot CLI executable changed during version verification.'
    }

    $marketplaceOutput = & $resolvedCopilotPath plugin marketplace add $RepoRoot 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Marketplace registration failed:`n$marketplaceOutput" }

    $installOutput = & $resolvedCopilotPath plugin install $pluginSpecification 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Plugin install failed:`n$installOutput" }
    $installText = $installOutput -join "`n"
    if ($installText -notmatch "Installed\s+$expectedSkills\s+skills") {
        throw "Plugin install did not report $expectedSkills skills:`n$installText"
    }

    $listOutput = & $resolvedCopilotPath plugin list 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Plugin list failed:`n$listOutput" }
    if (($listOutput -join "`n") -notmatch [regex]::Escape($pluginSpecification)) {
        throw "Installed plugin list does not contain $pluginSpecification."
    }

    $installedPluginsRoot = Join-Path $env:COPILOT_HOME 'installed-plugins'
    $marketplaceRoot = Join-Path $installedPluginsRoot $marketplaceName
    $installedPluginRoot = Join-Path $marketplaceRoot $plugin.name
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

    if ((Get-FileHash -LiteralPath $resolvedCopilotPath -Algorithm SHA256).Hash -cne
        $copilotExecutableSha256) {
        throw 'The selected Copilot CLI executable changed during the plugin smoke test.'
    }
    Write-Host "Copilot CLI: $(($copilotVersion -split '\r?\n')[0])"
    Write-Host "Copilot executable SHA-256: $copilotExecutableSha256"
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