#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string] $MaintenanceRoot,

    [switch] $PreparePrivateRepository,
    [switch] $PrivateGitHubSource,
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-PathWithin([string] $candidate, [string] $root) {
    $comparison = if ($IsWindows) {
        [System.StringComparison]::OrdinalIgnoreCase
    }
    else { [System.StringComparison]::Ordinal }
    $candidatePath = [System.IO.Path]::GetFullPath($candidate)
    $rootPath = [System.IO.Path]::GetFullPath($root).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    return $candidatePath.Equals($rootPath, $comparison) -or
        $candidatePath.StartsWith(
            "$rootPath$([System.IO.Path]::DirectorySeparatorChar)",
            $comparison)
}

function Get-ExistingAncestor([string] $path) {
    $candidate = [System.IO.Path]::GetFullPath($path)
    while (-not (Test-Path -LiteralPath $candidate)) {
        $parent = Split-Path -Parent $candidate
        if (-not $parent -or $parent -eq $candidate) {
            throw "No existing ancestor was found for '$path'."
        }
        $candidate = $parent
    }
    return $candidate
}

function Copy-Template([string] $source, [string] $destination, [hashtable] $tokens) {
    $content = [System.IO.File]::ReadAllText($source)
    foreach ($token in $tokens.Keys) {
        $content = $content.Replace("{{$token}}", [string]$tokens[$token])
    }
    if ($content -match '(?<!\$)\{\{[^}]+\}\}') {
        throw "Template '$source' contains an unresolved token."
    }
    $directory = Split-Path -Parent $destination
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    [System.IO.File]::WriteAllText(
        $destination,
        $content.TrimEnd("`r", "`n") + "`n",
        [System.Text.UTF8Encoding]::new($false))
}

$target = [System.IO.Path]::GetFullPath(
    $ExecutionContext.SessionState.Path.
        GetUnresolvedProviderPathFromPSPath($MaintenanceRoot))
$ancestor = Get-ExistingAncestor $target
if ($target.StartsWith('\\', [System.StringComparison]::Ordinal)) {
    throw 'The maintenance root cannot be a network path.'
}
foreach ($syncRoot in @(
        $env:OneDrive,
        $env:OneDriveConsumer,
        $env:OneDriveCommercial,
        $env:Dropbox,
        $env:GoogleDrive) | Where-Object { $_ }) {
    if (Test-PathWithin $target $syncRoot) {
        throw "The maintenance root is inside a synchronized directory: '$syncRoot'."
    }
}
$candidate = $ancestor
while ($candidate) {
    if (Test-Path -LiteralPath $candidate) {
        $item = Get-Item -LiteralPath $candidate -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "The maintenance path contains a reparse point: '$candidate'."
        }
    }
    $parent = Split-Path -Parent $candidate
    if (-not $parent -or $parent -eq $candidate) { break }
    $candidate = $parent
}

$git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($null -ne $git) {
    $gitRoot = @(& $git.Source -C $ancestor rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -eq 0 -and $gitRoot.Count -gt 0) {
        if (-not $PrivateGitHubSource) {
            throw 'The maintenance root is inside a Git repository. Pass -PrivateGitHubSource only after accepting and verifying the private GitHub source boundary.'
        }
        $repositoryValidator = Join-Path $PSScriptRoot 'Test-UserVoiceRepository.ps1'
        $pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
        $repositoryArguments = @(
            '-NoProfile',
            '-File', $repositoryValidator,
            '-RepositoryPath', $gitRoot[0],
            '-RequirePrivateGitHub',
            '-ContentPath', $target,
            '-ScanHistory')
        & $pwsh @repositoryArguments
        if ($LASTEXITCODE -ne 0) {
            throw 'The Git source could not be verified as private.'
        }
    }
    elseif ($PrivateGitHubSource) {
        throw '-PrivateGitHubSource requires the maintenance root to be inside a verifiable private GitHub repository.'
    }
}
elseif ($PrivateGitHubSource) {
    throw 'Git is required to verify a private GitHub source.'
}

$parentRoot = Split-Path -Parent $target
New-Item -ItemType Directory -Path $parentRoot -Force | Out-Null
$name = Split-Path -Leaf $target
$staging = Join-Path $parentRoot ".$name.user-voice-staging-$([guid]::NewGuid().ToString('N'))"
$backup = Join-Path $parentRoot ".$name.user-voice-backup-$([guid]::NewGuid().ToString('N'))"

if (Test-Path -LiteralPath $target) {
    if (-not $Force) { throw "The maintenance root already exists. Pass -Force to replace a generated root: '$target'." }
    if (-not (Test-Path -LiteralPath (Join-Path $target '.user-voice-maintenance.json') -PathType Leaf)) {
        throw 'Refusing to replace a directory without the user-voice maintenance marker.'
    }
}

try {
    New-Item -ItemType Directory -Path $staging | Out-Null
    $assets = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets'
    $runtimeAssets = Join-Path $assets 'user-voice-profile'
    $runtime = Join-Path $staging 'user-voice-profile'
    $references = Join-Path $runtime 'references'
    New-Item -ItemType Directory -Path $references -Force | Out-Null

    $tokens = @{
        SUPPORTED_CONTEXT = 'No context is approved until private profile review completes.'
        UNSUPPORTED_CONTEXT = 'All contexts remain unsupported while this profile is draft-unapproved.'
        ONE_PARAGRAPH_APPROVED_CENTER_OF_VOICE = 'Complete during private profile review.'
        ABSTRACT_WRITING_DECISION = 'Complete during private profile review.'
        BROAD_CONTEXT = 'unsupported'
        OBSERVABLE_CHECK = 'Complete during private profile review.'
        CONTEXT = 'Unreviewed context'
        DISTRIBUTION_OR_TOLERANCE = 'Complete during private profile review.'
        CONDITIONAL_APPROVED_MOVE = 'Complete during private profile review.'
        STATED_OR_VALIDATED_PREFERENCE = 'Complete during private profile review.'
        MATERIAL_CONFLICT_OR_GAP = 'The profile has not been reviewed or approved.'
    }
    $canonicalVoice = Join-Path $staging 'voice-profile.md'
    Copy-Template (Join-Path $runtimeAssets 'voice-profile.md.tmpl') $canonicalVoice $tokens
    Copy-Item -LiteralPath $canonicalVoice -Destination (Join-Path $references 'voice-profile.md')
    Copy-Template (Join-Path $runtimeAssets 'SKILL.md.tmpl') (Join-Path $runtime 'SKILL.md') @{}
    Copy-Template (Join-Path $runtimeAssets 'evaluations.md.tmpl') (Join-Path $references 'evaluations.md') @{}
    Copy-Template (Join-Path $runtimeAssets 'INSTALL.md.tmpl') (Join-Path $runtime 'INSTALL.md') @{}

    [System.IO.File]::WriteAllText(
        (Join-Path $staging 'consent-ledger.md'),
        "# Consent ledger`n`n- consent-schema: 1`n- consent-id: not-approved`n- status: incomplete`n- analysis-provider: not-approved`n- analysis-host: not-approved`n- retention: not-approved`n- expiry: not-approved`n- installed-hosts: none`n",
        [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText(
        (Join-Path $staging 'evidence-cards.md'),
        "# De-identified evidence cards`n`nNo evidence has been approved or retained.`n",
        [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText(
        (Join-Path $staging 'audit-results.md'),
        "# Audit results`n`n- deterministic-package-check: not-run`n- semantic-privacy-review: not-run`n- user-read-back: not-approved`n",
        [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText(
        (Join-Path $staging '.user-voice-maintenance.json'),
        ([ordered]@{
                schemaVersion = 1
                runtimeDirectory = 'user-voice-profile'
                profileStatus = 'draft-unapproved'
            } | ConvertTo-Json) + "`n",
        [System.Text.UTF8Encoding]::new($false))

    if ($PreparePrivateRepository) {
        $repositoryAssets = Join-Path $assets 'private-source-repository'
        Copy-Template (Join-Path $repositoryAssets 'gitignore.tmpl') (Join-Path $staging '.gitignore') @{}
        Copy-Template (Join-Path $repositoryAssets 'pre-push.tmpl') (Join-Path $staging '.githooks/pre-push') @{}
        Copy-Template (Join-Path $repositoryAssets 'private-voice-audit.yml.tmpl') (Join-Path $staging '.github/workflows/private-voice-audit.yml') @{}
        $privateTools = Join-Path $staging '.private-voice'
        New-Item -ItemType Directory -Path $privateTools | Out-Null
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Test-UserVoiceRepository.ps1') -Destination $privateTools
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Test-UserVoiceProfile.ps1') -Destination $privateTools
    }

    $pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
    & $pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Test-UserVoiceProfile.ps1') `
        -ProfilePath $runtime `
        -AllowDraft
    if ($LASTEXITCODE -ne 0) { throw 'The generated runtime candidate failed validation.' }

    if ($PSCmdlet.ShouldProcess($target, 'Create private user voice maintenance root')) {
        if (Test-Path -LiteralPath $target) {
            Move-Item -LiteralPath $target -Destination $backup
        }
        try {
            Move-Item -LiteralPath $staging -Destination $target
            if (Test-Path -LiteralPath $backup) {
                Remove-Item -LiteralPath $backup -Recurse -Force
            }
        }
        catch {
            if (Test-Path -LiteralPath $target) {
                Remove-Item -LiteralPath $target -Recurse -Force
            }
            if (Test-Path -LiteralPath $backup) {
                Move-Item -LiteralPath $backup -Destination $target
            }
            throw
        }
    }
}
finally {
    if (Test-Path -LiteralPath $staging) {
        Remove-Item -LiteralPath $staging -Recurse -Force
    }
    if (Test-Path -LiteralPath $backup) {
        Remove-Item -LiteralPath $backup -Recurse -Force
    }
}

[pscustomobject]@{
    MaintenanceRoot = $target
    RuntimeProfile = Join-Path $target 'user-voice-profile'
    Status = 'draft-unapproved'
    PreparedPrivateRepository = [bool]$PreparePrivateRepository
}