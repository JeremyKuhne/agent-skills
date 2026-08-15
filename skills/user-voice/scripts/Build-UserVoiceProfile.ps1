#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string] $MaintenanceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Text([string] $Path, [string] $Pattern, [string] $Message) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required maintenance file is missing: '$Path'."
    }
    $content = [System.IO.File]::ReadAllText($Path)
    if ($content -notmatch $Pattern) { throw $Message }
}

$inputPath = $ExecutionContext.SessionState.Path.
    GetUnresolvedProviderPathFromPSPath($MaintenanceRoot)
if (-not (Test-Path -LiteralPath $inputPath -PathType Container)) {
    throw "The maintenance root does not exist: '$MaintenanceRoot'."
}
$root = (Resolve-Path -LiteralPath $inputPath).Path
$markerPath = Join-Path $root '.user-voice-maintenance.json'
Assert-Text $markerPath '"schemaVersion"\s*:\s*1' 'The maintenance marker has an unsupported schema.'

$consentPath = Join-Path $root 'consent-ledger.md'
foreach ($requirement in @(
        @{ Pattern = '(?m)^- consent-schema:\s*1\s*$'; Message = 'Consent schema 1 is required.' }
        @{ Pattern = '(?m)^- consent-id:\s*(?!not-approved\s*$)\S+'; Message = 'An approved consent ID is required.' }
        @{ Pattern = '(?m)^- status:\s*approved\s*$'; Message = 'Consent status must be approved.' }
        @{ Pattern = '(?m)^- analysis-provider:\s*(?!not-approved\s*$)\S+'; Message = 'An approved analysis provider is required.' }
        @{ Pattern = '(?m)^- analysis-host:\s*(?!not-approved\s*$)\S+'; Message = 'An approved analysis host is required.' }
        @{ Pattern = '(?m)^- retention:\s*(?!not-approved\s*$).+'; Message = 'A retention decision is required.' }
        @{ Pattern = '(?m)^- expiry:\s*(?!not-approved\s*$).+'; Message = 'A consent expiry is required.' }
        @{ Pattern = '(?m)^- installed-hosts:\s*(?!none\s*$).+'; Message = 'Approved installed hosts are required.' }
    )) {
    Assert-Text $consentPath $requirement.Pattern $requirement.Message
}

$auditPath = Join-Path $root 'audit-results.md'
foreach ($requirement in @(
        @{ Pattern = '(?m)^- deterministic-package-check:\s*passed\s*$'; Message = 'The deterministic package check has not passed.' }
        @{ Pattern = '(?m)^- semantic-privacy-review:\s*passed\s*$'; Message = 'The semantic privacy review has not passed.' }
        @{ Pattern = '(?m)^- user-read-back:\s*approved\s*$'; Message = 'The user read-back has not been approved.' }
    )) {
    Assert-Text $auditPath $requirement.Pattern $requirement.Message
}

$canonicalProfile = Join-Path $root 'voice-profile.md'
Assert-Text $canonicalProfile '(?m)^- profile-status:\s*approved\s*$' 'The canonical profile is not approved.'
Assert-Text $canonicalProfile '(?m)^- profile-schema-version:\s*1\s*$' 'The canonical profile schema is not supported.'
Assert-Text $canonicalProfile '(?m)^- integration-contract:\s*technical-writing-user-voice-v1\s*$' 'The integration contract is not supported.'

$runtime = Join-Path $root 'user-voice-profile'
if (-not (Test-Path -LiteralPath $runtime -PathType Container)) {
    throw 'The runtime candidate directory is missing.'
}
$parent = Split-Path -Parent $runtime
$name = Split-Path -Leaf $runtime
$staging = Join-Path $parent ".$name.build-$([guid]::NewGuid().ToString('N'))"
$backup = Join-Path $parent ".$name.backup-$([guid]::NewGuid().ToString('N'))"

try {
    Copy-Item -LiteralPath $runtime -Destination $staging -Recurse
    [System.IO.File]::WriteAllText(
        (Join-Path $staging 'references/voice-profile.md'),
        [System.IO.File]::ReadAllText($canonicalProfile).TrimEnd("`r", "`n") + "`n",
        [System.Text.UTF8Encoding]::new($false))

    $pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
    & $pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Test-UserVoiceProfile.ps1') `
        -ProfilePath $staging
    if ($LASTEXITCODE -ne 0) { throw 'The built runtime profile failed validation.' }

    if ($PSCmdlet.ShouldProcess($runtime, 'Replace runtime profile with approved build')) {
        Move-Item -LiteralPath $runtime -Destination $backup
        try {
            Move-Item -LiteralPath $staging -Destination $runtime
            Remove-Item -LiteralPath $backup -Recurse -Force
        }
        catch {
            if (Test-Path -LiteralPath $runtime) {
                Remove-Item -LiteralPath $runtime -Recurse -Force
            }
            if (Test-Path -LiteralPath $backup) {
                Move-Item -LiteralPath $backup -Destination $runtime
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
    MaintenanceRoot = $root
    RuntimeProfile = $runtime
    ProfileStatus = 'approved'
}