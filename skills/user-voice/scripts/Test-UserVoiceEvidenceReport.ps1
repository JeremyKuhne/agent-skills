#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Path,

    [Parameter(Mandatory)]
    [string] $ConsentId,

    [string] $ConsentSchema = '1',

    [Parameter(Mandatory)]
    [string] $AnalysisProvider,

    [Parameter(Mandatory)]
    [string] $AnalysisHost,

    [Parameter(Mandatory)]
    [string] $ConsentExpiry,

    [ValidateSet('1', '2')]
    [string] $RequiredReportSchema,

    [string[]] $ForbiddenLiteral
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$errors = [System.Collections.Generic.List[string]]::new()
function Add-ReportError([string] $category, [string] $message) {
    $errors.Add("[$category] $message")
}

function Get-ReportSection([string] $heading) {
    $match = [regex]::Match(
        $content,
        "(?ms)^## $([regex]::Escape($heading))\r?\n(?<body>.*?)(?=^## |\z)")
    if (-not $match.Success) { return $null }
    return $match.Groups['body'].Value
}

function Get-ListFields([string] $section) {
    $fields = @{}
    foreach ($match in [regex]::Matches(
            $section,
            '(?m)^- (?<key>[a-z_]+):\s*(?<value>[^\r\n]*)\r?$')) {
        $fields[$match.Groups['key'].Value] = $match.Groups['value'].Value.Trim()
    }
    return $fields
}

function Test-ExactFields(
    [hashtable] $fields,
    [string[]] $expected,
    [string] $sectionName) {
    foreach ($key in $expected) {
        if (-not $fields.ContainsKey($key) -or
            [string]::IsNullOrWhiteSpace([string]$fields[$key])) {
            Add-ReportError 'unexpected-field' "$sectionName field '$key' is missing or empty."
        }
    }
    foreach ($key in $fields.Keys) {
        if ($key -notin $expected) {
            Add-ReportError 'unexpected-field' "Unexpected $sectionName field '$key'."
        }
    }
}

$reportPath = $ExecutionContext.SessionState.Path.
    GetUnresolvedProviderPathFromPSPath($Path)
if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
    throw "The evidence report does not exist: '$Path'."
}

$content = [System.IO.File]::ReadAllText($reportPath)
$reportSchemaVersion = $null
$expectedHeadings = @(
    '# User voice evidence report',
    '## Contract',
    '## Coverage',
    '## Candidate rules',
    '## Counterevidence and conflicts',
    '## Mechanics',
    '## Unsupported contexts',
    '## Tone hazards excluded',
    '## Recommended follow-up',
    '## Deletion attestation')
$actualHeadings = @([regex]::Matches($content, '(?m)^#{1,2} .+$') |
    ForEach-Object { $_.Value.TrimEnd("`r") })
if (@(Compare-Object $expectedHeadings $actualHeadings -SyncWindow 0).Count -gt 0) {
    Add-ReportError 'unexpected-field' 'Top-level headings do not match the required report schema.'
}

$contractSection = Get-ReportSection 'Contract'
if ($null -eq $contractSection) {
    Add-ReportError 'unexpected-field' 'The Contract section is missing or malformed.'
}
else {
    $contract = Get-ListFields $contractSection
    $expectedContract = [ordered]@{
        schema_version = $null
        report_id = $null
        consent_id = $ConsentId
        consent_schema = $ConsentSchema
        analysis_provider = $AnalysisProvider
        analysis_host = $AnalysisHost
        consent_expiry = $ConsentExpiry
        provenance = 'agent-derived, user-unconfirmed'
        raw_source_retained = 'no'
        private_identifiers_included = 'no'
    }
    foreach ($key in $expectedContract.Keys) {
        if (-not $contract.ContainsKey($key)) {
            Add-ReportError 'unexpected-field' "Contract field '$key' is missing."
            continue
        }
        if ($key -eq 'schema_version') {
            if ($contract[$key] -notin @('1', '2')) {
                Add-ReportError 'unexpected-field' 'schema_version must be 1 or 2.'
            }
            else {
                $reportSchemaVersion = $contract[$key]
                if ($RequiredReportSchema -and
                    $reportSchemaVersion -cne $RequiredReportSchema) {
                    Add-ReportError 'unexpected-field' "schema_version must be $RequiredReportSchema for this handoff."
                }
            }
        }
        elseif ($key -eq 'report_id') {
            if ($contract[$key] -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_-]{7,63}$') {
                Add-ReportError 'unexpected-field' 'report_id must be an opaque 8-64 character identifier.'
            }
        }
        elseif ([string]$contract[$key] -cne [string]$expectedContract[$key]) {
            $category = if ($key -in @(
                    'consent_id',
                    'consent_schema',
                    'analysis_provider',
                    'analysis_host',
                    'consent_expiry')) {
                'consent-mismatch'
            }
            elseif ($key -eq 'raw_source_retained') { 'raw-retention' }
            elseif ($key -eq 'provenance') { 'false-approval' }
            else { 'private-identifier' }
            Add-ReportError $category "Contract field '$key' does not match the receiving consent ledger."
        }
    }
    foreach ($key in $contract.Keys) {
        if ($key -notin $expectedContract.Keys) {
            Add-ReportError 'unexpected-field' "Unexpected Contract field '$key'."
        }
    }
}

$coverageSection = Get-ReportSection 'Coverage'
if ($null -eq $coverageSection) {
    Add-ReportError 'unexpected-field' 'The Coverage section is missing or malformed.'
}
else {
    $coverage = Get-ListFields $coverageSection
    $expectedCoverage = if ($reportSchemaVersion -eq '2') {
        @(
            'source_classes',
            'channels',
            'audiences',
            'relationships',
            'intents_and_stakes',
            'lengths_and_formality',
            'topics',
            'era_bands',
            'authorship_mix')
    }
    else {
        @(
            'source_classes',
            'channels',
            'audiences',
            'era_bands',
            'authorship_mix')
    }
    Test-ExactFields $coverage $expectedCoverage 'Coverage'
}

$rulesSection = Get-ReportSection 'Candidate rules'
if ($null -eq $rulesSection) {
    Add-ReportError 'unexpected-field' 'The Candidate rules section is missing or malformed.'
}
else {
    $ruleMatches = @([regex]::Matches(
            $rulesSection,
            '(?ms)^### (?<id>rule-[0-9]{3})\r?\n(?<body>.*?)(?=^### |\z)'))
    if ($ruleMatches.Count -eq 0) {
        Add-ReportError 'unexpected-field' 'At least one candidate rule is required.'
    }
    $ruleIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($ruleMatch in $ruleMatches) {
        $ruleId = $ruleMatch.Groups['id'].Value
        if (-not $ruleIds.Add($ruleId)) {
            Add-ReportError 'unexpected-field' "Duplicate candidate rule '$ruleId'."
        }
        $rule = Get-ListFields $ruleMatch.Groups['body'].Value
        Test-ExactFields $rule @(
            'claim',
            'scope',
            'evidence_class',
            'confidence',
            'supporting_count_band',
            'counterexample_count_band',
            'check') "Candidate rule '$ruleId'"
        if ($rule.ContainsKey('evidence_class') -and
            $rule.evidence_class -notin @('observed', 'stated', 'validated', 'uncertain')) {
            Add-ReportError 'unexpected-field' "Candidate rule '$ruleId' has an unsupported evidence_class."
        }
        foreach ($countField in @('supporting_count_band', 'counterexample_count_band')) {
            if ($rule.ContainsKey($countField) -and
                $rule[$countField] -notin @('none', '1-2', '3-5', '6-10', '10+')) {
                Add-ReportError 'unexpected-field' "Candidate rule '$ruleId' has an unsupported $countField."
            }
        }
    }
}

$deletionSection = Get-ReportSection 'Deletion attestation'
if ($null -eq $deletionSection) {
    Add-ReportError 'unexpected-field' 'The Deletion attestation section is missing or malformed.'
}
else {
    $deletion = Get-ListFields $deletionSection
    Test-ExactFields $deletion @(
        'transient_extracts_deleted',
        'raw_exports_created') 'Deletion attestation'
    if ($deletion.ContainsKey('transient_extracts_deleted') -and
        $deletion.transient_extracts_deleted -cne 'yes') {
        Add-ReportError 'raw-retention' 'Transient extracts were not attested as deleted.'
    }
    if ($deletion.ContainsKey('raw_exports_created') -and
        $deletion.raw_exports_created -cne 'no') {
        Add-ReportError 'raw-retention' 'The report says a raw export was created.'
    }
}

$checks = @(
    @{ Category = 'unexpected-field'; Pattern = '(?s)```'; Message = 'Code fences are not allowed.' },
    @{ Category = 'external-reference'; Pattern = '(?i)https?://|mailto:|www\.'; Message = 'External references are not allowed.' },
    @{ Category = 'external-reference'; Pattern = '\[[^\]]*\]\([^)]*\)'; Message = 'Markdown links are not allowed.' },
    @{ Category = 'private-identifier'; Pattern = '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'; Message = 'Email addresses are not allowed.' },
    @{ Category = 'embedded-instruction'; Pattern = '(?i)ignore (?:all |any )?(?:previous|prior) instructions|(?:open|read|fetch|execute|run) (?:the )?(?:file|path|command|script)\b'; Message = 'Embedded instructions are not allowed.' },
    @{ Category = 'external-reference'; Pattern = '(?m)(?:[A-Za-z]:\\|/(?:Users|home|mnt|tmp|var|etc)/)'; Message = 'Absolute paths are not allowed.' },
    @{ Category = 'false-approval'; Pattern = '(?i)\buser[- ]approved\b|\buser (?:has )?approved\b|\bprovenance:\s*user'; Message = 'The report cannot assert user approval.' },
    @{ Category = 'copied-source'; Pattern = '(?m)^(?:[-*]\s+)?(?:>\s)|“[^”]{12,}”|"[^"]{20,}"'; Message = 'Quotations and copied source fragments are not allowed.' },
    @{ Category = 'private-identifier'; Pattern = '(?i)-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|\bgh[pousr]_[A-Za-z0-9_]{20,}\b|\bAKIA[0-9A-Z]{16}\b'; Message = 'Secret material is not allowed.' },
    @{ Category = 'unexpected-field'; Pattern = '\{\{[^}]+\}\}'; Message = 'Template placeholders must be resolved.' })
foreach ($check in $checks) {
    if ($content -match $check.Pattern) {
        Add-ReportError $check.Category $check.Message
    }
}

foreach ($literal in @($ForbiddenLiteral | Where-Object { $_ })) {
    if ($content.Contains($literal, [System.StringComparison]::OrdinalIgnoreCase)) {
        Add-ReportError 'private-identifier' 'A caller-supplied forbidden literal is present.'
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "OK evidence report: $reportPath"
