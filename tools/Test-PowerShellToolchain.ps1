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

if ($manifest.schemaVersion -isnot [long] -or $manifest.schemaVersion -ne 1) {
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

$minimumPowerShellVersion = [string]$manifest.powerShell.minimumVersion
$minimumPowerShell = $null
$minimumPowerShellIsValid = $manifest.powerShell.minimumVersion -is [string] -and
    [version]::TryParse($minimumPowerShellVersion, [ref]$minimumPowerShell)
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
        continue
    }
    $hostVersionText = [string]$hostLane.powerShellVersion
    if ($hostVersionText -ceq 'latest-stable') {
        if ($hostName -cne 'scheduled') {
            $errors.Add("Manifest host '$hostName' cannot use the 'latest-stable' selector.") |
                Out-Null
        }
        continue
    }
    $hostVersion = $null
    if (-not [version]::TryParse($hostVersionText, [ref]$hostVersion)) {
        $errors.Add("Manifest host '$hostName' PowerShell version must be numeric or 'latest-stable'.") |
            Out-Null
    }
    elseif ($minimumPowerShellIsValid -and $hostVersion -lt $minimumPowerShell) {
        $errors.Add("Manifest host '$hostName' PowerShell version must be at least $minimumPowerShellVersion.") |
            Out-Null
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
$templateRoot = Join-Path $resolvedRoot '.agents'
$testTemplates = if (Test-Path -LiteralPath $templateRoot -PathType Container) {
    @(Get-ChildItem -LiteralPath $templateRoot -Filter '*.Tests.ps1.tmpl' -File -Recurse)
}
else { @() }
foreach ($testFile in @($testFiles) + @($testTemplates)) {
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile(
        $testFile.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        $relativePath = [IO.Path]::GetRelativePath($resolvedRoot, $testFile.FullName)
        $errors.Add("'$relativePath' does not parse: $($parseErrors -join '; ')") | Out-Null
        continue
    }
    if ([string]$ast.ScriptRequirements.RequiredPSVersion -cne $minimumPowerShellVersion) {
        $relativePath = [IO.Path]::GetRelativePath($resolvedRoot, $testFile.FullName)
        $errors.Add("'$relativePath' must require PowerShell $minimumPowerShellVersion exactly.") | Out-Null
    }
    $requirements = @($ast.ScriptRequirements.RequiredModules |
        Where-Object Name -CEQ 'Pester')
    if ($requirements.Count -ne 1 -or
        [string]$requirements[0].RequiredVersion -cne $pesterVersion) {
        $relativePath = [IO.Path]::GetRelativePath($resolvedRoot, $testFile.FullName)
        $errors.Add("'$relativePath' must require Pester $pesterVersion exactly.") | Out-Null
    }
}

$runnerPath = Join-Path $resolvedRoot 'tests/Invoke-PesterShards.ps1'
if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf)) {
    $errors.Add("'tests/Invoke-PesterShards.ps1' must exist.") | Out-Null
}
else {
    $tokens = $null
    $parseErrors = $null
    $runnerAst = [Management.Automation.Language.Parser]::ParseFile(
        $runnerPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        $errors.Add("'tests/Invoke-PesterShards.ps1' does not parse: $($parseErrors -join '; ')") |
            Out-Null
    }
    elseif ([string]$runnerAst.ScriptRequirements.RequiredPSVersion -cne
        $minimumPowerShellVersion) {
        $errors.Add("'tests/Invoke-PesterShards.ps1' must require PowerShell $minimumPowerShellVersion exactly.") |
            Out-Null
    }
}

$activeRoots = @('.agents', '.github', 'evals', 'skills', 'tests', 'tools')
$versionPatterns = @(
    '(?i)-PesterVersion\s+(?<version>[^\s`''"]+)',
    '(?i)PesterVersion\s*=\s*[''"](?<version>[^''"]+)[''"]'
)
$moduleRequirementPattern =
    '(?i)ModuleName\s*=\s*[''"]Pester[''"][^}\r\n]*(?<constraint>RequiredVersion|ModuleVersion)\s*=\s*[''"](?<version>[^''"]+)[''"]'
$moduleCommandPattern =
    '(?i)(?:Install-Module|Import-Module)\s+(?:-Name\s+)?Pester\b(?<arguments>[^\r\n]*)'
$requiredVersionSwitchPattern = '(?i)(?:^|\s)-RequiredVersion(?:\s+|$)'
$requiredVersionValuePattern =
    '(?i)(?:^|\s)-RequiredVersion\s+(?<value>''[^'']*''|"[^"]*"|[^\s`]+)'
$invokePesterName = 'Invoke' + '-Pester'
$invokePesterPattern = "(?i)\b$invokePesterName\b"
$importPesterPattern = '(?i)Import-Module\s+(?:-Name\s+)?Pester\b'
$scanFiles = @(
    foreach ($activeRoot in $activeRoots) {
        $path = Join-Path $resolvedRoot $activeRoot
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }
        Get-ChildItem -LiteralPath $path -File -Recurse |
            Where-Object Extension -In @('.md', '.ps1', '.psm1', '.psd1', '.yml', '.yaml', '.tmpl')
    }
    Get-ChildItem -LiteralPath $resolvedRoot -Filter '*.md' -File
)
foreach ($file in @($scanFiles | Sort-Object FullName -Unique)) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    $relativePath = [IO.Path]::GetRelativePath($resolvedRoot, $file.FullName)
    $normalizedPath = $relativePath.Replace('\', '/')
    foreach ($commandMatch in [regex]::Matches($content, $moduleCommandPattern)) {
        $arguments = $commandMatch.Groups['arguments'].Value
        if ($arguments -notmatch $requiredVersionSwitchPattern) {
            $errors.Add("'$relativePath' invokes Pester without -RequiredVersion $pesterVersion.") |
                Out-Null
            continue
        }
        $versionMatch = [regex]::Match($arguments, $requiredVersionValuePattern)
        if (-not $versionMatch.Success) {
            $errors.Add("'$relativePath' has an invalid Pester -RequiredVersion value.") | Out-Null
            continue
        }
        $requiredVersionValue = $versionMatch.Groups['value'].Value
        if (($requiredVersionValue.StartsWith("'") -and $requiredVersionValue.EndsWith("'")) -or
            ($requiredVersionValue.StartsWith('"') -and $requiredVersionValue.EndsWith('"'))) {
            $requiredVersionValue = $requiredVersionValue.Substring(
                1, $requiredVersionValue.Length - 2)
        }
        $isRunnerParameter = $normalizedPath -ceq 'tests/Invoke-PesterShards.ps1' -and
            $requiredVersionValue -ceq '$PesterVersion'
        if (-not $isRunnerParameter -and $requiredVersionValue -cne $pesterVersion) {
            $errors.Add("'$relativePath' copies Pester version '$requiredVersionValue' instead of '$pesterVersion'.") |
                Out-Null
        }
    }
    foreach ($versionPattern in $versionPatterns) {
        foreach ($match in [regex]::Matches($content, $versionPattern)) {
            if ($match.Groups['version'].Value -cne $pesterVersion) {
                $errors.Add("'$relativePath' copies Pester version '$($match.Groups['version'].Value)' instead of '$pesterVersion'.") |
                    Out-Null
            }
        }
    }
    foreach ($match in [regex]::Matches($content, $moduleRequirementPattern)) {
        if ($match.Groups['constraint'].Value -cne 'RequiredVersion') {
            $errors.Add("'$relativePath' must use RequiredVersion for its Pester module requirement.") |
                Out-Null
        }
        if ($match.Groups['version'].Value -cne $pesterVersion) {
            $errors.Add("'$relativePath' copies Pester version '$($match.Groups['version'].Value)' instead of '$pesterVersion'.") |
                Out-Null
        }
    }
    $isPinnedTest = $normalizedPath -like 'tests/*.Tests.ps1'
    foreach ($invokeMatch in [regex]::Matches($content, $invokePesterPattern)) {
        if ($isPinnedTest) { continue }
        $priorContent = $content.Substring(0, $invokeMatch.Index)
        if ($priorContent -notmatch $importPesterPattern) {
            $errors.Add("'$relativePath' invokes $invokePesterName without a preceding pinned Pester import.") |
                Out-Null
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
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $errors.Add("'$relativePath' must name PowerShell $minimumPowerShellVersion and Pester $pesterVersion.") | Out-Null
        continue
    }
    $content = Get-Content -LiteralPath $path -Raw
    $powerShellPattern =
        "PowerShell $([regex]::Escape($minimumPowerShellVersion))(?![0-9A-Za-z-]|\.[0-9A-Za-z])"
    $pesterPattern =
        "Pester $([regex]::Escape($pesterVersion))(?![0-9A-Za-z-]|\.[0-9A-Za-z])"
    if ($content -notmatch $powerShellPattern) {
        $errors.Add("'$relativePath' must name PowerShell $minimumPowerShellVersion.") | Out-Null
    }
    if ($content -notmatch $pesterPattern) {
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