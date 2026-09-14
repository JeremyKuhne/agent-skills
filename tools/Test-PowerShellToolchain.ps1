#Requires -Version 7.4
[CmdletBinding(PositionalBinding = $false)]
param(
    [string] $RepositoryRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$resolvedRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$manifestPath = Join-Path $resolvedRoot 'tools/powershell-toolchain.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "PowerShell toolchain manifest was not found: $manifestPath"
}

try {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw |
        ConvertFrom-Json -AsHashtable
}
catch {
    throw "PowerShell toolchain manifest is not valid JSON: $($_.Exception.Message)"
}

$errors = [System.Collections.Generic.List[string]]::new()
foreach ($key in @('schemaVersion', 'powerShell', 'modules', 'hosts', 'dotnet')) {
    if (-not $manifest.ContainsKey($key)) {
        $errors.Add("Manifest is missing '$key'.") | Out-Null
    }
}
if ($errors.Count -gt 0) {
    throw "PowerShell toolchain validation failed:`n- $($errors -join "`n- ")"
}

if ($manifest.schemaVersion -ne 1) {
    $errors.Add("Manifest schemaVersion must be the integer 1.") | Out-Null
}

$versionValues = [ordered]@{
    'powerShell.minimumVersion' = $manifest.powerShell.minimumVersion
    'modules.Pester' = $manifest.modules.Pester
    'modules.PSScriptAnalyzer' = $manifest.modules.PSScriptAnalyzer
    'dotnet.languageVersion' = $manifest.dotnet.languageVersion
}
foreach ($entry in $versionValues.GetEnumerator()) {
    $parsedVersion = $null
    if ($entry.Value -isnot [string] -or
        -not [version]::TryParse($entry.Value, [ref]$parsedVersion)) {
        $errors.Add("Manifest '$($entry.Key)' must be a version string.") | Out-Null
    }
}
if ($manifest.modules.Pester -notmatch '^\d+\.\d+\.\d+$') {
    $errors.Add("Manifest 'modules.Pester' must be an exact three-part version.") | Out-Null
}
if ($manifest.modules.PSScriptAnalyzer -notmatch '^\d+\.\d+\.\d+$') {
    $errors.Add("Manifest 'modules.PSScriptAnalyzer' must be an exact three-part version.") | Out-Null
}
if ($manifest.dotnet.sdkVersion -isnot [string] -or
    $manifest.dotnet.sdkVersion -notmatch '^\d+\.\d+\.x$') {
    $errors.Add("Manifest 'dotnet.sdkVersion' must be a feature-band selector such as '10.0.x'.") | Out-Null
}

foreach ($hostName in @('primary', 'windows', 'scheduled')) {
    if (-not $manifest.hosts.ContainsKey($hostName)) {
        $errors.Add("Manifest is missing the '$hostName' host lane.") | Out-Null
        continue
    }
    $hostLane = $manifest.hosts[$hostName]
    if ($hostLane.operatingSystem -isnot [string] -or
        [string]::IsNullOrWhiteSpace($hostLane.operatingSystem)) {
        $errors.Add("Manifest host '$hostName' must name an operating system.") | Out-Null
    }
    if ($hostLane.powerShellVersion -isnot [string] -or
        [string]::IsNullOrWhiteSpace($hostLane.powerShellVersion)) {
        $errors.Add("Manifest host '$hostName' must name a PowerShell version.") | Out-Null
    }
}

$pesterVersion = [string]$manifest.modules.Pester
$testRoot = Join-Path $resolvedRoot 'tests'
$testFiles = if (Test-Path -LiteralPath $testRoot -PathType Container) {
    @(Get-ChildItem -LiteralPath $testRoot -Filter '*.Tests.ps1' -File -Recurse)
}
else { @() }
if ($testFiles.Count -eq 0) {
    $errors.Add('No Pester test files were found.') | Out-Null
}
foreach ($testFile in $testFiles) {
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile(
        $testFile.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        $relativePath = [IO.Path]::GetRelativePath($resolvedRoot, $testFile.FullName)
        $errors.Add("'$relativePath' does not parse: $($parseErrors -join '; ')") | Out-Null
        continue
    }
    $requirements = @($ast.ScriptRequirements.RequiredModules |
        Where-Object Name -CEQ 'Pester')
    if ($requirements.Count -ne 1 -or
        [string]$requirements[0].RequiredVersion -cne $pesterVersion) {
        $relativePath = [IO.Path]::GetRelativePath($resolvedRoot, $testFile.FullName)
        $errors.Add("'$relativePath' must require Pester $pesterVersion exactly.") | Out-Null
    }
}

$activeRoots = @('.agents', '.github', 'evals', 'skills', 'tests', 'tools')
$versionPatterns = @(
    '(?i)(?:Install-Module|Import-Module)\s+(?:-Name\s+)?Pester\b[^\r\n]*?-RequiredVersion\s+(?<version>\d+\.\d+\.\d+)',
    '(?i)-PesterVersion\s+(?<version>\d+\.\d+\.\d+)',
    '(?i)PesterVersion\s*=\s*[''"](?<version>\d+\.\d+\.\d+)',
    '(?i)ModuleName\s*=\s*[''"]Pester[''"][^}\r\n]*(?:RequiredVersion|ModuleVersion)\s*=\s*[''"](?<version>\d+\.\d+\.\d+)'
)
foreach ($activeRoot in $activeRoots) {
    $path = Join-Path $resolvedRoot $activeRoot
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }
    foreach ($file in Get-ChildItem -LiteralPath $path -File -Recurse |
        Where-Object Extension -In @('.md', '.ps1', '.psm1', '.psd1', '.yml', '.yaml', '.tmpl')) {
        $content = Get-Content -LiteralPath $file.FullName -Raw
        foreach ($versionPattern in $versionPatterns) {
            foreach ($match in [regex]::Matches($content, $versionPattern)) {
                if ($match.Groups['version'].Value -cne $pesterVersion) {
                    $relativePath = [IO.Path]::GetRelativePath($resolvedRoot, $file.FullName)
                    $errors.Add("'$relativePath' copies Pester version '$($match.Groups['version'].Value)' instead of '$pesterVersion'.") | Out-Null
                }
            }
        }
    }
}

$guidancePaths = @(
    '.agents/skills/create-skill-repo/SKILL.md',
    'skills/dotnet-file-creation/SKILL.md',
    'skills/windows-acls/SKILL.md'
)
foreach ($relativePath in $guidancePaths) {
    $path = Join-Path $resolvedRoot $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-Content -LiteralPath $path -Raw) -notmatch "Pester $([regex]::Escape($pesterVersion))") {
        $errors.Add("'$relativePath' must name Pester $pesterVersion.") | Out-Null
    }
}

if ($errors.Count -gt 0) {
    throw "PowerShell toolchain validation failed:`n- $($errors -join "`n- ")"
}

[pscustomobject]@{
    ManifestPath = $manifestPath
    PowerShellVersion = [string]$manifest.powerShell.minimumVersion
    PesterVersion = $pesterVersion
    PSScriptAnalyzerVersion = [string]$manifest.modules.PSScriptAnalyzer
    TestFileCount = $testFiles.Count
}