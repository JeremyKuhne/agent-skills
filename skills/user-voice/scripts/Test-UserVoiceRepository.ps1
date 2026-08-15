#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $RepositoryPath,

    [string[]] $ContentPath,
    [switch] $RequirePrivateGitHub,
    [switch] $ScanHistory,
    [switch] $RequirePrePushHook,
    [string] $ExpectedOwner,
    [string[]] $ForbiddenLiteral
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$errors = [System.Collections.Generic.List[string]]::new()
function Add-RepositoryError([string] $category, [string] $message) {
    $errors.Add("[$category] $message")
}

function Test-Content([string] $content, [string] $source) {
    $checks = @(
        @{ Category = 'private-identifier'; Pattern = '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'; Message = 'email address' },
        @{ Category = 'secret'; Pattern = '(?i)-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|\bgh[pousr]_[A-Za-z0-9_]{20,}\b|\bAKIA[0-9A-Z]{16}\b'; Message = 'secret material' },
        @{ Category = 'absolute-path'; Pattern = '(?m)(?:[A-Za-z]:\\(?:Users|repos)\\|/(?:Users|home)/)'; Message = 'absolute user path' },
        @{ Category = 'patch-artifact'; Pattern = '(?m)^\*\*\* (?:Add|Update|Delete) File:'; Message = 'patch control text' })
    foreach ($check in $checks) {
        if ($content -match $check.Pattern) {
            Add-RepositoryError $check.Category "$source contains $($check.Message)."
        }
    }
    foreach ($literal in @($ForbiddenLiteral | Where-Object { $_ })) {
        if ($content.Contains($literal, [System.StringComparison]::OrdinalIgnoreCase)) {
            Add-RepositoryError 'private-identifier' "$source contains a caller-supplied forbidden literal."
        }
    }
}

function Test-RelativePath([string] $relativePath, [string] $source) {
    $normalized = $relativePath.Replace('\', '/')
    if ($normalized -match '(?i)(?:^|/)(?:artifacts|exports|mail|model-output|prompts|raw|scratch|transcripts)(?:/|$)' -or
        $normalized -match '(?i)\.(?:bak|eml|mbox|msg|ost|pst|zip)$') {
        Add-RepositoryError 'raw-source' "$source contains prohibited raw or scratch path '$normalized'."
    }
}

function Get-GitHubRepository([string] $url) {
    $match = [regex]::Match(
        $url,
        '(?i)^(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)(?<owner>[^/ :]+)/(?<repo>[^/]+?)(?:\.git)?$')
    if (-not $match.Success) { return $null }
    return "$($match.Groups['owner'].Value)/$($match.Groups['repo'].Value)"
}

$inputPath = $ExecutionContext.SessionState.Path.
    GetUnresolvedProviderPathFromPSPath($RepositoryPath)
if (-not (Test-Path -LiteralPath $inputPath -PathType Container)) {
    throw "The repository path does not exist: '$RepositoryPath'."
}
$root = (Resolve-Path -LiteralPath $inputPath).Path
$git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($null -eq $git) { throw 'Git is required to audit a voice source repository.' }

$gitRoot = @(& $git.Source -C $root rev-parse --show-toplevel 2>$null)
$isGitRepository = $LASTEXITCODE -eq 0 -and $gitRoot.Count -gt 0
if ($isGitRepository) { $root = [string]$gitRoot[0] }
elseif ($RequirePrivateGitHub -or $ScanHistory -or $RequirePrePushHook) {
    Add-RepositoryError 'not-git' 'A Git repository is required for the requested checks.'
}

$pathComparison = if ($IsWindows) {
    [System.StringComparison]::OrdinalIgnoreCase
}
else { [System.StringComparison]::Ordinal }
$gitMetadataPath = [System.IO.Path]::GetFullPath((Join-Path $root '.git'))
$gitMetadataPrefix = $gitMetadataPath.TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar) +
    [System.IO.Path]::DirectorySeparatorChar
$rootPrefix = [System.IO.Path]::GetFullPath($root).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar) +
    [System.IO.Path]::DirectorySeparatorChar
$scanRoots = [System.Collections.Generic.List[string]]::new()
if ($ContentPath) {
    foreach ($contentInput in $ContentPath) {
        $candidate = if ([System.IO.Path]::IsPathRooted($contentInput)) {
            [System.IO.Path]::GetFullPath($contentInput)
        }
        else { [System.IO.Path]::GetFullPath((Join-Path $root $contentInput)) }
        if (-not (Test-Path -LiteralPath $candidate)) {
            Add-RepositoryError 'content-scope' "Content path does not exist: '$contentInput'."
            continue
        }
        if (-not ($candidate.Equals($root, $pathComparison) -or
                $candidate.StartsWith($rootPrefix, $pathComparison))) {
            Add-RepositoryError 'content-scope' "Content path escapes the repository: '$contentInput'."
            continue
        }
        $scanRoots.Add($candidate)
    }
}
else { $scanRoots.Add($root) }

$workingFiles = @($scanRoots | ForEach-Object {
        if (Test-Path -LiteralPath $_ -PathType Leaf) {
            Get-Item -LiteralPath $_ -Force
        }
        else { Get-ChildItem -LiteralPath $_ -File -Recurse -Force }
    } | Sort-Object FullName -Unique)
foreach ($file in ($workingFiles |
        Where-Object {
            $fullPath = [System.IO.Path]::GetFullPath($_.FullName)
            -not $fullPath.Equals($gitMetadataPath, $pathComparison) -and
                -not $fullPath.StartsWith($gitMetadataPrefix, $pathComparison)
        })) {
    $relativePath = [System.IO.Path]::GetRelativePath($root, $file.FullName)
    Test-RelativePath $relativePath 'The working tree'
    if ($file.Length -le 2MB) {
        try { Test-Content ([System.IO.File]::ReadAllText($file.FullName)) "The working-tree file '$relativePath'" }
        catch [System.Text.DecoderFallbackException] { }
    }
}

if ($isGitRepository -and $ScanHistory) {
    $revListArguments = @('-C', $root, 'rev-list', '--objects', '--all')
    if ($ContentPath) {
        $pathSpecs = @($scanRoots | ForEach-Object {
                [System.IO.Path]::GetRelativePath($root, $_).Replace('\', '/')
            })
        $revListArguments += '--'
        $revListArguments += $pathSpecs
    }
    $objects = @(& $git.Source @revListArguments)
    if ($LASTEXITCODE -ne 0) {
        Add-RepositoryError 'history-scan' 'Could not enumerate reachable Git objects.'
    }
    else {
        foreach ($line in $objects) {
            $parts = $line -split ' ', 2
            $objectId = $parts[0]
            $relativePath = if ($parts.Count -gt 1) { $parts[1] } else { '' }
            if ($relativePath) { Test-RelativePath $relativePath 'Reachable history' }
            $objectType = @(& $git.Source -C $root cat-file -t $objectId 2>$null)
            if ($LASTEXITCODE -ne 0 -or $objectType -ne 'blob') { continue }
            $size = [int64](@(& $git.Source -C $root cat-file -s $objectId)[0])
            if ($LASTEXITCODE -ne 0 -or $size -gt 2MB) { continue }
            $blob = @(& $git.Source -C $root cat-file blob $objectId 2>$null) -join "`n"
            if ($LASTEXITCODE -eq 0) {
                Test-Content $blob "Reachable blob '$objectId'"
            }
        }
    }
}

if ($isGitRepository -and $RequirePrivateGitHub) {
    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if ($null -eq $gh) {
        Add-RepositoryError 'visibility' 'GitHub CLI is required to verify private visibility.'
    }
    else {
        $remoteLines = @(& $git.Source -C $root remote -v)
        $remoteUrls = @($remoteLines | ForEach-Object {
                ($_ -split '\s+')[1]
            } | Where-Object { $_ } | Sort-Object -Unique)
        if ($remoteUrls.Count -eq 0) {
            Add-RepositoryError 'visibility' 'No GitHub remote is configured.'
        }
        foreach ($url in $remoteUrls) {
            $repository = Get-GitHubRepository $url
            if ($null -eq $repository) {
                Add-RepositoryError 'visibility' "Remote '$url' is not a verifiable GitHub repository."
                continue
            }
            $detailsJson = @(& gh repo view $repository --json visibility,owner,name 2>$null) -join "`n"
            if ($LASTEXITCODE -ne 0) {
                Add-RepositoryError 'visibility' "Could not verify GitHub repository '$repository'."
                continue
            }
            try { $details = $detailsJson | ConvertFrom-Json -ErrorAction Stop }
            catch {
                Add-RepositoryError 'visibility' "GitHub returned invalid metadata for '$repository'."
                continue
            }
            if ([string]$details.visibility -cne 'PRIVATE') {
                Add-RepositoryError 'visibility' "GitHub repository '$repository' is not PRIVATE."
            }
            if ($ExpectedOwner -and [string]$details.owner.login -cne $ExpectedOwner) {
                Add-RepositoryError 'owner' "GitHub repository '$repository' is not owned by '$ExpectedOwner'."
            }
        }
    }
}

if ($isGitRepository -and $RequirePrePushHook) {
    $hooksPath = @(& $git.Source -C $root config --get core.hooksPath)
    if ($LASTEXITCODE -ne 0 -or $hooksPath.Count -ne 1 -or
        [string]::IsNullOrWhiteSpace([string]$hooksPath[0])) {
        Add-RepositoryError 'hook' 'core.hooksPath does not name the reviewed hook directory.'
    }
    else {
        $resolvedHooksPath = if ([System.IO.Path]::IsPathRooted($hooksPath[0])) {
            [System.IO.Path]::GetFullPath($hooksPath[0])
        }
        else { [System.IO.Path]::GetFullPath((Join-Path $root $hooksPath[0])) }
        $hook = Join-Path $resolvedHooksPath 'pre-push'
        if (-not (Test-Path -LiteralPath $hook -PathType Leaf)) {
            Add-RepositoryError 'hook' 'The reviewed pre-push hook is missing.'
        }
        else {
            $hookContent = [System.IO.File]::ReadAllText($hook)
            if ($hookContent -notmatch 'Test-UserVoiceRepository\.ps1') {
                Add-RepositoryError 'hook' 'The pre-push hook does not invoke the repository scanner.'
            }
            if (-not $IsWindows) {
                $mode = (Get-Item -LiteralPath $hook).UnixFileMode
                if (($mode -band [System.IO.UnixFileMode]::UserExecute) -eq 0) {
                    Add-RepositoryError 'hook' 'The pre-push hook is not executable.'
                }
            }
        }
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "OK user voice repository: $root"