#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Path,

    [Parameter(Mandatory)]
    [string] $MatrixPath,

    [Parameter(Mandatory)]
    [string] $ProfilePath,

    [switch] $RequirePresentationReady,

    [switch] $RequireResolved,

    [string[]] $ForbiddenLiteral
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$errors = [System.Collections.Generic.List[string]]::new()
function Add-BatchError([string] $category, [string] $message) {
    $errors.Add("[$category] $message")
}

function Get-ListFields([string] $section) {
    $fields = @{}
    foreach ($match in [regex]::Matches(
            $section,
            '(?m)^- (?<key>[a-z][a-z0-9-]*):\s*(?<value>[^\r\n]*)\r?$')) {
        $key = $match.Groups['key'].Value
        if ($fields.ContainsKey($key)) {
            Add-BatchError 'unexpected-field' "Duplicate field '$key'."
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
            [string]::IsNullOrWhiteSpace([string]$fields[$key])) {
            Add-BatchError 'unexpected-field' "$sectionName field '$key' is missing or empty."
        }
    }
    foreach ($key in $fields.Keys) {
        if ($key -notin $expected) {
            Add-BatchError 'unexpected-field' "Unexpected $sectionName field '$key'."
        }
    }
}

function Get-RuleIds([string] $value) {
    if ($value -ceq 'none') { return @() }
    return @($value -split ',\s*')
}

$batchPath = $ExecutionContext.SessionState.Path.
    GetUnresolvedProviderPathFromPSPath($Path)
$matrixFile = $ExecutionContext.SessionState.Path.
    GetUnresolvedProviderPathFromPSPath($MatrixPath)
$profileFile = $ExecutionContext.SessionState.Path.
    GetUnresolvedProviderPathFromPSPath($ProfilePath)
foreach ($requiredPath in @($batchPath, $matrixFile, $profileFile)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required file does not exist: '$requiredPath'."
    }
}

$content = [System.IO.File]::ReadAllText($batchPath)
$matrix = [System.IO.File]::ReadAllText($matrixFile)
$profile = [System.IO.File]::ReadAllText($profileFile)

$headings = @([regex]::Matches($content, '(?m)^#{1,2} .+$'))
if ($headings.Count -eq 0 -or
    $headings[0].Value.TrimEnd("`r") -cne '# User voice elicitation batch') {
    Add-BatchError 'unexpected-heading' 'The batch title is missing or malformed.'
}
foreach ($heading in @($headings | Select-Object -Skip 1)) {
    if ($heading.Value.TrimEnd("`r") -cnotmatch '^## case-[0-9]{3}$') {
        Add-BatchError 'unexpected-heading' "Unexpected batch heading '$($heading.Value.TrimEnd("`r"))'."
    }
}

$headerMatch = [regex]::Match(
    $content,
    '(?ms)\A# User voice elicitation batch\r?\n(?<body>.*?)(?=^## case-[0-9]{3}\r?$|\z)')
if (-not $headerMatch.Success) {
    Add-BatchError 'unexpected-field' 'The batch header is missing or malformed.'
    $header = @{}
}
else {
    $header = Get-ListFields $headerMatch.Groups['body'].Value
    Test-ExactFields $header @(
        'batch-schema-version',
        'draft-profile-version',
        'batch-kind',
        'client-model-condition',
        'sealed-before-presentation',
        'raw-output-retention') 'Batch header'
}

if ($header.ContainsKey('batch-schema-version') -and
    $header['batch-schema-version'] -cne '1') {
    Add-BatchError 'unsupported-schema' 'batch-schema-version must be 1.'
}
if ($header.ContainsKey('batch-kind') -and
    $header['batch-kind'] -notin @('preference', 'edit', 'impact', 'genericity')) {
    Add-BatchError 'invalid-state' 'batch-kind is unsupported.'
}
if ($header.ContainsKey('sealed-before-presentation') -and
    $header['sealed-before-presentation'] -cne 'yes') {
    Add-BatchError 'unsealed-case' 'The batch must be sealed before presentation.'
}
if ($header.ContainsKey('raw-output-retention') -and
    $header['raw-output-retention'] -cne 'transient-delete') {
    Add-BatchError 'retention' 'raw-output-retention must be transient-delete.'
}

$matrixVersionMatch = [regex]::Match(
    $matrix,
    '(?m)^- profile-version:\s*(?<value>\S+)\s*$')
$profileVersionMatch = [regex]::Match(
    $profile,
    '(?m)^- profile-version:\s*(?<value>\S+)\s*$')
if (-not $matrixVersionMatch.Success -or -not $profileVersionMatch.Success) {
    Add-BatchError 'version-mismatch' 'The matrix and profile must record profile-version.'
}
elseif ($matrixVersionMatch.Groups['value'].Value -cne
    $profileVersionMatch.Groups['value'].Value) {
    Add-BatchError 'version-mismatch' 'The matrix and profile versions do not match.'
}
elseif ($header.ContainsKey('draft-profile-version') -and
    $header['draft-profile-version'] -cne
    $profileVersionMatch.Groups['value'].Value) {
    Add-BatchError 'version-mismatch' 'The batch does not target the current draft profile version.'
}

$profileRuleIds = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal)
foreach ($match in [regex]::Matches($profile, '(?m)^### (?<id>rule-[0-9]{3})\r?$')) {
    $null = $profileRuleIds.Add($match.Groups['id'].Value)
}
$contextRuleMap = @{}
foreach ($match in [regex]::Matches(
        $matrix,
        '(?ms)^## (?<id>context-[0-9]{3})\r?\n(?<body>.*?)(?=^## |\z)')) {
    $fields = Get-ListFields $match.Groups['body'].Value
    $contextRuleMap[$match.Groups['id'].Value] = if ($fields.ContainsKey('candidate-rule-ids')) {
        @(Get-RuleIds $fields['candidate-rule-ids'])
    }
    else { @() }
}

$expectedCaseFields = @(
    'case-kind',
    'nuance-context-id',
    'draft-rule-id',
    'draft-profile-version',
    'controlled-contrast',
    'candidate-placement',
    'order',
    'option-a-contract-hash',
    'option-b-contract-hash',
    'option-a-hard-gates',
    'option-b-hard-gates',
    'exact-identity',
    'manual-option',
    'hard-gates',
    'profile-outcome',
    'attributed-nuance',
    'impact',
    'state',
    'result',
    'resolution')
$caseMatches = @([regex]::Matches(
        $content,
        '(?ms)^## (?<id>case-[0-9]{3})\r?\n(?<body>.*?)(?=^## |\z)'))
$caseIds = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal)
$genericityWins = 0
$genericityLosses = 0

if ($header.ContainsKey('batch-kind')) {
    $minimum = if ($header['batch-kind'] -eq 'preference') { 3 } else { 1 }
    $maximum = if ($header['batch-kind'] -eq 'genericity') { 5 } else { 5 }
    if ($header['batch-kind'] -eq 'genericity' -and $caseMatches.Count -ne 5) {
        Add-BatchError 'invalid-count' 'A genericity batch requires exactly five cases.'
    }
    elseif ($caseMatches.Count -lt $minimum -or $caseMatches.Count -gt $maximum) {
        Add-BatchError 'invalid-count' "The batch requires $minimum-$maximum cases."
    }
}

foreach ($caseMatch in $caseMatches) {
    $caseId = $caseMatch.Groups['id'].Value
    if (-not $caseIds.Add($caseId)) {
        Add-BatchError 'duplicate-case' "Duplicate case '$caseId'."
    }
    $fields = Get-ListFields $caseMatch.Groups['body'].Value
    Test-ExactFields $fields $expectedCaseFields $caseId
    if (@($expectedCaseFields | Where-Object { -not $fields.ContainsKey($_) }).Count -gt 0) {
        continue
    }

    if ($header.ContainsKey('batch-kind') -and
        $fields['case-kind'] -cne $header['batch-kind']) {
        Add-BatchError 'invalid-state' "$caseId kind does not match the batch."
    }
    if (-not $contextRuleMap.ContainsKey($fields['nuance-context-id'])) {
        Add-BatchError 'invalid-mapping' "$caseId cites an unknown nuance context."
    }
    elseif ($fields['draft-rule-id'] -notin
        $contextRuleMap[$fields['nuance-context-id']]) {
        Add-BatchError 'invalid-mapping' "$caseId rule is not mapped by its nuance context."
    }
    if (-not $profileRuleIds.Contains($fields['draft-rule-id'])) {
        Add-BatchError 'invalid-mapping' "$caseId cites an unknown draft rule."
    }
    if ($profileVersionMatch.Success -and
        $fields['draft-profile-version'] -cne
        $profileVersionMatch.Groups['value'].Value) {
        Add-BatchError 'version-mismatch' "$caseId targets a different draft profile version."
    }
    if ($fields['candidate-placement'] -notin @('a', 'b', 'not-applicable') -or
        $fields.order -notin @('a-first', 'b-first', 'not-applicable') -or
        $fields['option-a-hard-gates'] -notin @('not-run', 'passed', 'failed', 'not-applicable') -or
        $fields['option-b-hard-gates'] -notin @('not-run', 'passed', 'failed', 'not-applicable') -or
        $fields['exact-identity'] -notin @('yes', 'no', 'not-applicable') -or
        $fields['manual-option'] -notin @('allowed', 'not-applicable') -or
        $fields['hard-gates'] -notin @('not-run', 'passed', 'failed') -or
        $fields['profile-outcome'] -notin @('uncollected', 'win', 'tie', 'loss', 'no-churn') -or
        $fields.impact -notin @('low', 'high') -or
        $fields.state -notin @('sealed', 'presented', 'answered', 'resolved', 'auto-no-churn') -or
        $fields.result -notin @('uncollected', 'a', 'b', 'both', 'neither', 'manual', 'better', 'same', 'worse', 'no-churn') -or
        $fields.resolution -notin @('pending', 'accepted', 'rejected', 'tolerance', 'evidence-gap', 'not-applicable')) {
        Add-BatchError 'invalid-state' "$caseId contains an unsupported state value."
    }

    if ($fields['case-kind'] -in @('preference', 'genericity')) {
        if ($fields['candidate-placement'] -notin @('a', 'b') -or
            $fields.order -notin @('a-first', 'b-first') -or
            $fields['manual-option'] -cne 'allowed') {
            Add-BatchError 'invalid-case' "$caseId preference conditions are incomplete."
        }
    }
    if ($fields['case-kind'] -in @('preference', 'impact', 'genericity')) {
        if ($fields['option-a-contract-hash'] -cnotmatch '^[0-9a-fA-F]{64}$' -or
            $fields['option-b-contract-hash'] -cnotmatch '^[0-9a-fA-F]{64}$' -or
            $fields['option-a-contract-hash'] -cne $fields['option-b-contract-hash']) {
            Add-BatchError 'condition-mismatch' "$caseId conditions do not declare one identical fact, authority, and output contract."
        }
        if ($fields['option-a-hard-gates'] -cne 'passed' -or
            $fields['option-b-hard-gates'] -cne 'passed' -or
            $fields['hard-gates'] -cne 'passed') {
            Add-BatchError 'hard-gate' "$caseId requires passed hard gates for both compared conditions."
        }
    }
    elseif ($fields['option-a-contract-hash'] -cne 'not-applicable' -or
        $fields['option-b-contract-hash'] -cne 'not-applicable' -or
        $fields['option-a-hard-gates'] -cne 'not-applicable' -or
        $fields['option-b-hard-gates'] -cne 'not-applicable') {
        Add-BatchError 'invalid-case' "$caseId single-output edit conditions must be not-applicable."
    }
    if ($fields['exact-identity'] -eq 'yes' -and
        ($fields.state -cne 'auto-no-churn' -or
            $fields.result -cne 'no-churn' -or
            $fields['profile-outcome'] -cne 'no-churn')) {
        Add-BatchError 'no-churn' "$caseId exact identity must be recorded automatically as no-churn."
    }

    if ($RequirePresentationReady) {
        if ($fields['hard-gates'] -cne 'passed') {
            Add-BatchError 'hard-gate' "$caseId is not presentation-ready until hard gates pass."
        }
        if ($fields['exact-identity'] -eq 'yes') {
            if ($fields.state -cne 'auto-no-churn') {
                Add-BatchError 'no-churn' "$caseId exact identity must not be presented."
            }
        }
        elseif ($fields.state -cne 'sealed' -or
            $fields.result -cne 'uncollected' -or
            $fields['profile-outcome'] -cne 'uncollected') {
            Add-BatchError 'unsealed-case' "$caseId must be sealed and uncollected before presentation."
        }
    }

    if ($RequireResolved) {
        if ($fields['hard-gates'] -cne 'passed') {
            Add-BatchError 'hard-gate' "$caseId cannot resolve with a failed or unrun hard gate."
        }
        if ($fields.state -notin @('resolved', 'auto-no-churn') -or
            $fields.result -eq 'uncollected') {
            Add-BatchError 'unresolved-result' "$caseId is unresolved."
        }
        if ($fields.impact -eq 'high' -and $fields.resolution -eq 'pending') {
            Add-BatchError 'unresolved-result' "$caseId has a pending high-impact result."
        }
    }

    if ($fields['case-kind'] -eq 'genericity' -and $RequireResolved) {
        if ($fields['profile-outcome'] -eq 'win') {
            $genericityWins++
            if ($fields['attributed-nuance'] -cnotmatch '^observed:\s+\S.+$') {
                Add-BatchError 'generic-profile' "$caseId win lacks an observed nuance attribution."
            }
        }
        elseif ($fields['profile-outcome'] -eq 'loss') {
            $genericityLosses++
        }
    }
}

if ($header.ContainsKey('batch-kind') -and
    $header['batch-kind'] -eq 'genericity' -and
    $RequireResolved -and
    ($genericityWins -lt 3 -or $genericityLosses -gt 1)) {
    Add-BatchError 'genericity-threshold' 'Genericity control requires at least three wins and no more than one loss.'
}

$privacyChecks = @(
    @{ Category = 'private-identifier'; Pattern = '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'; Message = 'Email addresses are not allowed.' },
    @{ Category = 'external-reference'; Pattern = '(?i)https?://|mailto:|www\.'; Message = 'External references are not allowed.' },
    @{ Category = 'absolute-path'; Pattern = '(?m)(?:[A-Za-z]:\\|/(?:Users|home|mnt|tmp|var|etc)/)'; Message = 'Absolute paths are not allowed.' },
    @{ Category = 'raw-output'; Pattern = '(?m)^```|^>\s|^Option [AB]:|^Before:|^After:'; Message = 'Raw options and edits do not belong in the retained manifest.' },
    @{ Category = 'unresolved-template'; Pattern = '\{\{[^}]+\}\}'; Message = 'Template placeholders must be resolved.' })
foreach ($check in $privacyChecks) {
    if ($content -match $check.Pattern) {
        Add-BatchError $check.Category $check.Message
    }
}
foreach ($literal in @($ForbiddenLiteral | Where-Object { $_ })) {
    if ($content.Contains($literal, [System.StringComparison]::OrdinalIgnoreCase)) {
        Add-BatchError 'private-identifier' 'A caller-supplied forbidden literal is present.'
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "OK user voice elicitation batch: $batchPath"
