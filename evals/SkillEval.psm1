Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
                Get-Item -LiteralPath $candidatePath
            }
            elseif (Test-Path -LiteralPath $candidatePath -PathType Container) {
                Get-ChildItem -LiteralPath $candidatePath -File -Recurse
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
    Invoke-SkillEvalGit -GitPath $gitPath -WorkingDirectory $workspace -Arguments @('add', 'README.md') | Out-Null
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
        $overlaySource = (Resolve-Path -LiteralPath (Join-Path $EvalRoot ([string]$Scenario.overlayPath))).Path
        $overlayTarget = Join-Path $pluginDirectory "skills/$($Scenario.skill)/overlay.md"
        Copy-Item -LiteralPath $overlaySource -Destination $overlayTarget
    }
    $hasPersonalSkillFixture = $false
    if ($Scenario.PSObject.Properties['personalSkillFixturePath'] -and
        -not [string]::IsNullOrWhiteSpace([string]$Scenario.personalSkillFixturePath)) {
        $fixtureInput = [string]$Scenario.personalSkillFixturePath
        if ([System.IO.Path]::IsPathRooted($fixtureInput)) {
            throw 'Personal skill fixture paths must be relative to the evaluation root.'
        }
        $fixtureRoot = (Resolve-Path -LiteralPath (Join-Path $EvalRoot 'fixtures')).Path
        $personalSkillSource = (Resolve-Path -LiteralPath (Join-Path $EvalRoot $fixtureInput)).Path
        $pathComparison = if ($IsWindows) {
            [System.StringComparison]::OrdinalIgnoreCase
        }
        else { [System.StringComparison]::Ordinal }
        $fixturePrefix = $fixtureRoot.TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar) +
            [System.IO.Path]::DirectorySeparatorChar
        if (-not $personalSkillSource.StartsWith($fixturePrefix, $pathComparison) -or
            -not (Test-Path -LiteralPath $personalSkillSource -PathType Container)) {
            throw "Personal skill fixture '$fixtureInput' must be a directory under '$fixtureRoot'."
        }
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

function Test-SkillEvalEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Scenario,

        [Parameter(Mandatory)]
        [pscustomobject] $ProcessResult,

        [Parameter(Mandatory)]
        [pscustomobject] $Context
    )

    $evidence = [System.Collections.Generic.List[object]]::new()
    function Add-Evidence([string] $kind, [string] $pattern, [bool] $passed, [bool] $safety, [string] $detail) {
        $evidence.Add([pscustomobject]@{
                Kind = $kind
                Pattern = $pattern
                Passed = $passed
                Safety = $safety
                Detail = $detail
            })
    }

    $responseParts = [System.Collections.Generic.List[string]]::new()
    $invokedSkills = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    if (Test-Path -LiteralPath $ProcessResult.StandardOutputPath -PathType Leaf) {
        foreach ($line in (Get-Content -LiteralPath $ProcessResult.StandardOutputPath)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $event = $line | ConvertFrom-Json -ErrorAction Stop }
            catch { continue }
            if ($event.type -ne 'assistant.message') { continue }
            if ($event.data.PSObject.Properties['content'] -and -not [string]::IsNullOrWhiteSpace([string]$event.data.content)) {
                $responseParts.Add([string]$event.data.content)
            }
            foreach ($toolRequest in @($event.data.toolRequests)) {
                if ($toolRequest.name -eq 'skill' -and -not [string]::IsNullOrWhiteSpace([string]$toolRequest.arguments.skill)) {
                    $invokedSkills.Add([string]$toolRequest.arguments.skill) | Out-Null
                }
            }
        }
    }
    $response = $responseParts -join "`n"
    $skillInvoked = $invokedSkills.Contains([string]$Scenario.skill)
    $commandLog = if (Test-Path -LiteralPath $Context.ShimLogPath -PathType Leaf) {
        [string](Get-Content -LiteralPath $Context.ShimLogPath -Raw) -replace "\r\n?", "`n"
    }
    else { '' }
    $actionCommandLog = @($commandLog -split "`n" | Where-Object {
            $_ -notmatch '^(?:git (?:commit|push)|gh (?:pr|repo|issue) create)\b.*(?:--help|-h)(?: |$)' -and
            $_ -notmatch '^git push\b.*--dry-run(?: |$)'
        }) -join "`n"

    Add-Evidence 'process-exit' '0' ([bool]($ProcessResult.ExitCode -eq 0 -and -not $ProcessResult.TimedOut)) $false "Exit code $($ProcessResult.ExitCode); timed out: $($ProcessResult.TimedOut)."
    Add-Evidence 'skill-invocation' ([string]$Scenario.skill) ([bool]($skillInvoked -eq [bool]$Scenario.expectSkillInvocation)) $false "Expected invocation: $($Scenario.expectSkillInvocation); observed invocation: $skillInvoked."
    if ($Scenario.PSObject.Properties['requiredSkillInvocations']) {
        foreach ($skillName in @($Scenario.requiredSkillInvocations | Sort-Object -Unique)) {
            Add-Evidence 'required-skill-invocation' ([string]$skillName) ([bool]$invokedSkills.Contains([string]$skillName)) $false 'Required companion skill invocation.'
        }
    }
    if ($Scenario.PSObject.Properties['forbiddenSkillInvocations']) {
        foreach ($skillName in @($Scenario.forbiddenSkillInvocations | Sort-Object -Unique)) {
            Add-Evidence 'forbidden-skill-invocation' ([string]$skillName) (-not $invokedSkills.Contains([string]$skillName)) $false 'Forbidden companion skill invocation.'
        }
    }
    foreach ($pattern in @($Scenario.requiredResponsePatterns)) {
        Add-Evidence 'required-response' $pattern ([bool]($response -match $pattern)) $false 'Required response pattern.'
    }
    foreach ($pattern in @($Scenario.forbiddenResponsePatterns)) {
        Add-Evidence 'forbidden-response' $pattern ([bool]($response -notmatch $pattern)) $false 'Forbidden response pattern.'
    }
    foreach ($pattern in @($Scenario.requiredCommandPatterns)) {
        Add-Evidence 'required-command' $pattern ([bool]($actionCommandLog -match $pattern)) $false 'Required shim action command.'
    }
    foreach ($pattern in @($Scenario.forbiddenCommandPatterns)) {
        Add-Evidence 'forbidden-command' $pattern ([bool]($actionCommandLog -notmatch $pattern)) $true 'Forbidden shim action command.'
    }

    if ([bool]$Scenario.requireUnchangedWorktree) {
        $finalWorktree = if ($Context.PSObject.Properties['FinalWorktree']) {
            [string]$Context.FinalWorktree
        }
        else {
            Get-SkillEvalWorktreeSnapshot -GitPath $Context.GitPath -WorkingDirectory $Context.Workspace
        }
        Add-Evidence 'worktree' 'unchanged' ([bool]([string]$Context.BaselineWorktree -ceq [string]$finalWorktree)) $true 'Real fixture worktree must remain byte-for-byte equivalent at git status and HEAD.'
    }

    return [pscustomobject]@{
        Passed = @($evidence | Where-Object { -not $_.Passed }).Count -eq 0
        SafetyPassed = @($evidence | Where-Object { $_.Safety -and -not $_.Passed }).Count -eq 0
        InvokedSkills = @($invokedSkills | Sort-Object)
        Evidence = $evidence.ToArray()
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

    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($scenario in $scenarios) {
        $scenarioRunCount = if ($RunCount -gt 0) { $RunCount } else { [int]$scenario.runCount }
        for ($runNumber = 1; $runNumber -le $scenarioRunCount; $runNumber++) {
            $runDirectory = Join-Path $resolvedOutputDirectory "$($scenario.id)/run-$runNumber"
            New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $context = New-SkillEvalContext -Scenario $scenario -RepoRoot $resolvedRepoRoot -EvalRoot $evalRoot -RunDirectory $runDirectory
                $processResult = Invoke-SkillEvalProcess -Scenario $scenario -Context $context -Model $Model -TimeoutMinutes $TimeoutMinutes -Executor $Executor -IsolateCopilotHome:$IsolateCopilotHome
                $assessment = Test-SkillEvalEvidence -Scenario $scenario -ProcessResult $processResult -Context $context
                $result = [pscustomobject]@{
                    ScenarioId = [string]$scenario.id
                    Skill = [string]$scenario.skill
                    Category = [string]$scenario.category
                    EvidenceKind = [string]$scenario.evidenceKind
                    RunNumber = $runNumber
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
                    ScenarioId = [string]$scenario.id
                    Skill = [string]$scenario.skill
                    Category = [string]$scenario.category
                    EvidenceKind = [string]$scenario.evidenceKind
                    RunNumber = $runNumber
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
            $result | Add-Member -NotePropertyName DurationMilliseconds -NotePropertyValue $stopwatch.ElapsedMilliseconds
            $result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $runDirectory 'result.json')
            $results.Add($result)
        }
    }

    $resultArray = $results.ToArray()
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
    $summary = [pscustomobject]@{
        SchemaVersion = 1
        GeneratedAtUtc = [DateTime]::UtcNow.ToString('O')
        Model = $Model
        ScenarioRevision = (Get-FileHash -LiteralPath $resolvedScenarioPath -Algorithm SHA256).Hash
        CandidateRevision = $candidateRevision
        FixtureRevision = $fixtureRevision
        ScorerRevision = (Get-FileHash -LiteralPath (Join-Path $evalRoot 'SkillEval.psm1') -Algorithm SHA256).Hash
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

Export-ModuleMember -Function @(
    'Get-SkillEvalScenarios',
    'New-SkillEvalArguments',
    'Resolve-SkillEvalCopilotPath',
    'Test-SkillEvalEvidence',
    'Get-SkillEvalExitCode',
    'Invoke-SkillEvalSuite'
)
