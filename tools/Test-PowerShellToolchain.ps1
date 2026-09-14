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
    $errors.Add('Manifest root must be an object.') | Out-Null
}
else {
    foreach ($key in @('schemaVersion', 'powerShell', 'modules', 'hosts', 'dotnet')) {
        if (-not $manifest.ContainsKey($key)) {
            $errors.Add("Manifest is missing '$key'.") | Out-Null
        }
    }
    foreach ($key in @('powerShell', 'modules', 'hosts', 'dotnet')) {
        if ($manifest.ContainsKey($key) -and
            $manifest[$key] -isnot [System.Collections.IDictionary]) {
            $errors.Add("Manifest '$key' must be an object.") | Out-Null
        }
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
if ($manifest.dotnet.previewSdkVersion -isnot [string] -or
    $manifest.dotnet.previewSdkVersion -notmatch '^\d+\.\d+\.x$') {
    $errors.Add("Manifest 'dotnet.previewSdkVersion' must be a feature-band selector such as '11.0.x'.") |
        Out-Null
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
    if ($hostLane -isnot [System.Collections.IDictionary]) {
        $errors.Add("Manifest host '$hostName' must be an object.") | Out-Null
        continue
    }
    if ($hostLane.operatingSystem -isnot [string] -or
        [string]::IsNullOrWhiteSpace($hostLane.operatingSystem)) {
        $errors.Add("Manifest host '$hostName' must name an operating system.") | Out-Null
    }
    if ($hostLane.minimumPowerShellVersion -isnot [string] -or
        [string]::IsNullOrWhiteSpace($hostLane.minimumPowerShellVersion)) {
        $errors.Add("Manifest host '$hostName' must name a minimum PowerShell version.") |
            Out-Null
        continue
    }
    $hostVersionText = [string]$hostLane.minimumPowerShellVersion
    $hostVersion = $null
    if (-not [version]::TryParse($hostVersionText, [ref]$hostVersion)) {
        $errors.Add("Manifest host '$hostName' minimum PowerShell version must be numeric.") |
            Out-Null
    }
    elseif ($minimumPowerShellIsValid -and $hostVersion -lt $minimumPowerShell) {
        $errors.Add("Manifest host '$hostName' PowerShell version must be at least $minimumPowerShellVersion.") |
            Out-Null
    }
    if ($hostName -ceq 'scheduled') {
        if ($hostLane.channel -cne 'latest-stable') {
            $errors.Add("Manifest scheduled host channel must be 'latest-stable'.") | Out-Null
        }
    }
    elseif ($hostLane.ContainsKey('channel')) {
        $errors.Add("Manifest host '$hostName' cannot define a PowerShell channel.") | Out-Null
    }
}

$pesterVersion = [string]$manifest.modules.Pester
$pesterSemanticVersion = $null
$pesterVersionIsValid = $manifest.modules.Pester -is [string] -and
    [version]::TryParse($pesterVersion, [ref]$pesterSemanticVersion)
$portablePesterFloor = if ($pesterVersionIsValid) {
    "$($pesterSemanticVersion.Major).$($pesterSemanticVersion.Minor)"
}
else { $pesterVersion }

function Get-StaticStringAstValue ([object] $ExpressionAst) {
    while ($ExpressionAst -is
        [Management.Automation.Language.ConvertExpressionAst]) {
        $ExpressionAst = $ExpressionAst.Child
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
        Where-Object Name -IEQ 'Pester')
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
    else {
        if ([string]$runnerAst.ScriptRequirements.RequiredPSVersion -cne
            $minimumPowerShellVersion) {
            $errors.Add("'tests/Invoke-PesterShards.ps1' must require PowerShell $minimumPowerShellVersion exactly.") |
                Out-Null
        }
        $pesterVersionParameters = @($runnerAst.ParamBlock.Parameters |
            Where-Object { $_.Name.VariablePath.UserPath -ieq 'PesterVersion' })
        $runnerDefault = if ($pesterVersionParameters.Count -eq 1) {
            Get-StaticStringAstValue -ExpressionAst (
                $pesterVersionParameters[0].DefaultValue)
        }
        if ($pesterVersionParameters.Count -ne 1 -or
            $runnerDefault -cne $pesterVersion) {
            $errors.Add("'tests/Invoke-PesterShards.ps1' PesterVersion default must be '$pesterVersion'.") |
                Out-Null
        }
    }
}

function ConvertFrom-WorkflowRunScalar ([string] $Text) {
    $trimmed = $Text.Trim()
    if ($trimmed.StartsWith("'")) {
        $innerText = $trimmed.Substring(1)
        if ($trimmed.Length -gt 1 -and $trimmed.EndsWith("'")) {
            $innerText = $innerText.Substring(0, $innerText.Length - 1)
        }
        return $innerText.Replace("''", "'")
    }
    if ($trimmed.StartsWith('"')) {
        $jsonText = if ($trimmed.Length -gt 1 -and $trimmed.EndsWith('"')) {
            $trimmed
        }
        else { $trimmed + '"' }
        try { return [Text.Json.JsonSerializer]::Deserialize[string]($jsonText) }
        catch { return $trimmed.Substring(1) }
    }
    return $Text
}

function Get-WorkflowRunScope ([string] $Content, [int] $Position) {
    $lines = @([regex]::Matches($Content, '(?m)^.*(?:\r?\n|$)'))
    $targetLine = 0
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($Position -le $lines[$index].Index + $lines[$index].Length) {
            $targetLine = $index
            break
        }
    }
    for ($index = $targetLine; $index -ge 0; $index--) {
        $line = $lines[$index].Value.TrimEnd("`r", "`n")
        $runMatch = [regex]::Match(
            $line, '^(?<indent>\s*)(?:-\s+)?run:\s*(?<value>.*)$')
        if (-not $runMatch.Success) { continue }
        $indent = $runMatch.Groups['indent'].Length
        $value = $runMatch.Groups['value'].Value
        if ($index -eq $targetLine -and $value -notmatch '^[|>]') {
            $scopeStart = $lines[$index].Index + $runMatch.Groups['value'].Index
            return ConvertFrom-WorkflowRunScalar $Content.Substring(
                $scopeStart, $Position - $scopeStart)
        }
        $endLine = $index + 1
        while ($endLine -lt $lines.Count) {
            $candidate = $lines[$endLine].Value.TrimEnd("`r", "`n")
            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                $candidateIndent = $candidate.Length - $candidate.TrimStart().Length
                if ($candidateIndent -le $indent) { break }
            }
            $endLine++
        }
        if ($targetLine -lt $endLine) {
            $scopeStart = $lines[$index + 1].Index
            return $Content.Substring(
                $scopeStart, $Position - $scopeStart)
        }
        break
    }
    return $null
}

function Get-ToolchainWorkflowJobBody ([string] $Content, [string] $JobName) {
    $escapedJobName = [regex]::Escape($JobName)
    $match = [regex]::Match(
        $Content,
        "(?ms)^  ${escapedJobName}:\r?\n(?<body>.*?)(?=^  [a-z0-9-]+:\r?$|\z)")
    if (-not $match.Success) { return $null }
    return $match.Groups['body'].Value
}

function Test-WorkflowPwshStepCommand (
    [string] $JobBody,
    [string] $CommandPattern) {
    $lines = @([regex]::Matches($JobBody, '(?m)^.*(?:\r?\n|$)'))
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index].Value.TrimEnd("`r", "`n")
        $stepMatch = [regex]::Match($line, '^(?<indent>\s*)-\s+')
        if (-not $stepMatch.Success) { continue }
        $stepIndent = $stepMatch.Groups['indent'].Length
        $endLine = $index + 1
        while ($endLine -lt $lines.Count) {
            $candidate = $lines[$endLine].Value.TrimEnd("`r", "`n")
            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                $candidateIndent = $candidate.Length - $candidate.TrimStart().Length
                if ($candidateIndent -le $stepIndent) { break }
            }
            $endLine++
        }
        $stepText = @($lines[$index..($endLine - 1)].Value) -join ''
        if ($stepText -match '(?m)^\s+shell:\s*pwsh\s*$' -and
            $stepText -match "(?m)^\s+run:\s*$CommandPattern\s*$") {
            return $true
        }
    }
    return $false
}

function Get-MarkdownCommandScope (
    [string] $Content,
    [int] $Position,
    [switch] $FencedOnly) {
    $lines = @([regex]::Matches($Content, '(?m)^.*(?:\r?\n|$)'))
    $targetLine = 0
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($Position -le $lines[$index].Index + $lines[$index].Length) {
            $targetLine = $index
            break
        }
    }
    $openFence = $null
    for ($index = 0; $index -le $targetLine; $index++) {
        $line = $lines[$index].Value.TrimEnd("`r", "`n")
        $fenceMatch = [regex]::Match(
            $line, '^\s*(?<delimiter>`{3,}|~{3,})(?<tail>.*)$')
        if ($null -eq $openFence) {
            if ($fenceMatch.Success) {
                $delimiter = $fenceMatch.Groups['delimiter'].Value
                $openFence = [pscustomobject]@{
                    Character = $delimiter[0]
                    Length = $delimiter.Length
                    ContentStart = $lines[$index].Index + $lines[$index].Length
                }
            }
            continue
        }
        if ($fenceMatch.Success) {
            $delimiter = $fenceMatch.Groups['delimiter'].Value
            if ($delimiter[0] -eq $openFence.Character -and
                $delimiter.Length -ge $openFence.Length -and
                [string]::IsNullOrWhiteSpace($fenceMatch.Groups['tail'].Value)) {
                $openFence = $null
            }
        }
    }
    if ($null -ne $openFence) {
        return $Content.Substring(
            $openFence.ContentStart, $Position - $openFence.ContentStart)
    }
    if ($FencedOnly) { return $null }
    $priorContent = $Content.Substring(0, $Position)
    $paragraphBreaks = @([regex]::Matches($priorContent, '\r?\n\s*\r?\n'))
    $scopeStart = if ($paragraphBreaks.Count -gt 0) {
        $paragraphBreaks[-1].Index + $paragraphBreaks[-1].Length
    }
    else { 0 }
    return $Content.Substring($scopeStart, $Position - $scopeStart)
}

function Get-HereStringCommandScope ([string] $Content, [int] $Position) {
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput(
        $Content, [ref]$tokens, [ref]$parseErrors)
    $hereStrings = @($ast.FindAll({
                param($node)
                ($node -is
                    [Management.Automation.Language.StringConstantExpressionAst] -or
                    $node -is
                    [Management.Automation.Language.ExpandableStringExpressionAst]) -and
                    $node.Extent.StartOffset -lt $Position -and
                    $node.Extent.EndOffset -gt $Position -and
                    ($node.Extent.Text.StartsWith("@'") -or
                        $node.Extent.Text.StartsWith('@"'))
            }, $true))
    if ($hereStrings.Count -eq 0) { return $null }
    $hereString = @($hereStrings | Sort-Object {
            $_.Extent.EndOffset - $_.Extent.StartOffset
        })[0]
    $openingLineEnd = $Content.IndexOf("`n", $hereString.Extent.StartOffset)
    if ($openingLineEnd -lt 0 -or $openingLineEnd -ge $Position) { return $null }
    $scopeStart = $openingLineEnd + 1
    return $Content.Substring($scopeStart, $Position - $scopeStart)
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
            $elements[$index].ParameterName -ieq 'Name') {
            return Get-CommandParameterValueAst -Elements $elements `
                -ParameterIndex $index
        }
    }
    if ($elements.Count -gt 1 -and $elements[1] -isnot
        [Management.Automation.Language.CommandParameterAst]) {
        return $elements[1]
    }
    return $null
}

function Test-CommandTargetsPester (
    [Management.Automation.Language.CommandAst] $CommandAst) {
    $target = Get-CommandModuleTargetAst -CommandAst $CommandAst
    $nameText = Get-StaticStringAstValue -ExpressionAst $target
    return $null -ne $nameText -and $nameText -ieq 'Pester'
}

function Test-CommandIsInRootScriptBlock (
    [Management.Automation.Language.CommandAst] $CommandAst,
    [Management.Automation.Language.ScriptBlockAst] $RootAst) {
    $ancestor = $CommandAst.Parent
    while ($null -ne $ancestor -and
        $ancestor -isnot [Management.Automation.Language.ScriptBlockAst]) {
        $ancestor = $ancestor.Parent
    }
    return [object]::ReferenceEquals($ancestor, $RootAst)
}

function Test-CommandMayExecuteInScope (
    [Management.Automation.Language.CommandAst] $CommandAst,
    [Management.Automation.Language.ScriptBlockAst] $RootAst) {
    $ancestor = $CommandAst.Parent
    $insideDeferredScriptBlock = $false
    while ($null -ne $ancestor) {
        if ([object]::ReferenceEquals($ancestor, $RootAst)) { return $true }
        if ($ancestor -is [Management.Automation.Language.FunctionDefinitionAst]) {
            return $false
        }
        if ($ancestor -is
            [Management.Automation.Language.ScriptBlockExpressionAst]) {
            $insideDeferredScriptBlock = $true
        }
        elseif ($insideDeferredScriptBlock -and
            $ancestor -is [Management.Automation.Language.CommandAst]) {
            $insideDeferredScriptBlock = $false
        }
        elseif ($insideDeferredScriptBlock -and
            $ancestor -is [Management.Automation.Language.AssignmentStatementAst]) {
            return $false
        }
        $ancestor = $ancestor.Parent
    }
    return $false
}

function Test-ExecutableCommandAtOffset (
    [string] $ScriptText,
    [string] $CommandName,
    [int] $Offset) {
    if ([string]::IsNullOrWhiteSpace($ScriptText) -or $Offset -lt 0) {
        return $false
    }
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput(
        $ScriptText, [ref]$tokens, [ref]$parseErrors)
    return @($ast.FindAll({
                param($node)
                $node -is [Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -ieq $CommandName
            }, $true) | Where-Object {
            (Test-CommandMayExecuteInScope -CommandAst $_ -RootAst $ast) -and
                $_.CommandElements[0].Extent.StartOffset -eq $Offset
        }).Count -gt 0
}

function Test-PinnedPesterImport (
    [string] $Scope,
    [string] $ExpectedVersion,
    [switch] $AllowPesterVersionVariable) {
    if ([string]::IsNullOrWhiteSpace($Scope)) { return $false }
    $inlineCode = @([regex]::Matches($Scope, '`(?<code>[^`\r\n]+)`'))
    $scriptTexts = @($Scope)
    if ($inlineCode.Count -gt 0) {
        $scriptTexts += @($inlineCode | ForEach-Object {
                $_.Groups['code'].Value
            }) -join '; '
    }
    foreach ($scriptText in $scriptTexts) {
        $tokens = $null
        $parseErrors = $null
        $ast = [Management.Automation.Language.Parser]::ParseInput(
            $scriptText, [ref]$tokens, [ref]$parseErrors)
        $imports = @($ast.FindAll({
                    param($node)
                    $node -is [Management.Automation.Language.CommandAst] -and
                        $node.GetCommandName() -ieq 'Import-Module'
                }, $true) | Where-Object {
                Test-CommandIsInRootScriptBlock -CommandAst $_ -RootAst $ast
            })
        foreach ($commandAst in $imports) {
            if (-not (Test-CommandTargetsPester -CommandAst $commandAst)) { continue }
            $elements = @($commandAst.CommandElements)
            $versionParameters = @(for ($index = 1; $index -lt $elements.Count; $index++) {
                    if ($elements[$index] -is
                        [Management.Automation.Language.CommandParameterAst] -and
                        $elements[$index].ParameterName -ieq 'RequiredVersion') {
                        $index
                    }
                })
            if ($versionParameters.Count -ne 1) { continue }
            $versionValue = Get-CommandParameterValueAst -Elements $elements `
                -ParameterIndex $versionParameters[0]
            if ((Get-StaticStringAstValue -ExpressionAst $versionValue) -ceq
                $ExpectedVersion) {
                return $true
            }
            if ($AllowPesterVersionVariable -and
                $versionValue -is [Management.Automation.Language.VariableExpressionAst] -and
                [string]$versionValue.Extent.Text -ceq '$PesterVersion') {
                return $true
            }
        }
    }
    return $false
}

$globalJsonPath = Join-Path $resolvedRoot 'global.json'
if (-not (Test-Path -LiteralPath $globalJsonPath -PathType Leaf)) {
    $errors.Add("'global.json' must select the manifest .NET SDK.") | Out-Null
}
else {
    try {
        $globalJson = Get-Content -LiteralPath $globalJsonPath -Raw |
            ConvertFrom-Json -AsHashtable
        $globalSdkVersion = $null
        if ($globalJson -isnot [System.Collections.IDictionary] -or
            $globalJson.sdk -isnot [System.Collections.IDictionary]) {
            $errors.Add("'global.json' sdk must be an object.") | Out-Null
        }
        elseif ($globalJson.sdk.version -isnot [string] -or
            $globalJson.sdk.version -notmatch '^\d+\.\d+\.\d+$' -or
            -not [version]::TryParse($globalJson.sdk.version, [ref]$globalSdkVersion)) {
            $errors.Add("'global.json' sdk.version must be an exact three-part numeric SDK version.") |
                Out-Null
        }
        elseif ("$($globalSdkVersion.Major).$($globalSdkVersion.Minor).x" -cne
            [string]$manifest.dotnet.sdkVersion) {
            $errors.Add("'global.json' sdk.version must select manifest SDK '$($manifest.dotnet.sdkVersion)'.") |
                Out-Null
        }
        if ($globalJson.sdk -is [System.Collections.IDictionary] -and
            $globalJson.sdk.rollForward -cne 'latestFeature') {
            $errors.Add("'global.json' sdk.rollForward must be 'latestFeature'.") | Out-Null
        }
        if ($globalJson.sdk -is [System.Collections.IDictionary] -and
            ($globalJson.sdk.allowPrerelease -isnot [bool] -or
                $globalJson.sdk.allowPrerelease)) {
            $errors.Add("'global.json' sdk.allowPrerelease must be false.") | Out-Null
        }
    }
    catch {
        $errors.Add("'global.json' is invalid: $($_.Exception.Message)") | Out-Null
    }
}

$buildPropsPath = Join-Path $resolvedRoot 'Directory.Build.props'
if (-not (Test-Path -LiteralPath $buildPropsPath -PathType Leaf)) {
    $errors.Add("'Directory.Build.props' must set the manifest C# language version.") |
        Out-Null
}
else {
    try {
        [xml]$buildProps = Get-Content -LiteralPath $buildPropsPath -Raw
        $languageVersions = @($buildProps.Project.PropertyGroup.LangVersion)
        if ($languageVersions.Count -ne 1 -or
            [string]$languageVersions[0] -cne [string]$manifest.dotnet.languageVersion) {
            $errors.Add("'Directory.Build.props' must set LangVersion '$($manifest.dotnet.languageVersion)'.") |
                Out-Null
        }
    }
    catch {
        $errors.Add("'Directory.Build.props' is invalid XML: $($_.Exception.Message)") |
            Out-Null
    }
}

$workflowContracts = @(
    @{ Path = '.github/workflows/ci.yml'; Job = 'dotnet-pipes'; Host = $null; DotNet = 'sdkVersion'; Quality = $null }
    @{ Path = '.github/workflows/ci.yml'; Job = 'scaffold-linux'; Host = 'primary'; DotNet = 'sdkVersion'; Quality = $null }
    @{ Path = '.github/workflows/ci.yml'; Job = 'scaffold-windows'; Host = 'windows'; DotNet = 'sdkVersion'; Quality = $null }
    @{ Path = '.github/workflows/full-ci.yml'; Job = 'scaffold-linux'; Host = 'primary'; DotNet = 'sdkVersion'; Quality = $null }
    @{ Path = '.github/workflows/full-ci.yml'; Job = 'scaffold-linux-x64'; Host = 'scheduled'; DotNet = 'sdkVersion'; Quality = $null }
    @{ Path = '.github/workflows/full-ci.yml'; Job = 'scaffold-windows'; Host = 'windows'; DotNet = 'sdkVersion'; Quality = $null }
    @{ Path = '.github/workflows/full-ci.yml'; Job = 'scaffold-preview'; Host = 'windows'; DotNet = 'previewSdkVersion'; Quality = 'preview' }
)
$workflowContents = @{}
foreach ($contract in $workflowContracts) {
    if (-not $workflowContents.ContainsKey($contract.Path)) {
        $workflowPath = Join-Path $resolvedRoot $contract.Path
        $workflowContents[$contract.Path] = if (
            Test-Path -LiteralPath $workflowPath -PathType Leaf) {
            Get-Content -LiteralPath $workflowPath -Raw
        }
        else { $null }
    }
    $workflow = $workflowContents[$contract.Path]
    if ($null -eq $workflow) {
        $errors.Add("'$($contract.Path)' must exist.") | Out-Null
        continue
    }
    $jobBody = Get-ToolchainWorkflowJobBody -Content $workflow -JobName $contract.Job
    if ($null -eq $jobBody) {
        $errors.Add("'$($contract.Path)' must define job '$($contract.Job)'.") | Out-Null
        continue
    }
    if ($null -ne $contract.Host) {
        $expectedHost = [string]$manifest.hosts[$contract.Host].operatingSystem
        if ($jobBody -notmatch "(?m)^    runs-on: $([regex]::Escape($expectedHost))\r?$") {
            $errors.Add("'$($contract.Path)' job '$($contract.Job)' must run on manifest host '$expectedHost'.") |
                Out-Null
        }
            if (-not (Test-WorkflowPwshStepCommand -JobBody $jobBody `
                    -CommandPattern '\./tools/Test-PowerShellToolchain\.ps1')) {
                $errors.Add("'$($contract.Path)' job '$($contract.Job)' must validate the manifest PowerShell minimum in a pwsh step.") |
                Out-Null
            }
    }
    $expectedSdk = [string]$manifest.dotnet[$contract.DotNet]
    if ($jobBody -notmatch "(?m)^\s+dotnet-version: $([regex]::Escape($expectedSdk))\r?$") {
        $errors.Add("'$($contract.Path)' job '$($contract.Job)' must use manifest .NET SDK '$expectedSdk'.") |
            Out-Null
    }
    if ($null -ne $contract.Quality -and
        $jobBody -notmatch "(?m)^\s+dotnet-quality: $([regex]::Escape($contract.Quality))\r?$") {
        $errors.Add("'$($contract.Path)' job '$($contract.Job)' must use .NET quality '$($contract.Quality)'.") |
            Out-Null
    }
}
if ($workflowContents['.github/workflows/full-ci.yml'] -notmatch '(?m)^  schedule:\s*$') {
    $errors.Add("'.github/workflows/full-ci.yml' must define the scheduled host lane.") |
        Out-Null
}

$activeRoots = @('.agents', '.github', 'docs', 'evals', 'skills', 'tests', 'tools')
$historicalPesterEvidencePaths = @(
    'docs/dual-model-evaluation-plan.md',
    'docs/improvement-strategy.md',
    'docs/powershell-engineering-plan.md',
    'docs/pr-review-effectiveness-plan.md'
)
$copiedVersionPatterns = @(
    '(?i)-PesterVersion(?::\s*|\s+)(?<value>''[^'']*''|"[^"]*"|[^\s`]+)',
    '(?i)PesterVersion\s*=\s*(?<value>''[^'']*''|"[^"]*")'
)
$moduleSpecificationPattern =
    '(?i)@\{(?<body>[^}\r\n]*ModuleName\s*=\s*[''"]Pester[''"][^}\r\n]*)\}'
$moduleConstraintPattern =
    '(?i)(?<constraint>RequiredVersion|ModuleVersion)\s*=\s*[''"](?<version>[^''"]+)[''"]'
$moduleCommandNamePattern =
    '(?i)(?<![-\w])(?:Install-Module|Import-Module)(?![-\w])'
$invokePesterName = 'Invoke' + '-Pester'
$invokePesterPattern = "(?i)(?<![-\w])$invokePesterName(?![-\w])"
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
    if ($normalizedPath -cin $historicalPesterEvidencePaths) { continue }
    $isPinnedTest = $normalizedPath -like 'tests/*.Tests.ps1'
    $isWorkflow = $normalizedPath -like '.github/workflows/*' -or
        $normalizedPath -like '*/.github/workflows/*'
    $isMarkdown = $normalizedPath -like '*.md' -or
        $normalizedPath -like '*.md.tmpl'
    $isPowerShellSource = $file.Extension -in @('.ps1', '.psm1', '.psd1') -or
        $normalizedPath -like '*.ps1.tmpl'
    $moduleCommandTexts = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    $inlineCodeMatches = if ($isMarkdown) {
        @([regex]::Matches($content, '`(?<code>[^`\r\n]+)`'))
    }
    else { @() }
    if ($isPowerShellSource) {
        $tokens = $null
        $parseErrors = $null
        $sourceAst = [Management.Automation.Language.Parser]::ParseInput(
            $content, [ref]$tokens, [ref]$parseErrors)
        foreach ($commandAst in @($sourceAst.FindAll({
                    param($node)
                    $node -is [Management.Automation.Language.CommandAst] -and
                        $node.GetCommandName() -in @('Install-Module', 'Import-Module')
                }, $true))) {
            $moduleCommandTexts.Add($commandAst.Extent.Text) | Out-Null
        }
    }
    foreach ($commandMatch in [regex]::Matches(
            $content, $moduleCommandNamePattern)) {
        $lineEnd = $content.IndexOf("`n", $commandMatch.Index)
        $scopePosition = if ($lineEnd -ge 0) { $lineEnd } else { $content.Length }
        $containingInlineCode = @($inlineCodeMatches | Where-Object {
                $_.Index -lt $commandMatch.Index -and
                $_.Index + $_.Length -gt $commandMatch.Index
            } | Select-Object -First 1)
        $fencedCommandScope = if ($isMarkdown) {
            Get-MarkdownCommandScope -Content $content `
                -Position $scopePosition -FencedOnly
        }
        $commandScope = if ($null -ne $fencedCommandScope) {
            $fencedCommandScope
        }
        elseif ($containingInlineCode.Count -eq 1) {
            $containingInlineCode[0].Groups['code'].Value
        }
        elseif ($isWorkflow) {
            $workflowScope = Get-WorkflowRunScope -Content $content `
                -Position $scopePosition
            if ($null -ne $workflowScope) { $workflowScope }
            else {
                $lineStart = $content.LastIndexOf(
                    "`n", [Math]::Max(0, $commandMatch.Index - 1))
                if ($lineStart -lt 0) { $lineStart = 0 } else { $lineStart++ }
                $content.Substring($lineStart, $scopePosition - $lineStart)
            }
        }
        elseif ($isMarkdown) {
            Get-MarkdownCommandScope -Content $content -Position $scopePosition
        }
        elseif ($isPowerShellSource) {
            Get-HereStringCommandScope -Content $content -Position $scopePosition
        }
        else { $content.Substring(0, $scopePosition) }
        if ([string]::IsNullOrWhiteSpace($commandScope)) { continue }
        $commandScopes = @($commandScope)
        foreach ($scriptText in $commandScopes) {
            $tokens = $null
            $parseErrors = $null
            $scopeAst = [Management.Automation.Language.Parser]::ParseInput(
                $scriptText, [ref]$tokens, [ref]$parseErrors)
            foreach ($commandAst in @($scopeAst.FindAll({
                        param($node)
                        $node -is [Management.Automation.Language.CommandAst] -and
                            $node.GetCommandName() -in @(
                                'Install-Module', 'Import-Module')
                    }, $true))) {
                $moduleCommandTexts.Add($commandAst.Extent.Text) | Out-Null
            }
        }
    }
    foreach ($commandText in $moduleCommandTexts) {
        $tokens = $null
        $parseErrors = $null
        $commandAsts = @([Management.Automation.Language.Parser]::ParseInput(
                $commandText, [ref]$tokens, [ref]$parseErrors).FindAll({
                param($node)
                $node -is [Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -in @('Install-Module', 'Import-Module')
            }, $true))
        foreach ($commandAst in $commandAsts) {
            $elements = @($commandAst.CommandElements)
            $requiredVersionIndices = @(for ($index = 1; $index -lt $elements.Count; $index++) {
                    if ($elements[$index] -is [Management.Automation.Language.CommandParameterAst] -and
                        $elements[$index].ParameterName -ieq 'RequiredVersion') {
                        $index
                    }
                })
            $moduleTarget = Get-CommandModuleTargetAst -CommandAst $commandAst
            $moduleName = Get-StaticStringAstValue -ExpressionAst $moduleTarget
            if ($requiredVersionIndices.Count -gt 0 -and $null -eq $moduleName) {
                $errors.Add("'$relativePath' Pester module validation must use a static module name.") |
                    Out-Null
                continue
            }
            if ($moduleName -ine 'Pester') { continue }
            if ($requiredVersionIndices.Count -ne 1) {
                $errors.Add("'$relativePath' invokes Pester without -RequiredVersion $pesterVersion.") |
                    Out-Null
                continue
            }
            $versionElement = Get-CommandParameterValueAst -Elements $elements `
                -ParameterIndex $requiredVersionIndices[0]
            if ($null -eq $versionElement) {
                $errors.Add("'$relativePath' has an invalid Pester -RequiredVersion value.") |
                    Out-Null
                continue
            }
            $staticVersion = Get-StaticStringAstValue -ExpressionAst $versionElement
            $requiredVersionValue = if ($null -ne $staticVersion) {
                $staticVersion
            }
            else { [string]$versionElement.Extent.Text }
            $isRunnerParameter = $normalizedPath -ceq 'tests/Invoke-PesterShards.ps1' -and
                $versionElement -is [Management.Automation.Language.VariableExpressionAst] -and
                $requiredVersionValue -ceq '$PesterVersion'
            if (-not $isRunnerParameter -and $requiredVersionValue -cne $pesterVersion) {
                $errors.Add("'$relativePath' copies Pester version '$requiredVersionValue' instead of '$pesterVersion'.") |
                    Out-Null
            }
        }
    }
    foreach ($versionPattern in $copiedVersionPatterns) {
        foreach ($match in [regex]::Matches($content, $versionPattern)) {
            $copiedVersion = $match.Groups['value'].Value
            if (($copiedVersion.StartsWith("'") -and $copiedVersion.EndsWith("'")) -or
                ($copiedVersion.StartsWith('"') -and $copiedVersion.EndsWith('"'))) {
                $copiedVersion = $copiedVersion.Substring(1, $copiedVersion.Length - 2)
            }
            if ($copiedVersion -cne $pesterVersion) {
                $errors.Add("'$relativePath' copies Pester version '$copiedVersion' instead of '$pesterVersion'.") |
                    Out-Null
            }
        }
    }
    foreach ($moduleMatch in [regex]::Matches($content, $moduleSpecificationPattern)) {
        $constraintMatches = @([regex]::Matches(
                $moduleMatch.Groups['body'].Value, $moduleConstraintPattern))
        if ($constraintMatches.Count -ne 1) {
            $errors.Add("'$relativePath' must define one RequiredVersion for its Pester module requirement.") |
                Out-Null
            continue
        }
        $match = $constraintMatches[0]
        if ($match.Groups['constraint'].Value -ine 'RequiredVersion') {
            $errors.Add("'$relativePath' must use RequiredVersion for its Pester module requirement.") |
                Out-Null
        }
        if ($match.Groups['version'].Value -cne $pesterVersion) {
            $errors.Add("'$relativePath' copies Pester version '$($match.Groups['version'].Value)' instead of '$pesterVersion'.") |
                Out-Null
        }
    }
    $rawInvokeMatches = @([regex]::Matches($content, $invokePesterPattern))
    $invocations = if ($isPinnedTest) { @() }
    elseif ($isWorkflow) {
        @(foreach ($invokeMatch in $rawInvokeMatches) {
                $candidateEnd = $invokeMatch.Index + $invokeMatch.Length
                $candidateScope = Get-WorkflowRunScope -Content $content `
                    -Position $candidateEnd
                $lineStart = $content.LastIndexOf(
                    "`n", [Math]::Max(0, $invokeMatch.Index - 1))
                if ($lineStart -lt 0) { $lineStart = 0 } else { $lineStart++ }
                if ($null -eq $candidateScope) {
                    $candidateScope = $content.Substring(
                        $lineStart, $candidateEnd - $lineStart)
                }
                $offset = $candidateScope.Length - $invokeMatch.Length
                if (Test-ExecutableCommandAtOffset -ScriptText $candidateScope `
                        -CommandName $invokePesterName -Offset $offset) {
                    $invocationScope = Get-WorkflowRunScope -Content $content `
                        -Position $invokeMatch.Index
                    if ($null -eq $invocationScope) {
                        $invocationScope = $content.Substring(
                            $lineStart, $invokeMatch.Index - $lineStart)
                    }
                    [pscustomobject]@{
                        Position = $invokeMatch.Index
                        HereStringScope = $null
                        InvocationScope = $invocationScope
                    }
                }
            })
    }
    elseif ($isMarkdown) {
        @(foreach ($invokeMatch in $rawInvokeMatches) {
                $candidateEnd = $invokeMatch.Index + $invokeMatch.Length
                $candidateScope = Get-MarkdownCommandScope -Content $content `
                    -Position $candidateEnd -FencedOnly
                if ($null -ne $candidateScope) {
                    $offset = $candidateScope.Length - $invokeMatch.Length
                    if (Test-ExecutableCommandAtOffset -ScriptText $candidateScope `
                            -CommandName $invokePesterName -Offset $offset) {
                        [pscustomobject]@{
                            Position = $invokeMatch.Index
                            HereStringScope = $null
                            InvocationScope = Get-MarkdownCommandScope `
                                -Content $content -Position $invokeMatch.Index `
                                -FencedOnly
                        }
                    }
                    continue
                }
                $containingInlineCode = @($inlineCodeMatches | Where-Object {
                        $_.Index -lt $invokeMatch.Index -and
                        $_.Index + $_.Length -gt $invokeMatch.Index
                    } | Select-Object -First 1)
                if ($containingInlineCode.Count -ne 1) { continue }
                $scriptText = $containingInlineCode[0].Groups['code'].Value
                $offset = $invokeMatch.Index -
                    $containingInlineCode[0].Groups['code'].Index
                if (Test-ExecutableCommandAtOffset -ScriptText $scriptText `
                        -CommandName $invokePesterName -Offset $offset) {
                    [pscustomobject]@{
                        Position = $invokeMatch.Index
                        HereStringScope = $null
                        InvocationScope = Get-MarkdownCommandScope `
                            -Content $content -Position $invokeMatch.Index
                    }
                }
            })
    }
    else {
        $tokens = $null
        $parseErrors = $null
        $ast = [Management.Automation.Language.Parser]::ParseInput(
            $content, [ref]$tokens, [ref]$parseErrors)
        @(
            $ast.FindAll({
                    param($node)
                    $node -is [Management.Automation.Language.CommandAst] -and
                        $node.GetCommandName() -ieq $invokePesterName
                }, $true) | Where-Object {
                    Test-CommandMayExecuteInScope -CommandAst $_ -RootAst $ast
                } | ForEach-Object {
                    [pscustomobject]@{
                        Position = $_.Extent.StartOffset
                        HereStringScope = $null
                        InvocationScope = $null
                    }
                }
            foreach ($invokeMatch in $rawInvokeMatches) {
                $candidateEnd = $invokeMatch.Index + $invokeMatch.Length
                $candidateScope = Get-HereStringCommandScope -Content $content `
                    -Position $candidateEnd
                if ($null -eq $candidateScope) { continue }
                $offset = $candidateScope.Length - $invokeMatch.Length
                if (-not (Test-ExecutableCommandAtOffset `
                        -ScriptText $candidateScope `
                        -CommandName $invokePesterName -Offset $offset)) {
                    continue
                }
                [pscustomobject]@{
                    Position = $invokeMatch.Index
                    HereStringScope = Get-HereStringCommandScope `
                        -Content $content -Position $invokeMatch.Index
                    InvocationScope = $null
                }
            }
        )
    }
    foreach ($invocation in $invocations) {
        $invocationScope = if ($null -ne $invocation.InvocationScope) {
            $invocation.InvocationScope
        }
        elseif ($null -ne $invocation.HereStringScope) {
            $invocation.HereStringScope
        }
        else { $content.Substring(0, $invocation.Position) }
        if (-not (Test-PinnedPesterImport -Scope $invocationScope `
                -ExpectedVersion $pesterVersion `
                -AllowPesterVersionVariable:($normalizedPath -ceq
                    'tests/Invoke-PesterShards.ps1'))) {
            $errors.Add("'$relativePath' invokes $invokePesterName without a preceding pinned Pester import.") |
                Out-Null
        }
    }
}

$exactGuidancePaths = @('.agents/skills/create-skill-repo/SKILL.md')
$portableGuidancePaths = @(
    'skills/dotnet-file-creation/SKILL.md',
    'skills/windows-acls/SKILL.md'
)
foreach ($relativePath in $exactGuidancePaths) {
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
foreach ($relativePath in $portableGuidancePaths) {
    $path = Join-Path $resolvedRoot $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $errors.Add("'$relativePath' must name PowerShell $minimumPowerShellVersion and Pester $portablePesterFloor or later.") |
            Out-Null
        continue
    }
    $content = Get-Content -LiteralPath $path -Raw
    $powerShellPattern =
        "PowerShell $([regex]::Escape($minimumPowerShellVersion))(?![0-9A-Za-z-]|\.[0-9A-Za-z])"
    if ($content -notmatch $powerShellPattern) {
        $errors.Add("'$relativePath' must name PowerShell $minimumPowerShellVersion.") | Out-Null
    }
    $portablePesterPattern =
        "Pester $([regex]::Escape($portablePesterFloor)) or later(?![0-9A-Za-z-]|\.[0-9A-Za-z])"
    if ($content -notmatch $portablePesterPattern) {
        $errors.Add("'$relativePath' must name Pester $portablePesterFloor or later.") |
            Out-Null
    }
    if ($content -match 'source repository|Pester \d+\.\d+\.\d+') {
        $errors.Add("'$relativePath' must keep repository-specific Pester pins out of the portable core.") |
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
    PSScriptAnalyzerVersion = [string]$manifest.modules.PSScriptAnalyzer
    TestFileCount = $testFiles.Count
}