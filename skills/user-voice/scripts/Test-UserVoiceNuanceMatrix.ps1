#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Path,

    [Parameter(Mandatory)]
    [string] $ProfilePath,

    [string[]] $ForbiddenLiteral
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$errors = [System.Collections.Generic.List[string]]::new()
function Add-MatrixError([string] $category, [string] $message) {
    $errors.Add("[$category] $message")
}

function Get-ListFields([string] $section) {
    $fields = @{}
    foreach ($match in [regex]::Matches(
            $section,
            '(?m)^- (?<key>[a-z][a-z0-9-]*):\s*(?<value>[^\r\n]*)\r?$')) {
        $key = $match.Groups['key'].Value
        if ($fields.ContainsKey($key)) {
            Add-MatrixError 'unexpected-field' "Duplicate field '$key'."
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
            Add-MatrixError 'unexpected-field' "$sectionName field '$key' is missing or empty."
        }
    }
    foreach ($key in $fields.Keys) {
        if ($key -notin $expected) {
            Add-MatrixError 'unexpected-field' "Unexpected $sectionName field '$key'."
        }
    }
}

function Get-IdList(
    [string] $value,
    [string] $pattern,
    [string] $fieldName,
    [string] $contextId) {
    if ($value -ceq 'none') { return @() }
    $ids = @($value -split ',\s*')
    $seen = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($id in $ids) {
        if ($id -cnotmatch $pattern) {
            Add-MatrixError 'invalid-mapping' "$contextId field '$fieldName' contains invalid ID '$id'."
        }
        elseif (-not $seen.Add($id)) {
            Add-MatrixError 'invalid-mapping' "$contextId field '$fieldName' repeats '$id'."
        }
    }
    return $ids
}

function Get-DiversityCounts([string] $value, [string] $contextId) {
    $counts = @{}
    if ($value -ceq 'none') { return $counts }
    $allowed = @(
        'channel',
        'artifact',
        'audience',
        'relationship',
        'intent',
        'stakes',
        'length',
        'formality',
        'topic',
        'era')
    foreach ($entry in @($value -split ',\s*')) {
        $match = [regex]::Match(
            $entry,
            '^(?<dimension>[a-z]+)=(?<count>[2-9]|[1-9][0-9]+)\+$')
        if (-not $match.Success -or
            $match.Groups['dimension'].Value -notin $allowed) {
            Add-MatrixError 'invalid-diversity' "$contextId source-diversity entry '$entry' must use an allowed dimension and a coarse lower bound such as audience=2+."
            continue
        }
        $dimension = $match.Groups['dimension'].Value
        if ($counts.ContainsKey($dimension)) {
            Add-MatrixError 'invalid-diversity' "$contextId repeats source-diversity dimension '$dimension'."
            continue
        }
        $counts[$dimension] = [int]$match.Groups['count'].Value
    }
    return $counts
}

$matrixPath = $ExecutionContext.SessionState.Path.
    GetUnresolvedProviderPathFromPSPath($Path)
$canonicalProfilePath = $ExecutionContext.SessionState.Path.
    GetUnresolvedProviderPathFromPSPath($ProfilePath)
foreach ($requiredPath in @($matrixPath, $canonicalProfilePath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required file does not exist: '$requiredPath'."
    }
}

$content = [System.IO.File]::ReadAllText($matrixPath)
$profile = [System.IO.File]::ReadAllText($canonicalProfilePath)

$headingMatches = @([regex]::Matches($content, '(?m)^#{1,2} .+$'))
if ($headingMatches.Count -eq 0 -or
    $headingMatches[0].Value.TrimEnd("`r") -cne '# User voice nuance matrix') {
    Add-MatrixError 'unexpected-heading' 'The matrix title is missing or malformed.'
}
foreach ($heading in @($headingMatches | Select-Object -Skip 1)) {
    if ($heading.Value.TrimEnd("`r") -cnotmatch '^## context-[0-9]{3}$') {
        Add-MatrixError 'unexpected-heading' "Unexpected matrix heading '$($heading.Value.TrimEnd("`r"))'."
    }
}

$headerMatch = [regex]::Match(
    $content,
    '(?ms)\A# User voice nuance matrix\r?\n(?<body>.*?)(?=^## context-[0-9]{3}\r?$|\z)')
if (-not $headerMatch.Success) {
    Add-MatrixError 'unexpected-field' 'The matrix header is missing or malformed.'
    $header = @{}
}
else {
    $header = Get-ListFields $headerMatch.Groups['body'].Value
    Test-ExactFields $header @(
        'matrix-schema-version',
        'profile-schema-version',
        'profile-version',
        'retention-policy') 'Matrix header'
}

if ($header.ContainsKey('matrix-schema-version') -and
    $header['matrix-schema-version'] -cne '1') {
    Add-MatrixError 'unsupported-schema' 'matrix-schema-version must be 1.'
}
if ($header.ContainsKey('profile-schema-version') -and
    $header['profile-schema-version'] -cne '2') {
    Add-MatrixError 'unsupported-schema' 'A nuance matrix requires profile-schema-version 2.'
}
if ($header.ContainsKey('profile-version') -and
    $header['profile-version'] -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') {
    Add-MatrixError 'unexpected-field' 'profile-version must be an opaque 1-64 character value.'
}
if ($header.ContainsKey('retention-policy') -and
    $header['retention-policy'] -notin @('minimum', 'auditable')) {
    Add-MatrixError 'unexpected-field' 'retention-policy must be minimum or auditable.'
}

$profileSchemaMatch = [regex]::Match(
    $profile,
    '(?m)^- profile-schema-version:\s*(?<value>[0-9]+)\s*$')
$profileVersionMatch = [regex]::Match(
    $profile,
    '(?m)^- profile-version:\s*(?<value>\S+)\s*$')
if (-not $profileSchemaMatch.Success -or
    $profileSchemaMatch.Groups['value'].Value -cne '2') {
    Add-MatrixError 'profile-mismatch' 'The canonical profile must use profile-schema-version 2.'
}
if (-not $profileVersionMatch.Success) {
    Add-MatrixError 'profile-mismatch' 'The canonical profile is missing profile-version.'
}
elseif ($header.ContainsKey('profile-version') -and
    $profileVersionMatch.Groups['value'].Value -cne $header['profile-version']) {
    Add-MatrixError 'profile-mismatch' 'The matrix and canonical profile versions do not match.'
}

$profileRuleIds = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal)
$userApprovedProfileRuleIds = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal)
$activeProfileRuleIds = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal)
$profileRuleStates = @{}
$profileRuleMatches = @([regex]::Matches(
        $profile,
        '(?ms)^### (?<id>rule-[0-9]{3})\r?\n(?<body>.*?)(?=^### |^## |\z)'))
foreach ($ruleMatch in $profileRuleMatches) {
    $ruleId = $ruleMatch.Groups['id'].Value
    if (-not $profileRuleIds.Add($ruleId)) {
        Add-MatrixError 'invalid-mapping' "The canonical profile repeats '$ruleId'."
        continue
    }
    $ruleFields = Get-ListFields $ruleMatch.Groups['body'].Value
    if ($ruleFields.ContainsKey('user-approved') -and
        $ruleFields['user-approved'] -ceq 'yes') {
        $null = $userApprovedProfileRuleIds.Add($ruleId)
    }
    if (-not $ruleFields.ContainsKey('runtime-status') -or
        $ruleFields['runtime-status'] -notin @('inactive', 'active')) {
        Add-MatrixError 'invalid-mapping' "Schema version 2 profile rule '$ruleId' requires runtime-status inactive or active."
        $profileRuleStates[$ruleId] = 'invalid'
    }
    else {
        $profileRuleStates[$ruleId] = $ruleFields['runtime-status']
        if ($ruleFields['runtime-status'] -eq 'active') {
            if (-not $userApprovedProfileRuleIds.Contains($ruleId)) {
                Add-MatrixError 'missing-approval' "Active profile rule '$ruleId' is not user approved."
            }
            $null = $activeProfileRuleIds.Add($ruleId)
        }
    }
}

$expectedContextFields = @(
    'runtime-status',
    'channel-and-artifact',
    'audience-and-relationship',
    'intent-and-stakes',
    'length-and-formality',
    'direct-evidence-count-band',
    'source-diversity',
    'evidence-floor',
    'rhetorical-and-epistemic',
    'register-and-relationship',
    'mechanics',
    'interpersonal-stance',
    'lexical-behavior',
    'artifact-patterns',
    'conflicts-and-counterevidence',
    'unresolved-gaps',
    'candidate-rule-ids',
    'validation-case-ids',
    'genericity-control',
    'confidence',
    'user-status')
$passFields = @(
    'rhetorical-and-epistemic',
    'register-and-relationship',
    'mechanics',
    'interpersonal-stance',
    'lexical-behavior',
    'artifact-patterns',
    'conflicts-and-counterevidence')
$floorRanks = @{
    insufficient = 0
    draft = 1
    provisional = 2
    moderate = 3
    strong = 4
}
$confidenceRanks = @{
    low = 0
    provisional = 2
    moderate = 3
    strong = 4
}
$supportedRuleIds = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal)
$contextIds = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal)
$contextMatches = @([regex]::Matches(
        $content,
        '(?ms)^## (?<id>context-[0-9]{3})\r?\n(?<body>.*?)(?=^## |\z)'))
if ($contextMatches.Count -eq 0) {
    Add-MatrixError 'missing-context' 'At least one context block is required.'
}

foreach ($contextMatch in $contextMatches) {
    $contextId = $contextMatch.Groups['id'].Value
    if (-not $contextIds.Add($contextId)) {
        Add-MatrixError 'duplicate-context' "Duplicate context '$contextId'."
    }
    $fields = Get-ListFields $contextMatch.Groups['body'].Value
    Test-ExactFields $fields $expectedContextFields $contextId
    if (@($expectedContextFields | Where-Object { -not $fields.ContainsKey($_) }).Count -gt 0) {
        continue
    }

    foreach ($passField in $passFields) {
        if ($fields[$passField] -cne 'not-observed' -and
            $fields[$passField] -cnotmatch '^observed:\s+\S.+$') {
            Add-MatrixError 'invalid-pass' "$contextId field '$passField' must be not-observed or observed: followed by a de-identified decision."
        }
    }

    if ($fields['runtime-status'] -notin @('unsupported', 'provisional', 'supported')) {
        Add-MatrixError 'invalid-state' "$contextId has an unsupported runtime-status."
    }
    if ($fields['direct-evidence-count-band'] -notin @('none', '1-2', '3-5', '6-10', '10+')) {
        Add-MatrixError 'invalid-evidence' "$contextId has an unsupported direct-evidence-count-band."
    }
    if (-not $floorRanks.ContainsKey($fields['evidence-floor'])) {
        Add-MatrixError 'invalid-evidence' "$contextId has an unsupported evidence-floor."
    }
    if (-not $confidenceRanks.ContainsKey($fields.confidence)) {
        Add-MatrixError 'invalid-state' "$contextId has an unsupported confidence."
    }
    if ($fields['genericity-control'] -notin @('not-run', 'passed', 'failed')) {
        Add-MatrixError 'invalid-validation' "$contextId has an unsupported genericity-control state."
    }
    if ($fields['user-status'] -notin @('unreviewed', 'approved', 'rejected', 'skipped')) {
        Add-MatrixError 'invalid-state' "$contextId has an unsupported user-status."
    }

    $ruleIds = @(Get-IdList $fields['candidate-rule-ids'] '^rule-[0-9]{3}$' 'candidate-rule-ids' $contextId)
    $caseIds = @(Get-IdList $fields['validation-case-ids'] '^case-[0-9]{3}$' 'validation-case-ids' $contextId)
    $diversity = Get-DiversityCounts $fields['source-diversity'] $contextId
    foreach ($ruleId in $ruleIds) {
        if (-not $profileRuleIds.Contains($ruleId)) {
            Add-MatrixError 'invalid-mapping' "$contextId maps unknown profile rule '$ruleId'."
        }
    }

    if ($floorRanks.ContainsKey($fields['evidence-floor']) -and
        $confidenceRanks.ContainsKey($fields.confidence) -and
        $confidenceRanks[$fields.confidence] -gt $floorRanks[$fields['evidence-floor']]) {
        Add-MatrixError 'confidence-overreach' "$contextId confidence exceeds its evidence floor."
    }

    switch ($fields['evidence-floor']) {
        'draft' {
            if ($fields['direct-evidence-count-band'] -notin @('3-5', '6-10', '10+')) {
                Add-MatrixError 'invalid-evidence' "$contextId draft floor requires a count band containing at least five samples."
            }
        }
        'provisional' {
            if ($fields['direct-evidence-count-band'] -notin @('3-5', '6-10', '10+')) {
                Add-MatrixError 'invalid-evidence' "$contextId provisional floor requires at least three samples."
            }
        }
        'moderate' {
            if ($fields['direct-evidence-count-band'] -notin @('3-5', '6-10', '10+')) {
                Add-MatrixError 'invalid-evidence' "$contextId moderate floor requires a count band containing at least five samples."
            }
        }
        'strong' {
            if ($fields['direct-evidence-count-band'] -cne '10+') {
                Add-MatrixError 'invalid-evidence' "$contextId strong floor requires ten or more samples."
            }
        }
    }

    if ($fields['runtime-status'] -eq 'unsupported') {
        if ($fields.confidence -notin @('low', 'provisional')) {
            Add-MatrixError 'confidence-overreach' "$contextId unsupported runtime status cannot claim moderate or strong confidence."
        }
        continue
    }

    if ($diversity.Count -eq 0 -or
        @($diversity.Values | Where-Object { $_ -ge 2 }).Count -eq 0) {
        Add-MatrixError 'insufficient-diversity' "$contextId requires at least one variation dimension with two or more values."
    }
    if ($fields['runtime-status'] -eq 'provisional') {
        if ($fields['evidence-floor'] -notin @('provisional', 'moderate', 'strong')) {
            Add-MatrixError 'invalid-evidence' "$contextId provisional runtime status has not reached the provisional evidence floor."
        }
        if ($fields.confidence -notin @('low', 'provisional')) {
            Add-MatrixError 'confidence-overreach' "$contextId provisional runtime status cannot claim moderate or strong confidence."
        }
        continue
    }

    if ($fields['evidence-floor'] -notin @('moderate', 'strong')) {
        Add-MatrixError 'invalid-evidence' "$contextId supported runtime status requires the moderate or strong evidence floor."
    }
    if ($fields.confidence -notin @('moderate', 'strong')) {
        Add-MatrixError 'invalid-state' "$contextId supported runtime status requires moderate or strong confidence."
    }
    if ($fields['user-status'] -cne 'approved') {
        Add-MatrixError 'missing-approval' "$contextId supported runtime status requires user approval."
    }
    if ($fields['genericity-control'] -cne 'passed') {
        Add-MatrixError 'invalid-validation' "$contextId supported runtime status requires a passed genericity control."
    }
    if ($fields['unresolved-gaps'] -cne 'none') {
        Add-MatrixError 'unresolved-result' "$contextId cannot be supported while unresolved gaps remain."
    }
    if ($ruleIds.Count -eq 0) {
        Add-MatrixError 'invalid-mapping' "$contextId supported runtime status requires at least one profile rule."
    }
    if ($caseIds.Count -lt 5) {
        Add-MatrixError 'invalid-validation' "$contextId supported runtime status requires at least five independent held-out case IDs."
    }
    foreach ($requiredObserved in @($passFields | Select-Object -First 6)) {
        if ($fields[$requiredObserved] -cnotmatch '^observed:\s+\S.+$') {
            Add-MatrixError 'generic-profile' "$contextId supported runtime status requires an observed '$requiredObserved' decision."
        }
    }
    if (@($diversity.Values | Where-Object { $_ -ge 3 }).Count -eq 0 -and
        $diversity.Count -lt 2) {
        Add-MatrixError 'insufficient-diversity' "$contextId moderate support requires three values in one dimension or two varied dimensions."
    }
    if ($fields.confidence -eq 'strong' -and
        -not (($diversity.ContainsKey('artifact') -and $diversity.artifact -ge 2) -or
            ($diversity.ContainsKey('audience') -and $diversity.audience -ge 2))) {
        Add-MatrixError 'insufficient-diversity' "$contextId strong confidence requires at least two artifacts or audiences."
    }
    foreach ($ruleId in $ruleIds) {
        if (-not $userApprovedProfileRuleIds.Contains($ruleId)) {
            Add-MatrixError 'missing-approval' "$contextId supported rule '$ruleId' is not user approved in the canonical profile."
        }
        if (-not $profileRuleStates.ContainsKey($ruleId) -or
            $profileRuleStates[$ruleId] -ne 'active') {
            Add-MatrixError 'inactive-rule' "$contextId supported rule '$ruleId' is not active in the canonical profile."
        }
        $null = $supportedRuleIds.Add($ruleId)
    }
}

foreach ($ruleId in $activeProfileRuleIds) {
    if (-not $supportedRuleIds.Contains($ruleId)) {
        Add-MatrixError 'invalid-mapping' "Active profile rule '$ruleId' is not mapped by a supported context."
    }
}

$privacyChecks = @(
    @{ Category = 'private-identifier'; Pattern = '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'; Message = 'Email addresses are not allowed.' },
    @{ Category = 'external-reference'; Pattern = '(?i)https?://|mailto:|www\.'; Message = 'Source URLs are not allowed.' },
    @{ Category = 'absolute-path'; Pattern = '(?m)(?:[A-Za-z]:\\|/(?:Users|home|mnt|tmp|var|etc)/)'; Message = 'Absolute paths are not allowed.' },
    @{ Category = 'secret'; Pattern = '(?i)-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|\bgh[pousr]_[A-Za-z0-9_]{20,}\b|\bAKIA[0-9A-Z]{16}\b'; Message = 'Secret material is not allowed.' },
    @{ Category = 'unresolved-template'; Pattern = '\{\{[^}]+\}\}'; Message = 'Template placeholders must be resolved.' },
    @{ Category = 'source-mapping'; Pattern = '(?i)\b(?:source|evidence)-[0-9]{3}\b'; Message = 'Source-to-context IDs belong in the separate auditable ledger.' })
foreach ($check in $privacyChecks) {
    if ($content -match $check.Pattern) {
        Add-MatrixError $check.Category $check.Message
    }
}
foreach ($literal in @($ForbiddenLiteral | Where-Object { $_ })) {
    if ($content.Contains($literal, [System.StringComparison]::OrdinalIgnoreCase)) {
        Add-MatrixError 'private-identifier' 'A caller-supplied forbidden literal is present.'
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "OK user voice nuance matrix: $matrixPath"
