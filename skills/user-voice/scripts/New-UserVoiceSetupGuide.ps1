#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Windows', 'Posix')]
    [string] $Platform,

    [Parameter(Mandatory)]
    [ValidateSet('PrivateGitHub', 'LocalTransfer')]
    [string] $SourceMethod,

    [Parameter(Mandatory)]
    [string] $Client,

    [Parameter(Mandatory)]
    [string] $SourceRevision,

    [Parameter(Mandatory)]
    [string] $SourceLocation,

    [Parameter(Mandatory)]
    [string] $DestinationRoot,

    [Parameter(Mandatory)]
    [string] $InstallerPath,

    [Parameter(Mandatory)]
    [string] $VerifierPath,

    [Parameter(Mandatory)]
    [string] $RuntimePath,

    [Parameter(Mandatory)]
    [string] $InstalledPath,

    [ValidateSet('github-copilot')]
    [string] $TargetHost = 'github-copilot',

    [Parameter(Mandatory)]
    [string] $OutputPath,

    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-SafeValue([string] $value, [string] $name) {
    if ([string]::IsNullOrWhiteSpace($value) -or
        $value -match "[\r\n`0'`]" ) {
        throw "$name contains an unsupported character or is empty."
    }
}

function Get-PosixParentPath([string] $path) {
    $normalized = $path.Replace('\', '/').TrimEnd('/')
    $separator = $normalized.LastIndexOf('/')
    if ($separator -lt 0) {
        throw "InstalledPath must include a parent directory for a POSIX guide: '$path'."
    }
    if ($separator -eq 0) { return '/' }
    return $normalized.Substring(0, $separator)
}

foreach ($entry in @(
        @{ Value = $Client; Name = 'Client' }
        @{ Value = $SourceRevision; Name = 'SourceRevision' }
        @{ Value = $SourceLocation; Name = 'SourceLocation' }
        @{ Value = $DestinationRoot; Name = 'DestinationRoot' }
        @{ Value = $InstallerPath; Name = 'InstallerPath' }
        @{ Value = $VerifierPath; Name = 'VerifierPath' }
        @{ Value = $RuntimePath; Name = 'RuntimePath' }
        @{ Value = $InstalledPath; Name = 'InstalledPath' })) {
    Assert-SafeValue $entry.Value $entry.Name
}
if ($SourceMethod -eq 'PrivateGitHub' -and
    ($SourceLocation -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or
        $SourceRevision -cnotmatch '^[0-9a-fA-F]{40}$')) {
    throw 'PrivateGitHub requires an owner/repository source and a full 40-character commit.'
}
if ($SourceMethod -eq 'LocalTransfer' -and
    $SourceRevision -cnotmatch '^[0-9a-fA-F]{64}$') {
    throw 'LocalTransfer requires the reviewed manifest SHA-256 as SourceRevision.'
}

$assets = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets'
$templatePath = Join-Path $assets $(if ($Platform -eq 'Windows') {
        'setup-windows.md.tmpl'
    }
    else { 'setup-posix.md.tmpl' })
$template = [System.IO.File]::ReadAllText($templatePath)

if ($SourceMethod -eq 'PrivateGitHub') {
    $sourceOwner = ($SourceLocation -split '/', 2)[0]
    $repositoryVerifier = if ($Platform -eq 'Windows') {
        Join-Path $DestinationRoot '.private-voice\Test-UserVoiceRepository.ps1'
    }
    else {
        "$($DestinationRoot.TrimEnd('/'))/.private-voice/Test-UserVoiceRepository.ps1"
    }
    $sourceSteps = if ($Platform -eq 'Windows') {
@"
1. Authenticate interactively with GitHub CLI in its own interface. Do not put a token in this guide.
2. Verify the repository is owned as expected and reports exactly `PRIVATE`.
3. Clone and detach at the reviewed commit:

```pwsh
gh repo view '$SourceLocation' --json visibility,owner,name
gh repo clone '$SourceLocation' '$DestinationRoot'
git -C '$DestinationRoot' checkout --detach '$SourceRevision'
```
4. Scan the checked source and all reachable history before installing:

```pwsh
pwsh '$repositoryVerifier' -RepositoryPath '$DestinationRoot' -RequirePrivateGitHub -ScanHistory -ExpectedOwner '$sourceOwner'
```
"@
    }
    else {
@"
1. Authenticate interactively with GitHub CLI in its own interface. Do not put a token in this guide.
2. Verify the repository is owned as expected and reports exactly `PRIVATE`.
3. Clone and detach at the reviewed commit:

```bash
gh repo view '$SourceLocation' --json visibility,owner,name
gh repo clone '$SourceLocation' '$DestinationRoot'
git -C '$DestinationRoot' checkout --detach '$SourceRevision'
```
4. Scan the checked source and all reachable history before installing:

```bash
pwsh '$repositoryVerifier' -RepositoryPath '$DestinationRoot' -RequirePrivateGitHub -ScanHistory -ExpectedOwner '$sourceOwner'
```
"@
    }
}
else {
    $sourceSteps = @"
1. Transfer the reviewed private package through the separately approved secure local channel to `$DestinationRoot`.
2. Compare the transferred manifest SHA-256 with `$SourceRevision` before opening or installing it.
3. Stop if the manifest, owner, destination, or private-storage boundary differs.
"@
}

$discoveryRoot = if ($Platform -eq 'Windows') {
    [System.IO.Path]::GetDirectoryName($InstalledPath)
}
else { Get-PosixParentPath $InstalledPath }
if ([string]::IsNullOrWhiteSpace($discoveryRoot)) {
    throw "InstalledPath must include a parent directory: '$InstalledPath'."
}
$verifySteps = if ($Platform -eq 'Windows') {
@"
Run the exact source/install and duplicate-profile check:

```pwsh
pwsh '$VerifierPath' `
  -SourcePath '$RuntimePath' `
  -InstalledPath '$InstalledPath' `
    -DiscoveryRoot '$discoveryRoot' `
  -RequireSingleActiveProfile
```

Reload `$Client`, start a fresh session, and verify natural and explicit attributed-writing requests both use one profile and return local text only.
"@
}
else {
@"
Run the exact source/install and duplicate-profile check:

```bash
pwsh '$VerifierPath' \
  -SourcePath '$RuntimePath' \
  -InstalledPath '$InstalledPath' \
    -DiscoveryRoot '$discoveryRoot' \
  -RequireSingleActiveProfile
```

Reload `$Client`, start a fresh session, and verify natural and explicit attributed-writing requests both use one profile and return local text only.
"@
}

$tokens = @{
    CLIENT = $Client
    SOURCE_METHOD = $SourceMethod
    SOURCE_REVISION = $SourceRevision
    TARGET_DESCRIPTION = "private personal install for $Client"
    SOURCE_STEPS = $sourceSteps.TrimEnd("`r", "`n")
    INSTALLER_PATH = $InstallerPath
    RUNTIME_PATH = $RuntimePath
    TARGET_HOST = $TargetHost
    VERIFY_STEPS = $verifySteps.TrimEnd("`r", "`n")
}
$content = $template
foreach ($token in $tokens.Keys) {
    $content = $content.Replace("{{$token}}", [string] $tokens[$token])
}
if ($content -match '\{\{[^}]+\}\}') {
    throw 'The generated setup guide contains an unresolved token.'
}

$destination = $ExecutionContext.SessionState.Path.
    GetUnresolvedProviderPathFromPSPath($OutputPath)
$parent = Split-Path -Parent $destination
if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    throw "The output directory does not exist: '$parent'."
}
if ((Test-Path -LiteralPath $destination) -and -not $Force) {
    throw "The output already exists: '$OutputPath'. Pass -Force to replace it."
}
if ($PSCmdlet.ShouldProcess($destination, 'Write private another-machine setup guide')) {
    [System.IO.File]::WriteAllText(
        $destination,
        $content.TrimEnd("`r", "`n") + "`n",
        [System.Text.UTF8Encoding]::new($false))
}

[pscustomobject]@{
    OutputPath = $destination
    Platform = $Platform
    SourceMethod = $SourceMethod
    Client = $Client
}