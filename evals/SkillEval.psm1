Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'SkillEvalScorer.ps1')

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

        [string[]] $SecretEnvironmentNames = @(
            'COPILOT_GITHUB_TOKEN',
            'GH_TOKEN',
            'GITHUB_TOKEN',
            'COPILOT_PROVIDER_API_KEY',
            'COPILOT_PROVIDER_BEARER_TOKEN'
        )
    )

    $arguments = [System.Collections.Generic.List[string]]::new()
    foreach ($argument in @(
            '-p', [string]$Scenario.prompt,
            '--plugin-dir', $PluginDirectory,
            '--add-dir', $PluginDirectory,
            '--model', $Model,
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

    return $arguments.ToArray()
}

function Resolve-SkillEvalCopilotPath {
    [CmdletBinding()]
    param()

    $commands = @(Get-Command copilot -CommandType Application -All -ErrorAction SilentlyContinue)
    $preferred = @(if ($IsWindows) {
        $commands | Where-Object { $_.Name -ceq 'copilot.exe' } | Select-Object -First 1
    }
    else {
        $commands | Where-Object { $_.Name -ceq 'copilot' } | Select-Object -First 1
    })
    if ($preferred.Count -eq 0) {
        throw 'A native Copilot CLI executable was not found.'
    }
    return [string]$preferred[0].Source
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

    $manifest = @(foreach ($fileName in @(
                'stdout.jsonl',
                'stderr.txt',
                'transcript.md',
                'shim.log')) {
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

        [string[]] $ScenarioId
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
    if (-not $baseline.PSObject.Properties['ScenarioRevisions'] -or
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

function New-SkillEvalContext {
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Scenario,

        [Parameter(Mandatory)]
        [string] $RepoRoot,

        [Parameter(Mandatory)]
        [string] $EvalRoot,

        [Parameter(Mandatory)]
        [string] $RunDirectory
    )

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

    foreach ($component in @('plugin.json', '.mcp.json', 'skills', 'agents')) {
        Copy-Item -LiteralPath (Join-Path $RepoRoot $component) -Destination $pluginDirectory -Recurse
    }
    $projectSkillSource = Join-Path $RepoRoot ".agents/skills/$($Scenario.skill)"
    if (Test-Path -LiteralPath $projectSkillSource -PathType Container) {
        $projectSkillsRoot = Join-Path $workspace '.agents/skills'
        New-Item -ItemType Directory -Path $projectSkillsRoot -Force | Out-Null
        Copy-Item -LiteralPath $projectSkillSource -Destination $projectSkillsRoot -Recurse
    }
    if ($Scenario.PSObject.Properties['overlayPath'] -and -not [string]::IsNullOrWhiteSpace([string]$Scenario.overlayPath)) {
        $overlaySource = Resolve-SkillEvalFixturePath `
            -EvalRoot $EvalRoot `
            -RelativePath ([string]$Scenario.overlayPath) `
            -Description 'Overlay' `
            -PathType Leaf
        $overlayTarget = Join-Path $pluginDirectory "skills/$($Scenario.skill)/overlay.md"
        Copy-Item -LiteralPath $overlaySource -Destination $overlayTarget
    }
    $hasPersonalSkillFixture = $false
    if ($Scenario.PSObject.Properties['personalSkillFixturePath'] -and
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

    return [pscustomobject]@{
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

        [scriptblock] $Executor,

        [switch] $IsolateCopilotHome = $true
    )

    $transcriptPath = Join-Path $Context.RunDirectory 'transcript.md'
    $standardOutputPath = Join-Path $Context.RunDirectory 'stdout.jsonl'
    $standardErrorPath = Join-Path $Context.RunDirectory 'stderr.txt'
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
        -PluginDirectory $Context.PluginDirectory `
        -Model $Model `
        -TranscriptPath $transcriptPath `
        -SecretEnvironmentNames @($secretEnvironmentNames)
    $effectiveCopilotHomeIsolation = $IsolateCopilotHome -or
        $Context.HasPersonalSkillFixture
    $invocation = [pscustomobject]@{
        Scenario = $Scenario
        Arguments = $arguments
        WorkingDirectory = $Context.Workspace
        PluginDirectory = $Context.PluginDirectory
        CopilotHome = $Context.CopilotHome
        IsolateCopilotHome = [bool] $effectiveCopilotHomeIsolation
        TranscriptPath = $transcriptPath
        StandardOutputPath = $standardOutputPath
        StandardErrorPath = $standardErrorPath
        ShimLogPath = $Context.ShimLogPath
    }
    $invocation | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $Context.RunDirectory 'invocation.json')

    if ($Executor) {
        $executorResult = & $Executor $invocation
        if ($executorResult.PSObject.Properties['Transcript']) {
            Set-Content -LiteralPath $transcriptPath -Value ([string]$executorResult.Transcript)
        }
        Set-Content -LiteralPath $standardOutputPath -Value ([string]$executorResult.StandardOutput)
        Set-Content -LiteralPath $standardErrorPath -Value ([string]$executorResult.StandardError)
        return [pscustomobject]@{
            ExitCode = [int]$executorResult.ExitCode
            TimedOut = $false
            TranscriptPath = $transcriptPath
            StandardOutputPath = $standardOutputPath
            StandardErrorPath = $standardErrorPath
            Arguments = $arguments
        }
    }

    $copilotPath = Resolve-SkillEvalCopilotPath
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $copilotPath
    $startInfo.WorkingDirectory = $Context.Workspace
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
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

    return [pscustomobject]@{
        ExitCode = if ($completed) { $process.ExitCode } else { -1 }
        TimedOut = -not $completed
        TranscriptPath = $transcriptPath
        StandardOutputPath = $standardOutputPath
        StandardErrorPath = $standardErrorPath
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

        [Parameter(Mandatory)]
        [string] $OutputDirectory,

        [Parameter(Mandatory)]
        [string] $Model,

        [Parameter(Mandatory)]
        [int] $TimeoutMinutes,

        [Parameter(Mandatory)]
        [datetime] $QueuedAtUtc,

        [scriptblock] $Executor,

        [switch] $IsolateCopilotHome = $true
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
    try {
        $phaseStarted = $stopwatch.ElapsedMilliseconds
        $context = New-SkillEvalContext `
            -Scenario $Scenario `
            -RepoRoot $RepoRoot `
            -EvalRoot $EvalRoot `
            -RunDirectory $runDirectory
        $contextMilliseconds = $stopwatch.ElapsedMilliseconds - $phaseStarted

        $phaseStarted = $stopwatch.ElapsedMilliseconds
        $processResult = Invoke-SkillEvalProcess `
            -Scenario $Scenario `
            -Context $context `
            -Model $Model `
            -TimeoutMinutes $TimeoutMinutes `
            -Executor $Executor `
            -IsolateCopilotHome:$IsolateCopilotHome
        $processMilliseconds = $stopwatch.ElapsedMilliseconds - $phaseStarted

        if ([bool]$Scenario.requireUnchangedWorktree) {
            $finalWorktree = Get-SkillEvalWorktreeSnapshot `
                -GitPath $context.GitPath `
                -WorkingDirectory $context.Workspace
            $context | Add-Member `
                -NotePropertyName FinalWorktree `
                -NotePropertyValue $finalWorktree
        }
        [pscustomobject]@{
            ShimLogPath = $context.ShimLogPath
            Workspace = $context.Workspace
            BaselineWorktree = $context.BaselineWorktree
            FinalWorktree = if ($context.PSObject.Properties['FinalWorktree']) {
                $context.FinalWorktree
            }
            else { $null }
        } | ConvertTo-Json -Depth 10 |
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
    }
    catch {
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
            ExitCode = -1
            TimedOut = $false
            InvokedSkills = @()
            Evidence = @()
            RunDirectory = $runDirectory
            Error = $_.Exception.Message
        }
    }
    $stopwatch.Stop()
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

        [string] $Model = 'gpt-5.4',

        [string[]] $ScenarioId,

        [int] $RunCount,

        [int] $TimeoutMinutes = 5,

        [ValidateRange(1, 32)]
        [int] $MaxConcurrency = 8,

        [scriptblock] $Executor,

        [switch] $IsolateCopilotHome = $true
    )

    $resolvedRepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
    $resolvedScenarioPath = (Resolve-Path -LiteralPath $ScenarioPath).Path
    $evalRoot = (Resolve-Path -LiteralPath (Join-Path (Split-Path $resolvedScenarioPath) '..')).Path
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
                    -OutputDirectory $resolvedOutputDirectory `
                    -Model $Model `
                    -TimeoutMinutes $TimeoutMinutes `
                    -QueuedAtUtc $_.QueuedAtUtc `
                    -Executor $Executor `
                    -IsolateCopilotHome:$IsolateCopilotHome
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
                        $OutputDirectory,
                        $Model,
                        $TimeoutMinutes,
                        $IsolateCopilotHome
                    )

                    Invoke-SkillEvalWorkItem `
                        -Scenario $WorkItem.Scenario `
                        -ScenarioIndex $WorkItem.ScenarioIndex `
                        -RunNumber $WorkItem.RunNumber `
                        -RepoRoot $RepoRoot `
                        -EvalRoot $EvalRoot `
                        -OutputDirectory $OutputDirectory `
                        -Model $Model `
                        -TimeoutMinutes $TimeoutMinutes `
                        -QueuedAtUtc $WorkItem.QueuedAtUtc `
                        -IsolateCopilotHome:$IsolateCopilotHome
                } `
                    $_ `
                    $using:resolvedRepoRoot `
                    $using:evalRoot `
                    $using:resolvedOutputDirectory `
                    $using:Model `
                    $using:TimeoutMinutes `
                    $using:isolateCopilotHomeValue
            } -ThrottleLimit $effectiveMaxConcurrency)
    }
    $suiteStopwatch.Stop()
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
    $fixtureManifest = @(Get-ChildItem -LiteralPath (Join-Path $evalRoot 'fixtures') -File -Recurse |
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
        ScenarioRevision = (Get-FileHash -LiteralPath $resolvedScenarioPath -Algorithm SHA256).Hash
        CandidateRevision = $candidateRevision
        CandidateComponents = Get-SkillEvalCandidateComponents -RepoRoot $resolvedRepoRoot
        FixtureRevision = $fixtureRevision
        ScenarioRevisions = $scenarioMetadata
        ScorerRevision = (Get-FileHash -LiteralPath (Join-Path $evalRoot 'SkillEvalScorer.ps1') -Algorithm SHA256).Hash
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
        CopilotVersion = if ($Executor) { 'fake-executor' } else { (& copilot --version 2>&1) -join ' ' }
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
        CopilotVersion = [string]$sourceSummary.CopilotVersion
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        OperatingSystem = $PSVersionTable.OS
        Runs = $resultArray
    }
    Write-SkillEvalSummary -Summary $summary -OutputDirectory $outputPath
    return $summary
}

Export-ModuleMember -Function @(
    'Get-SkillEvalScenarios',
    'New-SkillEvalArguments',
    'Resolve-SkillEvalCopilotPath',
    'Test-SkillEvalEvidence',
    'Get-SkillEvalExitCode',
    'Invoke-SkillEvalSuite',
    'Invoke-SkillEvalRescore',
    'Get-SkillEvalAffectedScenarioIds',
    'Get-SkillEvalWorkerAllocation'
)
