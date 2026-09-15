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
if ($manifest -isnot [System.Collections.IDictionary]) {
    throw "PowerShell toolchain validation failed:`n- Manifest root must be an object."
}
foreach ($key in @('schemaVersion', 'powerShell', 'modules')) {
    if (-not $manifest.ContainsKey($key)) {
        $errors.Add("Manifest is missing '$key'.") | Out-Null
    }
}
foreach ($key in @('powerShell', 'modules')) {
    if ($manifest.ContainsKey($key) -and
        $manifest[$key] -isnot [System.Collections.IDictionary]) {
        $errors.Add("Manifest '$key' must be an object.") | Out-Null
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
$pesterVersion = [string]$manifest.modules.Pester
$minimumPowerShellVersion = [string]$manifest.powerShell.minimumVersion

function Get-StaticStringAstValue ([object] $ExpressionAst) {
    while ($ExpressionAst -is
        [Management.Automation.Language.CommandExpressionAst] -or
        $ExpressionAst -is [Management.Automation.Language.ConvertExpressionAst]) {
        $ExpressionAst = if ($ExpressionAst -is
            [Management.Automation.Language.CommandExpressionAst]) {
            $ExpressionAst.Expression
        }
        else { $ExpressionAst.Child }
    }
    if ($ExpressionAst -is
        [Management.Automation.Language.StringConstantExpressionAst]) {
        return [string]$ExpressionAst.Value
    }
    if ($ExpressionAst -is
        [Management.Automation.Language.ExpandableStringExpressionAst] -and
        $ExpressionAst.NestedExpressions.Count -eq 0) {
        return [string]$ExpressionAst.Value
    }
    return $null
}

function Get-CommandParameterValueAst (
    [object[]] $Elements,
    [int] $ParameterIndex) {
    $parameter = $Elements[$ParameterIndex]
    if ($null -ne $parameter.Argument) { return $parameter.Argument }
    if ($ParameterIndex + 1 -lt $Elements.Count -and
        $Elements[$ParameterIndex + 1] -isnot
            [Management.Automation.Language.CommandParameterAst]) {
        return $Elements[$ParameterIndex + 1]
    }
    return $null
}

function Get-CommandModuleTargetAst (
    [Management.Automation.Language.CommandAst] $CommandAst) {
    $elements = @($CommandAst.CommandElements)
    for ($index = 1; $index -lt $elements.Count; $index++) {
        if ($elements[$index] -is
            [Management.Automation.Language.CommandParameterAst] -and
            $elements[$index].ParameterName -in @('Name', 'ModuleName')) {
            return Get-CommandParameterValueAst -Elements $elements `
                -ParameterIndex $index
        }
    }
    $switchParameters = @(
        'AcceptLicense', 'AllowClobber', 'AllowPrerelease', 'AsCustomObject',
        'Confirm', 'Debug', 'DisableNameChecking', 'Force', 'Global',
        'NoClobber', 'PassThru', 'SkipEditionCheck', 'SkipPublisherCheck',
        'UseWindowsPowerShell', 'Verbose', 'WhatIf')
    $skipParameterArgument = $false
    for ($index = 1; $index -lt $elements.Count; $index++) {
        if ($skipParameterArgument) {
            $skipParameterArgument = $false
            continue
        }
        if ($elements[$index] -is
            [Management.Automation.Language.CommandParameterAst]) {
            if ($null -eq $elements[$index].Argument -and
                $elements[$index].ParameterName -notin $switchParameters) {
                $skipParameterArgument = $true
            }
            continue
        }
        return $elements[$index]
    }
    return $null
}

function Get-PesterCommandRecords (
    [Management.Automation.Language.ScriptBlockAst] $Ast,
    [string] $RelativePath,
    [string] $ExpectedVersion,
    [System.Collections.Generic.List[string]] $ErrorList) {
    $commands = @($Ast.FindAll({
                param($node)
                $node -is [Management.Automation.Language.CommandAst]
            }, $true) | Sort-Object { $_.Extent.StartOffset })
    foreach ($commandAst in $commands) {
        $commandName = $commandAst.GetCommandName()
        if ($null -eq $commandName) {
            $staticArguments = @($commandAst.CommandElements |
                Select-Object -Skip 1 | ForEach-Object {
                    Get-StaticStringAstValue -ExpressionAst $_
                } | Where-Object { $null -ne $_ })
            if (@($staticArguments | Where-Object {
                        $_ -ieq 'Pester' -or
                            ([Management.Automation.WildcardPattern]::ContainsWildcardCharacters(
                                $_) -and
                                [Management.Automation.WildcardPattern]::new(
                                    $_,
                                    [Management.Automation.WildcardOptions]::IgnoreCase).IsMatch(
                                    'Pester'))
                    }).Count -gt 0) {
                $ErrorList.Add("'$RelativePath' contains a dynamic command name that cannot be verified statically.") |
                    Out-Null
            }
            continue
        }
        if ($null -ne $commandName -and $commandName.Contains('\')) {
            $commandName = $commandName.Substring(
                $commandName.LastIndexOf('\') + 1)
        }
        if ($commandName -notin @(
                'Install-Module', 'Import-Module', 'ipmo')) { continue }
        $elements = @($commandAst.CommandElements)
        $moduleTarget = Get-CommandModuleTargetAst -CommandAst $commandAst
        $moduleName = Get-StaticStringAstValue -ExpressionAst $moduleTarget
        if ($null -eq $moduleName) {
            $ErrorList.Add("'$RelativePath' contains a module command whose target cannot be verified statically.") |
                Out-Null
            continue
        }
        if ([Management.Automation.WildcardPattern]::ContainsWildcardCharacters(
                $moduleName)) {
            if ([Management.Automation.WildcardPattern]::new(
                    $moduleName,
                    [Management.Automation.WildcardOptions]::IgnoreCase).IsMatch(
                    'Pester')) {
                $ErrorList.Add("'$RelativePath' contains a wildcard module target that cannot be verified statically.") |
                    Out-Null
            }
            continue
        }
        if ($moduleName -ine 'Pester') { continue }
        $versionParameters = @(for ($index = 1;
                $index -lt $elements.Count; $index++) {
                if ($elements[$index] -is
                    [Management.Automation.Language.CommandParameterAst] -and
                    $elements[$index].ParameterName -ieq 'RequiredVersion') {
                    $index
                }
            })
        $pinned = $false
        if ($versionParameters.Count -ne 1) {
            $ErrorList.Add("'$RelativePath' must pin Pester with -RequiredVersion $ExpectedVersion.") |
                Out-Null
        }
        else {
            $versionAst = Get-CommandParameterValueAst -Elements $elements `
                -ParameterIndex $versionParameters[0]
            $version = Get-StaticStringAstValue -ExpressionAst $versionAst
            if ($version -cne $ExpectedVersion) {
                $ErrorList.Add("'$RelativePath' copies Pester version '$version' instead of '$ExpectedVersion'.") |
                    Out-Null
            }
            else { $pinned = $true }
        }
        [pscustomobject]@{ Pinned = $pinned }
    }
}

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
    if ([string]$ast.ScriptRequirements.RequiredPSVersion -cne
        $minimumPowerShellVersion) {
        $relativePath = [IO.Path]::GetRelativePath($resolvedRoot, $testFile.FullName)
        $errors.Add("'$relativePath' must require PowerShell $minimumPowerShellVersion exactly.") |
            Out-Null
    }
    $requirements = @($ast.ScriptRequirements.RequiredModules |
        Where-Object Name -IEQ 'Pester')
    if ($requirements.Count -ne 1 -or
        [string]$requirements[0].Version -cne $pesterVersion -or
        $null -ne $requirements[0].RequiredVersion) {
        $relativePath = [IO.Path]::GetRelativePath($resolvedRoot, $testFile.FullName)
        $errors.Add("'$relativePath' must require Pester $pesterVersion or later.") |
            Out-Null
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
    $pesterVersionParameters = @($runnerAst.ParamBlock.Parameters |
        Where-Object {
            $_.Name.VariablePath.UserPath -ieq 'PesterVersion'
        })
    $runnerDefault = if ($pesterVersionParameters.Count -eq 1) {
        Get-StaticStringAstValue -ExpressionAst (
            $pesterVersionParameters[0].DefaultValue)
    }
    if ($parseErrors.Count -gt 0 -or
        [string]$runnerAst.ScriptRequirements.RequiredPSVersion -cne
            $minimumPowerShellVersion -or
        $pesterVersionParameters.Count -ne 1 -or
        $runnerDefault -cne $pesterVersion) {
        $errors.Add("'tests/Invoke-PesterShards.ps1' must require PowerShell $minimumPowerShellVersion and default PesterVersion to '$pesterVersion'.") |
            Out-Null
    }
}

$parserRoot = Join-Path $resolvedRoot 'tools/powershell-toolchain-validator'
$parserManifestPath = Join-Path $parserRoot 'package.json'
$parserLockPath = Join-Path $parserRoot 'package-lock.json'
$parserPackagePath = Join-Path $parserRoot 'node_modules/yaml/package.json'
$parserScriptPath = Join-Path $parserRoot 'read-workflow-runs.mjs'
$parserVersion = '2.9.1'
$parserIntegrity = 'sha512-3NxN8+78OdzbT7C/WjGsyfPAtJaN3FNDsWxv7Y7mcDsT/oOmgW8BpyQQFFBnvZE3j9Y2Sdz1ULFLezL7Eb2yFw=='
$parserMetadataReady = @(
    $parserManifestPath, $parserLockPath, $parserScriptPath | Where-Object {
        -not (Test-Path -LiteralPath $_ -PathType Leaf)
    }).Count -eq 0
if (-not $parserMetadataReady) {
    $errors.Add("Workflow parser files are missing under '$parserRoot'.") |
        Out-Null
}
else {
    $parserManifest = Get-Content -LiteralPath $parserManifestPath -Raw |
        ConvertFrom-Json -AsHashtable
    $parserLock = Get-Content -LiteralPath $parserLockPath -Raw |
        ConvertFrom-Json -AsHashtable
    if ([string]$parserManifest.dependencies.yaml -cne $parserVersion -or
        [string]$parserLock.packages['node_modules/yaml'].version -cne
            $parserVersion -or
        [string]$parserLock.packages['node_modules/yaml'].integrity -cne
            $parserIntegrity) {
        $errors.Add("Workflow parser metadata must pin yaml $parserVersion exactly.") |
            Out-Null
    }
}
$node = @(Get-Command node -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1)
if (-not $parserMetadataReady -or $node.Count -ne 1 -or
    -not (Test-Path -LiteralPath $parserPackagePath -PathType Leaf)) {
    $errors.Add("Install workflow parser dependencies with 'npm ci --prefix ./tools/powershell-toolchain-validator --ignore-scripts'.") |
        Out-Null
}
else {
    $installedParser = Get-Content -LiteralPath $parserPackagePath -Raw |
        ConvertFrom-Json
    if ([string]$installedParser.version -cne $parserVersion) {
        $errors.Add("Workflow parser must use yaml $parserVersion exactly.") |
            Out-Null
    }
}

$workflowFiles = @(
    $workflowRoot = Join-Path $resolvedRoot '.github/workflows'
    if (Test-Path -LiteralPath $workflowRoot -PathType Container) {
        Get-ChildItem -LiteralPath $workflowRoot -File |
            Where-Object Extension -In @('.yml', '.yaml')
    }
    if (Test-Path -LiteralPath $templateRoot -PathType Container) {
        Get-ChildItem -LiteralPath $templateRoot -File -Recurse |
            Where-Object {
                $_.Name -like '*.yml.tmpl' -or $_.Name -like '*.yaml.tmpl'
            }
    }
)
if ($parserMetadataReady -and $node.Count -eq 1 -and
    (Test-Path -LiteralPath $parserPackagePath -PathType Leaf)) {
    foreach ($workflowFile in $workflowFiles) {
        $relativePath = [IO.Path]::GetRelativePath(
            $resolvedRoot, $workflowFile.FullName)
        $parserOutput = @(& $node[0].Source $parserScriptPath `
                $workflowFile.FullName 2>&1)
        if ($LASTEXITCODE -ne 0) {
            $errors.Add("'$relativePath' is not valid workflow YAML: $($parserOutput -join '; ')") |
                Out-Null
            continue
        }
        try { $runRecords = @(($parserOutput -join "`n") | ConvertFrom-Json) }
        catch {
            $errors.Add("'$relativePath' workflow parser output is invalid JSON: $($_.Exception.Message)") |
                Out-Null
            continue
        }
        foreach ($runRecord in $runRecords | Sort-Object job, step) {
            $shellParts = @([string]$runRecord.shell -split '\s+', 2)
            if ($shellParts.Count -eq 0 -or
                $shellParts[0] -notin @('pwsh', 'powershell')) {
                continue
            }
            $tokens = $null
            $parseErrors = $null
            $runAst = [Management.Automation.Language.Parser]::ParseInput(
                [string]$runRecord.run, [ref]$tokens, [ref]$parseErrors)
            if ($parseErrors.Count -gt 0) {
                $errors.Add("'$relativePath' job '$($runRecord.job)' step $($runRecord.step) contains invalid PowerShell: $($parseErrors -join '; ')") |
                    Out-Null
                continue
            }
            $pesterCommands = @(Get-PesterCommandRecords -Ast $runAst `
                -RelativePath $relativePath -ExpectedVersion $pesterVersion `
                -ErrorList $errors)
            if ($pesterCommands.Count -eq 0) { continue }
            if ($shellParts[0] -ine 'pwsh') {
                $errors.Add("'$relativePath' job '$($runRecord.job)' step $($runRecord.step) contains a Pester command outside a pwsh shell.") |
                    Out-Null
            }
        }
    }
}

$legacyPesterVersion = '5.7' + '.1'
$activeRoots = @('.agents', '.github', 'evals', 'skills', 'tests', 'tools')
$textExtensions = @(
    '.json', '.md', '.ps1', '.psd1', '.psm1', '.tmpl', '.yaml', '.yml')
$inventoryFiles = @(
    foreach ($activeRoot in $activeRoots) {
        $path = Join-Path $resolvedRoot $activeRoot
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }
        Get-ChildItem -LiteralPath $path -File -Recurse |
            Where-Object {
                $_.Extension -in $textExtensions -and
                    $_.FullName -notmatch '[\\/]node_modules[\\/]'
            }
    }
    Get-ChildItem -LiteralPath $resolvedRoot -File |
        Where-Object Extension -In $textExtensions
)
foreach ($file in @($inventoryFiles | Sort-Object FullName -Unique)) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    if ($content.IndexOf(
            $legacyPesterVersion,
            [StringComparison]::Ordinal) -ge 0) {
        $relativePath = [IO.Path]::GetRelativePath(
            $resolvedRoot, $file.FullName)
        $errors.Add("'$relativePath' retains legacy Pester $legacyPesterVersion text.") |
            Out-Null
    }
}

$guidanceContracts = @(
    @{ Path = '.agents/skills/create-skill-repo/SKILL.md'; Pester = "Pester $pesterVersion" }
    @{ Path = 'skills/dotnet-file-creation/SKILL.md'; Pester = 'Pester 6.2 or later' }
    @{ Path = 'skills/windows-acls/SKILL.md'; Pester = 'Pester 6.2 or later' }
)
foreach ($contract in $guidanceContracts) {
    $relativePath = $contract.Path
    $path = Join-Path $resolvedRoot $relativePath
    $content = if (Test-Path -LiteralPath $path -PathType Leaf) {
        Get-Content -LiteralPath $path -Raw
    }
    if ($null -eq $content -or
        $content.IndexOf(
            "PowerShell $minimumPowerShellVersion",
            [StringComparison]::Ordinal) -lt 0 -or
        $content.IndexOf(
            [string]$contract.Pester,
            [StringComparison]::Ordinal) -lt 0) {
        $errors.Add("'$relativePath' must name PowerShell $minimumPowerShellVersion and $($contract.Pester).") |
            Out-Null
    }
}

if ($errors.Count -gt 0) {
    throw "PowerShell toolchain validation failed:`n- $($errors -join "`n- ")"
}

[pscustomobject]@{
    ManifestPath = $manifestPath
    PowerShellVersion = [string]$manifest.powerShell.minimumVersion
    PesterVersion = $pesterVersion
    TestFileCount = $testFiles.Count
}