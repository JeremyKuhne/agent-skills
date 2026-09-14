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
if ($minimumPowerShellIsValid -and
    $PSVersionTable.PSVersion -lt $minimumPowerShell) {
    $errors.Add("Toolchain validation requires PowerShell $minimumPowerShellVersion or later; current process is $($PSVersionTable.PSVersion).") |
        Out-Null
}
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

function Get-StaticStringAstValues ([object] $ExpressionAst) {
    if ($null -eq $ExpressionAst) { return }
    while ($ExpressionAst -is
        [Management.Automation.Language.CommandExpressionAst]) {
        $ExpressionAst = $ExpressionAst.Expression
    }
    try { $value = $ExpressionAst.SafeGetValue() }
    catch {
        $value = Get-StaticStringAstValue -ExpressionAst $ExpressionAst
    }
    if ($value -is [string]) {
        $value
        return
    }
    if ($value -is [Collections.IEnumerable]) {
        $values = @($value)
        if ($values.Count -gt 0 -and
            @($values | Where-Object { $_ -isnot [string] }).Count -eq 0) {
            $values
        }
    }
}

function Add-PesterModuleRequirementErrors (
    [string] $ScriptText,
    [string] $RelativePath,
    [string] $ExpectedVersion,
    [Collections.Generic.List[string]] $ErrorList) {
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput(
        $ScriptText, [ref]$tokens, [ref]$parseErrors)
    foreach ($requirement in @($ast.ScriptRequirements.RequiredModules |
            Where-Object Name -IEQ 'Pester')) {
        if ($null -eq $requirement.RequiredVersion) {
            $ErrorList.Add("'$RelativePath' must use RequiredVersion for its Pester module requirement.") |
                Out-Null
        }
        elseif ([string]$requirement.RequiredVersion -cne $ExpectedVersion) {
            $ErrorList.Add("'$RelativePath' copies Pester version '$($requirement.RequiredVersion)' instead of '$ExpectedVersion'.") |
                Out-Null
        }
    }
    foreach ($hashtableAst in @($ast.FindAll({
                param($node)
                $node -is [Management.Automation.Language.HashtableAst]
            }, $true))) {
        $table = [ordered]@{}
        $dynamicKeys = [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::OrdinalIgnoreCase)
        foreach ($pair in $hashtableAst.KeyValuePairs) {
            try { $key = [string]$pair.Item1.SafeGetValue() }
            catch { continue }
            try { $table[$key] = $pair.Item2.SafeGetValue() }
            catch { $dynamicKeys.Add($key) | Out-Null }
        }
        $hasVersionConstraint = $dynamicKeys.Contains('RequiredVersion') -or
            $dynamicKeys.Contains('ModuleVersion') -or
            @($table.Keys | Where-Object {
                    [string]$_ -ieq 'RequiredVersion' -or
                    [string]$_ -ieq 'ModuleVersion'
                }).Count -gt 0
        if ($dynamicKeys.Contains('ModuleName') -and $hasVersionConstraint) {
            $ErrorList.Add("'$RelativePath' Pester module requirement must use the exact static ModuleName.") |
                Out-Null
            continue
        }
        $moduleNameKey = @($table.Keys | Where-Object {
                [string]$_ -ieq 'ModuleName'
            } | Select-Object -First 1)
        if ($moduleNameKey.Count -ne 1) {
            continue
        }
        $moduleName = [string]$table[$moduleNameKey[0]]
        if ([Management.Automation.WildcardPattern]::ContainsWildcardCharacters(
                $moduleName) -and
            [Management.Automation.WildcardPattern]::new(
                $moduleName,
                [Management.Automation.WildcardOptions]::IgnoreCase).IsMatch(
                'Pester')) {
            $ErrorList.Add("'$RelativePath' Pester module requirement must use the exact static ModuleName.") |
                Out-Null
            continue
        }
        if ($moduleName -ine 'Pester') { continue }
        if ($dynamicKeys.Contains('RequiredVersion')) {
            $ErrorList.Add("'$RelativePath' must use a static RequiredVersion for its Pester module requirement.") |
                Out-Null
            continue
        }
        $requiredVersionKey = @($table.Keys | Where-Object {
                [string]$_ -ieq 'RequiredVersion'
            } | Select-Object -First 1)
        $moduleVersionKey = @($table.Keys | Where-Object {
                [string]$_ -ieq 'ModuleVersion'
            } | Select-Object -First 1)
        if ($requiredVersionKey.Count -ne 1 -or
            $moduleVersionKey.Count -gt 0) {
            $ErrorList.Add("'$RelativePath' must use RequiredVersion for its Pester module requirement.") |
                Out-Null
            continue
        }
        $requiredVersion = [string]$table[$requiredVersionKey[0]]
        if ($requiredVersion -cne $ExpectedVersion) {
            $ErrorList.Add("'$RelativePath' copies Pester version '$requiredVersion' instead of '$ExpectedVersion'.") |
                Out-Null
        }
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
        $scalarMatch = [regex]::Match(
            $trimmed,
            '^(?<scalar>\x27(?:[^\x27]|\x27\x27)*\x27)(?:\s+#.*)?$')
        if ($scalarMatch.Success) {
            $scalar = $scalarMatch.Groups['scalar'].Value
            return $scalar.Substring(1, $scalar.Length - 2).Replace("''", "'")
        }
        return $trimmed.Substring(1).Replace("''", "'")
    }
    if ($trimmed.StartsWith('"')) {
        $scalarMatch = [regex]::Match(
            $trimmed,
            '^(?<scalar>"(?:\\.|[^"\\])*")(?:\s+#.*)?$')
        $jsonText = if ($scalarMatch.Success) {
            $scalarMatch.Groups['scalar'].Value
        }
        else { $trimmed + '"' }
        try { return [Text.Json.JsonSerializer]::Deserialize[string]($jsonText) }
        catch { return $trimmed.Substring(1) }
    }
    return [regex]::Replace($Text.TrimEnd(), '\s+#.*$', '')
}

function ConvertFrom-WorkflowBlockScalar (
    [string] $Text,
    [switch] $Folded) {
    if (-not $Folded) { return $Text }
    return [regex]::Replace($Text, '\r?\n(?=[ \t]*\S)', ' ')
}

function Get-WorkflowRunScope (
    [string] $Content,
    [int] $Position,
    [switch] $Complete) {
    $lines = @([regex]::Matches($Content, '(?m)^.*(?:\r?\n|$)'))
    $targetLine = $lines.Count - 1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($Position -lt $lines[$index].Index + $lines[$index].Length) {
            $targetLine = $index
            break
        }
    }
    for ($index = $targetLine; $index -ge 0; $index--) {
        $line = $lines[$index].Value.TrimEnd("`r", "`n")
        $runMatch = [regex]::Match(
            $line,
            '^(?<indent>\s*)(?<dash>-\s+)?run:\s*(?<value>.*)$')
        if (-not $runMatch.Success) { continue }
        $isStepRun = $runMatch.Groups['dash'].Success
        if (-not $isStepRun) {
            for ($priorIndex = $index - 1; $priorIndex -ge 0; $priorIndex--) {
                $priorLine = $lines[$priorIndex].Value.TrimEnd("`r", "`n")
                $stepMatch = [regex]::Match(
                    $priorLine, '^(?<indent>\s*)-\s+')
                if (-not $stepMatch.Success) { continue }
                $isStepRun = $runMatch.Groups['indent'].Length -eq
                    $stepMatch.Groups['indent'].Length + 2
                break
            }
        }
        if (-not $isStepRun) { continue }
        $indent = $runMatch.Groups['indent'].Length
        $value = $runMatch.Groups['value'].Value
        $isBlockScalar = $value -match '^[|>]'
        if (-not $isBlockScalar) {
            if ($index -ne $targetLine) { continue }
            $scopeStart = $lines[$index].Index + $runMatch.Groups['value'].Index
            if (-not $Complete -and $Position -lt $scopeStart) { continue }
            $scopeLength = if ($Complete) {
                $runMatch.Groups['value'].Length
            }
            else { $Position - $scopeStart }
            if ($scopeLength -lt 0) { continue }
            return ConvertFrom-WorkflowRunScalar $Content.Substring(
                $scopeStart, $scopeLength)
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
        if ($targetLine -lt $endLine -and
            ($targetLine -gt $index -or $Complete)) {
            $scopeStart = $lines[$index + 1].Index
            $scopeEnd = if ($Complete) {
                if ($endLine -lt $lines.Count) { $lines[$endLine].Index }
                else { $Content.Length }
            }
            else { $Position }
            return ConvertFrom-WorkflowBlockScalar `
                -Text $Content.Substring($scopeStart, $scopeEnd - $scopeStart) `
                -Folded:$value.StartsWith('>')
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

function Remove-PowerShellComments ([string] $Text) {
    $tokens = $null
    $parseErrors = $null
    [Management.Automation.Language.Parser]::ParseInput(
        $Text, [ref]$tokens, [ref]$parseErrors) | Out-Null
    $result = $Text
    foreach ($token in @($tokens | Where-Object Kind -EQ Comment |
            Sort-Object { $_.Extent.StartOffset } -Descending)) {
        $result = $result.Remove(
            $token.Extent.StartOffset,
            $token.Extent.EndOffset - $token.Extent.StartOffset)
    }
    return $result
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
        $sequenceIndent = [regex]::Escape(' ' * $stepIndent)
        $mappingIndent = [regex]::Escape(' ' * ($stepIndent + 2))
        $shellValues = @([regex]::Matches(
            $stepText,
            "(?m)^(?:${sequenceIndent}-\s+|${mappingIndent})" +
            'shell:\s*(?<value>.*)$'))
        $hasPwshShell = @($shellValues | Where-Object {
            (ConvertFrom-WorkflowRunScalar `
                $_.Groups['value'].Value) -ieq 'pwsh'
            }).Count -gt 0
        if (-not $hasPwshShell) {
            continue
        }
        $runKeys = @([regex]::Matches(
                $stepText,
                "(?m)^(?:${sequenceIndent}-\s+|${mappingIndent})run:"))
        foreach ($runKey in $runKeys) {
            $runScope = Get-WorkflowRunScope -Content $stepText `
            -Position ($runKey.Index + $runKey.Length) -Complete
            $normalizedRunScope = if ($null -ne $runScope) {
                Remove-PowerShellComments -Text $runScope
            }
            if ($null -ne $normalizedRunScope -and
                $normalizedRunScope -match "(?s)^\s*$CommandPattern\s*$") {
                return $true
            }
        }
    }
    return $false
}

function Get-MarkdownCommandScope (
    [string] $Content,
    [int] $Position,
    [switch] $FencedOnly,
    [switch] $Complete) {
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
        $scopeEnd = $Position
        if ($Complete) {
            $scopeEnd = $Content.Length
            for ($index = $targetLine + 1; $index -lt $lines.Count; $index++) {
                $line = $lines[$index].Value.TrimEnd("`r", "`n")
                $fenceMatch = [regex]::Match(
                    $line, '^\s*(?<delimiter>`{3,}|~{3,})(?<tail>.*)$')
                if (-not $fenceMatch.Success) { continue }
                $delimiter = $fenceMatch.Groups['delimiter'].Value
                if ($delimiter[0] -eq $openFence.Character -and
                    $delimiter.Length -ge $openFence.Length -and
                    [string]::IsNullOrWhiteSpace(
                        $fenceMatch.Groups['tail'].Value)) {
                    $scopeEnd = $lines[$index].Index
                    break
                }
            }
        }
        return $Content.Substring(
            $openFence.ContentStart, $scopeEnd - $openFence.ContentStart)
    }
    $targetText = $lines[$targetLine].Value.TrimEnd("`r", "`n")
    if ($targetText -match '^(?: {4}|\t)') {
        $scopeStartLine = $targetLine
        while ($scopeStartLine -gt 0) {
            $previousText = $lines[$scopeStartLine - 1].Value.TrimEnd(
                "`r", "`n")
            if (-not [string]::IsNullOrWhiteSpace($previousText) -and
                $previousText -notmatch '^(?: {4}|\t)') {
                break
            }
            $scopeStartLine--
        }
        $scopeEndLine = $targetLine
        if ($Complete) {
            for ($index = $targetLine + 1; $index -lt $lines.Count; $index++) {
                $candidate = $lines[$index].Value.TrimEnd("`r", "`n")
                if (-not [string]::IsNullOrWhiteSpace($candidate) -and
                    $candidate -notmatch '^(?: {4}|\t)') {
                    break
                }
                $scopeEndLine = $index
            }
        }
        $codeLines = @(for ($index = $scopeStartLine;
                $index -le $scopeEndLine; $index++) {
                $segmentEnd = if ($Complete) {
                    $lines[$index].Index + $lines[$index].Length
                }
                else {
                    [Math]::Min(
                        $Position, $lines[$index].Index + $lines[$index].Length)
                }
                if ($segmentEnd -le $lines[$index].Index) { continue }
                $segment = $Content.Substring(
                    $lines[$index].Index, $segmentEnd - $lines[$index].Index)
                if ($segment.StartsWith('    ')) { $segment.Substring(4) }
                elseif ($segment.StartsWith("`t")) { $segment.Substring(1) }
                else { $segment }
            })
        return $codeLines -join ''
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

function Get-HereStringCommandScope (
    [string] $Content,
    [int] $Position,
    [switch] $Complete) {
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
    $scopeEnd = $Position
    if ($Complete) {
        $scopeEnd = $Content.LastIndexOf(
            "`n", $hereString.Extent.EndOffset - 1)
        if ($scopeEnd -lt $scopeStart) { return $null }
    }
    return $Content.Substring($scopeStart, $scopeEnd - $scopeStart)
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

function Test-CommandTargetsPester (
    [Management.Automation.Language.CommandAst] $CommandAst) {
    $target = Get-CommandModuleTargetAst -CommandAst $CommandAst
    return @(Get-StaticStringAstValues -ExpressionAst $target |
        Where-Object { $_ -ieq 'Pester' }).Count -gt 0
}

function Test-CommandTargetsAssignedPester (
    [Management.Automation.Language.CommandAst] $CommandAst,
    [Management.Automation.Language.ScriptBlockAst] $RootAst) {
    $target = Get-CommandModuleTargetAst -CommandAst $CommandAst
    if ($target -isnot [Management.Automation.Language.VariableExpressionAst] -or
        $target.Splatted) {
        return $false
    }
    $variableName = $target.VariablePath.UserPath
    $assignments = @($RootAst.FindAll({
                param($node)
                $node -is [Management.Automation.Language.AssignmentStatementAst]
            }, $true) | Where-Object {
            $_.Extent.StartOffset -lt $CommandAst.Extent.StartOffset -and
                $_.Left -is
                    [Management.Automation.Language.VariableExpressionAst] -and
                $_.Left.VariablePath.UserPath -ieq $variableName
        } | Sort-Object { $_.Extent.StartOffset } -Descending)
    foreach ($assignment in $assignments) {
        return @(Get-StaticStringAstValues -ExpressionAst $assignment.Right |
            Where-Object { $_ -ieq 'Pester' }).Count -gt 0
    }
    return $false
}

function Test-CommandInvokesScriptBlockArguments (
    [Management.Automation.Language.CommandAst] $CommandAst) {
    if ($CommandAst.InvocationOperator -in @(
            [Management.Automation.Language.TokenKind]::Ampersand,
            [Management.Automation.Language.TokenKind]::Dot)) {
        return $true
    }
    return $CommandAst.GetCommandName() -in @(
        'ForEach-Object', 'Where-Object', 'Invoke-Command', 'Measure-Command',
        'Trace-Command', 'Start-Job', 'Start-ThreadJob')
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
            if (-not (Test-CommandInvokesScriptBlockArguments `
                    -CommandAst $ancestor)) {
                return $false
            }
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
                $_.CommandElements[0].Extent.StartOffset -le $Offset -and
                $_.CommandElements[0].Extent.EndOffset -ge
                    $Offset + $CommandName.Length
        }).Count -gt 0
}

function Test-PositionIsInIgnoredPowerShellText (
    [Management.Automation.Language.Token[]] $Tokens,
    [int] $Position) {
    foreach ($token in $Tokens) {
        if ($token.Extent.StartOffset -gt $Position) { break }
        if ($token.Extent.StartOffset -le $Position -and
            $token.Extent.EndOffset -gt $Position) {
            if ($token.Kind -eq
                [Management.Automation.Language.TokenKind]::Comment -and
                $token.Text.TrimStart().StartsWith(
                    '#Requires', [StringComparison]::OrdinalIgnoreCase)) {
                return $false
            }
            return $token.Kind -in @(
                [Management.Automation.Language.TokenKind]::Comment,
                [Management.Automation.Language.TokenKind]::StringExpandable,
                [Management.Automation.Language.TokenKind]::StringLiteral)
        }
    }
    return $false
}

function Test-PinnedPesterImport (
    [string] $Scope,
    [string] $ExpectedVersion,
    [switch] $AllowPesterVersionVariable) {
    if ([string]::IsNullOrWhiteSpace($Scope)) { return $false }
    $scriptTexts = @($Scope)
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
                Test-CommandMayExecuteInScope -CommandAst $_ -RootAst $ast
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
    $sdkVersions = @([regex]::Matches(
            $jobBody, '(?m)^\s+dotnet-version:\s*(?<value>.*?)\s*$') |
        ForEach-Object {
            ConvertFrom-WorkflowRunScalar $_.Groups['value'].Value
        })
    if ($sdkVersions.Count -eq 0 -or
        @($sdkVersions | Where-Object { $_ -cne $expectedSdk }).Count -gt 0) {
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
    '(?i)-PesterVersion(?::\s*|(?:\s|`\r?\n)+)(?<value>''[^'']*''|"[^"]*"|[^\s`]+)',
    '(?i)PesterVersion\s*=\s*(?<value>''[^'']*''|"[^"]*")'
)
$moduleNamePropertyPattern =
    '(?i)(?:\bModuleName\b|[''"]ModuleName[''"])\s*='
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
    $moduleRequirementScopes = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    $assignedPesterModuleCommandTexts =
        [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal)
    $copiedVersionScopes = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    $sourceTokens = @()
    $inlineCodeMatches = if ($isMarkdown) {
        @([regex]::Matches($content, '`(?<code>[^`\r\n]+)`'))
    }
    else { @() }
    if ($isWorkflow) {
        foreach ($runKeyMatch in [regex]::Matches(
                $content, '(?m)^\s*(?:-\s+)?run:')) {
            $runScope = Get-WorkflowRunScope -Content $content `
                -Position ($runKeyMatch.Index + $runKeyMatch.Length) -Complete
            if ($null -ne $runScope) {
                $copiedVersionScopes.Add($runScope) | Out-Null
            }
        }
    }
    else {
        $copiedVersionScopes.Add($content) | Out-Null
    }
    if ($isPowerShellSource) {
        $tokens = $null
        $parseErrors = $null
        $sourceAst = [Management.Automation.Language.Parser]::ParseInput(
            $content, [ref]$tokens, [ref]$parseErrors)
        $sourceTokens = @($tokens)
        foreach ($commandAst in @($sourceAst.FindAll({
                    param($node)
                    $node -is [Management.Automation.Language.CommandAst] -and
                        $node.GetCommandName() -in @('Install-Module', 'Import-Module')
                }, $true) | Where-Object {
                    Test-CommandMayExecuteInScope -CommandAst $_ `
                        -RootAst $sourceAst
                })) {
            $moduleCommandTexts.Add($commandAst.Extent.Text) | Out-Null
            if (Test-CommandTargetsAssignedPester -CommandAst $commandAst `
                    -RootAst $sourceAst) {
                $assignedPesterModuleCommandTexts.Add(
                    $commandAst.Extent.Text) | Out-Null
            }
        }
        $moduleRequirementScopes.Add($content) | Out-Null
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
                -Position $commandMatch.Index -FencedOnly -Complete
        }
        $commandScope = if ($null -ne $fencedCommandScope) {
            $fencedCommandScope
        }
        elseif ($containingInlineCode.Count -eq 1) {
            $containingInlineCode[0].Groups['code'].Value
        }
        elseif ($isWorkflow) {
            $workflowScope = Get-WorkflowRunScope -Content $content `
                -Position $commandMatch.Index -Complete
            if ($null -ne $workflowScope) { $workflowScope }
            else {
                $lineStart = $content.LastIndexOf(
                    "`n", [Math]::Max(0, $commandMatch.Index - 1))
                if ($lineStart -lt 0) { $lineStart = 0 } else { $lineStart++ }
                $lineScope = $content.Substring(
                    $lineStart, $scopePosition - $lineStart)
                if ($lineScope -notmatch
                    '^\s*(?:-\s+)?[A-Za-z_][\w.-]*:\s*') {
                    $lineScope
                }
            }
        }
        elseif ($isMarkdown) {
            $null
        }
        elseif ($isPowerShellSource) {
            Get-HereStringCommandScope -Content $content `
                -Position $commandMatch.Index -Complete
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
                    }, $true) | Where-Object {
                        Test-CommandMayExecuteInScope -CommandAst $_ `
                            -RootAst $scopeAst
                    })) {
                $moduleCommandTexts.Add($commandAst.Extent.Text) | Out-Null
                if (Test-CommandTargetsAssignedPester -CommandAst $commandAst `
                        -RootAst $scopeAst) {
                    $assignedPesterModuleCommandTexts.Add(
                        $commandAst.Extent.Text) | Out-Null
                }
            }
        }
    }
    foreach ($propertyMatch in [regex]::Matches(
            $content, $moduleNamePropertyPattern)) {
        $containingInlineCode = @($inlineCodeMatches | Where-Object {
                $_.Index -lt $propertyMatch.Index -and
                $_.Index + $_.Length -gt $propertyMatch.Index
            } | Select-Object -First 1)
        $requirementScope = if ($containingInlineCode.Count -eq 1) {
            $containingInlineCode[0].Groups['code'].Value
        }
        elseif ($isWorkflow) {
            Get-WorkflowRunScope -Content $content `
                -Position $propertyMatch.Index -Complete
        }
        elseif ($isMarkdown) {
            Get-MarkdownCommandScope -Content $content `
                -Position $propertyMatch.Index -FencedOnly -Complete
        }
        elseif ($isPowerShellSource) {
            Get-HereStringCommandScope -Content $content `
                -Position $propertyMatch.Index -Complete
        }
        if (-not [string]::IsNullOrWhiteSpace($requirementScope)) {
            $moduleRequirementScopes.Add($requirementScope) | Out-Null
        }
    }
    foreach ($requirementScope in $moduleRequirementScopes) {
        Add-PesterModuleRequirementErrors -ScriptText $requirementScope `
            -RelativePath $relativePath -ExpectedVersion $pesterVersion `
            -ErrorList $errors
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
            if (@($elements | Where-Object {
                        $_ -is [Management.Automation.Language.VariableExpressionAst] -and
                            $_.Splatted
                    }).Count -gt 0) {
                $errors.Add("'$relativePath' must not use splatting for module validation.") |
                    Out-Null
                continue
            }
            $requiredVersionIndices = @(for ($index = 1; $index -lt $elements.Count; $index++) {
                    if ($elements[$index] -is [Management.Automation.Language.CommandParameterAst] -and
                        $elements[$index].ParameterName -ieq 'RequiredVersion') {
                        $index
                    }
                })
            $moduleTarget = Get-CommandModuleTargetAst -CommandAst $commandAst
            $moduleNames = @(Get-StaticStringAstValues -ExpressionAst $moduleTarget)
            if ($moduleNames.Count -eq 0 -and
                $requiredVersionIndices.Count -eq 0 -and
                $assignedPesterModuleCommandTexts.Contains($commandText)) {
                $moduleNames = @('Pester')
            }
            if ($requiredVersionIndices.Count -gt 0 -and $moduleNames.Count -eq 0) {
                $errors.Add("'$relativePath' Pester module validation must use a static module name.") |
                    Out-Null
                continue
            }
            $wildcardNames = @($moduleNames | Where-Object {
                [Management.Automation.WildcardPattern]::ContainsWildcardCharacters(
                    $_) -and
                    [Management.Automation.WildcardPattern]::new(
                        $_,
                        [Management.Automation.WildcardOptions]::IgnoreCase).IsMatch(
                        'Pester')
                })
            if ($wildcardNames.Count -gt 0) {
                $errors.Add("'$relativePath' Pester module validation must use the exact module name 'Pester'.") |
                    Out-Null
                continue
            }
            if (@($moduleNames | Where-Object { $_ -ieq 'Pester' }).Count -eq 0) {
                continue
            }
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
    foreach ($versionScope in $copiedVersionScopes) {
        $versionTokens = if ($isWorkflow) {
            $tokens = $null
            $parseErrors = $null
            [Management.Automation.Language.Parser]::ParseInput(
                $versionScope, [ref]$tokens, [ref]$parseErrors) | Out-Null
            @($tokens)
        }
        elseif ($isPowerShellSource) { $sourceTokens }
        else { @() }
        foreach ($versionPattern in $copiedVersionPatterns) {
            foreach ($match in [regex]::Matches($versionScope, $versionPattern)) {
                if (($isPowerShellSource -or $isWorkflow) -and
                    (Test-PositionIsInIgnoredPowerShellText `
                        -Tokens $versionTokens -Position $match.Index)) {
                    continue
                }
                $copiedVersion = $match.Groups['value'].Value
                if (($copiedVersion.StartsWith("'") -and
                        $copiedVersion.EndsWith("'")) -or
                    ($copiedVersion.StartsWith('"') -and
                        $copiedVersion.EndsWith('"'))) {
                    $copiedVersion = $copiedVersion.Substring(
                        1, $copiedVersion.Length - 2)
                }
                if ($copiedVersion -cne $pesterVersion) {
                    $errors.Add("'$relativePath' copies Pester version '$copiedVersion' instead of '$pesterVersion'.") |
                        Out-Null
                }
            }
        }
    }
    $rawInvokeMatches = @([regex]::Matches($content, $invokePesterPattern))
    $invocations = if ($isPinnedTest) { @() }
    elseif ($isWorkflow) {
        @(foreach ($invokeMatch in $rawInvokeMatches) {
                $candidateEnd = $invokeMatch.Index + $invokeMatch.Length
                $candidatePrefix = Get-WorkflowRunScope -Content $content `
                    -Position $candidateEnd
                $candidateScope = Get-WorkflowRunScope -Content $content `
                    -Position $invokeMatch.Index -Complete
                $lineStart = $content.LastIndexOf(
                    "`n", [Math]::Max(0, $invokeMatch.Index - 1))
                if ($lineStart -lt 0) { $lineStart = 0 } else { $lineStart++ }
                $lineScope = $content.Substring(
                    $lineStart, $candidateEnd - $lineStart)
                if ($null -eq $candidatePrefix -and
                    $lineScope -notmatch
                    '^\s*(?:-\s+)?[A-Za-z_][\w.-]*:\s*') {
                    $candidatePrefix = $lineScope
                    $candidateScope = $lineScope
                }
                if ($null -eq $candidatePrefix -or
                    $null -eq $candidateScope) {
                    continue
                }
                $offset = $candidatePrefix.LastIndexOf(
                    $invokePesterName,
                    [StringComparison]::OrdinalIgnoreCase)
                if (Test-ExecutableCommandAtOffset -ScriptText $candidateScope `
                        -CommandName $invokePesterName -Offset $offset) {
                    $invocationScope = Get-WorkflowRunScope -Content $content `
                        -Position $invokeMatch.Index
                    if ($null -eq $invocationScope) { $invocationScope = '' }
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
            $candidatePrefix = Get-MarkdownCommandScope -Content $content `
                    -Position $candidateEnd -FencedOnly
            if ($null -ne $candidatePrefix) {
                $candidateScope = Get-MarkdownCommandScope -Content $content `
                    -Position $invokeMatch.Index -FencedOnly -Complete
                $offset = $candidatePrefix.LastIndexOf(
                        $invokePesterName,
                        [StringComparison]::OrdinalIgnoreCase)
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
                        InvocationScope = $scriptText.Substring(0, $offset)
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
                $candidatePrefix = Get-HereStringCommandScope -Content $content `
                    -Position $candidateEnd
                if ($null -eq $candidatePrefix) { continue }
                $candidateScope = Get-HereStringCommandScope -Content $content `
                    -Position $invokeMatch.Index -Complete
                $offset = $candidatePrefix.LastIndexOf(
                    $invokePesterName,
                    [StringComparison]::OrdinalIgnoreCase)
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