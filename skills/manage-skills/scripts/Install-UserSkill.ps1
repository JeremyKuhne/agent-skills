#Requires -Version 7.0

<#
.SYNOPSIS
    Installs a complete Agent Skill directory at user scope.

.DESCRIPTION
    Validates and copies one skill into documented host-specific user roots.
    Multiple hosts are installed as one transaction. Private mode adds
    fail-closed source visibility, synchronization, and shared-root gates.

.PARAMETER SourceSkillPath
    Path to the canonical skill directory containing SKILL.md.

.PARAMETER TargetHost
    One or more user-scope host mappings. Use shared-agents for the neutral
    ~/.agents/skills root shared by several compatible clients.

.PARAMETER ProfileRoot
    User profile root under which documented host-specific skill roots are
    created. Defaults to the current PowerShell home directory.

.PARAMETER Private
    Require a local-only source or one unambiguous github.com repository whose
    identity and PRIVATE visibility GitHub CLI verifies. Also reject configured
    synchronized source/destination roots, destination reparse points, and
    unapproved multi-host or shared-root exposure.

.PARAMETER AllowPrivateMultiHostExposure
    Explicitly accept the expanded discovery surface when a private skill is
    copied to multiple roots or to the neutral ~/.agents/skills root.

.PARAMETER Force
    Replace existing copied skill directories after staging and hash
    verification. Does not override source, path-type, or Git protections.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string] $SourceSkillPath,

    [ValidateSet(
        'github-copilot',
        'shared-agents',
        'claude-code',
        'codex',
        'gemini-cli',
        'cursor')]
    [string[]] $TargetHost = @('github-copilot'),

    [string] $ProfileRoot = $HOME,

    [switch] $Private,
    [switch] $AllowPrivateMultiHostExposure,
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-PathWithin {
    param(
        [Parameter(Mandatory)] [string] $Candidate,
        [Parameter(Mandatory)] [string] $Root
    )

    if (-not [System.IO.Path]::IsPathFullyQualified($Candidate)) {
        throw "Candidate path must be fully qualified: '$Candidate'."
    }
    if (-not [System.IO.Path]::IsPathFullyQualified($Root)) {
        throw "Root path must be fully qualified: '$Root'."
    }

    $comparison = if ($IsWindows) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }

    $candidatePath = [System.IO.Path]::GetFullPath($Candidate)
    $rootPath = [System.IO.Path]::GetFullPath($Root).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)

    return $candidatePath.Equals($rootPath, $comparison) -or
        $candidatePath.StartsWith(
            "$rootPath$([System.IO.Path]::DirectorySeparatorChar)",
            $comparison)
}

function Test-PathEqual {
    param(
        [Parameter(Mandatory)] [string] $Left,
        [Parameter(Mandatory)] [string] $Right
    )

    $comparison = if ($IsWindows) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparison]::Ordinal
    }

    return [System.IO.Path]::GetFullPath($Left).Equals(
        [System.IO.Path]::GetFullPath($Right),
        $comparison)
}

function Test-NetworkPath {
    param([Parameter(Mandatory)] [string] $Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if ($fullPath.StartsWith('\\', [System.StringComparison]::Ordinal)) {
        return $true
    }

    if ($IsWindows) {
        $root = [System.IO.Path]::GetPathRoot($fullPath)
        if (-not [string]::IsNullOrEmpty($root)) {
            try {
                return [System.IO.DriveInfo]::new($root).DriveType -eq
                    [System.IO.DriveType]::Network
            }
            catch {
                return $false
            }
        }
    }

    return $false
}

function Get-ReparsePointInPath {
    param([Parameter(Mandatory)] [string] $Path)

    $candidate = [System.IO.Path]::GetFullPath($Path)
    while (-not [string]::IsNullOrEmpty($candidate)) {
        if (Test-Path -LiteralPath $candidate) {
            $item = Get-Item -LiteralPath $candidate -Force
            if (($item.Attributes -band
                    [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                return $item.FullName
            }
        }

        $parent = Split-Path -Parent $candidate
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $candidate) {
            break
        }
        $candidate = $parent
    }

    return $null
}

function Get-ExistingAncestor {
    param([Parameter(Mandatory)] [string] $Path)

    $candidate = [System.IO.Path]::GetFullPath($Path)
    while (-not (Test-Path -LiteralPath $candidate)) {
        $parent = Split-Path -Parent $candidate
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $candidate) {
            throw "No existing ancestor was found for '$Path'."
        }

        $candidate = $parent
    }

    return $candidate
}

function Get-TreeManifest {
    param([Parameter(Mandatory)] [string] $Root)

    Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
        ForEach-Object {
            [pscustomobject]@{
                Path = ([System.IO.Path]::GetRelativePath(
                        $Root,
                        $_.FullName)).Replace('\', '/')
                Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
        } |
        Sort-Object Path
}

function Remove-EmptyDirectoriesToAncestor {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Ancestor
    )

    $current = [System.IO.Path]::GetFullPath($Path)
    while (-not (Test-PathEqual $current $Ancestor)) {
        if (-not (Test-Path -LiteralPath $current -PathType Container)) {
            break
        }
        if (@(Get-ChildItem -LiteralPath $current -Force).Count -ne 0) {
            break
        }

        Remove-Item -LiteralPath $current -Force
        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $current) {
            break
        }
        $current = $parent
    }
}

function Get-UserSkillsRoot {
    param([Parameter(Mandatory)] [string] $Name)

    switch ($Name) {
        'github-copilot' { Join-Path $ProfileRoot '.copilot/skills' }
        'shared-agents' { Join-Path $ProfileRoot '.agents/skills' }
        'claude-code' { Join-Path $ProfileRoot '.claude/skills' }
        'codex' { Join-Path $ProfileRoot '.agents/skills' }
        'gemini-cli' { Join-Path $ProfileRoot '.gemini/skills' }
        'cursor' { Join-Path $ProfileRoot '.cursor/skills' }
        default { throw "Unsupported target host '$Name'." }
    }
}

function Invoke-GitInspection {
    param(
        [Parameter(Mandatory)] [string] $GitPath,
        [Parameter(Mandatory)] [string] $WorkingPath,
        [Parameter(Mandatory)] [string[]] $Arguments
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $GitPath
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    [void] $startInfo.ArgumentList.Add('-C')
    [void] $startInfo.ArgumentList.Add($WorkingPath)
    foreach ($argument in $Arguments) {
        [void] $startInfo.ArgumentList.Add($argument)
    }

    foreach ($name in @(
            'GIT_DIR',
            'GIT_WORK_TREE',
            'GIT_COMMON_DIR',
            'GIT_INDEX_FILE',
            'GIT_OBJECT_DIRECTORY',
            'GIT_ALTERNATE_OBJECT_DIRECTORIES',
            'GIT_CEILING_DIRECTORIES')) {
        [void] $startInfo.Environment.Remove($name)
    }
    $startInfo.Environment['LC_ALL'] = 'C'
    $startInfo.Environment['LANG'] = 'C'
    $startInfo.Environment['GIT_TERMINAL_PROMPT'] = '0'

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw "Git could not be started from '$GitPath'."
        }

        $standardOutput = $process.StandardOutput.ReadToEndAsync()
        $standardError = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            StandardOutput = $standardOutput.GetAwaiter().GetResult()
            StandardError = $standardError.GetAwaiter().GetResult()
        }
    }
    finally {
        $process.Dispose()
    }
}

function Get-GitRepositoryInspection {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $GitPath,
        [Parameter(Mandatory)] [string] $BoundaryName
    )

    $result = Invoke-GitInspection `
        -GitPath $GitPath `
        -WorkingPath $Path `
        -Arguments @('rev-parse', '--show-toplevel')
    if ($result.ExitCode -eq 0) {
        $roots = @($result.StandardOutput -split '\r?\n' |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique)
        if ($roots.Count -ne 1 -or
            -not [System.IO.Path]::IsPathFullyQualified($roots[0])) {
            throw "Git returned an invalid repository root while inspecting the $BoundaryName boundary at '$Path'."
        }

        return [pscustomobject]@{
            IsRepository = $true
            Root = [System.IO.Path]::GetFullPath($roots[0])
        }
    }

    $errorText = $result.StandardError.Trim()
    $notRepositoryPatterns = @(
        '^fatal: not a git repository \(or any of the parent directories\): \.git$'
        '^fatal: not a git repository \(or any parent up to mount point [^\r\n]+\)\r?\nStopping at filesystem boundary \(GIT_DISCOVERY_ACROSS_FILESYSTEM not set\)\.$'
    )
    $isNotRepository = @($notRepositoryPatterns | Where-Object {
            $errorText -match $_
        }).Count -gt 0
    if ($result.ExitCode -eq 128 -and $isNotRepository) {
        return [pscustomobject]@{
            IsRepository = $false
            Root = $null
        }
    }

    $detail = if ([string]::IsNullOrWhiteSpace($errorText)) {
        $result.StandardOutput.Trim()
    }
    else {
        $errorText
    }
    throw "Git could not inspect the $BoundaryName repository boundary at '$Path' (exit code $($result.ExitCode)): $detail"
}

function ConvertTo-GitHubRepositoryIdentity {
    param([Parameter(Mandatory)] [string] $RemoteUrl)

    $value = $RemoteUrl.Trim()
    $remotePath = $null
    foreach ($pattern in @(
            '^https://github\.com/(?<path>[^?#]+)$',
            '^git@github\.com:(?<path>[^?#]+)$',
            '^ssh://git@github\.com/(?<path>[^?#]+)$')) {
        if ($value -match $pattern) {
            $remotePath = $Matches['path']
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($remotePath)) {
        return $null
    }

    $remotePath = $remotePath.TrimEnd('/')
    if ($remotePath.EndsWith('.git', [StringComparison]::OrdinalIgnoreCase)) {
        $remotePath = $remotePath.Substring(0, $remotePath.Length - 4)
    }
    $parts = @($remotePath -split '/')
    if ($parts.Count -ne 2 -or
        $parts | Where-Object {
            [string]::IsNullOrWhiteSpace($_) -or
            $_ -in @('.', '..') -or
            $_ -match '\s'
        }) {
        return $null
    }

    return "$($parts[0])/$($parts[1])"
}

function Get-SourceGitHubRepositoryIdentity {
    param(
        [Parameter(Mandatory)] [string] $RepositoryRoot,
        [Parameter(Mandatory)] [string] $GitPath
    )

    $remoteResult = Invoke-GitInspection `
        -GitPath $GitPath `
        -WorkingPath $RepositoryRoot `
        -Arguments @('remote')
    if ($remoteResult.ExitCode -ne 0) {
        throw 'The source repository remotes could not be inspected.'
    }

    $remoteNames = @($remoteResult.StandardOutput -split '\r?\n' |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($remoteNames.Count -eq 0) {
        throw 'The source repository does not have a remote to verify as private.'
    }

    $identities = [System.Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    foreach ($remoteName in $remoteNames) {
        $urlResult = Invoke-GitInspection `
            -GitPath $GitPath `
            -WorkingPath $RepositoryRoot `
            -Arguments @('remote', 'get-url', '--all', $remoteName)
        if ($urlResult.ExitCode -ne 0) {
            throw "The source repository remote '$remoteName' could not be inspected."
        }

        $remoteUrls = @($urlResult.StandardOutput -split '\r?\n' |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($remoteUrls.Count -eq 0) {
            throw "The source repository remote '$remoteName' does not have a fetch URL."
        }

        foreach ($remoteUrl in $remoteUrls) {
            $identity = ConvertTo-GitHubRepositoryIdentity $remoteUrl
            if ($null -eq $identity) {
                throw "The source repository has an unsupported remote on '$remoteName'; private verification requires unambiguous github.com remotes."
            }
            [void] $identities.Add($identity)
        }
    }

    if ($identities.Count -ne 1) {
        throw 'The source repository has ambiguous GitHub remote identities.'
    }

    return @($identities)[0]
}

function Assert-PrivateSource {
    param(
        [Parameter(Mandatory)] [string] $SkillRoot,
        [Parameter(Mandatory)] [string] $GitPath
    )

    $inspection = Get-GitRepositoryInspection `
        -Path $SkillRoot `
        -GitPath $GitPath `
        -BoundaryName 'source'
    if (-not $inspection.IsRepository) {
        return
    }

    $sourceRepository = $inspection.Root
    $sourceIdentity = Get-SourceGitHubRepositoryIdentity `
        -RepositoryRoot $sourceRepository `
        -GitPath $GitPath

    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if ($null -eq $gh) {
        throw 'GitHub CLI is required to verify a private Git repository.'
    }

    $sourceRepositoryUrl = "https://github.com/$sourceIdentity"
    $repositoryOutput = @(
        & gh repo view $sourceRepositoryUrl `
            --json 'nameWithOwner,visibility' 2>&1
    )
    $repositoryExitCode = $LASTEXITCODE

    if ($repositoryExitCode -ne 0) {
        throw 'The source repository visibility could not be verified as private.'
    }

    $repositoryJson = @($repositoryOutput | ForEach-Object {
            $_.ToString()
        }) -join "`n"
    try {
        $repositoryMetadata = $repositoryJson | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw 'The source repository returned malformed repository metadata.'
    }

    $identityProperty = $repositoryMetadata.PSObject.Properties['nameWithOwner']
    $visibilityProperty = $repositoryMetadata.PSObject.Properties['visibility']
    if ($null -eq $identityProperty -or
        $identityProperty.Value -isnot [string] -or
        [string]::IsNullOrWhiteSpace($identityProperty.Value) -or
        $null -eq $visibilityProperty -or
        $visibilityProperty.Value -isnot [string] -or
        [string]::IsNullOrWhiteSpace($visibilityProperty.Value)) {
        throw 'The source repository returned malformed repository metadata.'
    }

    if (-not $identityProperty.Value.Equals(
            $sourceIdentity,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "The returned repository identity '$($identityProperty.Value)' does not match the reviewed source '$sourceIdentity'."
    }

    $visibilityValue = $visibilityProperty.Value.Trim().ToUpperInvariant()
    if ($visibilityValue -notin @('PRIVATE', 'PUBLIC', 'INTERNAL')) {
        throw 'The source repository returned an unrecognized visibility result.'
    }
    if ($visibilityValue -cne 'PRIVATE') {
        throw "Refusing to install a private skill from a $visibilityValue repository."
    }
}

$sourceInputPath = $ExecutionContext.SessionState.Path.
    GetUnresolvedProviderPathFromPSPath($SourceSkillPath)
if (-not (Test-Path -LiteralPath $sourceInputPath -PathType Container)) {
    throw "The source skill directory does not exist: '$SourceSkillPath'."
}

$sourceReparsePoint = Get-ReparsePointInPath $sourceInputPath
if ($null -ne $sourceReparsePoint) {
    throw "The source path contains a reparse point: '$sourceReparsePoint'."
}

$skillRoot = (Resolve-Path -LiteralPath $sourceInputPath).Path
$ProfileRoot = [System.IO.Path]::GetFullPath(
    $ExecutionContext.SessionState.Path.
        GetUnresolvedProviderPathFromPSPath($ProfileRoot))

$skillEntryPoint = Join-Path $skillRoot 'SKILL.md'
if (-not (Test-Path -LiteralPath $skillEntryPoint -PathType Leaf)) {
    throw "The selected source directory must contain a top-level SKILL.md: '$skillRoot'."
}

$skillName = Split-Path -Leaf $skillRoot
$validator = Join-Path $PSScriptRoot 'Validate-Skills.ps1'
$pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
$validationOutput = & $pwsh -NoProfile -File $validator $skillRoot -Quiet 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "The source skill failed validation:`n$($validationOutput -join "`n")"
}

$reparsePoint = Get-ChildItem -LiteralPath $skillRoot -Recurse -Force |
    Where-Object {
        ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
    } |
    Select-Object -First 1
if ($null -ne $reparsePoint) {
    throw "The source contains a reparse point: '$($reparsePoint.FullName)'."
}

if (Test-NetworkPath $skillRoot) {
    throw 'The source skill cannot be installed from a network share.'
}

$git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($null -eq $git) {
    throw 'Git is required to verify source and destination repository boundaries.'
}

$syncRoots = @(
    $env:OneDrive,
    $env:OneDriveConsumer,
    $env:OneDriveCommercial,
    $env:Dropbox,
    $env:GoogleDrive
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

if ($Private) {
    foreach ($syncRoot in $syncRoots) {
        if (Test-PathWithin $skillRoot $syncRoot) {
            throw "The source is under a synchronized folder: '$syncRoot'."
        }
    }

    Assert-PrivateSource $skillRoot $git.Source
}

$targets = [System.Collections.Generic.List[object]]::new()
foreach ($name in ($TargetHost | Select-Object -Unique)) {
    $root = [System.IO.Path]::GetFullPath((Get-UserSkillsRoot $name))
    $existing = $targets | Where-Object { Test-PathEqual $_.Root $root } |
        Select-Object -First 1
    if ($null -ne $existing) {
        $existing.Hosts.Add($name)
        continue
    }

    $hosts = [System.Collections.Generic.List[string]]::new()
    $hosts.Add($name)
    $targets.Add([pscustomobject]@{
            Root = $root
            Hosts = $hosts
            Destination = Join-Path $root $skillName
            ExistingAncestor = $null
            RootPreExisting = $false
        })
}

$sharedRoot = Get-UserSkillsRoot 'shared-agents'
$usesSharedRoot = @($targets | Where-Object {
        Test-PathEqual $_.Root $sharedRoot
    }).Count -gt 0
if ($Private -and
    ($targets.Count -gt 1 -or $usesSharedRoot) -and
    -not $AllowPrivateMultiHostExposure) {
    throw 'A private skill requires -AllowPrivateMultiHostExposure for multiple roots or ~/.agents/skills.'
}

foreach ($target in $targets) {
    if (Test-NetworkPath $target.Root) {
        throw "The destination cannot be a network share: '$($target.Root)'."
    }

    $target.RootPreExisting = Test-Path -LiteralPath $target.Root -PathType Container
    $target.ExistingAncestor = Get-ExistingAncestor $target.Root
    if (-not (Test-Path -LiteralPath $target.ExistingAncestor -PathType Container)) {
        throw "The destination path is blocked by a file: '$($target.ExistingAncestor)'."
    }

    $destinationExists = Test-Path -LiteralPath $target.Destination
    if ($destinationExists -and
        -not (Test-Path -LiteralPath $target.Destination -PathType Container)) {
        throw "The destination path is blocked by a file: '$($target.Destination)'."
    }

    $repositoryInspectionPath = if ($destinationExists) {
        $target.Destination
    }
    else {
        $target.ExistingAncestor
    }
    $destinationInspection = Get-GitRepositoryInspection `
        -Path $repositoryInspectionPath `
        -GitPath $git.Source `
        -BoundaryName 'destination'
    if ($destinationInspection.IsRepository) {
        throw "The destination is inside a Git worktree: '$($destinationInspection.Root)'."
    }

    if ($Private) {
        $destinationReparsePoint = Get-ReparsePointInPath $target.ExistingAncestor
        if ($null -ne $destinationReparsePoint) {
            throw "The destination path contains a reparse point: '$destinationReparsePoint'."
        }
    }

    if ($Private) {
        foreach ($syncRoot in $syncRoots) {
            if (Test-PathWithin $target.Destination $syncRoot) {
                throw "The destination is under a synchronized folder: '$syncRoot'."
            }
        }
    }

    if (Test-PathWithin $target.Destination $skillRoot) {
        throw 'A destination cannot be inside the source skill directory.'
    }

    if ((Test-Path -LiteralPath $target.Destination) -and -not $Force) {
        throw "'$($target.Destination)' already exists. Pass -Force to replace it."
    }
}

$approvedTargets = @($targets | Where-Object {
        $PSCmdlet.ShouldProcess(
            $_.Destination,
            "Install '$skillName' for $($_.Hosts -join ', ')")
    })
if ($approvedTargets.Count -eq 0) {
    return
}

$sourceManifest = @(Get-TreeManifest $skillRoot)
$states = [System.Collections.Generic.List[object]]::new()
$committed = $false

try {
    foreach ($target in $approvedTargets) {
        $stagingPath = Join-Path $target.Root (
            ".$skillName.install-$([guid]::NewGuid().ToString('N'))")
        $state = [pscustomobject]@{
                Target = $target
                StagingPath = $stagingPath
                BackupPath = $null
                Installed = $false
            }
        $states.Add($state)

        New-Item -ItemType Directory -Path $target.Root -Force | Out-Null
        Copy-Item -LiteralPath $skillRoot -Destination $stagingPath -Recurse -Force

        $stagingManifest = @(Get-TreeManifest $stagingPath)
        $differences = Compare-Object $sourceManifest $stagingManifest -Property Path, Hash
        if ($differences) {
            throw "The staged copy for '$($target.Root)' does not match the source."
        }
    }

    foreach ($state in $states) {
        if (Test-Path -LiteralPath $state.Target.Destination) {
            $state.BackupPath = "$($state.Target.Destination).backup-$([guid]::NewGuid().ToString('N'))"
            Move-Item -LiteralPath $state.Target.Destination -Destination $state.BackupPath
        }

        Move-Item -LiteralPath $state.StagingPath -Destination $state.Target.Destination
        $state.Installed = $true
    }
    $committed = $true
}
catch {
    $rollbackStates = @($states)
    [array]::Reverse($rollbackStates)
    foreach ($state in $rollbackStates) {
        if ($state.Installed -and
            (Test-Path -LiteralPath $state.Target.Destination)) {
            Remove-Item -LiteralPath $state.Target.Destination -Recurse -Force
        }

        if ($null -ne $state.BackupPath -and
            (Test-Path -LiteralPath $state.BackupPath)) {
            Move-Item -LiteralPath $state.BackupPath -Destination $state.Target.Destination
        }

        if (Test-Path -LiteralPath $state.StagingPath) {
            Remove-Item -LiteralPath $state.StagingPath -Recurse -Force
        }

        if (-not $state.Target.RootPreExisting) {
            Remove-EmptyDirectoriesToAncestor `
                $state.Target.Root `
                $state.Target.ExistingAncestor
        }
    }

    throw
}
finally {
    foreach ($state in $states) {
        if (Test-Path -LiteralPath $state.StagingPath) {
            Remove-Item -LiteralPath $state.StagingPath -Recurse -Force
        }
    }
}

if ($committed) {
    foreach ($state in $states) {
        if ($null -ne $state.BackupPath) {
            Remove-Item -LiteralPath $state.BackupPath -Recurse -Force
        }
    }
}

foreach ($state in $states) {
    [pscustomobject]@{
        Skill = $skillName
        Hosts = $state.Target.Hosts -join ', '
        Scope = 'user'
        Mode = 'copy'
        Private = [bool]$Private
        Destination = $state.Target.Destination
        Status = 'Installed'
    }
}
