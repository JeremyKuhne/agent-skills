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
$markerContent = [System.IO.File]::ReadAllText($markerPath)
$marker = $markerContent | ConvertFrom-Json
if ($marker.schemaVersion -notin @(1, 2)) {
    throw 'The maintenance marker has an unsupported schema.'
}

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
        @{ Pattern = '(?m)^- semantic-privacy-review:\s*passed\s*$'; Message = 'The semantic privacy review has not passed.' }
        @{ Pattern = '(?m)^- user-read-back:\s*approved\s*$'; Message = 'The user read-back has not been approved.' }
    )) {
    Assert-Text $auditPath $requirement.Pattern $requirement.Message
}
$packageCheckCount = [regex]::Matches(
    [System.IO.File]::ReadAllText($auditPath),
    '(?m)^- deterministic-package-check:\s*[^\r\n]+\r?$').Count
if ($packageCheckCount -ne 1) {
    throw 'The audit must contain exactly one deterministic-package-check field.'
}

$canonicalProfile = Join-Path $root 'voice-profile.md'
Assert-Text $canonicalProfile '(?m)^- profile-status:\s*approved\s*$' 'The canonical profile is not approved.'
Assert-Text $canonicalProfile '(?m)^- integration-contract:\s*technical-writing-user-voice-v1\s*$' 'The integration contract is not supported.'
$canonicalContent = [System.IO.File]::ReadAllText($canonicalProfile)
$schemaMatch = [regex]::Match(
    $canonicalContent,
    '(?m)^- profile-schema-version:\s*(?<version>[0-9]+)\s*$')
if (-not $schemaMatch.Success -or
    $schemaMatch.Groups['version'].Value -notin @('1', '2')) {
    throw 'The canonical profile schema is not supported.'
}
$profileSchemaVersion = [int]$schemaMatch.Groups['version'].Value
if ($marker.schemaVersion -ne $profileSchemaVersion) {
    throw 'The maintenance marker and canonical profile schema versions do not match.'
}
if ($profileSchemaVersion -eq 2) {
    foreach ($requirement in @(
            @{ Pattern = '(?m)^- source-confirmation-check:\s*passed\s*$'; Message = 'The source confirmation check has not passed.' }
            @{ Pattern = '(?m)^- nuance-matrix-check:\s*passed\s*$'; Message = 'The nuance matrix check has not passed.' }
            @{ Pattern = '(?m)^- elicitation-high-impact-results:\s*resolved\s*$'; Message = 'High-impact elicitation results remain unresolved.' }
            @{ Pattern = '(?m)^- transient-cleanup-check:\s*passed\s*$'; Message = 'The transient cleanup check has not passed.' }
            @{ Pattern = '(?m)^- section-review:\s*approved\s*$'; Message = 'The profile section review is not approved.' }
            @{ Pattern = '(?m)^- release-review:\s*passed\s*$'; Message = 'The independent release review has not passed.' }
        )) {
        Assert-Text $auditPath $requirement.Pattern $requirement.Message
    }
    $matrixPath = Join-Path $root 'nuance-matrix.md'
    $pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
    & $pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Test-UserVoiceNuanceMatrix.ps1') `
        -Path $matrixPath `
        -ProfilePath $canonicalProfile
    if ($LASTEXITCODE -ne 0) { throw 'The private nuance matrix failed validation.' }
    & $pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Test-UserVoiceTransientCleanup.ps1') `
        -MaintenanceRoot $root
    if ($LASTEXITCODE -ne 0) { throw 'Transient evaluation material remains in the maintenance root.' }
}

$runtime = Join-Path $root 'user-voice-profile'
if (-not (Test-Path -LiteralPath $runtime -PathType Container)) {
    throw 'The runtime candidate directory is missing.'
}
$parent = Split-Path -Parent $runtime
$name = Split-Path -Leaf $runtime
$staging = Join-Path $parent ".$name.build-$([guid]::NewGuid().ToString('N'))"
$backup = Join-Path $parent ".$name.backup-$([guid]::NewGuid().ToString('N'))"
$pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
$profileValidator = Join-Path $PSScriptRoot 'Test-UserVoiceProfile.ps1'

if ($WhatIfPreference) {
    & $pwsh -NoProfile -File $profileValidator `
        -ProfilePath $runtime `
        -VoiceProfileOverridePath $canonicalProfile
    if ($LASTEXITCODE -ne 0) { throw 'The built runtime profile failed validation.' }
    $null = $PSCmdlet.ShouldProcess($runtime, 'Replace runtime profile with approved build')
}
else {
    try {
        Copy-Item -LiteralPath $runtime -Destination $staging -Recurse
        [System.IO.File]::WriteAllText(
            (Join-Path $staging 'references/voice-profile.md'),
            [System.IO.File]::ReadAllText($canonicalProfile).TrimEnd("`r", "`n") + "`n",
            [System.Text.UTF8Encoding]::new($false))

        & $pwsh -NoProfile -File $profileValidator -ProfilePath $staging
        if ($LASTEXITCODE -ne 0) { throw 'The built runtime profile failed validation.' }

        if ($PSCmdlet.ShouldProcess($runtime, 'Replace runtime profile with approved build')) {
            $auditContent = [System.IO.File]::ReadAllText($auditPath)
            if ($auditContent -notmatch '(?m)^- deterministic-package-check:\s*[^\r\n]+\r?$') {
                throw 'The audit is missing deterministic-package-check.'
            }
            $updatedAuditContent = [regex]::Replace(
                $auditContent,
                '(?m)^- deterministic-package-check:\s*[^\r\n]+\r?$',
                '- deterministic-package-check: passed')
            Move-Item -LiteralPath $runtime -Destination $backup
            try {
                Move-Item -LiteralPath $staging -Destination $runtime
                [System.IO.File]::WriteAllText(
                    $auditPath,
                    $updatedAuditContent,
                    [System.Text.UTF8Encoding]::new($false))
                Remove-Item -LiteralPath $backup -Recurse -Force
            }
            catch {
                [System.IO.File]::WriteAllText(
                    $auditPath,
                    $auditContent,
                    [System.Text.UTF8Encoding]::new($false))
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
}

[pscustomobject]@{
    MaintenanceRoot = $root
    RuntimeProfile = $runtime
    ProfileStatus = 'approved'
    DeterministicPackageCheck = $(if ($WhatIfPreference) { 'validated-only' } else { 'passed' })
}
