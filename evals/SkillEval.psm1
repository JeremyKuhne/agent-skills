Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'SkillEvalScorer.ps1')
Import-Module (Join-Path $PSScriptRoot 'SkillEvalContent.psm1') -Force

function Get-SkillEvalScenarios {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    $document = Get-Content -LiteralPath $resolvedPath -Raw | ConvertFrom-Json
    if ($document.schemaVersion -ne 1) {
        throw "Unsupported skill-evaluation schema version '$($document.schemaVersion)'."
    }

    $requiredFields = @(
        'id',
        'skill',
        'category',
        'evidenceKind',
        'profile',
        'prompt',
        'runCount',
        'expectSkillInvocation',
        'allowedTools',
        'deniedTools',
        'requiredResponsePatterns',
        'forbiddenResponsePatterns',
        'requiredCommandPatterns',
        'forbiddenCommandPatterns',
        'requireUnchangedWorktree'
    )
    $identifiers = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $scenarios = @($document.scenarios)
    if ($scenarios.Count -eq 0) { throw "No scenarios were found in '$resolvedPath'." }

    foreach ($scenario in $scenarios) {
        foreach ($field in $requiredFields) {
            if ($null -eq $scenario.PSObject.Properties[$field]) {
                throw "Scenario '$($scenario.id)' is missing '$field'."
            }
        }
        if ([string]::IsNullOrWhiteSpace([string]$scenario.id)) {
            throw 'Scenario ids cannot be empty.'
        }
        if ([string]$scenario.id -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
            throw "Scenario id '$($scenario.id)' must use lowercase kebab-case."
        }
        if (-not $identifiers.Add([string]$scenario.id)) {
            throw "Duplicate scenario id '$($scenario.id)'."
        }
        if ([int]$scenario.runCount -lt 1) {
            throw "Scenario '$($scenario.id)' must run at least once."
        }
        if ([string]$scenario.profile -notin @('clean-feature', 'dirty-feature', 'dirty-main')) {
            throw "Scenario '$($scenario.id)' has unsupported profile '$($scenario.profile)'."
        }
    }

    return $scenarios
}

function New-SkillEvalArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Scenario,

        [Parameter(Mandatory)]
        [string] $PluginDirectory,

        [Parameter(Mandatory)]
        [string] $Model,

        [Parameter(Mandatory)]
        [string] $TranscriptPath,

        [string] $Prompt = [string]$Scenario.prompt,

        [string] $UsageOutputPath,

        [string[]] $SecretEnvironmentNames = @(
            'COPILOT_GITHUB_TOKEN',
            'GH_TOKEN',
            'GITHUB_TOKEN',
            'COPILOT_PROVIDER_API_KEY',
            'COPILOT_PROVIDER_BEARER_TOKEN'
        ),

        [ValidateSet('enabled', 'no-skill')]
        [string] $SkillCondition = 'enabled'
    )

    $arguments = [System.Collections.Generic.List[string]]::new()
    $arguments.Add('-p')
    $arguments.Add($Prompt)
    if ($SkillCondition -eq 'enabled') {
        $arguments.Add('--plugin-dir')
        $arguments.Add($PluginDirectory)
        $arguments.Add('--add-dir')
        $arguments.Add($PluginDirectory)
    }
    foreach ($argument in @(
            '--model', $Model,
            '--reasoning-effort', 'medium',
            '--no-ask-user',
            '--no-auto-update',
            '--no-color',
            '--no-remote',
            '--disable-builtin-mcps',
            '--disable-mcp-server', 'microsoft-learn',
            '--disable-mcp-server', 'nuget',
            '--output-format', 'json',
            '--share', $TranscriptPath
        )) {
        $arguments.Add($argument)
    }
    $secretNames = @($SecretEnvironmentNames | Where-Object { $_ } | Sort-Object -Unique)
    if ($secretNames.Count -gt 0) {
        $arguments.Add("--secret-env-vars=$($secretNames -join ',')")
    }
    foreach ($tool in @($Scenario.allowedTools)) {
        $arguments.Add("--allow-tool=$tool")
    }
    foreach ($tool in @($Scenario.deniedTools)) {
        $arguments.Add("--deny-tool=$tool")
    }
    if (-not [string]::IsNullOrWhiteSpace($UsageOutputPath)) {
        $arguments.Add('--usage-output-file')
        $arguments.Add($UsageOutputPath)
        $arguments.Add('--excluded-tools=task')
    }

    return $arguments.ToArray()
}

function Resolve-SkillEvalCopilotPath {
    [CmdletBinding()]
    param([string] $CopilotPath)

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
            $signature = [Convert]::ToHexString($header)
            return $read -eq 4 -and $signature -in @(
                'FEEDFACE', 'FEEDFACF', 'CEFAEDFE', 'CFFAEDFE',
                'CAFEBABE', 'BEBAFECA', 'CAFEBABF', 'BFBAFECA')
        }
        return $false
    }

    if (-not [string]::IsNullOrWhiteSpace($CopilotPath)) {
        $resolvedPath = (Resolve-Path -LiteralPath $CopilotPath -ErrorAction Stop).Path
        $expectedName = if ($IsWindows) { 'copilot.exe' } else { 'copilot' }
        if ([System.IO.Path]::GetFileName($resolvedPath) -cne $expectedName) {
            throw "Copilot CLI path must name '$expectedName': $resolvedPath"
        }
        if (-not (Test-NativeExecutable $resolvedPath)) {
            throw "Copilot CLI path is not a native executable for this host: $resolvedPath"
        }
        return $resolvedPath
    }

    $commands = @(Get-Command copilot -CommandType Application -All -ErrorAction SilentlyContinue)
    $nativeCommands = @($commands | Where-Object {
            Test-NativeExecutable ([string]$_.Source)
        })
    if ($nativeCommands.Count -eq 0) {
        $candidates = @($commands | ForEach-Object { [string]$_.Source } |
            Sort-Object -Unique)
        $detail = if ($candidates.Count -gt 0) {
            " Launcher candidates were rejected: $($candidates -join ', ')."
        }
        else { '' }
        throw "A native Copilot CLI executable was not found.$detail"
    }
    return [string]$nativeCommands[0].Source
}

function ConvertFrom-SkillEvalCopilotVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Output
    )

    $version = $Output.Trim()
    $bannerLine = ($version -split '\r?\n', 2)[0]
    $prefix = 'GitHub Copilot CLI '
    if (-not $bannerLine.StartsWith($prefix, [StringComparison]::Ordinal)) {
        throw "Selected executable did not identify itself as GitHub Copilot CLI: $version"
    }
    $versionToken = $bannerLine.Substring($prefix.Length)
    if ($versionToken.EndsWith('.', [StringComparison]::Ordinal)) {
        $versionToken = $versionToken.Substring(0, $versionToken.Length - 1)
    }
    try {
        return [System.Management.Automation.SemanticVersion]::Parse(
            $versionToken)
    }
    catch {
        throw "Selected executable did not identify itself as GitHub Copilot CLI: $version"
    }
}

function Test-SkillEvalUsageModel ([string] $Model) {
    return $Model -in @(
        'gpt-5.6-sol', 'gpt-5.6-luna',
        'gpt-6-sol', 'gpt-6-luna', 'gpt-6.1-sol')
}

function Get-SkillEvalValidatedCopilotVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Output,

        [string] $Model
    )

    $version = $Output.Trim()
    $reportedVersion = ConvertFrom-SkillEvalCopilotVersion -Output $version
    $minimumVersionString = if (-not [string]::IsNullOrWhiteSpace($Model)) {
        '1.0.83'
    }
    else { '1.0.63' }
    $minimumVersion = [System.Management.Automation.SemanticVersion]::Parse(
        $minimumVersionString)
    if ($reportedVersion -lt $minimumVersion) {
        throw "Copilot CLI $minimumVersionString or later is required; selected executable reported: $version"
    }
    return $version
}

function Assert-SkillEvalCopilotExecutableHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $CopilotPath,

        [Parameter(Mandatory)]
        [string] $ExpectedSha256,

        [Parameter(Mandatory)]
        [string] $Operation
    )

    $actualSha256 = (Get-FileHash -LiteralPath $CopilotPath -Algorithm SHA256).Hash
    if ($actualSha256 -cne $ExpectedSha256) {
        throw "The selected Copilot CLI executable changed $Operation."
    }
}

function Get-SkillEvalClientIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Summary
    )

    if ($Summary.Count -eq 0) {
        throw 'Matrix client identity is incomplete because no document summaries were provided.'
    }
    $identities = foreach ($documentSummary in $Summary) {
        $versionProperty = $documentSummary.PSObject.Properties['CopilotVersion']
        $hashProperty = $documentSummary.PSObject.Properties['CopilotExecutableSha256']
        $verifiedProperty = $documentSummary.PSObject.Properties[
            'CopilotExecutableEvidenceVerified']
        $version = if ($versionProperty) { [string]$versionProperty.Value } else { '' }
        $hash = if ($hashProperty) { [string]$hashProperty.Value } else { '' }
        if ([string]::IsNullOrWhiteSpace($version) -or $hash -notmatch '^[0-9A-Fa-f]{64}$') {
            throw 'Matrix client identity is incomplete or invalid in a document summary.'
        }
        try {
            Get-SkillEvalValidatedCopilotVersion -Output $version | Out-Null
        }
        catch {
            throw "Matrix document summary has an invalid client version: $($_.Exception.Message)"
        }
        if (-not $verifiedProperty) {
            throw 'Matrix client identity is unverified in a document summary.'
        }
        if ($verifiedProperty.Value -isnot [bool]) {
            throw 'Matrix client identity verification flag must be a Boolean.'
        }
        if (-not $verifiedProperty.Value) {
            throw 'Matrix client identity is unverified in a document summary.'
        }
        [pscustomobject]@{
            CopilotVersion = $version
            CopilotExecutableSha256 = $hash.ToUpperInvariant()
        }
    }
    $versions = @($identities.CopilotVersion | Sort-Object -Unique -CaseSensitive)
    $hashes = @($identities.CopilotExecutableSha256 | Sort-Object -Unique)
    if ($versions.Count -ne 1 -or $hashes.Count -ne 1) {
        throw "Matrix client identities differ: versions=$($versions.Count), hashes=$($hashes.Count)."
    }
    return [pscustomobject]@{
        CopilotVersion = $versions[0]
        CopilotExecutableSha256 = $hashes[0]
        CopilotExecutableEvidenceVerified = $true
    }
}

function New-SkillEvalCopilotStartInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $CopilotPath,

        [string] $WorkingDirectory
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $CopilotPath
    if ($WorkingDirectory) { $startInfo.WorkingDirectory = $WorkingDirectory }
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $encoding = [System.Text.UTF8Encoding]::new($false)
    $startInfo.StandardOutputEncoding = $encoding
    $startInfo.StandardErrorEncoding = $encoding
    return $startInfo
}

function Get-SkillEvalCopilotVersion ([string] $CopilotPath, [string] $Model) {
    $startInfo = New-SkillEvalCopilotStartInfo -CopilotPath $CopilotPath
    $startInfo.Environment['COPILOT_AUTO_UPDATE'] = 'false'
    $startInfo.ArgumentList.Add('--version')
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'Copilot CLI version process did not start.' }
        $process.StandardInput.Close()
        $standardOutput = $process.StandardOutput.ReadToEndAsync()
        $standardError = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30 * 1000)) {
            $process.Kill($true)
            $process.WaitForExit()
            throw 'Copilot CLI version query timed out.'
        }
        $output = @(
            $standardOutput.GetAwaiter().GetResult()
            $standardError.GetAwaiter().GetResult()) -join [Environment]::NewLine
        if ($process.ExitCode -ne 0) {
            throw "Copilot CLI version query exited with code $($process.ExitCode):`n$output"
        }
        return Get-SkillEvalValidatedCopilotVersion -Output $output -Model $Model
    }
    finally { $process.Dispose() }
}

function Invoke-SkillEvalGit {
    param(
        [Parameter(Mandatory)]
        [string] $GitPath,

        [Parameter(Mandatory)]
        [string] $WorkingDirectory,

        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    $output = & $GitPath -C $WorkingDirectory @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed in '$WorkingDirectory':`n$($output -join "`n")"
    }
    return $output -join "`n"
}

function Get-SkillEvalWorktreeSnapshot {
    param(
        [Parameter(Mandatory)]
        [string] $GitPath,

        [Parameter(Mandatory)]
        [string] $WorkingDirectory
    )

    $status = [string](Invoke-SkillEvalGit -GitPath $GitPath -WorkingDirectory $WorkingDirectory -Arguments @('status', '--porcelain=v1', '--branch'))
    $head = [string](Invoke-SkillEvalGit -GitPath $GitPath -WorkingDirectory $WorkingDirectory -Arguments @('rev-parse', 'HEAD'))
    return [string]"$head`n$status"
}

function Get-SkillEvalCandidateRevision {
    param(
        [Parameter(Mandatory)]
        [string] $RepoRoot
    )

    $candidatePaths = @(
        'plugin.json',
        '.mcp.json',
        'skills',
        'agents',
        '.agents/skills')
    $candidateManifest = @($candidatePaths | ForEach-Object {
            $candidatePath = Join-Path $RepoRoot $_
            if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
                Get-Item -LiteralPath $candidatePath -Force
            }
            elseif (Test-Path -LiteralPath $candidatePath -PathType Container) {
                Get-ChildItem -LiteralPath $candidatePath -File -Recurse -Force
            }
        } |
        Sort-Object FullName -Unique |
        ForEach-Object {
            $relativePath = [System.IO.Path]::GetRelativePath(
                $RepoRoot,
                $_.FullName).Replace('\', '/')
            "$relativePath`:$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
        }) -join "`n"
    return [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData(
            [System.Text.Encoding]::UTF8.GetBytes($candidateManifest)))
}

function Get-SkillEvalObjectRevision {
    param(
        [Parameter(Mandatory)]
        [object] $InputObject
    )

    $json = $InputObject | ConvertTo-Json -Depth 30 -Compress
    return [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData(
            [System.Text.Encoding]::UTF8.GetBytes($json)))
}

function Get-SkillEvalRunArtifactRevision {
    param(
        [Parameter(Mandatory)]
        [string] $RunDirectory
    )

    $fileNames = @('stdout.jsonl', 'stderr.txt', 'transcript.md')
    foreach ($fileName in @('usage.json', 'telemetry.jsonl')) {
        if (Test-Path -LiteralPath (Join-Path $RunDirectory $fileName) -PathType Leaf) {
            $fileNames += $fileName
        }
    }
    $fileNames += 'shim.log'
    $manifest = @(foreach ($fileName in $fileNames) {
            $path = Join-Path $RunDirectory $fileName
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                "$fileName`:$((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash)"
            }
            else {
                "$fileName`:MISSING"
            }
        }) -join "`n"
    return [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData(
            [System.Text.Encoding]::UTF8.GetBytes($manifest)))
}

function Assert-SkillEvalUsageReceipt {
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $TelemetryPath,

        [Parameter(Mandatory)]
        [string] $ExpectedModel,

        [switch] $AllowRecoveredClientErrors
    )

    $receipt = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop |
        ConvertFrom-Json -AsHashtable -ErrorAction Stop
    if ($receipt -isnot [System.Collections.IDictionary] -or
        -not $receipt.Contains('totalUserRequests') -or
        [long]$receipt.totalUserRequests -lt 1 -or
        $receipt.modelMetrics -isnot [System.Collections.IDictionary] -or
        $receipt.modelMetrics.Count -eq 0) {
        throw 'The model usage receipt has no completed inference.'
    }
    foreach ($modelId in $receipt.modelMetrics.Keys) {
        if ([string]$modelId -cne $ExpectedModel) {
            throw "The usage receipt reports model '$modelId', not '$ExpectedModel'."
        }
    }
    $metrics = $receipt.modelMetrics[$ExpectedModel]
    if ($metrics -isnot [System.Collections.IDictionary] -or
        [long]$metrics.requests.count -lt 1 -or
        [long]$metrics.usage.inputTokens -lt 1 -or
        [long]$metrics.usage.outputTokens -lt 1) {
        throw 'The model usage receipt has incomplete token counts.'
    }

    $chatCount = 0
    $inputTokens = 0L
    $outputTokens = 0L
    $failedAttempts = [System.Collections.Generic.List[object]]::new()
    foreach ($line in (Get-Content -LiteralPath $TelemetryPath -ErrorAction Stop)) {
        $span = $line | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        if ($span -isnot [System.Collections.IDictionary] -or
            $span['type'] -ne 'span' -or
            $span['attributes'] -isnot [System.Collections.IDictionary]) {
            continue
        }
        $attributes = $span['attributes']
        if ($attributes['gen_ai.operation.name'] -ne 'chat') { continue }
        if ($attributes['gen_ai.request.model'] -cne $ExpectedModel -or
            $attributes['gen_ai.request.reasoning.level'] -cne 'medium') {
            throw 'A model call did not use the requested model and medium effort.'
        }
        if ($span['status'] -isnot [System.Collections.IDictionary] -or
            -not $span['status'].Contains('code')) {
            throw 'A model call is missing status code evidence.'
        }
        $finish = $attributes['gen_ai.response.finish_reasons']
        if ($AllowRecoveredClientErrors -and $finish -is [array] -and $finish.Count -eq 1 -and
            $finish[0] -ceq 'error' -and -not $attributes.Contains('gen_ai.response.model') -and
            -not $attributes.Contains('gen_ai.usage.input_tokens') -and
            -not $attributes.Contains('gen_ai.usage.output_tokens')) {
            $failedAttempts.Add([pscustomobject]@{
                SpanId = $span['spanId']
                RequestedModel = $ExpectedModel
                ReasoningEffort = 'medium'
                Outcome = 'client-internal-error-without-response'
                ResponseModel = $null
                InputTokens = $null
                OutputTokens = $null
            })
            continue
        }
        if ($attributes['gen_ai.response.model'] -cne $ExpectedModel -or
            ($finish -is [array] -and $finish -ccontains 'error')) {
            throw 'A model call did not use the requested model and medium effort: served-model evidence is missing, mismatched, or an error response.'
        }
        if ([int]$span['status']['code'] -ne 0) {
            throw 'A model call reported a failing status code.'
        }
        if (-not $attributes.Contains('gen_ai.usage.input_tokens') -or
            -not $attributes.Contains('gen_ai.usage.output_tokens')) {
            throw 'A model call is missing input or output tokens.'
        }
        $chatCount++
        $inputTokens += [long]$attributes.'gen_ai.usage.input_tokens'
        $outputTokens += [long]$attributes.'gen_ai.usage.output_tokens'
    }
    if ($chatCount -ne [long]$metrics.requests.count -or
        $inputTokens -ne [long]$metrics.usage.inputTokens -or
        $outputTokens -ne [long]$metrics.usage.outputTokens) {
        throw 'Per-call model usage does not reconcile with the final receipt.'
    }
    return [pscustomobject]@{
        CompletedCalls = $chatCount
        FailedClientAttempts = $failedAttempts.ToArray()
        InputTokens = $inputTokens
        OutputTokens = $outputTokens
    }
}

function Get-SkillEvalPathRevision {
    param(
        [Parameter(Mandatory)]
        [string] $Root,

        [Parameter(Mandatory)]
        [string] $RelativePath
    )

    $path = Join-Path $Root $RelativePath
    $items = @(if (Test-Path -LiteralPath $path -PathType Leaf) {
            Get-Item -LiteralPath $path -Force
        }
        elseif (Test-Path -LiteralPath $path -PathType Container) {
            Get-ChildItem -LiteralPath $path -File -Recurse -Force
        })
    $manifest = if ($items.Count -eq 0) {
        "$($RelativePath.Replace('\', '/')):MISSING_OR_EMPTY"
    }
    else {
        @($items | Sort-Object FullName | ForEach-Object {
                $itemRelativePath = [System.IO.Path]::GetRelativePath(
                    $Root,
                    $_.FullName).Replace('\', '/')
                "$itemRelativePath`:$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
            }) -join "`n"
    }
    return [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData(
            [System.Text.Encoding]::UTF8.GetBytes($manifest)))
}

function Resolve-SkillEvalFixturePath {
    param(
        [Parameter(Mandatory)]
        [string] $EvalRoot,

        [Parameter(Mandatory)]
        [string] $RelativePath,

        [Parameter(Mandatory)]
        [string] $Description,

        [Parameter(Mandatory)]
        [ValidateSet('Leaf', 'Container')]
        [string] $PathType,

        [bool] $RejectGitMetadata = $false
    )

    if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        throw "$Description fixture paths must be relative to the evaluation root."
    }
    $fixtureRoot = (Resolve-Path -LiteralPath (Join-Path $EvalRoot 'fixtures')).Path
    $fixturePath = (Resolve-Path -LiteralPath (Join-Path $EvalRoot $RelativePath)).Path
    $pathComparison = if ($IsWindows) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else { [System.StringComparison]::Ordinal }
    $fixturePrefix = $fixtureRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar) +
        [System.IO.Path]::DirectorySeparatorChar
    $pathDescription = if ($PathType -eq 'Leaf') { 'a file' } else { 'a directory' }
    if (-not $fixturePath.StartsWith($fixturePrefix, $pathComparison) -or
        -not (Test-Path -LiteralPath $fixturePath -PathType $PathType)) {
        throw "$Description fixture '$RelativePath' must be $pathDescription under '$fixtureRoot'."
    }

    $fixtureRelativePath = [System.IO.Path]::GetRelativePath($fixtureRoot, $fixturePath)
    $currentPath = $fixtureRoot
    foreach ($segment in $fixtureRelativePath -split '[\\/]') {
        $currentPath = Join-Path $currentPath $segment
        $currentItem = Get-Item -LiteralPath $currentPath -Force
        if (($currentItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "$Description fixture '$RelativePath' contains a reparse point at '$segment'."
        }
    }

    if ($PathType -eq 'Container') {
        $unsafeItem = @(Get-ChildItem -LiteralPath $fixturePath -Force -Recurse |
            Where-Object {
                ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
                ($RejectGitMetadata -and $_.Name -ieq '.git')
            } |
            Select-Object -First 1)
        if ($unsafeItem.Count -gt 0) {
            $unsafeRelativePath = [System.IO.Path]::GetRelativePath(
                $fixturePath,
                $unsafeItem[0].FullName)
            $unsafeKind = if (($unsafeItem[0].Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                'a reparse point'
            }
            else { 'Git metadata' }
            throw "$Description fixture '$RelativePath' contains $unsafeKind at '$unsafeRelativePath'."
        }
    }

    return $fixturePath
}

function Get-SkillEvalScenarioDependencies {
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Scenario,

        [Parameter(Mandatory)]
        [string] $RepoRoot
    )

    $dependencies = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    $dependencies.Add('manifest:plugin.json') | Out-Null
    $dependencies.Add('manifest:.mcp.json') | Out-Null
    $skillNames = [System.Collections.Generic.List[string]]::new()
    $skillNames.Add([string]$Scenario.skill)
    foreach ($propertyName in @(
            'requiredSkillInvocations',
            'forbiddenSkillInvocations')) {
        if ($Scenario.PSObject.Properties[$propertyName]) {
            foreach ($skillName in @($Scenario.$propertyName)) {
                $skillNames.Add([string]$skillName)
            }
        }
    }
    foreach ($skillName in $skillNames) {
        if ([string]::IsNullOrWhiteSpace($skillName)) { continue }
        $dependencies.Add("skill:$skillName") | Out-Null
        if (Test-Path -LiteralPath (Join-Path $RepoRoot ".agents/skills/$skillName") -PathType Container) {
            $dependencies.Add("project-skill:$skillName") | Out-Null
        }
    }
    return @($dependencies | Sort-Object)
}

function Get-SkillEvalScenarioMetadata {
    param(
        [Parameter(Mandatory)]
        [pscustomobject[]] $Scenarios,

        [Parameter(Mandatory)]
        [string] $RepoRoot,

        [Parameter(Mandatory)]
        [string] $EvalRoot
    )

    return @(foreach ($scenario in $Scenarios) {
            $fixturePaths = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::Ordinal)
            foreach ($fixtureProperty in @(
                    @{ Name = 'overlayPath'; Description = 'Overlay'; PathType = 'Leaf'; RejectGitMetadata = $false }
                    @{ Name = 'personalSkillFixturePath'; Description = 'Personal skill'; PathType = 'Container'; RejectGitMetadata = $false }
                    @{ Name = 'workspaceFixturePath'; Description = 'Workspace'; PathType = 'Container'; RejectGitMetadata = $true })) {
                $propertyName = [string]$fixtureProperty.Name
                if ($scenario.PSObject.Properties[$propertyName] -and
                    -not [string]::IsNullOrWhiteSpace([string]$scenario.$propertyName)) {
                    $fixturePath = Resolve-SkillEvalFixturePath `
                        -EvalRoot $EvalRoot `
                        -RelativePath ([string]$scenario.$propertyName) `
                        -Description ([string]$fixtureProperty.Description) `
                        -PathType ([string]$fixtureProperty.PathType) `
                        -RejectGitMetadata ([bool]$fixtureProperty.RejectGitMetadata)
                    $fixtureRelativePath = [System.IO.Path]::GetRelativePath(
                        $EvalRoot,
                        $fixturePath).Replace('\', '/')
                    $fixturePaths.Add($fixtureRelativePath) | Out-Null
                }
            }
            $fixtureManifest = @($fixturePaths | Sort-Object | ForEach-Object {
                    "$_`:$((Get-SkillEvalPathRevision -Root $EvalRoot -RelativePath $_))"
                }) -join "`n"
            $fixtureRevision = [Convert]::ToHexString(
                [System.Security.Cryptography.SHA256]::HashData(
                    [System.Text.Encoding]::UTF8.GetBytes($fixtureManifest)))
            [pscustomobject]@{
                ScenarioId = [string]$scenario.id
                Revision = Get-SkillEvalObjectRevision -InputObject $scenario
                FixtureRevision = $fixtureRevision
                Dependencies = Get-SkillEvalScenarioDependencies `
                    -Scenario $scenario `
                    -RepoRoot $RepoRoot
            }
        })
}

function Get-SkillEvalCandidateComponents {
    param(
        [Parameter(Mandatory)]
        [string] $RepoRoot
    )

    $components = [System.Collections.Generic.List[object]]::new()
    foreach ($manifestPath in @('plugin.json', '.mcp.json')) {
        $components.Add([pscustomobject]@{
                Key = "manifest:$manifestPath"
                Revision = Get-SkillEvalPathRevision -Root $RepoRoot -RelativePath $manifestPath
            })
    }
    foreach ($skillDirectory in @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'skills') -Directory | Sort-Object Name)) {
        $components.Add([pscustomobject]@{
                Key = "skill:$($skillDirectory.Name)"
                Revision = Get-SkillEvalPathRevision `
                    -Root $RepoRoot `
                    -RelativePath "skills/$($skillDirectory.Name)"
            })
    }
    foreach ($agentFile in @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'agents') -File | Sort-Object Name)) {
        $components.Add([pscustomobject]@{
                Key = "agent:$($agentFile.Name)"
                Revision = Get-SkillEvalPathRevision `
                    -Root $RepoRoot `
                    -RelativePath "agents/$($agentFile.Name)"
            })
    }
    $projectSkillsRoot = Join-Path $RepoRoot '.agents/skills'
    if (Test-Path -LiteralPath $projectSkillsRoot -PathType Container) {
        foreach ($skillDirectory in @(Get-ChildItem -LiteralPath $projectSkillsRoot -Directory | Sort-Object Name)) {
            $components.Add([pscustomobject]@{
                    Key = "project-skill:$($skillDirectory.Name)"
                    Revision = Get-SkillEvalPathRevision `
                        -Root $RepoRoot `
                        -RelativePath ".agents/skills/$($skillDirectory.Name)"
                })
        }
    }
    return @($components | Sort-Object Key)
}

function Get-SkillEvalAffectedScenarioIds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepoRoot,

        [Parameter(Mandatory)]
        [string] $ScenarioPath,

        [Parameter(Mandatory)]
        [string] $BaselineSummaryPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrWhiteSpace()]
        [string] $Model,

        [string[]] $ScenarioId,

        [ValidateSet('enabled', 'no-skill')]
        [string] $SkillCondition = 'enabled',

        [string] $TargetSkill
    )

    $resolvedRepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
    $resolvedScenarioPath = (Resolve-Path -LiteralPath $ScenarioPath).Path
    $evalRoot = (Resolve-Path -LiteralPath (Join-Path (Split-Path $resolvedScenarioPath) '..')).Path
    $baseline = Get-Content `
        -LiteralPath (Resolve-Path -LiteralPath $BaselineSummaryPath).Path `
        -Raw | ConvertFrom-Json
    $scenarios = @(Get-SkillEvalScenarios -Path $resolvedScenarioPath)
    if ($ScenarioId) {
        $scenarios = @($scenarios | Where-Object id -In $ScenarioId)
    }
    $exposure = Get-SkillEvalExposure -RepoRoot $resolvedRepoRoot `
        -SkillCondition $SkillCondition -TargetSkill $TargetSkill
    if ($baseline.PSObject.Properties['Exposure']) {
        if ([string]$baseline.Exposure.Revision -cne [string]$exposure.Revision) {
            return @($scenarios.id)
        }
    }
    elseif ($SkillCondition -ne 'enabled' -or $TargetSkill) {
        return @($scenarios.id)
    }
    if (-not $baseline.PSObject.Properties['Model'] -or
        [string]$baseline.Model -cne $Model -or
        -not $baseline.PSObject.Properties['ScenarioRevisions'] -or
        -not $baseline.PSObject.Properties['CandidateComponents']) {
        return @($scenarios.id)
    }

    $currentMetadata = @(Get-SkillEvalScenarioMetadata `
            -Scenarios $scenarios `
            -RepoRoot $resolvedRepoRoot `
            -EvalRoot $evalRoot)
    $baselineMetadataById = @{}
    foreach ($metadata in @($baseline.ScenarioRevisions)) {
        $baselineMetadataById[[string]$metadata.ScenarioId] = $metadata
    }
    $currentComponents = @(Get-SkillEvalCandidateComponents -RepoRoot $resolvedRepoRoot)
    $currentComponentByKey = @{}
    foreach ($component in $currentComponents) {
        $currentComponentByKey[[string]$component.Key] = [string]$component.Revision
    }
    $baselineComponentByKey = @{}
    foreach ($component in @($baseline.CandidateComponents)) {
        $baselineComponentByKey[[string]$component.Key] = [string]$component.Revision
    }
    $componentKeys = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($key in @($currentComponentByKey.Keys)) {
        $componentKeys.Add([string]$key) | Out-Null
    }
    foreach ($key in @($baselineComponentByKey.Keys)) {
        $componentKeys.Add([string]$key) | Out-Null
    }
    $changedComponents = @($componentKeys | Where-Object {
            -not $currentComponentByKey.ContainsKey($_) -or
            -not $baselineComponentByKey.ContainsKey($_) -or
            $currentComponentByKey[$_] -cne $baselineComponentByKey[$_]
        })

    $scenarioById = @{}
    foreach ($scenario in $scenarios) {
        $scenarioById[[string]$scenario.id] = $scenario
    }
    $affected = [System.Collections.Generic.List[string]]::new()
    foreach ($metadata in $currentMetadata) {
        $baselineMetadata = $baselineMetadataById[[string]$metadata.ScenarioId]
        if (-not $baselineMetadata -or
            [string]$baselineMetadata.Revision -cne [string]$metadata.Revision -or
            [string]$baselineMetadata.FixtureRevision -cne [string]$metadata.FixtureRevision) {
            $affected.Add([string]$metadata.ScenarioId)
            continue
        }
        $scenario = $scenarioById[[string]$metadata.ScenarioId]
        $isAffected = $false
        foreach ($componentKey in $changedComponents) {
            if ($componentKey -like 'manifest:*' -or
                $componentKey -like 'agent:*' -or
                $componentKey -in @($metadata.Dependencies) -or
                ([string]$scenario.category -ceq 'routing' -and
                    $componentKey -match '^(?:skill|project-skill):')) {
                $isAffected = $true
                break
            }
        }
        if ($isAffected) {
            $affected.Add([string]$metadata.ScenarioId)
        }
    }
    return $affected.ToArray()
}

function Get-SkillEvalWorkerAllocation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject[]] $Workload,

        [Parameter(Mandatory)]
        [ValidateRange(1, 32)]
        [int] $MaxConcurrency
    )

    if ($Workload.Count -eq 0) { throw 'At least one workload is required.' }
    if ($MaxConcurrency -lt $Workload.Count) {
        throw "Concurrency $MaxConcurrency cannot cover $($Workload.Count) workloads."
    }
    $allocations = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $Workload) {
        if ([int]$item.WorkItemCount -lt 1) {
            throw "Workload '$($item.Name)' must contain at least one item."
        }
        $allocations.Add([pscustomobject]@{
                Name = [string]$item.Name
                WorkItemCount = [int]$item.WorkItemCount
                Workers = 1
            })
    }
    for ($worker = $Workload.Count; $worker -lt $MaxConcurrency; $worker++) {
        $next = @($allocations | Sort-Object `
                @{ Expression = {
                        $_.WorkItemCount / ($_.Workers * ($_.Workers + 1))
                    }; Descending = $true },
                Name | Select-Object -First 1)[0]
        $next.Workers++
    }
    return @($allocations | Sort-Object Name)
}

function Get-SkillEvalUnixWrapper {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('git', 'gh')]
        [string] $CommandName
    )

    return (@'
#!/usr/bin/env sh
exec pwsh -NoProfile -File "$(dirname "$0")/{0}.ps1" "$@"
'@ -f $CommandName)
}

function New-SkillEvalShims {
    param(
        [Parameter(Mandatory)]
        [string] $Directory
    )

    New-Item -ItemType Directory -Path $Directory -Force | Out-Null

    $gitShim = @'
$ErrorActionPreference = 'Stop'
function Write-ShimLog([string] $Value) {
    $mutex = [System.Threading.Mutex]::new($false, $env:SKILL_EVAL_SHIM_MUTEX)
    $lockTaken = $false
    try {
        try { $lockTaken = $mutex.WaitOne([TimeSpan]::FromSeconds(30)) }
        catch [System.Threading.AbandonedMutexException] { $lockTaken = $true }
        if (-not $lockTaken) { throw 'Timed out waiting for the evaluation shim log.' }
        [System.IO.File]::AppendAllText(
            $env:SKILL_EVAL_SHIM_LOG,
            "$Value`n",
            [System.Text.UTF8Encoding]::new($false))
    }
    finally {
        if ($lockTaken) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

$effectiveArguments = @($args)
if ($effectiveArguments.Count -gt 0 -and $effectiveArguments[0] -eq '--no-pager') {
    $effectiveArguments = @($effectiveArguments | Select-Object -Skip 1)
}
$argumentsText = $effectiveArguments -join ' '
Write-ShimLog "git $argumentsText"

switch -Regex ($argumentsText) {
    '^remote -v$' {
        "origin`thttps://example.invalid/eval.git (fetch)"
        "origin`thttps://example.invalid/eval.git (push)"
        exit 0
    }
    '^remote get-url origin$' { 'https://example.invalid/eval.git'; exit 0 }
    '^remote$' { 'origin'; exit 0 }
    '^rev-parse --abbrev-ref HEAD$' { $env:SKILL_EVAL_BRANCH; exit 0 }
    '^rev-parse --show-toplevel$' { $env:SKILL_EVAL_WORKSPACE; exit 0 }
    '^branch --show-current$' { $env:SKILL_EVAL_BRANCH; exit 0 }
    '^status --porcelain(?:=v1)?$' {
        if ($env:SKILL_EVAL_DIRTY -eq 'true') { ' M README.md' }
        exit 0
    }
    '^status(?: --short)?$' {
        if ($env:SKILL_EVAL_DIRTY -eq 'true') { ' M README.md' } else { 'nothing to commit, working tree clean' }
        exit 0
    }
    '^log ' { exit 0 }
    '^diff --cached' { "diff --git a/README.md b/README.md`n+evaluation change"; exit 0 }
    '^diff' { "diff --git a/README.md b/README.md`n+evaluation change"; exit 0 }
    '^switch -c (?<branch>\S+)$' { "Switched to a new branch '$($Matches.branch)'"; exit 0 }
    '^add(?: |$)' { exit 0 }
    '^commit (?:--help|-h)(?: |$)' { 'usage: git commit [options]'; exit 0 }
    '^commit(?: |$)' { '[eval-feature 0123456] Evaluate README change'; exit 0 }
    '^fetch(?: |$)' { exit 0 }
    '^rev-list --left-right --count ' { "0`t1"; exit 0 }
    '^merge-base ' { '0123456789abcdef0123456789abcdef01234567'; exit 0 }
    '^merge-tree ' { exit 0 }
    '^push(?=.*(?:^| )--dry-run(?: |$))' { 'Everything up-to-date (dry run)'; exit 0 }
    '^push (?:--help|-h)(?: |$)' { 'usage: git push [options]'; exit 0 }
    '^push(?: |$)' { 'branch eval-feature set up to track origin/eval-feature.'; exit 0 }
    '^config --get-regexp ' { exit 1 }
    '^config(?: |$)' { exit 0 }
    '^branch(?: |$)' { "* $env:SKILL_EVAL_BRANCH"; exit 0 }
    default {
        [Console]::Error.WriteLine("Unsupported evaluation git command: git $argumentsText")
        exit 2
    }
}
'@

    $ghShim = @'
$ErrorActionPreference = 'Stop'
function Write-ShimLog([string] $Value) {
    $mutex = [System.Threading.Mutex]::new($false, $env:SKILL_EVAL_SHIM_MUTEX)
    $lockTaken = $false
    try {
        try { $lockTaken = $mutex.WaitOne([TimeSpan]::FromSeconds(30)) }
        catch [System.Threading.AbandonedMutexException] { $lockTaken = $true }
        if (-not $lockTaken) { throw 'Timed out waiting for the evaluation shim log.' }
        [System.IO.File]::AppendAllText(
            $env:SKILL_EVAL_SHIM_LOG,
            "$Value`n",
            [System.Text.UTF8Encoding]::new($false))
    }
    finally {
        if ($lockTaken) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

$argumentsText = @($args) -join ' '
Write-ShimLog "gh $argumentsText"

switch -Regex ($argumentsText) {
    '^auth status$' { 'Logged in to github.com as eval-user'; exit 0 }
    '^(?:--version|version)$' { 'gh version 2.90.0 (evaluation shim)'; exit 0 }
    '^repo view' { '{"nameWithOwner":"eval-user/eval-repo"}'; exit 0 }
    '^pr create (?:--help|-h)(?: |$)' { 'Create a pull request on GitHub.'; exit 0 }
    '^pr create(?: |$)' { 'https://github.com/eval-user/eval-repo/pull/1'; exit 0 }
    default {
        [Console]::Error.WriteLine("Unsupported evaluation gh command: gh $argumentsText")
        exit 2
    }
}
'@

    Set-Content -LiteralPath (Join-Path $Directory 'git.ps1') -Value $gitShim
    Set-Content -LiteralPath (Join-Path $Directory 'gh.ps1') -Value $ghShim

    foreach ($commandName in @('git', 'gh')) {
        $cmdWrapper = @"
@echo off
pwsh -NoProfile -File "%~dp0$commandName.ps1" %*
"@
        Set-Content -LiteralPath (Join-Path $Directory "$commandName.cmd") -Value $cmdWrapper

        if (-not $IsWindows) {
            $shellWrapper = Get-SkillEvalUnixWrapper -CommandName $commandName
            $shellPath = Join-Path $Directory $commandName
            Set-Content -LiteralPath $shellPath -Value $shellWrapper
            & chmod +x $shellPath
            if ($LASTEXITCODE -ne 0) { throw "Could not make '$shellPath' executable." }
        }
    }
}

function Get-SkillEvalExposure {
    <#
    .SYNOPSIS
        Resolves the evaluation treatment without staging or invoking a model.
    .DESCRIPTION
        The default enabled condition retains the complete plugin composition.
        TargetSkill restricts enabled staging to one public core and its transitive
        hard dependencies, with no agents, MCP configuration, or local overlays.
        Target selection accepts the commons' literal frontmatter contract:
        name: <directory-name>, metadata:, and consistently space-indented requires:
        none or comma-separated lowercase skill names. Other encodings fail closed.
        No-skill stages no customization artifacts. Both controlled treatments
        require fresh isolated homes and customization-free task fixtures.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    param(
        [Parameter(Mandatory)]
        [string] $RepoRoot,

        [ValidateSet('enabled', 'no-skill')]
        [string] $SkillCondition = 'enabled',

        [ValidatePattern('^(?:[a-z0-9]+(?:-[a-z0-9]+)*)?$')]
        [string] $TargetSkill
    )

    $skills = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $visiting = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    if ($TargetSkill) {
        $visit = {
            param([string] $Name)
            if ($visiting.Contains($Name)) { throw "Hard skill dependency cycle at '$Name'." }
            if ($skills.Contains($Name)) { return }
            $skillDirectory = Join-Path $RepoRoot "skills/$Name"
            $skillPath = Join-Path $skillDirectory 'SKILL.md'
            if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) {
                throw "Target or hard-required skill '$Name' does not exist."
            }
            $unsafeItems = @(Get-Item -LiteralPath $skillDirectory -Force) +
                @(Get-ChildItem -LiteralPath $skillDirectory -Force -Recurse)
            if (@($unsafeItems | Where-Object {
                        ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
                    }).Count -gt 0) {
                throw "Target or hard-required skill '$Name' contains a reparse point."
            }
            $lines = @(Get-Content -LiteralPath $skillPath)
            if ($lines.Count -lt 3 -or $lines[0] -cne '---') {
                throw "Unsupported literal frontmatter for skill '$Name'."
            }
            $end = [Array]::IndexOf($lines, '---', 1)
            if ($end -lt 0) { throw "Unclosed frontmatter for skill '$Name'." }
            $frontmatter = @($lines[1..($end - 1)])
            foreach ($line in $frontmatter) {
                if ($line -cmatch '^\S' -and -not $line.StartsWith('#') -and
                    $line -cnotmatch '^[a-z][a-z-]*:(?: |$)') {
                    throw "Unsupported literal top-level frontmatter for skill '$Name'."
                }
            }
            $nameLines = @($frontmatter | Where-Object { $_ -cmatch '^name:' })
            $metadataLines = @($frontmatter | Where-Object { $_ -cmatch '^metadata:' })
            if ($nameLines.Count -ne 1 -or $nameLines[0] -cne "name: $Name" -or
                $metadataLines.Count -ne 1 -or $metadataLines[0] -cne 'metadata:') {
                throw "Unsupported literal name/metadata frontmatter for skill '$Name'."
            }
            $metadataStart = [Array]::IndexOf($frontmatter, 'metadata:') + 1
            $requires = @()
            $metadataIndent = $null
            for ($index = $metadataStart; $index -lt $frontmatter.Count; $index++) {
                $line = [string]$frontmatter[$index]
                if ($line -cmatch '^\S') { break }
                if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) {
                    continue
                }
                $indent = [regex]::Match($line, '^ +').Length
                if ($indent -eq 0 -or ($null -ne $metadataIndent -and $indent -ne $metadataIndent)) {
                    throw "Unsupported literal metadata for skill '$Name'."
                }
                $metadataIndent = $indent
                $metadataLine = $line.Substring($indent)
                if ($metadataLine -cnotmatch '^[a-z][a-z-]*: [^\r\n]+$') {
                    throw "Unsupported literal metadata for skill '$Name'."
                }
                if ($metadataLine.StartsWith('requires:', [StringComparison]::Ordinal)) {
                    $requires += $metadataLine
                }
            }
            if ($requires.Count -ne 1 -or
                $requires[0] -cnotmatch '^requires: (none|[a-z0-9]+(?:-[a-z0-9]+)*(?:, [a-z0-9]+(?:-[a-z0-9]+)*)*)$') {
                throw "Unsupported literal metadata.requires for skill '$Name'."
            }
            $visiting.Add($Name) | Out-Null
            $value = $requires[0].Substring('requires: '.Length)
            if ($value -cne 'none') {
                foreach ($dependency in $value.Split(', ')) {
                    if ($dependency -ceq 'none') { throw "Invalid hard skill dependency 'none' for '$Name'." }
                    & $visit $dependency
                }
            }
            $visiting.Remove($Name) | Out-Null
            $skills.Add($Name) | Out-Null
        }
        & $visit $TargetSkill
    }
    elseif ($SkillCondition -eq 'enabled') {
        foreach ($directory in Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'skills') -Directory) {
            $skills.Add($directory.Name) | Out-Null
        }
    }
    $components = @()
    if ($SkillCondition -eq 'enabled') {
        $components = if ($TargetSkill) {
            @([pscustomobject]@{
                    Key = 'manifest:plugin.json'
                    Revision = Get-SkillEvalPathRevision -Root $RepoRoot -RelativePath 'plugin.json'
                }) + @(foreach ($name in @($skills | Sort-Object)) {
                    [pscustomobject]@{
                        Key = "skill:$name"
                        Revision = Get-SkillEvalPathRevision -Root $RepoRoot -RelativePath "skills/$name"
                    }
                })
        }
        else { @(Get-SkillEvalCandidateComponents -RepoRoot $RepoRoot) }
    }
    $exposedSkills = @()
    if ($SkillCondition -eq 'enabled') { $exposedSkills = @($skills | Sort-Object) }
    $exposure = [pscustomobject]@{
        SkillCondition = $SkillCondition
        TargetSkill = $TargetSkill
        Composition = if ($SkillCondition -eq 'no-skill') { 'none' }
            elseif ($TargetSkill) { 'target-core-and-hard-requires' } else { 'full-plugin' }
        Skills = $exposedSkills
        Components = @($components)
    }
    $exposure | Add-Member -NotePropertyName Revision `
        -NotePropertyValue (Get-SkillEvalObjectRevision -InputObject $exposure)
    return $exposure
}

function Get-SkillEvalStagedExposure {
    param([Parameter(Mandatory)][string] $RunDirectory)

    $runtimeFiles = [System.Collections.Generic.List[object]]::new()
    $runtimePrefix = 'sandbox-home/localappdata/copilot/pkg/'
    $files = @(foreach ($root in @('plugin', 'copilot-home', 'workspace', 'sandbox-home')) {
            $path = Join-Path $RunDirectory $root
            if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }
            $rootFiles = @(Get-ChildItem -LiteralPath $path -File -Force -Recurse)
            $bundlePrefixes = @(foreach ($entry in $rootFiles) {
                    if ($entry.Name -iin @('SKILL.md', 'plugin.json')) {
                        $relativeDirectory = [IO.Path]::GetRelativePath(
                            $RunDirectory, $entry.DirectoryName).Replace('\', '/') + '/'
                        if ($relativeDirectory.StartsWith($runtimePrefix, [StringComparison]::OrdinalIgnoreCase)) {
                            $relativeDirectory
                        }
                    }
                })
            $bundlePrefixes = @($bundlePrefixes | Sort-Object -Unique)
            foreach ($file in $rootFiles) {
                $relativePath = [IO.Path]::GetRelativePath($RunDirectory, $file.FullName).Replace('\', '/')
                $isBundledResource = $false
                foreach ($prefix in $bundlePrefixes) {
                    if ($relativePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                        $isBundledResource = $true
                        break
                    }
                }
                $isCustomization = $isBundledResource -or $root -eq 'plugin' -or
                    $file.Name -iin @('.mcp.json', 'plugin.json') -or
                    $file.Name -imatch '^(AGENTS|CLAUDE|GEMINI|SKILL)\.md$|(?:\.agent|\.instructions|\.prompt)\.md$|^copilot-instructions\.md$' -or
                    $relativePath -match '/(?:\.agents|\.claude|\.copilot)/(?:skills|agents|plugins)/|/\.github/(?:skills|agents|instructions|prompts)/|^copilot-home/(?:skills|agents|plugins)/'
                if ($isCustomization -and $relativePath -notmatch '^workspace/\.git/') {
                    $record = [pscustomobject]@{
                        Path = $relativePath
                        Sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
                    }
                    if ($relativePath.StartsWith($runtimePrefix, [StringComparison]::OrdinalIgnoreCase)) {
                        $runtimeFiles.Add($record)
                    }
                    else { $record }
                }
            }
        })
    $files = @($files | Sort-Object Path)
    return [pscustomobject]@{
        Files = $files
        Revision = Get-SkillEvalObjectRevision -InputObject ([pscustomobject]@{ Files = $files })
        ClientRuntimeExposure = [pscustomobject]@{
            Files = @($runtimeFiles | Sort-Object Path)
            Revision = Get-SkillEvalObjectRevision -InputObject ([pscustomobject]@{ Files = @($runtimeFiles | Sort-Object Path) })
        }
    }
}

function New-SkillEvalContext {
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Scenario,

        [Parameter(Mandatory)]
        [string] $RepoRoot,

        [Parameter(Mandatory)]
        [string] $EvalRoot,

        [Parameter(Mandatory)]
        [string] $RunDirectory,

        [ValidateSet('enabled', 'no-skill')]
        [string] $SkillCondition = 'enabled',

        [string] $TargetSkill
    )

    $exposure = Get-SkillEvalExposure -RepoRoot $RepoRoot `
        -SkillCondition $SkillCondition -TargetSkill $TargetSkill
    if ($TargetSkill -and $SkillCondition -eq 'enabled') {
        foreach ($propertyName in @('overlayPath', 'personalSkillFixturePath')) {
            if ($Scenario.PSObject.Properties[$propertyName] -and
                -not [string]::IsNullOrWhiteSpace([string]$Scenario.$propertyName)) {
                throw "Target-core exposure cannot include '$propertyName'; select a scenario without composition fixtures."
            }
        }
    }
    $gitPath = [string]@(Get-Command git -CommandType Application -All -ErrorAction Stop)[0].Source
    $workspace = Join-Path $RunDirectory 'workspace'
    $pluginDirectory = Join-Path $RunDirectory 'plugin'
    $shimDirectory = Join-Path $RunDirectory 'shims'
    $shimLogPath = Join-Path $RunDirectory 'shim.log'
    $sandboxHome = Join-Path $RunDirectory 'sandbox-home'
    $copilotHome = Join-Path $RunDirectory 'copilot-home'
    New-Item -ItemType Directory -Path $workspace, $pluginDirectory, $sandboxHome, $copilotHome | Out-Null

    & $gitPath -C $workspace init --initial-branch=main *> $null
    if ($LASTEXITCODE -ne 0) { throw "Could not initialize evaluation repository in '$workspace'." }
    Invoke-SkillEvalGit -GitPath $gitPath -WorkingDirectory $workspace -Arguments @('config', 'user.name', 'Skill Eval') | Out-Null
    Invoke-SkillEvalGit -GitPath $gitPath -WorkingDirectory $workspace -Arguments @('config', 'user.email', 'skill-eval@example.invalid') | Out-Null
    Set-Content -LiteralPath (Join-Path $workspace 'README.md') -Value "# Evaluation fixture`n"
    $hasWorkspaceFixture = $false
    if ($Scenario.PSObject.Properties['workspaceFixturePath'] -and
        -not [string]::IsNullOrWhiteSpace([string]$Scenario.workspaceFixturePath)) {
        $workspaceFixtureSource = Resolve-SkillEvalFixturePath `
            -EvalRoot $EvalRoot `
            -RelativePath ([string]$Scenario.workspaceFixturePath) `
            -Description 'Workspace' `
            -PathType Container `
            -RejectGitMetadata $true
        foreach ($item in Get-ChildItem -LiteralPath $workspaceFixtureSource -Force) {
            Copy-Item -LiteralPath $item.FullName -Destination $workspace -Recurse -Force
        }
        $hasWorkspaceFixture = $true
    }
    Invoke-SkillEvalGit -GitPath $gitPath -WorkingDirectory $workspace -Arguments @('add', '--all') | Out-Null
    Invoke-SkillEvalGit -GitPath $gitPath -WorkingDirectory $workspace -Arguments @('commit', '-m', 'Initialize evaluation fixture') | Out-Null

    $branch = 'main'
    if ([string]$Scenario.profile -in @('clean-feature', 'dirty-feature')) {
        $branch = 'eval-feature'
        Invoke-SkillEvalGit -GitPath $gitPath -WorkingDirectory $workspace -Arguments @('switch', '-c', $branch) | Out-Null
    }
    $isDirty = [string]$Scenario.profile -in @('dirty-feature', 'dirty-main')
    if ($isDirty) {
        Add-Content -LiteralPath (Join-Path $workspace 'README.md') -Value 'Evaluation change.'
    }

    if ($SkillCondition -eq 'enabled' -and $TargetSkill) {
        $plugin = Get-Content -LiteralPath (Join-Path $RepoRoot 'plugin.json') -Raw |
            ConvertFrom-Json -AsHashtable -ErrorAction Stop
        $plugin['skills'] = @('skills/')
        $plugin.Remove('agents') | Out-Null
        $plugin.Remove('mcpServers') | Out-Null
        $plugin | ConvertTo-Json -Depth 20 |
            Set-Content -LiteralPath (Join-Path $pluginDirectory 'plugin.json')
        $skillsRoot = Join-Path $pluginDirectory 'skills'
        New-Item -ItemType Directory -Path $skillsRoot | Out-Null
        foreach ($skillName in $exposure.Skills) {
            Copy-Item -LiteralPath (Join-Path $RepoRoot "skills/$skillName") `
                -Destination $skillsRoot -Recurse
        }
    }
    elseif ($SkillCondition -eq 'enabled') {
        foreach ($component in @('plugin.json', '.mcp.json', 'skills', 'agents')) {
            Copy-Item -LiteralPath (Join-Path $RepoRoot $component) -Destination $pluginDirectory -Recurse
        }
    }
    $projectSkillSource = Join-Path $RepoRoot ".agents/skills/$($Scenario.skill)"
    if ($SkillCondition -eq 'enabled' -and -not $TargetSkill -and
        (Test-Path -LiteralPath $projectSkillSource -PathType Container)) {
        $projectSkillsRoot = Join-Path $workspace '.agents/skills'
        New-Item -ItemType Directory -Path $projectSkillsRoot -Force | Out-Null
        Copy-Item -LiteralPath $projectSkillSource -Destination $projectSkillsRoot -Recurse
    }
    if ($SkillCondition -eq 'enabled' -and $Scenario.PSObject.Properties['overlayPath'] -and -not [string]::IsNullOrWhiteSpace([string]$Scenario.overlayPath)) {
        $overlaySource = Resolve-SkillEvalFixturePath `
            -EvalRoot $EvalRoot `
            -RelativePath ([string]$Scenario.overlayPath) `
            -Description 'Overlay' `
            -PathType Leaf
        $overlayTarget = Join-Path $pluginDirectory "skills/$($Scenario.skill)/overlay.md"
        Copy-Item -LiteralPath $overlaySource -Destination $overlayTarget
    }
    $hasPersonalSkillFixture = $false
    if ($SkillCondition -eq 'enabled' -and $Scenario.PSObject.Properties['personalSkillFixturePath'] -and
        -not [string]::IsNullOrWhiteSpace([string]$Scenario.personalSkillFixturePath)) {
        $personalSkillSource = Resolve-SkillEvalFixturePath `
            -EvalRoot $EvalRoot `
            -RelativePath ([string]$Scenario.personalSkillFixturePath) `
            -Description 'Personal skill' `
            -PathType Container
        $personalSkillRoot = Join-Path $copilotHome 'skills'
        $personalSkillTarget = Join-Path $personalSkillRoot (Split-Path -Leaf $personalSkillSource)
        New-Item -ItemType Directory -Path $personalSkillRoot -Force | Out-Null
        Copy-Item -LiteralPath $personalSkillSource -Destination $personalSkillTarget -Recurse
        $hasPersonalSkillFixture = $true
    }

    New-SkillEvalShims -Directory $shimDirectory
    Set-Content -LiteralPath $shimLogPath -Value @()
    $baselineWorktree = Get-SkillEvalWorktreeSnapshot -GitPath $gitPath -WorkingDirectory $workspace

    $stagedExposure = Get-SkillEvalStagedExposure -RunDirectory $RunDirectory
    if ($SkillCondition -eq 'no-skill' -and $stagedExposure.Files.Count -gt 0) {
        throw 'No-skill context contains customization artifacts in the task fixture; use a customization-free task fixture.'
    }
    if ($TargetSkill -and @($stagedExposure.Files | Where-Object Path -Like 'workspace/*').Count -gt 0) {
        throw 'Target-core context contains workspace customization artifacts; use a customization-free task fixture.'
    }
    return [pscustomobject]@{
        SkillCondition = $SkillCondition
        TargetSkill = $TargetSkill
        Exposure = $exposure
        StagedExposure = $stagedExposure
        GitPath = $gitPath
        Workspace = $workspace
        PluginDirectory = $pluginDirectory
        ShimDirectory = $shimDirectory
        ShimLogPath = $shimLogPath
        Branch = $branch
        IsDirty = $isDirty
        SandboxHome = $sandboxHome
        CopilotHome = $copilotHome
        HasWorkspaceFixture = $hasWorkspaceFixture
        HasPersonalSkillFixture = $hasPersonalSkillFixture
        BaselineWorktree = $baselineWorktree
        RunDirectory = $RunDirectory
    }
}

function Invoke-SkillEvalProcess {
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Scenario,

        [Parameter(Mandatory)]
        [pscustomobject] $Context,

        [Parameter(Mandatory)]
        [string] $Model,

        [Parameter(Mandatory)]
        [int] $TimeoutMinutes,

        [string] $CopilotPath,

        [scriptblock] $Executor,

        [switch] $IsolateCopilotHome = $true,

        [pscustomobject] $ContentPreparation
    )

    $transcriptPath = Join-Path $Context.RunDirectory 'transcript.md'
    $standardOutputPath = Join-Path $Context.RunDirectory 'stdout.jsonl'
    $standardErrorPath = Join-Path $Context.RunDirectory 'stderr.txt'
    $usageOutputPath = if (-not $Executor -and
        (Test-SkillEvalUsageModel -Model $Model)) {
        Join-Path $Context.RunDirectory 'usage.json'
    }
    else { $null }
    $secretEnvironmentNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($environmentName in @(
            'COPILOT_GITHUB_TOKEN',
            'GH_TOKEN',
            'GITHUB_TOKEN',
            'COPILOT_PROVIDER_API_KEY',
            'COPILOT_PROVIDER_BEARER_TOKEN'
        )) {
        $secretEnvironmentNames.Add($environmentName) | Out-Null
    }
    foreach ($environmentName in [Environment]::GetEnvironmentVariables('Process').Keys) {
        if ([string]$environmentName -match '(?i)(?:TOKEN|SECRET|PASSWORD|PASSCODE|API_KEY|PRIVATE_KEY|CREDENTIAL)') {
            $secretEnvironmentNames.Add([string]$environmentName) | Out-Null
        }
    }
    $arguments = New-SkillEvalArguments `
        -Scenario $Scenario `
        -Prompt $(if ($null -ne $ContentPreparation) { [string]$ContentPreparation.prompt } else { [string]$Scenario.prompt }) `
        -PluginDirectory $Context.PluginDirectory `
        -SkillCondition $Context.SkillCondition `
        -Model $Model `
        -TranscriptPath $transcriptPath `
        -UsageOutputPath $usageOutputPath `
        -SecretEnvironmentNames @($secretEnvironmentNames)
    if (($Context.SkillCondition -eq 'no-skill' -or $Context.TargetSkill) -and
        -not $IsolateCopilotHome) {
        throw 'Controlled skill exposure requires isolated Copilot homes.'
    }
    $effectiveCopilotHomeIsolation = $IsolateCopilotHome -or
        $Context.HasPersonalSkillFixture
    $invocation = [pscustomobject]@{
        SkillCondition = $Context.SkillCondition
        TargetSkill = $Context.TargetSkill
        Exposure = $Context.Exposure
        StagedExposure = $Context.StagedExposure
        Scenario = $Scenario
        Arguments = $arguments
        WorkingDirectory = $Context.Workspace
        PluginDirectory = $Context.PluginDirectory
        CopilotHome = $Context.CopilotHome
        IsolateCopilotHome = [bool] $effectiveCopilotHomeIsolation
        TranscriptPath = $transcriptPath
        StandardOutputPath = $standardOutputPath
        StandardErrorPath = $standardErrorPath
        UsageOutputPath = $usageOutputPath
        ShimLogPath = $Context.ShimLogPath
    }
    if ($null -ne $ContentPreparation) {
        $invocation | Add-Member -NotePropertyName ContentProfileRevision `
            -NotePropertyValue ([string]$ContentPreparation.profileRevision)
        $invocation | Add-Member -NotePropertyName ContentInputRevision `
            -NotePropertyValue ([string]$ContentPreparation.inputRevision)
    }
    $invocation | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $Context.RunDirectory 'invocation.json')

    if ($Executor) {
        $executorResult = & $Executor $invocation
        if ($executorResult.PSObject.Properties['Transcript']) {
            Set-Content -LiteralPath $transcriptPath -Value ([string]$executorResult.Transcript)
        }
        Set-Content -LiteralPath $standardOutputPath -Value ([string]$executorResult.StandardOutput)
        Set-Content -LiteralPath $standardErrorPath -Value ([string]$executorResult.StandardError)
        [pscustomobject]@{
            IsRealClient = $false
            ExitCode = [int]$executorResult.ExitCode
            TimedOut = $false
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Context.RunDirectory 'process.json')
        return [pscustomobject]@{
            ExitCode = [int]$executorResult.ExitCode
            TimedOut = $false
            TranscriptPath = $transcriptPath
            StandardOutputPath = $standardOutputPath
            StandardErrorPath = $standardErrorPath
            UsageOutputPath = $usageOutputPath
            Arguments = $arguments
        }
    }

    if ([string]::IsNullOrWhiteSpace($CopilotPath)) {
        throw 'A resolved native Copilot CLI path is required for a real evaluation.'
    }
    $startInfo = New-SkillEvalCopilotStartInfo `
        -CopilotPath $CopilotPath -WorkingDirectory $Context.Workspace
    foreach ($argument in $arguments) { $startInfo.ArgumentList.Add($argument) }

    $pathSeparator = [System.IO.Path]::PathSeparator
    $startInfo.Environment['PATH'] = "$($Context.ShimDirectory)$pathSeparator$($startInfo.Environment['PATH'])"
    $startInfo.Environment['SKILL_EVAL_SHIM_LOG'] = $Context.ShimLogPath
    $startInfo.Environment['SKILL_EVAL_SHIM_MUTEX'] = "SkillEval-$([guid]::NewGuid().ToString('N'))"
    $startInfo.Environment['SKILL_EVAL_BRANCH'] = $Context.Branch
    $startInfo.Environment['SKILL_EVAL_DIRTY'] = $Context.IsDirty.ToString().ToLowerInvariant()
    $startInfo.Environment['SKILL_EVAL_WORKSPACE'] = $Context.Workspace
    $startInfo.Environment['CI'] = 'true'
    $startInfo.Environment['NO_COLOR'] = '1'
    $startInfo.Environment['COPILOT_AUTO_UPDATE'] = 'false'
    if ($usageOutputPath) {
        $startInfo.Environment['COPILOT_OTEL_FILE_EXPORTER_PATH'] = Join-Path $Context.RunDirectory 'telemetry.jsonl'
        $startInfo.Environment['OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT'] = 'false'
    }
    $sandboxHome = $Context.SandboxHome
    $startInfo.Environment['HOME'] = $sandboxHome
    $startInfo.Environment['USERPROFILE'] = $sandboxHome
    $startInfo.Environment['APPDATA'] = Join-Path $sandboxHome 'appdata'
    $startInfo.Environment['LOCALAPPDATA'] = Join-Path $sandboxHome 'localappdata'
    $startInfo.Environment['XDG_CONFIG_HOME'] = Join-Path $sandboxHome 'config'
    $startInfo.Environment['GH_CONFIG_DIR'] = Join-Path $sandboxHome 'gh'
    $startInfo.Environment['GIT_CONFIG_GLOBAL'] = Join-Path $sandboxHome 'gitconfig'
    $startInfo.Environment['GIT_TERMINAL_PROMPT'] = '0'
    $startInfo.Environment['GH_PROMPT_DISABLED'] = '1'
    $startInfo.Environment['GCM_INTERACTIVE'] = 'Never'
    $startInfo.Environment.Remove('GH_TOKEN') | Out-Null
    $startInfo.Environment.Remove('GITHUB_TOKEN') | Out-Null
    $startInfo.Environment.Remove('GIT_ASKPASS') | Out-Null
    $startInfo.Environment.Remove('SSH_ASKPASS') | Out-Null
    $startInfo.Environment.Remove('SSH_AUTH_SOCK') | Out-Null
    if ($effectiveCopilotHomeIsolation) {
        $startInfo.Environment['COPILOT_HOME'] = $Context.CopilotHome
    }
    elseif (-not $startInfo.Environment.ContainsKey('COPILOT_HOME')) {
        $userProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
        $startInfo.Environment['COPILOT_HOME'] = Join-Path $userProfile '.copilot'
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $started = $process.Start()
    if (-not $started) { throw 'Copilot CLI did not start.' }
    $process.StandardInput.Close()
    $standardOutputTask = $process.StandardOutput.ReadToEndAsync()
    $standardErrorTask = $process.StandardError.ReadToEndAsync()
    $completed = $process.WaitForExit($TimeoutMinutes * 60 * 1000)
    if (-not $completed) {
        $process.Kill($true)
        $process.WaitForExit()
    }
    $standardOutput = $standardOutputTask.GetAwaiter().GetResult()
    $standardError = $standardErrorTask.GetAwaiter().GetResult()
    [System.IO.File]::WriteAllText($standardOutputPath, $standardOutput)
    [System.IO.File]::WriteAllText($standardErrorPath, $standardError)
    [pscustomobject]@{
        IsRealClient = $true
        ExitCode = if ($completed) { $process.ExitCode } else { -1 }
        TimedOut = -not $completed
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Context.RunDirectory 'process.json')

    return [pscustomobject]@{
        ExitCode = if ($completed) { $process.ExitCode } else { -1 }
        TimedOut = -not $completed
        TranscriptPath = $transcriptPath
        StandardOutputPath = $standardOutputPath
        StandardErrorPath = $standardErrorPath
        UsageOutputPath = $usageOutputPath
        Arguments = $arguments
    }
}

function Write-SkillEvalSummary {
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Summary,

        [Parameter(Mandatory)]
        [string] $OutputDirectory
    )

    $Summary | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'summary.json')
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Skill evaluation summary')
    $lines.Add('')
    $lines.Add("- Model: ``$($Summary.Model)``")
    if ($Summary.PSObject.Properties['Exposure']) {
        $lines.Add("- Skill condition: ``$($Summary.SkillCondition)``")
        $lines.Add("- Exposure composition: ``$($Summary.Exposure.Composition)``")
        $lines.Add("- Target skill: ``$($Summary.TargetSkill)``")
        $lines.Add("- Exposure input revision: ``$($Summary.Exposure.Revision)``")
        $lines.Add("- Staged exposure manifests: ``summary.json`` (StagedExposures)")
    }
    $lines.Add("- Copilot CLI: ``$($Summary.CopilotVersion)``")
    if (-not [string]::IsNullOrWhiteSpace([string]$Summary.CopilotExecutableSha256)) {
        $lines.Add("- Copilot executable SHA-256: ``$($Summary.CopilotExecutableSha256)``")
    }
    if ($Summary.PSObject.Properties['CopilotExecutableEvidenceVerified']) {
        $lines.Add("- Copilot executable evidence verified: ``$($Summary.CopilotExecutableEvidenceVerified.ToString().ToLowerInvariant())``")
    }
    $lines.Add("- Scenario revision: ``$($Summary.ScenarioRevision)``")
    $lines.Add("- Candidate revision: ``$($Summary.CandidateRevision)``")
    $lines.Add("- Fixture revision: ``$($Summary.FixtureRevision)``")
    $lines.Add("- Scorer revision: ``$($Summary.ScorerRevision)``")
    $lines.Add("- Requested concurrency: $($Summary.RequestedMaxConcurrency)")
    $lines.Add("- Effective concurrency: $($Summary.MaxConcurrency)")
    $lines.Add("- Wall time: $($Summary.WallTimeMilliseconds) ms")
    $lines.Add("- Scenarios: $($Summary.ScenarioCount)")
    $lines.Add("- Runs: $($Summary.RunCount)")
    $lines.Add("- Passed: $($Summary.PassedCount)")
    $lines.Add("- Failed: $($Summary.FailedCount)")
    $lines.Add("- Safety failures: $($Summary.SafetyFailureCount)")
    $lines.Add("- Infrastructure failures: $($Summary.InfrastructureFailureCount)")
    $lines.Add('')
    $lines.Add('| Scenario | Run | Result | Safety |')
    $lines.Add('| --- | ---: | --- | --- |')
    foreach ($run in $Summary.Runs) {
        $lines.Add("| ``$($run.ScenarioId)`` | $($run.RunNumber) | $(if ($run.Passed) { 'pass' } else { 'fail' }) | $(if ($run.SafetyPassed) { 'pass' } else { 'fail' }) |")
    }
    Set-Content -LiteralPath (Join-Path $OutputDirectory 'summary.md') -Value $lines
}

function Get-SkillEvalExitCode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Summary,

        [switch] $ReportOnly
    )

    if ($Summary.SafetyFailureCount -gt 0) { return 2 }
    if ($Summary.InfrastructureFailureCount -gt 0) { return 3 }
    if (-not $ReportOnly -and $Summary.FailedCount -gt 0) { return 1 }
    return 0
}

function Invoke-SkillEvalWorkItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Scenario,

        [Parameter(Mandatory)]
        [int] $ScenarioIndex,

        [Parameter(Mandatory)]
        [int] $RunNumber,

        [Parameter(Mandatory)]
        [string] $RepoRoot,

        [Parameter(Mandatory)]
        [string] $EvalRoot,

        [string] $ScenarioPath,

        [Parameter(Mandatory)]
        [string] $OutputDirectory,

        [Parameter(Mandatory)]
        [string] $Model,

        [Parameter(Mandatory)]
        [int] $TimeoutMinutes,

        [Parameter(Mandatory)]
        [datetime] $QueuedAtUtc,

        [string] $CopilotPath,

        [scriptblock] $Executor,

        [switch] $IsolateCopilotHome = $true,

        [pscustomobject] $ContentPreparation,

        [ValidateSet('enabled', 'no-skill')]
        [string] $SkillCondition = 'enabled',

        [string] $TargetSkill,

        [string] $ExposureRevision
    )

    $runDirectory = Join-Path $OutputDirectory "$($Scenario.id)/run-$RunNumber"
    New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
    $startedAtUtc = [DateTime]::UtcNow
    $queueMilliseconds = [Math]::Max(
        0,
        [long]($startedAtUtc - $QueuedAtUtc).TotalMilliseconds)
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $contextMilliseconds = 0L
    $processMilliseconds = 0L
    $scoringMilliseconds = 0L
    $result = $null
    $context = $null
    $finalStagedExposure = $null
    $usageEvidence = $null
    $processResult = $null
    try {
        $phaseStarted = $stopwatch.ElapsedMilliseconds
        $context = New-SkillEvalContext `
            -Scenario $Scenario `
            -RepoRoot $RepoRoot `
            -EvalRoot $EvalRoot `
            -RunDirectory $runDirectory `
            -SkillCondition $SkillCondition `
            -TargetSkill $TargetSkill
        $contextMilliseconds = $stopwatch.ElapsedMilliseconds - $phaseStarted
        if ($ExposureRevision -and $context.Exposure.Revision -cne $ExposureRevision) {
            throw 'Skill exposure inputs changed before context staging.'
        }
        [pscustomobject]@{
            SkillCondition = $SkillCondition
            TargetSkill = $TargetSkill
            Exposure = $context.Exposure
            StagedExposure = $context.StagedExposure
            ClientRuntimeExposure = $context.StagedExposure.ClientRuntimeExposure
            ShimLogPath = $context.ShimLogPath
            Workspace = $context.Workspace
            BaselineWorktree = $context.BaselineWorktree
            FinalWorktree = $null
        } | ConvertTo-Json -Depth 20 |
            Set-Content -LiteralPath (Join-Path $runDirectory 'context.json')

        $phaseStarted = $stopwatch.ElapsedMilliseconds
        $processResult = Invoke-SkillEvalProcess `
            -Scenario $Scenario `
            -Context $context `
            -Model $Model `
            -TimeoutMinutes $TimeoutMinutes `
            -CopilotPath $CopilotPath `
            -Executor $Executor `
            -IsolateCopilotHome:$IsolateCopilotHome `
            -ContentPreparation $ContentPreparation
        $processMilliseconds = $stopwatch.ElapsedMilliseconds - $phaseStarted
        $finalStagedExposure = Get-SkillEvalStagedExposure -RunDirectory $runDirectory
        if (($SkillCondition -eq 'no-skill' -or $TargetSkill) -and
            $finalStagedExposure.Revision -cne $context.StagedExposure.Revision) {
            throw 'Staged skill exposure changed during the evaluation.'
        }
        if ($processResult.TimedOut) {
            throw "Copilot CLI timed out after $TimeoutMinutes minute(s); no successful capture is reported."
        }
        if ($processResult.PSObject.Properties['UsageOutputPath'] -and
            $processResult.UsageOutputPath) {
            $usageEvidence = Assert-SkillEvalUsageReceipt `
                -Path $processResult.UsageOutputPath `
                -TelemetryPath (Join-Path $runDirectory 'telemetry.jsonl') `
                -ExpectedModel $Model `
                -AllowRecoveredClientErrors:([bool]$TargetSkill)
        }

        if ([bool]$Scenario.requireUnchangedWorktree) {
            $finalWorktree = Get-SkillEvalWorktreeSnapshot `
                -GitPath $context.GitPath `
                -WorkingDirectory $context.Workspace
            $context | Add-Member `
                -NotePropertyName FinalWorktree `
                -NotePropertyValue $finalWorktree
        }
        [pscustomobject]@{
            SkillCondition = $SkillCondition
            TargetSkill = $TargetSkill
            Exposure = $context.Exposure
            StagedExposure = $context.StagedExposure
            ShimLogPath = $context.ShimLogPath
            Workspace = $context.Workspace
            BaselineWorktree = $context.BaselineWorktree
            FinalWorktree = if ($context.PSObject.Properties['FinalWorktree']) {
                $context.FinalWorktree
            }
            else { $null }
            ClientRuntimeExposure = $finalStagedExposure.ClientRuntimeExposure
        } | ConvertTo-Json -Depth 20 |
            Set-Content -LiteralPath (Join-Path $runDirectory 'context.json')

        $phaseStarted = $stopwatch.ElapsedMilliseconds
        $assessment = Test-SkillEvalEvidence `
            -Scenario $Scenario `
            -ProcessResult $processResult `
            -Context $context
        $scoringMilliseconds = $stopwatch.ElapsedMilliseconds - $phaseStarted
        $result = [pscustomobject]@{
            ScenarioId = [string]$Scenario.id
            ScenarioIndex = $ScenarioIndex
            Skill = [string]$Scenario.skill
            Category = [string]$Scenario.category
            EvidenceKind = [string]$Scenario.evidenceKind
            RunNumber = $RunNumber
            Model = $Model
            Passed = $assessment.Passed
            SafetyPassed = $assessment.SafetyPassed
            ExitCode = $processResult.ExitCode
            TimedOut = $processResult.TimedOut
            InvokedSkills = $assessment.InvokedSkills
            Evidence = $assessment.Evidence
            RunDirectory = $runDirectory
            Error = $null
        }
        if ($null -ne $ContentPreparation) {
            $captureStarted = $stopwatch.ElapsedMilliseconds
            $captureReceipt = Invoke-SkillEvalContentCli -Arguments @(
                'capture',
                '--repo-root', $RepoRoot,
                '--scenario', $ScenarioPath,
                '--scenario-id', [string]$Scenario.id,
                '--workspace', [string]$context.Workspace,
                '--run-directory', $runDirectory,
                '--run-number', $RunNumber.ToString(),
                '--scenario-revision', (Get-SkillEvalObjectRevision -InputObject $Scenario)
            )
            if ($captureReceipt.ExitCode -ne 0) {
                throw "Content capture failed (exit $($captureReceipt.ExitCode)): $($captureReceipt.StandardError)"
            }
            $capture = ConvertFrom-Json -InputObject $captureReceipt.StandardOutput -ErrorAction Stop
            if ([string]$capture.profileRevision -cne [string]$ContentPreparation.profileRevision -or
                [string]$capture.inputRevision -cne [string]$ContentPreparation.inputRevision -or
                [string]$capture.modelOutputRevision -cne (Get-SkillEvalRunArtifactRevision -RunDirectory $runDirectory)) {
                throw 'Content inputs or source output changed during artifact capture.'
            }
            $result | Add-Member -NotePropertyName ArtifactManifestRevision `
                -NotePropertyValue ([string]$capture.artifactManifestRevision)
            $result | Add-Member -NotePropertyName ContentProfileRevision `
                -NotePropertyValue ([string]$capture.profileRevision)
            $result | Add-Member -NotePropertyName ContentInputRevision `
                -NotePropertyValue ([string]$capture.inputRevision)
            $result | Add-Member -NotePropertyName ContentCaptureMilliseconds `
                -NotePropertyValue ($stopwatch.ElapsedMilliseconds - $captureStarted)
        }
    }
    catch {
        if ($null -ne $result) {
            $result.Error = $_.Exception.Message
        }
        else {
            $result = [pscustomobject]@{
            ScenarioId = [string]$Scenario.id
            ScenarioIndex = $ScenarioIndex
            Skill = [string]$Scenario.skill
            Category = [string]$Scenario.category
            EvidenceKind = [string]$Scenario.evidenceKind
            RunNumber = $RunNumber
            Model = $Model
            Passed = $false
            SafetyPassed = $true
            ExitCode = if ($null -ne $processResult) { $processResult.ExitCode } else { -1 }
            TimedOut = if ($null -ne $processResult) { $processResult.TimedOut } else { $false }
            InvokedSkills = @()
            Evidence = @()
            RunDirectory = $runDirectory
            Error = $_.Exception.Message
            }
        }
    }
    $stopwatch.Stop()
    $result | Add-Member -NotePropertyName SkillCondition -NotePropertyValue $SkillCondition
    $result | Add-Member -NotePropertyName TargetSkill -NotePropertyValue $TargetSkill
    $result | Add-Member -NotePropertyName StagedExposure `
        -NotePropertyValue $(if ($null -ne $context) { $context.StagedExposure } else { $null })
    $result | Add-Member -NotePropertyName ClientRuntimeExposure `
        -NotePropertyValue $(if ($null -ne $finalStagedExposure) { $finalStagedExposure.ClientRuntimeExposure } else { $null })
    $result | Add-Member -NotePropertyName ModelUsageEvidence -NotePropertyValue $usageEvidence
    $result | Add-Member -NotePropertyName ExposureRevision `
        -NotePropertyValue $(if ($null -ne $context) { $context.Exposure.Revision } else { $ExposureRevision })
    $result | Add-Member -NotePropertyName QueuedAtUtc -NotePropertyValue $QueuedAtUtc.ToString('O')
    $result | Add-Member -NotePropertyName StartedAtUtc -NotePropertyValue $startedAtUtc.ToString('O')
    $result | Add-Member -NotePropertyName QueueMilliseconds -NotePropertyValue $queueMilliseconds
    $result | Add-Member -NotePropertyName ContextMilliseconds -NotePropertyValue $contextMilliseconds
    $result | Add-Member -NotePropertyName ProcessMilliseconds -NotePropertyValue $processMilliseconds
    $result | Add-Member -NotePropertyName ScoringMilliseconds -NotePropertyValue $scoringMilliseconds
    $result | Add-Member -NotePropertyName DurationMilliseconds -NotePropertyValue $stopwatch.ElapsedMilliseconds
    $result | Add-Member `
        -NotePropertyName ScenarioRevision `
        -NotePropertyValue (Get-SkillEvalObjectRevision -InputObject $Scenario)
    $result | Add-Member `
        -NotePropertyName ModelOutputRevision `
        -NotePropertyValue (Get-SkillEvalRunArtifactRevision -RunDirectory $runDirectory)
    $result | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath (Join-Path $runDirectory 'result.json')
    return $result
}

function Invoke-SkillEvalSuite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepoRoot,

        [Parameter(Mandatory)]
        [string] $ScenarioPath,

        [Parameter(Mandatory)]
        [string] $OutputDirectory,

        [Parameter(Mandatory)]
        [ValidateNotNullOrWhiteSpace()]
        [string] $Model,

        [string[]] $ScenarioId,

        [int] $RunCount,

        [int] $TimeoutMinutes = 5,

        [ValidateRange(1, 32)]
        [int] $MaxConcurrency = 8,

        [scriptblock] $Executor,

        [switch] $IsolateCopilotHome = $true,

        [string] $CopilotPath,

        [ValidateSet('enabled', 'no-skill')]
        [string] $SkillCondition = 'enabled',

        [string] $TargetSkill
    )

    $resolvedRepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
    if (($SkillCondition -eq 'no-skill' -or $TargetSkill) -and -not $IsolateCopilotHome) {
        throw 'Controlled skill exposure requires isolated Copilot homes.'
    }
    $exposure = Get-SkillEvalExposure -RepoRoot $resolvedRepoRoot `
        -SkillCondition $SkillCondition -TargetSkill $TargetSkill
    $resolvedScenarioPath = (Resolve-Path -LiteralPath $ScenarioPath).Path
    $evalRoot = (Resolve-Path -LiteralPath (Join-Path (Split-Path $resolvedScenarioPath) '..')).Path
    $fixtureRoot = (Resolve-Path -LiteralPath (Join-Path $evalRoot 'fixtures')).Path
    $scorerRevision = (Get-FileHash -LiteralPath (Join-Path $evalRoot 'SkillEvalScorer.ps1') -Algorithm SHA256).Hash
    $resolvedCopilotPath = if ($Executor) {
        $null
    }
    else { Resolve-SkillEvalCopilotPath -CopilotPath $CopilotPath }
    $copilotExecutableSha256 = if ($Executor) {
        $null
    }
    else { (Get-FileHash -LiteralPath $resolvedCopilotPath -Algorithm SHA256).Hash }
    $copilotVersion = if ($Executor) {
        'fake-executor'
    }
    else { Get-SkillEvalCopilotVersion -CopilotPath $resolvedCopilotPath -Model $Model }
    if (-not $Executor) {
        Assert-SkillEvalCopilotExecutableHash `
            -CopilotPath $resolvedCopilotPath `
            -ExpectedSha256 $copilotExecutableSha256 `
            -Operation 'during version verification'
    }
    $candidateRevision = Get-SkillEvalCandidateRevision -RepoRoot $resolvedRepoRoot
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    $resolvedOutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
    $scenarios = @(Get-SkillEvalScenarios -Path $resolvedScenarioPath)
    if ($ScenarioId) {
        $scenarios = @($scenarios | Where-Object id -In $ScenarioId)
        $missingIdentifiers = @($ScenarioId | Where-Object { $_ -notin $scenarios.id })
        if ($missingIdentifiers.Count -gt 0) {
            throw "Unknown scenario id(s): $($missingIdentifiers -join ', ')."
        }
    }

    $contentByScenario = @{}
    if (@($scenarios | Where-Object { $_.PSObject.Properties['contentEvaluation'] }).Count -gt 0) {
        $preparationReceipt = Invoke-SkillEvalContentCli -Arguments @(
            'prepare',
            '--repo-root', $resolvedRepoRoot,
            '--scenario', $resolvedScenarioPath
        )
        if ($preparationReceipt.ExitCode -ne 0) {
            throw "Content profile preparation failed (exit $($preparationReceipt.ExitCode)): $($preparationReceipt.StandardError)"
        }
        $preparations = ConvertFrom-Json -InputObject $preparationReceipt.StandardOutput -NoEnumerate -ErrorAction Stop
        if ($preparations -isnot [array]) { throw 'Content preparation must return a JSON array.' }
        foreach ($preparation in $preparations) {
            if ($contentByScenario.ContainsKey([string]$preparation.scenarioId)) {
                throw 'Content preparation returned a duplicate scenario.'
            }
            $contentByScenario[[string]$preparation.scenarioId] = $preparation
        }
        foreach ($scenario in @($scenarios | Where-Object { $_.PSObject.Properties['contentEvaluation'] })) {
            if (-not $contentByScenario.ContainsKey([string]$scenario.id)) {
                throw "Content preparation omitted profiled scenario '$($scenario.id)'."
            }
        }
    }
    $queuedAtUtc = [DateTime]::UtcNow
    $workItems = [System.Collections.Generic.List[object]]::new()
    for ($scenarioIndex = 0; $scenarioIndex -lt $scenarios.Count; $scenarioIndex++) {
        $scenario = $scenarios[$scenarioIndex]
        $scenarioRunCount = if ($RunCount -gt 0) { $RunCount } else { [int]$scenario.runCount }
        for ($runNumber = 1; $runNumber -le $scenarioRunCount; $runNumber++) {
            $workItems.Add([pscustomobject]@{
                    Scenario = $scenario
                    ScenarioIndex = $scenarioIndex
                    RunNumber = $runNumber
                    QueuedAtUtc = $queuedAtUtc
                    ContentPreparation = $contentByScenario[[string]$scenario.id]
                    SkillCondition = $SkillCondition
                    TargetSkill = $TargetSkill
                    ExposureRevision = $exposure.Revision
                })
        }
    }

    $effectiveMaxConcurrency = if ($Executor) { 1 } else { $MaxConcurrency }
    $suiteStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    if ($effectiveMaxConcurrency -eq 1) {
        $resultArray = @($workItems | ForEach-Object {
                Invoke-SkillEvalWorkItem `
                    -Scenario $_.Scenario `
                    -ScenarioIndex $_.ScenarioIndex `
                    -RunNumber $_.RunNumber `
                    -RepoRoot $resolvedRepoRoot `
                    -EvalRoot $evalRoot `
                    -ScenarioPath $resolvedScenarioPath `
                    -OutputDirectory $resolvedOutputDirectory `
                    -Model $Model `
                    -TimeoutMinutes $TimeoutMinutes `
                    -QueuedAtUtc $_.QueuedAtUtc `
                    -CopilotPath $resolvedCopilotPath `
                    -Executor $Executor `
                    -IsolateCopilotHome:$IsolateCopilotHome `
                    -ContentPreparation $_.ContentPreparation `
                    -SkillCondition $_.SkillCondition `
                    -TargetSkill $_.TargetSkill `
                    -ExposureRevision $_.ExposureRevision
            })
    }
    else {
        $modulePath = $MyInvocation.MyCommand.Module.Path
        $isolateCopilotHomeValue = [bool]$IsolateCopilotHome
        $resultArray = @($workItems | ForEach-Object -Parallel {
                $module = Import-Module $using:modulePath -Force -PassThru
                & $module {
                    param(
                        $WorkItem,
                        $RepoRoot,
                        $EvalRoot,
                        $ScenarioPath,
                        $OutputDirectory,
                        $Model,
                        $TimeoutMinutes,
                        $CopilotPath,
                        $IsolateCopilotHome
                    )

                    Invoke-SkillEvalWorkItem `
                        -Scenario $WorkItem.Scenario `
                        -ScenarioIndex $WorkItem.ScenarioIndex `
                        -RunNumber $WorkItem.RunNumber `
                        -RepoRoot $RepoRoot `
                        -EvalRoot $EvalRoot `
                        -ScenarioPath $ScenarioPath `
                        -OutputDirectory $OutputDirectory `
                        -Model $Model `
                        -TimeoutMinutes $TimeoutMinutes `
                        -QueuedAtUtc $WorkItem.QueuedAtUtc `
                        -CopilotPath $CopilotPath `
                        -IsolateCopilotHome:$IsolateCopilotHome `
                        -ContentPreparation $WorkItem.ContentPreparation `
                        -SkillCondition $WorkItem.SkillCondition `
                        -TargetSkill $WorkItem.TargetSkill `
                        -ExposureRevision $WorkItem.ExposureRevision
                } `
                    $_ `
                    $using:resolvedRepoRoot `
                    $using:evalRoot `
                    $using:resolvedScenarioPath `
                    $using:resolvedOutputDirectory `
                    $using:Model `
                    $using:TimeoutMinutes `
                    $using:resolvedCopilotPath `
                    $using:isolateCopilotHomeValue
            } -ThrottleLimit $effectiveMaxConcurrency)
    }
    $suiteStopwatch.Stop()
    if (-not $Executor) {
        Assert-SkillEvalCopilotExecutableHash `
            -CopilotPath $resolvedCopilotPath `
            -ExpectedSha256 $copilotExecutableSha256 `
            -Operation 'during evaluation execution'
    }
    $resultArray = @($resultArray | Sort-Object ScenarioIndex, RunNumber)
    if ($resultArray.Count -ne $workItems.Count) {
        throw "Expected $($workItems.Count) evaluation results but received $($resultArray.Count)."
    }
    $resultKeys = @($resultArray | ForEach-Object {
            "$($_.ScenarioIndex):$($_.RunNumber)"
        })
    if (@($resultKeys | Sort-Object -Unique).Count -ne $workItems.Count) {
        throw 'Evaluation results contain a missing or duplicate scenario/run pair.'
    }
    $finalCandidateRevision = Get-SkillEvalCandidateRevision -RepoRoot $resolvedRepoRoot
    if ($finalCandidateRevision -cne $candidateRevision) {
        throw 'Evaluated candidate inputs changed while the suite was running.'
    }
    $fixtureManifest = @(Get-ChildItem -LiteralPath $fixtureRoot -File -Recurse |
        Sort-Object FullName |
        ForEach-Object {
            $relativePath = [System.IO.Path]::GetRelativePath(
                $evalRoot,
                $_.FullName).Replace('\', '/')
            "$relativePath`:$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
        }) -join "`n"
    $fixtureRevision = [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData(
            [System.Text.Encoding]::UTF8.GetBytes($fixtureManifest)))
    $scenarioMetadata = Get-SkillEvalScenarioMetadata `
        -Scenarios $scenarios `
        -RepoRoot $resolvedRepoRoot `
        -EvalRoot $evalRoot
    $summary = [pscustomobject]@{
        SchemaVersion = 1
        GeneratedAtUtc = [DateTime]::UtcNow.ToString('O')
        Model = $Model
        SkillCondition = $SkillCondition
        TargetSkill = $TargetSkill
        Exposure = $exposure
        StagedExposures = @($resultArray | ForEach-Object {
                [pscustomobject]@{
                    ScenarioId = $_.ScenarioId
                    RunNumber = $_.RunNumber
                    StagedExposure = $_.StagedExposure
                }
            })
        ScenarioRevision = (Get-FileHash -LiteralPath $resolvedScenarioPath -Algorithm SHA256).Hash
        CandidateRevision = $candidateRevision
        CandidateComponents = Get-SkillEvalCandidateComponents -RepoRoot $resolvedRepoRoot
        FixtureRevision = $fixtureRevision
        ScenarioRevisions = $scenarioMetadata
        ScorerRevision = $scorerRevision
        RequestedMaxConcurrency = $MaxConcurrency
        MaxConcurrency = $effectiveMaxConcurrency
        WallTimeMilliseconds = $suiteStopwatch.ElapsedMilliseconds
        GeneratedRunCount = $resultArray.Count
        RescoredRunCount = 0
        ReusedRunCount = 0
        RetryCount = 0
        ScenarioCount = $scenarios.Count
        RunCount = $resultArray.Count
        PassedCount = @($resultArray | Where-Object Passed).Count
        FailedCount = @($resultArray | Where-Object { -not $_.Passed }).Count
        SafetyFailureCount = @($resultArray | Where-Object { -not $_.SafetyPassed }).Count
        InfrastructureFailureCount = @($resultArray | Where-Object {
                $_.TimedOut -or $_.ExitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace([string]$_.Error)
            }).Count
        CopilotVersion = $copilotVersion
        CopilotExecutableSha256 = $copilotExecutableSha256
        CopilotExecutableEvidenceVerified = $true
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        OperatingSystem = $PSVersionTable.OS
        Runs = $resultArray
    }
    Write-SkillEvalSummary -Summary $summary -OutputDirectory $resolvedOutputDirectory
    return $summary
}

function Invoke-SkillEvalRescore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RepoRoot,

        [Parameter(Mandatory)]
        [string] $ScenarioPath,

        [Parameter(Mandatory)]
        [string] $InputDirectory,

        [Parameter(Mandatory)]
        [string] $OutputDirectory,

        [string[]] $ScenarioId,

        [switch] $AllowLegacyUnverifiedEvidence
    )

    $resolvedRepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
    $resolvedScenarioPath = (Resolve-Path -LiteralPath $ScenarioPath).Path
    $evalRoot = (Resolve-Path -LiteralPath (Join-Path (Split-Path $resolvedScenarioPath) '..')).Path
    $resolvedInputDirectory = (Resolve-Path -LiteralPath $InputDirectory).Path
    $sourceSummaryPath = Join-Path $resolvedInputDirectory 'summary.json'
    if (-not (Test-Path -LiteralPath $sourceSummaryPath -PathType Leaf)) {
        throw "Source summary not found: $sourceSummaryPath"
    }
    $sourceSummary = Get-Content -LiteralPath $sourceSummaryPath -Raw |
        ConvertFrom-Json
    $sourceCopilotVersion = if ($sourceSummary.PSObject.Properties['CopilotVersion']) {
        [string]$sourceSummary.CopilotVersion
    }
    else { '' }
    $sourceCopilotExecutableSha256 = if (
        $sourceSummary.PSObject.Properties['CopilotExecutableSha256']) {
        [string]$sourceSummary.CopilotExecutableSha256
    }
    else { '' }
    $isDeterministicExecutorEvidence = $sourceCopilotVersion -ceq 'fake-executor'
    $sourceCopilotVersionVerified = $isDeterministicExecutorEvidence
    $sourceCopilotVersionError = ''
    if (-not $isDeterministicExecutorEvidence) {
        $reportedSourceCopilotVersion = ConvertFrom-SkillEvalCopilotVersion `
            -Output $sourceCopilotVersion
        $minimumCopilotVersion = [System.Management.Automation.SemanticVersion]::Parse(
            '1.0.63')
        if ($reportedSourceCopilotVersion -lt $minimumCopilotVersion) {
            $sourceCopilotVersionError =
                "Copilot CLI 1.0.63 or later is required; selected executable reported: $sourceCopilotVersion"
        }
        else {
            $sourceCopilotVersionVerified = $true
        }
    }
    $hasCopilotExecutableHash = $sourceCopilotExecutableSha256 -match '^[0-9A-Fa-f]{64}$'
    $sourceVerificationProperty = $sourceSummary.PSObject.Properties[
        'CopilotExecutableEvidenceVerified']
    if ($sourceVerificationProperty -and
        $sourceVerificationProperty.Value -isnot [bool]) {
        throw 'Source summary Copilot executable verification flag must be a Boolean.'
    }
    $sourceVerificationMissing = -not $sourceVerificationProperty
    $sourceMarksCopilotEvidenceUnverified = $sourceVerificationProperty -and
        -not $sourceVerificationProperty.Value
    $sourceMarksCopilotEvidenceVerified = $sourceVerificationProperty -and
        $sourceVerificationProperty.Value
    $copilotExecutableEvidenceVerified = $sourceMarksCopilotEvidenceVerified -and
        $sourceCopilotVersionVerified -and
        ($isDeterministicExecutorEvidence -or $hasCopilotExecutableHash)
    if (-not $copilotExecutableEvidenceVerified -and
        -not $AllowLegacyUnverifiedEvidence) {
        if ($sourceMarksCopilotEvidenceUnverified) {
            throw 'Source summary marks Copilot executable evidence unverified; use -AllowLegacyUnverifiedEvidence only to retain it as unverified evidence.'
        }
        if ($sourceVerificationMissing) {
            throw 'Source summary lacks a Copilot executable verification flag; use -AllowLegacyUnverifiedEvidence only to accept legacy evidence without that flag.'
        }
        if (-not $sourceCopilotVersionVerified) {
            throw "$sourceCopilotVersionError Use -AllowLegacyUnverifiedEvidence only to retain an unverified source client version."
        }
        throw 'Source summary lacks a Copilot executable SHA-256; use -AllowLegacyUnverifiedEvidence only to accept legacy real-client evidence without executable hashing.'
    }
    $outputPath = [System.IO.Path]::GetFullPath($OutputDirectory)
    if ($outputPath -ceq $resolvedInputDirectory) {
        throw 'Rescore output must differ from the immutable source directory.'
    }
    if (Test-Path -LiteralPath $outputPath) {
        if (@(Get-ChildItem -LiteralPath $outputPath -Force).Count -gt 0) {
            throw "Rescore output directory is not empty: $outputPath"
        }
    }
    else {
        New-Item -ItemType Directory -Path $outputPath | Out-Null
    }

    $scenarios = @(Get-SkillEvalScenarios -Path $resolvedScenarioPath)
    if ($ScenarioId) {
        $scenarios = @($scenarios | Where-Object id -In $ScenarioId)
    }
    $scenarioById = @{}
    for ($scenarioIndex = 0; $scenarioIndex -lt $scenarios.Count; $scenarioIndex++) {
        $scenarioById[[string]$scenarios[$scenarioIndex].id] = [pscustomobject]@{
            Scenario = $scenarios[$scenarioIndex]
            ScenarioIndex = $scenarioIndex
        }
    }
    $sourceRuns = @($sourceSummary.Runs | Where-Object {
            -not $ScenarioId -or $_.ScenarioId -In $ScenarioId
        })
    if ($sourceRuns.Count -eq 0) {
        throw 'No source runs matched the requested scenarios.'
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($sourceRun in $sourceRuns) {
        $scenarioEntry = $scenarioById[[string]$sourceRun.ScenarioId]
        if (-not $scenarioEntry) {
            throw "Scenario '$($sourceRun.ScenarioId)' is not present in '$resolvedScenarioPath'."
        }
        $runNumber = 0
        if ($null -eq $sourceRun.RunNumber -or
            -not [int]::TryParse(
                [string]$sourceRun.RunNumber,
                [System.Globalization.NumberStyles]::None,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$runNumber) -or
            $runNumber -lt 1) {
            throw "Scenario '$($sourceRun.ScenarioId)' has run number '$($sourceRun.RunNumber)'; run numbers must be positive integers."
        }
        $sourceRunDirectory = (Resolve-Path -LiteralPath (
            Join-Path $resolvedInputDirectory "$($sourceRun.ScenarioId)/run-$runNumber")).Path
        $modelOutputRevision = Get-SkillEvalRunArtifactRevision `
            -RunDirectory $sourceRunDirectory
        $modelOutputEvidenceVerified = [bool]$sourceRun.PSObject.Properties['ModelOutputRevision']
        if ($modelOutputEvidenceVerified -and
            [string]$sourceRun.ModelOutputRevision -cne $modelOutputRevision) {
            throw "Captured model output changed for '$($sourceRun.ScenarioId)' run $runNumber."
        }
        if (-not $modelOutputEvidenceVerified -and
            -not $AllowLegacyUnverifiedEvidence) {
            throw "Run '$($sourceRun.ScenarioId)' $runNumber lacks a model-output revision; use -AllowLegacyUnverifiedEvidence only to accept legacy runs without model-output hashing or verified worktree context."
        }

        $contextPath = Join-Path $sourceRunDirectory 'context.json'
        $worktreeEvidenceVerified = Test-Path -LiteralPath $contextPath -PathType Leaf
        if ($worktreeEvidenceVerified) {
            $contextRecord = Get-Content -LiteralPath $contextPath -Raw |
                ConvertFrom-Json
            $context = [pscustomobject]@{
                ShimLogPath = Join-Path $sourceRunDirectory 'shim.log'
                Workspace = [string]$contextRecord.Workspace
                BaselineWorktree = [string]$contextRecord.BaselineWorktree
                FinalWorktree = [string]$contextRecord.FinalWorktree
            }
        }
        else {
            if (-not $AllowLegacyUnverifiedEvidence) {
                throw "Run '$($sourceRun.ScenarioId)' $runNumber lacks context.json; use -AllowLegacyUnverifiedEvidence only to accept legacy runs without model-output hashing or verified worktree context."
            }
            $worktreeEvidence = @($sourceRun.Evidence | Where-Object Kind -eq 'worktree' | Select-Object -First 1)
            $context = [pscustomobject]@{
                ShimLogPath = Join-Path $sourceRunDirectory 'shim.log'
                Workspace = Join-Path $sourceRunDirectory 'workspace'
                BaselineWorktree = 'recorded-worktree'
                FinalWorktree = if ($worktreeEvidence.Count -eq 0 -or $worktreeEvidence[0].Passed) {
                    'recorded-worktree'
                }
                else { 'recorded-change' }
            }
        }
        $processResult = [pscustomobject]@{
            ExitCode = [int]$sourceRun.ExitCode
            TimedOut = [bool]$sourceRun.TimedOut
            TranscriptPath = Join-Path $sourceRunDirectory 'transcript.md'
            StandardOutputPath = Join-Path $sourceRunDirectory 'stdout.jsonl'
            StandardErrorPath = Join-Path $sourceRunDirectory 'stderr.txt'
        }
        $runStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $assessment = Test-SkillEvalEvidence `
            -Scenario $scenarioEntry.Scenario `
            -ProcessResult $processResult `
            -Context $context
        $runStopwatch.Stop()
        $result = [pscustomobject]@{
            ScenarioId = [string]$sourceRun.ScenarioId
            ScenarioIndex = if ($sourceRun.PSObject.Properties['ScenarioIndex']) {
                [int]$sourceRun.ScenarioIndex
            }
            else { $scenarioEntry.ScenarioIndex }
            Skill = [string]$scenarioEntry.Scenario.skill
            Category = [string]$scenarioEntry.Scenario.category
            EvidenceKind = [string]$scenarioEntry.Scenario.evidenceKind
            RunNumber = $runNumber
            Model = [string]$sourceSummary.Model
            Passed = $assessment.Passed
            SafetyPassed = $assessment.SafetyPassed
            ExitCode = [int]$sourceRun.ExitCode
            TimedOut = [bool]$sourceRun.TimedOut
            InvokedSkills = $assessment.InvokedSkills
            Evidence = $assessment.Evidence
            RunDirectory = $sourceRunDirectory
            Error = [string]$sourceRun.Error
            SourceScenarioRevision = if ($sourceRun.PSObject.Properties['ScenarioRevision']) {
                [string]$sourceRun.ScenarioRevision
            }
            else { $null }
            ScenarioRevision = Get-SkillEvalObjectRevision -InputObject $scenarioEntry.Scenario
            ModelOutputRevision = $modelOutputRevision
            ModelOutputEvidenceVerified = $modelOutputEvidenceVerified
            WorktreeEvidenceVerified = $worktreeEvidenceVerified
            RescoreMilliseconds = $runStopwatch.ElapsedMilliseconds
        }
        foreach ($property in @('ArtifactManifestRevision', 'ContentProfileRevision', 'ContentInputRevision',
                'SkillCondition', 'TargetSkill', 'StagedExposure', 'ClientRuntimeExposure',
                'ModelUsageEvidence', 'ExposureRevision')) {
            if ($sourceRun.PSObject.Properties[$property]) {
                $result | Add-Member -NotePropertyName $property -NotePropertyValue $sourceRun.$property
            }
        }
        $derivedRunDirectory = Join-Path $outputPath "$($result.ScenarioId)/run-$($result.RunNumber)"
        New-Item -ItemType Directory -Path $derivedRunDirectory -Force | Out-Null
        $result | ConvertTo-Json -Depth 20 |
            Set-Content -LiteralPath (Join-Path $derivedRunDirectory 'result.json')
        $results.Add($result)
    }
    $stopwatch.Stop()

    $resultArray = @($results.ToArray() | Sort-Object ScenarioIndex, RunNumber)
    $scenarioMetadata = Get-SkillEvalScenarioMetadata `
        -Scenarios $scenarios `
        -RepoRoot $resolvedRepoRoot `
        -EvalRoot $evalRoot
    $summary = [pscustomobject]@{
        SchemaVersion = 1
        GeneratedAtUtc = [DateTime]::UtcNow.ToString('O')
        OriginalGeneratedAtUtc = [string]$sourceSummary.GeneratedAtUtc
        EvidenceMode = 'rescored'
        SourceSummaryPath = $sourceSummaryPath
        Model = [string]$sourceSummary.Model
        ScenarioRevision = (Get-FileHash -LiteralPath $resolvedScenarioPath -Algorithm SHA256).Hash
        CandidateRevision = [string]$sourceSummary.CandidateRevision
        CurrentCandidateRevision = Get-SkillEvalCandidateRevision -RepoRoot $resolvedRepoRoot
        CandidateComponents = Get-SkillEvalCandidateComponents -RepoRoot $resolvedRepoRoot
        FixtureRevision = [string]$sourceSummary.FixtureRevision
        ScenarioRevisions = $scenarioMetadata
        ScorerRevision = (Get-FileHash -LiteralPath (Join-Path $evalRoot 'SkillEvalScorer.ps1') -Algorithm SHA256).Hash
        SourceScorerRevision = [string]$sourceSummary.ScorerRevision
        ModelOutputEvidenceVerified = @($resultArray |
            Where-Object { -not $_.ModelOutputEvidenceVerified }).Count -eq 0
        WorktreeEvidenceVerified = @($resultArray |
            Where-Object { -not $_.WorktreeEvidenceVerified }).Count -eq 0
        RequestedMaxConcurrency = 0
        MaxConcurrency = 0
        WallTimeMilliseconds = $stopwatch.ElapsedMilliseconds
        GeneratedRunCount = 0
        RescoredRunCount = $resultArray.Count
        ReusedRunCount = 0
        RetryCount = 0
        ScenarioCount = @($resultArray.ScenarioId | Sort-Object -Unique).Count
        RunCount = $resultArray.Count
        PassedCount = @($resultArray | Where-Object Passed).Count
        FailedCount = @($resultArray | Where-Object { -not $_.Passed }).Count
        SafetyFailureCount = @($resultArray | Where-Object { -not $_.SafetyPassed }).Count
        InfrastructureFailureCount = @($resultArray | Where-Object {
                $_.TimedOut -or $_.ExitCode -ne 0 -or
                -not [string]::IsNullOrWhiteSpace([string]$_.Error)
            }).Count
        CopilotVersion = $sourceCopilotVersion
        CopilotExecutableSha256 = if ($hasCopilotExecutableHash) {
            $sourceCopilotExecutableSha256.ToUpperInvariant()
        }
        else { $null }
        CopilotExecutableEvidenceVerified = $copilotExecutableEvidenceVerified
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        OperatingSystem = $PSVersionTable.OS
        Runs = $resultArray
    }
    foreach ($property in @('SkillCondition', 'TargetSkill', 'Exposure')) {
        if ($sourceSummary.PSObject.Properties[$property]) {
            $summary | Add-Member -NotePropertyName $property -NotePropertyValue $sourceSummary.$property
        }
    }
    if ($sourceSummary.PSObject.Properties['StagedExposures']) {
        $summary | Add-Member -NotePropertyName StagedExposures -NotePropertyValue @(
            $sourceSummary.StagedExposures | Where-Object ScenarioId -In $resultArray.ScenarioId)
    }
    Write-SkillEvalSummary -Summary $summary -OutputDirectory $outputPath
    return $summary
}

Export-ModuleMember -Function @(
    'Get-SkillEvalScenarios',
    'New-SkillEvalArguments',
    'Resolve-SkillEvalCopilotPath',
    'Get-SkillEvalCopilotVersion',
    'Get-SkillEvalClientIdentity',
    'Test-SkillEvalEvidence',
    'Get-SkillEvalExitCode',
    'Invoke-SkillEvalSuite',
    'Invoke-SkillEvalRescore',
    'Get-SkillEvalAffectedScenarioIds',
    'Get-SkillEvalWorkerAllocation',
    'Get-SkillEvalExposure'
)
