#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$skillRoot = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $skillRoot 'scripts/Test-UserVoiceElicitationBatch.ps1'
$template = Join-Path $skillRoot 'assets/elicitation-batch.md.tmpl'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "user-voice-elicitation-$([guid]::NewGuid().ToString('N'))"
$pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })

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

function New-GenericityCase(
    [int] $number,
    [string] $outcome,
    [string] $result,
    [string] $attribution,
    [string] $resolution = 'accepted') {
    $caseId = 'case-{0:D3}' -f $number
    $placement = if ($number % 2 -eq 0) { 'b' } else { 'a' }
    $order = if ($number % 2 -eq 0) { 'b-first' } else { 'a-first' }
    $case = @"
## $caseId

- case-kind: genericity
- nuance-context-id: context-001
- draft-rule-id: rule-001
- draft-profile-version: candidate-1
- controlled-contrast: information order
- candidate-placement: $placement
- order: $order
- option-a-contract-hash: $('a' * 64)
- option-b-contract-hash: $('a' * 64)
- option-a-hard-gates: passed
- option-b-hard-gates: passed
- exact-identity: no
- manual-option: allowed
- hard-gates: passed
- profile-outcome: $outcome
- attributed-nuance: $attribution
- impact: high
- state: resolved
- result: $result
- resolution: $resolution
"@
    return $case.TrimEnd("`r", "`n") + "`n"
}

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $profilePath = Join-Path $testRoot 'profile.md'
    $matrixPath = Join-Path $testRoot 'matrix.md'
    Write-TestFile $profilePath @'
# Private user voice profile

- profile-schema-version: 2
- profile-version: candidate-1

## Durable rhetorical and epistemic traits

### rule-001

- claim: Lead with the controlling constraint.
- user-approved: no
- runtime-status: inactive
'@
    Write-TestFile $matrixPath @'
# User voice nuance matrix

- matrix-schema-version: 1
- profile-schema-version: 2
- profile-version: candidate-1
- retention-policy: minimum

## context-001

- candidate-rule-ids: rule-001
'@

    $preference = [System.IO.File]::ReadAllText($template)
    foreach ($number in 1..3) {
        $preference = $preference.
            Replace("{{CONTEXT_ID_$number}}", 'context-001').
            Replace("{{RULE_ID_$number}}", 'rule-001').
            Replace("{{CONTROLLED_CONTRAST_$number}}", 'information order')
    }
    $preference = $preference.Replace('{{PROFILE_VERSION}}', 'candidate-1')
    $preference = $preference.Replace(
        '{{CLIENT_MODEL_CONDITION}}',
        'example-client-model')
    foreach ($number in 1..3) {
        $preference = $preference.Replace(
            "{{CONTRACT_HASH_$number}}",
            ('a' * 64))
    }
    $preferencePath = Join-Path $testRoot 'preference.md'
    Write-TestFile $preferencePath $preference
    $baseArguments = @(
        '-NoProfile', '-File', $validator,
        '-MatrixPath', $matrixPath,
        '-ProfilePath', $profilePath)
    Invoke-RequiredSuccess 'Presentation ready' ($baseArguments + @(
            '-Path', $preferencePath,
            '-RequirePresentationReady'))

    $genericityHeader = @'
# User voice elicitation batch

- batch-schema-version: 1
- draft-profile-version: candidate-1
- batch-kind: genericity
- client-model-condition: example-client-model
- sealed-before-presentation: yes
- raw-output-retention: transient-delete
'@
    $genericity = $genericityHeader.TrimEnd("`r", "`n") + "`n"
    $genericity += New-GenericityCase 1 'win' 'a' 'observed: controlling constraint appears first'
    $genericity += New-GenericityCase 2 'win' 'b' 'observed: mechanism follows the result'
    $genericity += New-GenericityCase 3 'win' 'a' 'observed: uncertainty remains explicit'
    $genericity += New-GenericityCase 4 'tie' 'both' 'none'
    $genericity += New-GenericityCase 5 'loss' 'b' 'none' 'tolerance'
    $genericityPath = Join-Path $testRoot 'genericity.md'
    Write-TestFile $genericityPath $genericity
    Invoke-RequiredSuccess 'Genericity threshold' ($baseArguments + @(
            '-Path', $genericityPath,
            '-RequireResolved'))

    $unknownRule = Join-Path $testRoot 'unknown-rule.md'
    Write-TestFile $unknownRule ($preference.Replace('rule-001', 'rule-999'))
    Invoke-RequiredFailure 'Unknown rule' ($baseArguments + @(
            '-Path', $unknownRule,
            '-RequirePresentationReady'))

    $unsealed = Join-Path $testRoot 'unsealed.md'
    Write-TestFile $unsealed ($preference.Replace('- state: sealed', '- state: presented'))
    Invoke-RequiredFailure 'Unsealed case' ($baseArguments + @(
            '-Path', $unsealed,
            '-RequirePresentationReady'))

        $mismatchedContract = Join-Path $testRoot 'mismatched-contract.md'
        Write-TestFile $mismatchedContract ($preference.Replace(
            '- option-b-contract-hash: ' + ('a' * 64),
            '- option-b-contract-hash: ' + ('b' * 64)))
        Invoke-RequiredFailure 'Mismatched contract' ($baseArguments + @(
            '-Path', $mismatchedContract,
            '-RequirePresentationReady'))

        $failedConditionGate = Join-Path $testRoot 'failed-condition-gate.md'
        Write-TestFile $failedConditionGate ($preference.Replace(
            '- option-b-hard-gates: passed',
            '- option-b-hard-gates: failed'))
        Invoke-RequiredFailure 'Failed condition gate' ($baseArguments + @(
            '-Path', $failedConditionGate,
            '-RequirePresentationReady'))

    $weakGenericity = Join-Path $testRoot 'weak-genericity.md'
    Write-TestFile $weakGenericity ($genericity.Replace(
            '- profile-outcome: win',
            '- profile-outcome: tie'))
    Invoke-RequiredFailure 'Weak genericity' ($baseArguments + @(
            '-Path', $weakGenericity,
            '-RequireResolved'))

    $pending = Join-Path $testRoot 'pending.md'
    Write-TestFile $pending ($genericity.Replace(
            '- resolution: accepted',
            '- resolution: pending'))
    Invoke-RequiredFailure 'Pending high impact' ($baseArguments + @(
            '-Path', $pending,
            '-RequireResolved'))

    $invalidNoChurn = Join-Path $testRoot 'invalid-no-churn.md'
    $noChurnText = $preference.
        Replace('- exact-identity: not-applicable', '- exact-identity: yes').
        Replace('- profile-outcome: uncollected', '- profile-outcome: no-churn').
        Replace('- result: uncollected', '- result: no-churn')
    Write-TestFile $invalidNoChurn $noChurnText
    Invoke-RequiredFailure 'No churn presented' ($baseArguments + @(
            '-Path', $invalidNoChurn,
            '-RequirePresentationReady'))

    Write-Host 'OK elicitation acceptance tests'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
