#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Path,

    [ValidateSet('unapproved', 'approved-by-read-back')]
    [string] $RequiredFindingsStatus = 'unapproved',

    [string[]] $ForbiddenLiteral
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$errors = [System.Collections.Generic.List[string]]::new()
function Add-AnalysisError([string] $category, [string] $message) {
    $errors.Add("[$category] $message")
}

function Get-Section([string] $heading, [int] $level = 2) {
    $prefix = '#' * $level
    $next = if ($level -eq 2) { '^## ' } else { '^### ' }
    $match = [regex]::Match(
        $content,
        "(?ms)^$prefix $([regex]::Escape($heading))\r?\n(?<body>.*?)(?=$next|^## |\z)")
    if (-not $match.Success) { return $null }
    return $match.Groups['body'].Value
}

function Get-ListFields([string] $section) {
    $fields = @{}
    foreach ($match in [regex]::Matches(
            $section,
            '(?m)^- (?<key>[a-z][a-z0-9-]*):\s*(?<value>[^\r\n]*)\r?$')) {
        $key = $match.Groups['key'].Value
        if ($fields.ContainsKey($key)) {
            Add-AnalysisError 'unexpected-field' "Duplicate field '$key'."
        }
        else {
            $fields[$key] = $match.Groups['value'].Value.Trim()
        }
    }
    return $fields
}

function Test-ExactFields(
    [hashtable] $fields,
    [string[]] $expected,
    [string] $sectionName) {
    foreach ($key in $expected) {
        if (-not $fields.ContainsKey($key) -or
            [string]::IsNullOrWhiteSpace([string] $fields[$key])) {
            Add-AnalysisError 'unexpected-field' "$sectionName field '$key' is missing or empty."
        }
    }
    foreach ($key in $fields.Keys) {
        if ($key -notin $expected) {
            Add-AnalysisError 'unexpected-field' "Unexpected $sectionName field '$key'."
        }
    }
}

$reportPath = $ExecutionContext.SessionState.Path.
    GetUnresolvedProviderPathFromPSPath($Path)
if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
    throw "The targeted analysis report does not exist: '$Path'."
}
$content = [System.IO.File]::ReadAllText($reportPath)

$expectedHeadings = @(
    '# Targeted source analysis',
    '## Contract',
    '## Coverage',
    '## Seven-pass findings',
    '### Rhetorical and epistemic',
    '### Register and relationship',
    '### Mechanics',
    '### Interpersonal stance',
    '### Lexical behavior',
    '### Artifact patterns',
    '### Conflicts and counterevidence',
    '## Hypothesis dispositions',
    '### hypothesis-001',
    '### hypothesis-002',
    '### hypothesis-003',
    '## Existing-rule implications',
    '## Gaps',
    '## Deletion attestation')
$actualHeadings = @([regex]::Matches($content, '(?m)^#{1,3} .+$') |
    ForEach-Object { $_.Value.TrimEnd("`r") })
if (@(Compare-Object $expectedHeadings $actualHeadings -SyncWindow 0).Count -gt 0) {
    Add-AnalysisError 'unexpected-heading' 'Headings do not match the targeted analysis schema.'
}

$contractSection = Get-Section 'Contract'
if ($null -eq $contractSection) {
    Add-AnalysisError 'unexpected-field' 'The Contract section is missing.'
}
else {
    $contract = Get-ListFields $contractSection
    Test-ExactFields $contract @(
        'source-count-band',
        'retrieval-completeness',
        'source-independence',
        'authorship-confirmation',
        'raw-source-retained',
        'identifiers-included',
        'provenance',
        'findings-status') 'Contract'
    foreach ($requirement in @(
            @{ Key = 'source-count-band'; Value = '6-10' },
            @{ Key = 'retrieval-completeness'; Value = 'complete' },
            @{ Key = 'raw-source-retained'; Value = 'no' },
            @{ Key = 'identifiers-included'; Value = 'no' },
            @{ Key = 'provenance'; Value = 'agent-derived, user-confirmed sources' },
            @{ Key = 'findings-status'; Value = $RequiredFindingsStatus })) {
        if ($contract.ContainsKey($requirement.Key) -and
            $contract[$requirement.Key] -cne $requirement.Value) {
            Add-AnalysisError 'contract-mismatch' "Contract field '$($requirement.Key)' is invalid."
        }
    }
}

$coverageSection = Get-Section 'Coverage'
if ($null -eq $coverageSection) {
    Add-AnalysisError 'unexpected-field' 'The Coverage section is missing.'
}
else {
    Test-ExactFields (Get-ListFields $coverageSection) @(
        'channel-and-artifact',
        'audience-and-relationship',
        'intent-and-stakes',
        'length-and-formality',
        'topic-variation',
        'era-variation',
        'confounds-excluded') 'Coverage'
}

$countBands = @('none', '1-2', '3-5', '6-10', '10+')
foreach ($pass in @(
        'Rhetorical and epistemic',
        'Register and relationship',
        'Mechanics',
        'Interpersonal stance',
        'Lexical behavior',
        'Artifact patterns',
        'Conflicts and counterevidence')) {
    $section = Get-Section $pass 3
    if ($null -eq $section) {
        Add-AnalysisError 'missing-pass' "Analysis pass '$pass' is missing."
        continue
    }
    $fields = Get-ListFields $section
    Test-ExactFields $fields @(
        'result',
        'supporting-count-band',
        'counterexample-count-band') "Analysis pass '$pass'"
    if ($fields.ContainsKey('result') -and
        $fields.result -cne 'not-observed' -and
        $fields.result -cnotmatch '^observed:\s+\S.+$') {
        Add-AnalysisError 'invalid-pass' "Analysis pass '$pass' has an invalid result."
    }
    foreach ($countField in @('supporting-count-band', 'counterexample-count-band')) {
        if ($fields.ContainsKey($countField) -and
            $fields[$countField] -notin $countBands) {
            Add-AnalysisError 'invalid-count-band' "Analysis pass '$pass' has an invalid $countField."
        }
    }
}

foreach ($hypothesisId in 1..3) {
    $heading = 'hypothesis-{0:D3}' -f $hypothesisId
    $section = Get-Section $heading 3
    if ($null -eq $section) {
        Add-AnalysisError 'missing-hypothesis' "$heading is missing."
        continue
    }
    $fields = Get-ListFields $section
    Test-ExactFields $fields @(
        'disposition',
        'scope',
        'supporting-count-band',
        'counterexample-count-band',
        'abstract-observation',
        'confidence-ceiling',
        'next-check') $heading
    if ($fields.ContainsKey('disposition') -and
        $fields.disposition -notin @('supported', 'contradicted', 'insufficient')) {
        Add-AnalysisError 'invalid-hypothesis' "$heading has an invalid disposition."
    }
    if ($fields.ContainsKey('confidence-ceiling') -and
        $fields['confidence-ceiling'] -notin @('low', 'provisional', 'moderate', 'strong')) {
        Add-AnalysisError 'invalid-hypothesis' "$heading has an invalid confidence ceiling."
    }
    foreach ($countField in @('supporting-count-band', 'counterexample-count-band')) {
        if ($fields.ContainsKey($countField) -and
            $fields[$countField] -notin $countBands) {
            Add-AnalysisError 'invalid-count-band' "$heading has an invalid $countField."
        }
    }
    if ($fields.ContainsKey('supporting-count-band') -and
        $fields.ContainsKey('confidence-ceiling') -and
        $fields['supporting-count-band'] -in @('none', '1-2') -and
        $fields['confidence-ceiling'] -notin @('low', 'provisional')) {
        Add-AnalysisError 'confidence-overreach' "$heading confidence exceeds its source support."
    }
    if ($fields.ContainsKey('supporting-count-band') -and
        $fields.ContainsKey('confidence-ceiling') -and
        $fields['supporting-count-band'] -eq '3-5' -and
        $fields['confidence-ceiling'] -eq 'strong') {
        Add-AnalysisError 'confidence-overreach' "$heading cannot claim strong confidence from a 3-5 support band."
    }
}

$ruleSection = Get-Section 'Existing-rule implications'
if ($null -eq $ruleSection) {
    Add-AnalysisError 'missing-rule-implication' 'The Existing-rule implications section is missing.'
}
else {
    $expectedRules = @('rule-002', 'rule-004', 'rule-005', 'rule-008', 'rule-010', 'rule-013')
    $ruleMatches = @([regex]::Matches(
            $ruleSection,
            '(?m)^- (?<id>rule-[0-9]{3}):\s*(?<status>retain|narrow|revise-candidate|insufficient)\s+-\s+(?<reason>\S.+)$'))
    $actualRules = @($ruleMatches | ForEach-Object { $_.Groups['id'].Value })
    if (@(Compare-Object $expectedRules $actualRules -SyncWindow 0).Count -gt 0) {
        Add-AnalysisError 'missing-rule-implication' 'Existing-rule implications must contain each required rule exactly once and in order.'
    }
}

$gapsSection = Get-Section 'Gaps'
if ($null -eq $gapsSection -or
    [string]::IsNullOrWhiteSpace($gapsSection)) {
    Add-AnalysisError 'missing-gap' 'The Gaps section is empty or missing.'
}

$deletionSection = Get-Section 'Deletion attestation'
if ($null -eq $deletionSection) {
    Add-AnalysisError 'unexpected-field' 'The Deletion attestation section is missing.'
}
else {
    $deletion = Get-ListFields $deletionSection
    Test-ExactFields $deletion @(
        'raw-extracts-written',
        'raw-source-returned',
        'transient-analysis-complete') 'Deletion attestation'
    foreach ($requirement in @(
            @{ Key = 'raw-extracts-written'; Value = 'no' },
            @{ Key = 'raw-source-returned'; Value = 'no' },
            @{ Key = 'transient-analysis-complete'; Value = 'yes' })) {
        if ($deletion.ContainsKey($requirement.Key) -and
            $deletion[$requirement.Key] -cne $requirement.Value) {
            Add-AnalysisError 'raw-retention' "Deletion field '$($requirement.Key)' is invalid."
        }
    }
}

$privacyChecks = @(
    @{ Category = 'unexpected-prose'; Pattern = '(?s)\A(?!# Targeted source analysis\r?\n)'; Message = 'The report contains prose before the required title.' },
    @{ Category = 'copied-source'; Pattern = '["''“”‘’]'; Message = 'Quotation marks and apostrophes are not allowed.' },
    @{ Category = 'copied-source'; Pattern = '(?m)^\s*>|```|`'; Message = 'Quoted or fenced source is not allowed.' },
    @{ Category = 'external-reference'; Pattern = '(?i)https?://|mailto:|www\.|\[[^\]]*\]\([^)]*\)'; Message = 'External references are not allowed.' },
    @{ Category = 'private-identifier'; Pattern = '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'; Message = 'Email addresses are not allowed.' },
    @{ Category = 'source-identifier'; Pattern = '(?i)#\d+|\b(?:19|20)\d{2}\b'; Message = 'Source numbers and exact years are not allowed.' },
    @{ Category = 'source-count'; Pattern = '(?i)\b(?:one|two|three|four|five|six|seven|eight|nine|ten)\s+(?:independent\s+)?(?:sources|threads|documents|items)\b'; Message = 'Exact source counts are not allowed.' },
    @{ Category = 'embedded-instruction'; Pattern = '(?i)ignore (?:all |any )?(?:previous|prior) instructions|(?:open|read|fetch|execute|run) (?:the )?(?:file|path|command|script)\b'; Message = 'Embedded instructions are not allowed.' },
    @{ Category = 'absolute-path'; Pattern = '(?m)(?:[A-Za-z]:\\|/(?:Users|home|mnt|tmp|var|etc)/)'; Message = 'Absolute paths are not allowed.' },
    @{ Category = 'false-approval'; Pattern = '(?i)\bfindings?[- ]approved\b|\buser[- ]approved\b'; Message = 'The report cannot assert finding approval.' },
    @{ Category = 'unresolved-template'; Pattern = '\{\{[^}]+\}\}'; Message = 'Template placeholders must be resolved.' })
foreach ($check in $privacyChecks) {
    if ($content -match $check.Pattern) {
        Add-AnalysisError $check.Category $check.Message
    }
}
foreach ($literal in @($ForbiddenLiteral | Where-Object { $_ })) {
    if ($content.Contains($literal, [System.StringComparison]::OrdinalIgnoreCase)) {
        Add-AnalysisError 'source-identifier' 'A caller-supplied forbidden literal is present.'
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "OK targeted source analysis: $reportPath"