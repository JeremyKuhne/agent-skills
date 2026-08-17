#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ProfilePath,

    [switch] $AllowDraft,

    [string[]] $ForbiddenLiteral
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$errors = [System.Collections.Generic.List[string]]::new()
function Add-ProfileError([string] $category, [string] $message) {
    $errors.Add("[$category] $message")
}

$profileRoot = $ExecutionContext.SessionState.Path.
    GetUnresolvedProviderPathFromPSPath($ProfilePath)
if (-not (Test-Path -LiteralPath $profileRoot -PathType Container)) {
    throw "The profile directory does not exist: '$ProfilePath'."
}
$profileRoot = (Resolve-Path -LiteralPath $profileRoot).Path

$expectedFiles = @(
    'INSTALL.md',
    'SKILL.md',
    'references/evaluations.md',
    'references/voice-profile.md')
$actualFiles = @(Get-ChildItem -LiteralPath $profileRoot -File -Recurse -Force |
    ForEach-Object {
        [System.IO.Path]::GetRelativePath($profileRoot, $_.FullName).
            Replace('\', '/')
    } |
    Sort-Object)
foreach ($difference in @(Compare-Object $expectedFiles $actualFiles)) {
    $category = if ($difference.SideIndicator -eq '=>') {
        'unexpected-file'
    }
    else { 'missing-file' }
    Add-ProfileError $category "Package file '$($difference.InputObject)' does not match the required manifest."
}

foreach ($item in (Get-ChildItem -LiteralPath $profileRoot -Recurse -Force)) {
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        Add-ProfileError 'reparse-point' "Package contains a reparse point: '$($item.Name)'."
    }
}

$skillPath = Join-Path $profileRoot 'SKILL.md'
$voicePath = Join-Path $profileRoot 'references/voice-profile.md'
$skillSchemaVersion = $null
$profileSchemaVersion = $null
if (Test-Path -LiteralPath $skillPath -PathType Leaf) {
    $skill = [System.IO.File]::ReadAllText($skillPath)
    if ($skill -notmatch '(?m)^name:\s*user-voice-profile\s*$') {
        Add-ProfileError 'discovery-metadata' 'The runtime skill name must be user-voice-profile.'
    }
    if ($skill -notmatch '(?m)^description:.*current user') {
        Add-ProfileError 'discovery-metadata' 'The runtime description must be generic and current-user scoped.'
    }
    $skillSchemaMatch = [regex]::Match(
        $skill,
        '(?m)^\s*profile-schema-version:\s*(?<version>[0-9]+)\s*$')
    if (-not $skillSchemaMatch.Success) {
        Add-ProfileError 'missing-boundary' 'SKILL.md is missing profile-schema-version.'
    }
    else {
        $skillSchemaVersion = $skillSchemaMatch.Groups['version'].Value
        if ($skillSchemaVersion -notin @('1', '2')) {
            Add-ProfileError 'unsupported-schema' "SKILL.md uses unsupported profile schema '$skillSchemaVersion'."
        }
    }
    foreach ($requiredText in @(
            'integration-contract: technical-writing-user-voice-v1',
            'Compose with `technical-writing`',
            'This skill ends with local text',
            'Refuse third-party impersonation')) {
        if (-not $skill.Contains($requiredText, [System.StringComparison]::OrdinalIgnoreCase)) {
            Add-ProfileError 'missing-boundary' "SKILL.md is missing required boundary text: $requiredText"
        }
    }
}

if (Test-Path -LiteralPath $voicePath -PathType Leaf) {
    $voice = [System.IO.File]::ReadAllText($voicePath)
    $profileSchemaMatch = [regex]::Match(
        $voice,
        '(?m)^- profile-schema-version:\s*(?<version>[0-9]+)\s*$')
    if (-not $profileSchemaMatch.Success) {
        Add-ProfileError 'missing-boundary' 'voice-profile.md is missing profile-schema-version.'
    }
    else {
        $profileSchemaVersion = $profileSchemaMatch.Groups['version'].Value
        if ($profileSchemaVersion -notin @('1', '2')) {
            Add-ProfileError 'unsupported-schema' "voice-profile.md uses unsupported profile schema '$profileSchemaVersion'."
        }
        elseif ($profileSchemaVersion -eq '2' -and
            $voice -notmatch '(?m)^- profile-version:\s*\S+\s*$') {
            Add-ProfileError 'missing-boundary' 'Schema version 2 requires profile-version.'
        }
        if ($profileSchemaVersion -eq '2') {
            if ($voice -match '(?m)^- (?:installation|installation-status|active-runtime|installed-path|rollback-version|profile-disposition|build-status):') {
                Add-ProfileError 'volatile-lifecycle' 'Schema version 2 voice-profile.md cannot contain current build, installation, active-runtime, path, rollback, or disposition fields.'
            }
            if ($voice -match '(?im)^(?:#{1,6}\s*)?(?:approved, but not built, installed, or active|approved and ready to install|installed and checked|not installed|pending build|pending installation)\s*:?\s*$') {
                Add-ProfileError 'volatile-lifecycle' 'Schema version 2 voice-profile.md cannot describe current build or installation state in profile prose.'
            }
            $ruleMatches = @([regex]::Matches(
                    $voice,
                    '(?ms)^### (?<id>rule-[0-9]{3})\r?\n(?<body>.*?)(?=^### |^## |\z)'))
            foreach ($ruleMatch in $ruleMatches) {
                $ruleId = $ruleMatch.Groups['id'].Value
                $ruleBody = $ruleMatch.Groups['body'].Value
                $runtimeMatch = [regex]::Match(
                    $ruleBody,
                    '(?m)^- runtime-status:\s*(?<value>\S+)\s*$')
                $approvalMatch = [regex]::Match(
                    $ruleBody,
                    '(?m)^- user-approved:\s*(?<value>\S+)\s*$')
                if (-not $runtimeMatch.Success -or
                    $runtimeMatch.Groups['value'].Value -notin @('inactive', 'active')) {
                    Add-ProfileError 'invalid-rule' "Schema version 2 rule '$ruleId' requires runtime-status inactive or active."
                }
                elseif ($runtimeMatch.Groups['value'].Value -eq 'active' -and
                    (-not $approvalMatch.Success -or
                        $approvalMatch.Groups['value'].Value -ne 'yes')) {
                    Add-ProfileError 'invalid-rule' "Active rule '$ruleId' must be user approved."
                }
            }
        }
    }
    foreach ($requiredText in @(
            'integration-contract: technical-writing-user-voice-v1',
            'This profile shapes form only')) {
        if (-not $voice.Contains($requiredText, [System.StringComparison]::OrdinalIgnoreCase)) {
            Add-ProfileError 'missing-boundary' "voice-profile.md is missing required contract text: $requiredText"
        }
    }
    if (-not $AllowDraft -and $voice -match '(?m)^- profile-status:\s*draft-unapproved\s*$') {
        Add-ProfileError 'unapproved-profile' 'The profile remains draft-unapproved.'
    }
}

if ($null -ne $skillSchemaVersion -and
    $null -ne $profileSchemaVersion -and
    $skillSchemaVersion -cne $profileSchemaVersion) {
    Add-ProfileError 'schema-mismatch' 'SKILL.md and voice-profile.md use different profile schema versions.'
}

$allText = @($actualFiles | ForEach-Object {
        [System.IO.File]::ReadAllText((Join-Path $profileRoot $_))
    }) -join "`n"
$checks = @(
    @{ Category = 'private-identifier'; Pattern = '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'; Message = 'Email addresses are not allowed.' },
    @{ Category = 'external-reference'; Pattern = '(?i)https?://|mailto:|www\.'; Message = 'Source URLs are not allowed in the runtime package.' },
    @{ Category = 'absolute-path'; Pattern = '(?m)(?:[A-Za-z]:\\|/(?:Users|home|mnt|tmp|var|etc)/)'; Message = 'Absolute paths are not allowed.' },
    @{ Category = 'secret'; Pattern = '(?i)-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|\bgh[pousr]_[A-Za-z0-9_]{20,}\b|\bAKIA[0-9A-Z]{16}\b'; Message = 'Secret material is not allowed.' },
    @{ Category = 'unresolved-template'; Pattern = '\{\{[^}]+\}\}'; Message = 'Template placeholders must be resolved.' },
    @{ Category = 'raw-source'; Pattern = '(?i)\b(?:mailbox export|raw email|message subject|source transcript)\b'; Message = 'Raw-source material is not allowed.' })
foreach ($check in $checks) {
    if ($allText -match $check.Pattern) {
        Add-ProfileError $check.Category $check.Message
    }
}
foreach ($literal in @($ForbiddenLiteral | Where-Object { $_ })) {
    if ($allText.Contains($literal, [System.StringComparison]::OrdinalIgnoreCase)) {
        Add-ProfileError 'private-identifier' 'A caller-supplied forbidden literal is present.'
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "OK user voice profile: $profileRoot"
