#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $MaintenanceRoot,

    [string] $InstalledProfilePath,

    [string[]] $DiscoveryRoot,

    [string[]] $ForbiddenProfileName,

    [string[]] $InstalledClient,

    [ValidateSet('not-run', 'passed')]
    [string] $InvocationVerification = 'not-run',

    [string] $AnotherMachineStatus = 'not prepared',

    [string] $NextReview,

    [string] $NextApproval
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$rootInput = $ExecutionContext.SessionState.Path.
    GetUnresolvedProviderPathFromPSPath($MaintenanceRoot)
if (-not (Test-Path -LiteralPath $rootInput -PathType Container)) {
    throw "The maintenance root does not exist: '$MaintenanceRoot'."
}
$root = (Resolve-Path -LiteralPath $rootInput).Path
$profilePath = Join-Path $root 'voice-profile.md'
$consentPath = Join-Path $root 'consent-ledger.md'
foreach ($required in @($profilePath, $consentPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required maintenance file is missing: '$required'."
    }
}
$profile = [System.IO.File]::ReadAllText($profilePath)
$consent = [System.IO.File]::ReadAllText($consentPath)

$profileVersionMatch = [regex]::Match(
    $profile,
    '(?m)^- profile-version:\s*(?<value>\S+)\s*$')
$profileStatusMatch = [regex]::Match(
    $profile,
    '(?m)^- profile-status:\s*(?<value>\S+)\s*$')
if (-not $profileVersionMatch.Success -or -not $profileStatusMatch.Success) {
    throw 'The canonical profile is missing profile-version or profile-status.'
}

$status = if ($profileStatusMatch.Groups['value'].Value -eq 'approved') {
    'approved and ready to install'
}
else { 'draft, not approved' }
$installedClients = 'not installed'
if ($InstalledProfilePath) {
    if (@($InstalledClient | Where-Object { $_ }).Count -eq 0) {
        throw 'InstalledClient is required when InstalledProfilePath is supplied.'
    }
    if ($InvocationVerification -ne 'passed') {
        throw 'Installed completion requires passed fresh-session invocation verification.'
    }
    $sourceRuntime = Join-Path $root 'user-voice-profile'
    $verificationParameters = @{
        SourcePath = $sourceRuntime
        InstalledPath = $InstalledProfilePath
        RequireSingleActiveProfile = $true
    }
    if (@($DiscoveryRoot | Where-Object { $_ }).Count -gt 0) {
        $verificationParameters.DiscoveryRoot = $DiscoveryRoot
    }
    if (@($ForbiddenProfileName | Where-Object { $_ }).Count -gt 0) {
        $verificationParameters.ForbiddenProfileName = $ForbiddenProfileName
    }
    $verificationOutput = @(& (Join-Path $PSScriptRoot 'Test-UserVoiceInstallation.ps1') `
            @verificationParameters 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Installed profile verification failed; completion cannot claim installation:`n$($verificationOutput -join "`n")"
    }
    $status = 'installed and checked'
    $installedClients = @($InstalledClient | Where-Object { $_ }) -join ', '
}

$contexts = @{
    Supported = [System.Collections.Generic.List[string]]::new()
    Provisional = [System.Collections.Generic.List[string]]::new()
    Unsupported = [System.Collections.Generic.List[string]]::new()
}
$contextSection = [regex]::Match(
    $profile,
    '(?ms)^## Context matrix\r?\n(?<body>.*?)(?=^## |\z)')
if (-not $contextSection.Success) {
    throw 'The canonical profile is missing the required Context matrix section.'
}
$recognizedContexts = 0
foreach ($row in [regex]::Matches(
        $contextSection.Groups['body'].Value,
        '(?m)^\|\s*(?<context>[^|]+?)\s*\|\s*(?<status>[^|]+?)\s*\|')) {
    $context = $row.Groups['context'].Value.Trim()
    $contextStatus = $row.Groups['status'].Value.Trim()
    if ($context -eq 'Context' -or $context -match '^-+$') { continue }
    if ($contextStatus -match '(?i)^unsupported(?:\s|,|$)') {
        $contexts.Unsupported.Add($context)
    }
    elseif ($contextStatus -match '(?i)^provisional(?:\s|,|$)') {
        $contexts.Provisional.Add($context)
    }
    elseif ($contextStatus -match '(?i)^supported(?:\s|,|$)') {
        $contexts.Supported.Add($context)
    }
    else {
        throw "Context '$context' has an unsupported evidence status: '$contextStatus'."
    }
    $recognizedContexts++
}
if ($recognizedContexts -eq 0) {
    throw 'The canonical profile Context matrix contains no recognized context rows.'
}
foreach ($key in @('Supported', 'Provisional', 'Unsupported')) {
    if ($contexts[$key].Count -eq 0) { $contexts[$key].Add('none') }
}

$retentionMatch = [regex]::Match(
    $consent,
    '(?m)^- retention:\s*(?<value>.+?)\s*$')
$retention = if ($retentionMatch.Success) {
    $retentionMatch.Groups['value'].Value
}
else { 'not recorded' }
if (-not $NextReview) {
    $expiryMatch = [regex]::Match($consent, '(?m)^- expiry:\s*(?<value>.+?)\s*$')
    $NextReview = if ($expiryMatch.Success) {
        $expiryMatch.Groups['value'].Value
    }
    else { 'not recorded' }
}
if (-not $NextApproval) {
    $NextApproval = switch ($status) {
        'draft, not approved' { 'review each part and decide whether to approve this exact draft' }
        'approved and ready to install' { 'separate decision to install' }
        default { 'none' }
    }
}

@"
Profile state: $status
Profile version: $($profileVersionMatch.Groups['value'].Value)

Use it naturally:
- Rewrite this design note in my voice.
- Review this comment for fit with my voice.

Where it can help:
- Ready to use: $($contexts.Supported -join '; ')
- Not ready yet; uses general writing: $($contexts.Provisional -join '; ')
- Not covered: $($contexts.Unsupported -join '; ')

Installed in: $installedClients
Can it send or post: No
Private evidence kept: $retention
Moving to another machine: $AnotherMachineStatus
Next check: $NextReview
Next decision: $NextApproval
"@.TrimEnd("`r", "`n")