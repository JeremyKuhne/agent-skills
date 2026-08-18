#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$skillRoot = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $skillRoot 'scripts/Test-UserVoiceThreeWayComparison.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "user-voice-three-way-$([guid]::NewGuid().ToString('N'))"
$pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
$briefKinds = @(
    'short-technical-correction',
    'extended-design-disagreement',
    'proposal',
    'defect-response',
    'decision-summary',
    'investigation-guidance',
    'low-confidence-professional-message')

function Write-TestFile([string] $path, [string] $content) {
    [System.IO.File]::WriteAllText(
        $path,
        $content.TrimEnd("`r", "`n") + "`n",
        [System.Text.UTF8Encoding]::new($false))
}

function Invoke-RequiredSuccess([string] $name, [string[]] $arguments) {
    $output = @(& $pwsh @arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "$name failed unexpectedly:`n$($output -join "`n")"
    }
}

function Invoke-RequiredFailure([string] $name, [string[]] $arguments) {
    $output = @(& $pwsh @arguments 2>&1)
    if ($LASTEXITCODE -eq 0) {
        throw "$name passed unexpectedly."
    }
}

function Get-Outcomes(
    [string] $preference,
    [string] $draftOption,
    [string] $oldOption,
    [string] $generalOption) {
    $outcomes = @{
        draft = 'loss'
        old = 'loss'
        general = 'loss'
    }
    $mapping = @{
        $draftOption = 'draft'
        $oldOption = 'old'
        $generalOption = 'general'
    }
    if ($preference -in @('a', 'b', 'c')) {
        $outcomes[$mapping[$preference]] = 'win'
    }
    elseif ($preference -match '^tie-(?<first>[abc])(?<second>[abc])$') {
        $outcomes[$mapping[$Matches.first]] = 'tie'
        $outcomes[$mapping[$Matches.second]] = 'tie'
    }
    elseif ($preference -eq 'all') {
        $outcomes.draft = 'tie'
        $outcomes.old = 'tie'
        $outcomes.general = 'tie'
    }
    return $outcomes
}

function New-Case(
    [int] $number,
    [string] $kind,
    [string] $draftOption,
    [string] $oldOption,
    [string] $generalOption,
    [string] $preference = 'uncollected') {
    $resolved = $preference -ne 'uncollected'
    $outcomes = if ($resolved) {
        Get-Outcomes $preference $draftOption $oldOption $generalOption
    }
    else {
        @{ draft = 'uncollected'; old = 'uncollected'; general = 'uncollected' }
    }
    $state = if ($resolved) { 'resolved' } else { 'sealed' }
    $usability = if ($resolved) { 'minor-edit' } else { 'uncollected' }
    $editCategory = if ($resolved) { 'none' } else { 'uncollected' }
    $editTarget = if ($resolved) { 'none' } else { 'uncollected' }
    $resolution = if ($resolved) { 'accepted' } else { 'pending' }
    $caseId = 'case-{0:D3}' -f $number
    $hash = $number.ToString('x').PadLeft(64, 'a')
    $case = @"
## $caseId

- brief-kind: $kind
- brief-contract-hash: $hash
- draft-option: $draftOption
- old-profile-option: $oldOption
- general-writing-option: $generalOption
- option-a-hard-gates: passed
- option-b-hard-gates: passed
- option-c-hard-gates: passed
- draft-old-exact-identity: no
- draft-general-exact-identity: no
- old-general-exact-identity: no
- manual-option: allowed
- preference: $preference
- option-a-usability: $usability
- option-b-usability: $usability
- option-c-usability: $usability
- first-edit-category: $editCategory
- edit-target: $editTarget
- draft-outcome: $($outcomes.draft)
- old-profile-outcome: $($outcomes.old)
- general-writing-outcome: $($outcomes.general)
- impact: high
- state: $state
- resolution: $resolution
"@
    return $case.TrimEnd("`r", "`n") + "`n"
}

function New-Batch([string[]] $preferences) {
    $mappings = @(
        @('a', 'b', 'c'),
        @('b', 'c', 'a'),
        @('c', 'a', 'b'),
        @('a', 'c', 'b'),
        @('b', 'a', 'c'),
        @('c', 'b', 'a'),
        @('a', 'b', 'c'))
    $content = @'
# User voice three-way comparison

- comparison-schema-version: 1
- draft-profile-version: candidate-1
- old-profile-version: old-1
- client-model-condition: example-client-model
- sealed-before-presentation: yes
- raw-output-retention: transient-delete
'@
    $content = $content.TrimEnd("`r", "`n") + "`n"
    foreach ($index in 0..6) {
        $mapping = $mappings[$index]
        $content += New-Case `
            -number ($index + 1) `
            -kind $briefKinds[$index] `
            -draftOption $mapping[0] `
            -oldOption $mapping[1] `
            -generalOption $mapping[2] `
            -preference $preferences[$index]
    }
    return $content
}

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $baseArguments = @('-NoProfile', '-File', $validator)

    $sealedPath = Join-Path $testRoot 'sealed.md'
    Write-TestFile $sealedPath (New-Batch (@('uncollected') * 7))
    Invoke-RequiredSuccess 'Sealed comparison' ($baseArguments + @(
            '-Path', $sealedPath,
            '-RequirePresentationReady'))

    $resolvedPath = Join-Path $testRoot 'resolved.md'
    Write-TestFile $resolvedPath (New-Batch @(
            'a',
            'b',
            'c',
            'c',
            'tie-ab',
            'tie-bc',
            'tie-ab'))
    Invoke-RequiredSuccess 'Resolved comparison' ($baseArguments + @(
            '-Path', $resolvedPath,
            '-RequireResolved'))

    $duplicateMappingPath = Join-Path $testRoot 'duplicate-mapping.md'
    Write-TestFile $duplicateMappingPath (([System.IO.File]::ReadAllText($sealedPath)).Replace(
            '- old-profile-option: b',
            '- old-profile-option: a'))
    Invoke-RequiredFailure 'Duplicate mapping' ($baseArguments + @(
            '-Path', $duplicateMappingPath,
            '-RequirePresentationReady'))

    $failedGatePath = Join-Path $testRoot 'failed-gate.md'
    Write-TestFile $failedGatePath (([System.IO.File]::ReadAllText($sealedPath)).Replace(
            '- option-c-hard-gates: passed',
            '- option-c-hard-gates: failed'))
    Invoke-RequiredFailure 'Failed safety gate' ($baseArguments + @(
            '-Path', $failedGatePath,
            '-RequirePresentationReady'))

    $identityPath = Join-Path $testRoot 'identity.md'
    Write-TestFile $identityPath (([System.IO.File]::ReadAllText($sealedPath)).Replace(
            '- draft-old-exact-identity: no',
            '- draft-old-exact-identity: yes'))
    Invoke-RequiredFailure 'Exact identity' ($baseArguments + @(
            '-Path', $identityPath,
            '-RequirePresentationReady'))

    $weakPath = Join-Path $testRoot 'weak.md'
    Write-TestFile $weakPath (New-Batch @(
            'a',
            'c',
            'a',
            'c',
            'a',
            'b',
            'b'))
    Invoke-RequiredFailure 'Weak draft result' ($baseArguments + @(
            '-Path', $weakPath,
            '-RequireResolved'))

    $outcomeMismatchPath = Join-Path $testRoot 'outcome-mismatch.md'
    Write-TestFile $outcomeMismatchPath (([System.IO.File]::ReadAllText($resolvedPath)).Replace(
            '- draft-outcome: win',
            '- draft-outcome: loss'))
    Invoke-RequiredFailure 'Outcome mismatch' ($baseArguments + @(
            '-Path', $outcomeMismatchPath,
            '-RequireResolved'))

    Write-Host 'OK three-way comparison acceptance tests'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}