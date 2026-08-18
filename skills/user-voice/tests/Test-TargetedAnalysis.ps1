#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$skillRoot = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $skillRoot 'scripts/Test-UserVoiceTargetedAnalysis.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "user-voice-targeted-$([guid]::NewGuid().ToString('N'))"
$pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })

function Write-TestFile([string] $path, [string] $content) {
    [System.IO.File]::WriteAllText(
        $path,
        $content.TrimEnd("`r", "`n") + "`n",
        [System.Text.UTF8Encoding]::new($false))
}

function Invoke-RequiredSuccess([string] $name, [string] $path) {
    $output = @(& $pwsh -NoProfile -File $validator -Path $path -ForbiddenLiteral 'ExampleIdentifier' 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "$name failed unexpectedly:`n$($output -join "`n")"
    }
}

function Invoke-RequiredFailure([string] $name, [string] $path) {
    $output = @(& $pwsh -NoProfile -File $validator -Path $path -ForbiddenLiteral 'ExampleIdentifier' 2>&1)
    if ($LASTEXITCODE -eq 0) {
        throw "$name passed unexpectedly."
    }
}

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $valid = @'
# Targeted source analysis

## Contract

- source-count-band: 6-10
- retrieval-completeness: complete
- source-independence: Each confirmed discussion is one independent source.
- authorship-confirmation: Each selected source was user confirmed and author filtered.
- raw-source-retained: no
- identifiers-included: no
- provenance: agent-derived, user-confirmed sources
- findings-status: unapproved

## Coverage

- channel-and-artifact: Public technical proposals, reviews, reports, and diagnostics.
- audience-and-relationship: Engineering peers, maintainers, and implementation collaborators.
- intent-and-stakes: Explain, correct, diagnose, recommend, and decide at medium to high stakes.
- length-and-formality: Short replies through extended technical reasoning at moderate formality.
- topic-variation: Multiple unrelated technical categories.
- era-variation: Multiple broad historical bands.
- confounds-excluded: Templates, third-party text, copied code, specifications, and topic vocabulary.

## Seven-pass findings

### Rhetorical and epistemic

- result: observed: Mechanism and evidence precede judgment while alternatives preserve uncertainty.
- supporting-count-band: 6-10
- counterexample-count-band: 1-2

### Register and relationship

- result: observed: Direct peer register varies detail with ambiguity and risk.
- supporting-count-band: 6-10
- counterexample-count-band: none

### Mechanics

- result: observed: Corrective prose stays compact while causal explanations expand as needed.
- supporting-count-band: 6-10
- counterexample-count-band: 1-2

### Interpersonal stance

- result: observed: Disagreement targets mechanisms and consequences without personal attribution.
- supporting-count-band: 6-10
- counterexample-count-band: none

### Lexical behavior

- result: observed: Concrete causal verbs and calibrated qualifiers distinguish evidence states.
- supporting-count-band: 6-10
- counterexample-count-band: 1-2

### Artifact patterns

- result: observed: Proposals compare constraints while diagnostics expose setup, action, comparison, and observation.
- supporting-count-band: 3-5
- counterexample-count-band: 1-2

### Conflicts and counterevidence

- result: observed: First-person and impersonal framing both occur and diagnostic closure remains context dependent.
- supporting-count-band: 3-5
- counterexample-count-band: 1-2

## Hypothesis dispositions

### hypothesis-001

- disposition: supported
- scope: Peer technical disagreement.
- supporting-count-band: 3-5
- counterexample-count-band: 1-2
- abstract-observation: Concise risk or first-person judgment can coexist with mechanism and a concrete check.
- confidence-ceiling: moderate
- next-check: Compare a newly revised candidate on independent held-out briefs.

### hypothesis-002

- disposition: supported
- scope: Qualified interpretation with explicit alternatives.
- supporting-count-band: 3-5
- counterexample-count-band: 1-2
- abstract-observation: Explicit alternatives can preserve uncertainty without an additional caveat.
- confidence-ceiling: provisional
- next-check: Test across different stakes and reader familiarity.

### hypothesis-003

- disposition: insufficient
- scope: Open technical diagnosis.
- supporting-count-band: 1-2
- counterexample-count-band: 1-2
- abstract-observation: Both open checks and conditional conclusions appear, so preference remains underdetermined.
- confidence-ceiling: low
- next-check: Gather a larger independently confirmed diagnostic sample.

## Existing-rule implications

- rule-002: retain - Evidence states remain distinct.
- rule-004: narrow - Diagnostic sequence is supported but causal closure remains context dependent.
- rule-005: retain - Supportability remains distinct from possibility.
- rule-008: retain - Coordination remains compact unless ambiguity or risk requires detail.
- rule-010: revise-candidate - Mechanism framing remains but assumption framing is not mandatory.
- rule-013: retain - Direct qualified interpretation with alternatives remains supported.

## Gaps

- Relationship coverage remains concentrated in peer technical collaboration.
- Diagnostic evidence is insufficient for hypothesis-003.

## Deletion attestation

- raw-extracts-written: no
- raw-source-returned: no
- transient-analysis-complete: yes
'@
    $validPath = Join-Path $testRoot 'valid.md'
    Write-TestFile $validPath $valid
    Invoke-RequiredSuccess 'Valid targeted analysis' $validPath

    $quotedPath = Join-Path $testRoot 'quoted.md'
    Write-TestFile $quotedPath ($valid.Replace(
            'Mechanism and evidence precede judgment',
            'Mechanism and evidence precede "judgment"'))
    Invoke-RequiredFailure 'Quoted source' $quotedPath

    $identifierPath = Join-Path $testRoot 'identifier.md'
    Write-TestFile $identifierPath ($valid.Replace(
            'Multiple unrelated technical categories.',
            'ExampleIdentifier categories.'))
    Invoke-RequiredFailure 'Forbidden identifier' $identifierPath

    $invalidBandPath = Join-Path $testRoot 'invalid-band.md'
    Write-TestFile $invalidBandPath ($valid.Replace(
            '- supporting-count-band: 3-5',
            '- supporting-count-band: 2-3'))
    Invoke-RequiredFailure 'Invalid count band' $invalidBandPath

    $missingPassPath = Join-Path $testRoot 'missing-pass.md'
    Write-TestFile $missingPassPath ($valid -replace '(?ms)^### Mechanics\r?\n.*?(?=^### )', '')
    Invoke-RequiredFailure 'Missing pass' $missingPassPath

    Write-Host 'OK targeted analysis acceptance tests'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}