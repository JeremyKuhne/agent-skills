#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Path,

    [switch] $RequirePresentationReady,

    [switch] $RequireResolved,

    [string[]] $ForbiddenLiteral
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$errors = [System.Collections.Generic.List[string]]::new()
function Add-ComparisonError([string] $category, [string] $message) {
    $errors.Add("[$category] $message")
}

function Get-ListFields([string] $section) {
    $fields = @{}
    foreach ($match in [regex]::Matches(
            $section,
            '(?m)^- (?<key>[a-z][a-z0-9-]*):\s*(?<value>[^\r\n]*)\r?$')) {
        $key = $match.Groups['key'].Value
        if ($fields.ContainsKey($key)) {
            Add-ComparisonError 'unexpected-field' "Duplicate field '$key'."
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
            Add-ComparisonError 'unexpected-field' "$sectionName field '$key' is missing or empty."
        }
    }
    foreach ($key in $fields.Keys) {
        if ($key -notin $expected) {
            Add-ComparisonError 'unexpected-field' "Unexpected $sectionName field '$key'."
        }
    }
}

function Get-ConditionForOption([hashtable] $fields, [string] $option) {
    foreach ($condition in @('draft', 'old-profile', 'general-writing')) {
        if ($fields["$condition-option"] -eq $option) { return $condition }
    }
    return $null
}

function Get-UsabilityRank([string] $value) {
    switch ($value) {
        'ready' { return 0 }
        'minor-edit' { return 1 }
        'major-edit' { return 2 }
        'unusable' { return 3 }
        default { return 99 }
    }
}

$comparisonPath = $ExecutionContext.SessionState.Path.
    GetUnresolvedProviderPathFromPSPath($Path)
if (-not (Test-Path -LiteralPath $comparisonPath -PathType Leaf)) {
    throw "The comparison file does not exist: '$Path'."
}
$content = [System.IO.File]::ReadAllText($comparisonPath)

$headings = @([regex]::Matches($content, '(?m)^#{1,2} .+$'))
if ($headings.Count -eq 0 -or
    $headings[0].Value.TrimEnd("`r") -cne '# User voice three-way comparison') {
    Add-ComparisonError 'unexpected-heading' 'The comparison title is missing or malformed.'
}
foreach ($heading in @($headings | Select-Object -Skip 1)) {
    if ($heading.Value.TrimEnd("`r") -cnotmatch '^## case-[0-9]{3}$') {
        Add-ComparisonError 'unexpected-heading' "Unexpected comparison heading '$($heading.Value.TrimEnd("`r"))'."
    }
}

$headerMatch = [regex]::Match(
    $content,
    '(?ms)\A# User voice three-way comparison\r?\n(?<body>.*?)(?=^## case-[0-9]{3}\r?$|\z)')
if (-not $headerMatch.Success) {
    Add-ComparisonError 'unexpected-field' 'The comparison header is missing or malformed.'
    $header = @{}
}
else {
    $header = Get-ListFields $headerMatch.Groups['body'].Value
    Test-ExactFields $header @(
        'comparison-schema-version',
        'draft-profile-version',
        'old-profile-version',
        'client-model-condition',
        'sealed-before-presentation',
        'raw-output-retention') 'Comparison header'
}
if ($header.ContainsKey('comparison-schema-version') -and
    $header['comparison-schema-version'] -cne '1') {
    Add-ComparisonError 'unsupported-schema' 'comparison-schema-version must be 1.'
}
if ($header.ContainsKey('sealed-before-presentation') -and
    $header['sealed-before-presentation'] -cne 'yes') {
    Add-ComparisonError 'unsealed-case' 'The comparison must be sealed before presentation.'
}
if ($header.ContainsKey('raw-output-retention') -and
    $header['raw-output-retention'] -cne 'transient-delete') {
    Add-ComparisonError 'retention' 'raw-output-retention must be transient-delete.'
}

$expectedBriefKinds = @(
    'short-technical-correction',
    'extended-design-disagreement',
    'proposal',
    'defect-response',
    'decision-summary',
    'investigation-guidance',
    'low-confidence-professional-message')
$expectedCaseFields = @(
    'brief-kind',
    'brief-contract-hash',
    'draft-option',
    'old-profile-option',
    'general-writing-option',
    'option-a-hard-gates',
    'option-b-hard-gates',
    'option-c-hard-gates',
    'draft-old-exact-identity',
    'draft-general-exact-identity',
    'old-general-exact-identity',
    'manual-option',
    'preference',
    'option-a-usability',
    'option-b-usability',
    'option-c-usability',
    'first-edit-category',
    'edit-target',
    'draft-outcome',
    'old-profile-outcome',
    'general-writing-outcome',
    'impact',
    'state',
    'resolution')
$caseMatches = @([regex]::Matches(
        $content,
        '(?ms)^## (?<id>case-[0-9]{3})\r?\n(?<body>.*?)(?=^## |\z)'))
if ($caseMatches.Count -ne 7) {
    Add-ComparisonError 'invalid-count' 'The comparison requires exactly seven cases.'
}
$caseIds = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal)
$actualBriefKinds = [System.Collections.Generic.List[string]]::new()
$draftPairWins = 0
$draftPairLosses = 0

foreach ($caseMatch in $caseMatches) {
    $caseId = $caseMatch.Groups['id'].Value
    if (-not $caseIds.Add($caseId)) {
        Add-ComparisonError 'duplicate-case' "Duplicate case '$caseId'."
    }
    $fields = Get-ListFields $caseMatch.Groups['body'].Value
    Test-ExactFields $fields $expectedCaseFields $caseId
    if (@($expectedCaseFields | Where-Object { -not $fields.ContainsKey($_) }).Count -gt 0) {
        continue
    }

    $actualBriefKinds.Add($fields['brief-kind'])
    if ($fields['brief-kind'] -notin $expectedBriefKinds) {
        Add-ComparisonError 'invalid-brief' "$caseId has an unsupported brief-kind."
    }
    if ($fields['brief-contract-hash'] -cnotmatch '^[0-9a-fA-F]{64}$') {
        Add-ComparisonError 'condition-mismatch' "$caseId has an invalid brief contract hash."
    }
    $mappedOptions = @(
        $fields['draft-option'],
        $fields['old-profile-option'],
        $fields['general-writing-option'])
    if (@($mappedOptions | Sort-Object -Unique).Count -ne 3 -or
        @($mappedOptions | Where-Object { $_ -notin @('a', 'b', 'c') }).Count -gt 0) {
        Add-ComparisonError 'condition-mapping' "$caseId must map draft, old profile, and general writing to different A, B, and C options."
    }
    foreach ($gateField in @(
            'option-a-hard-gates',
            'option-b-hard-gates',
            'option-c-hard-gates')) {
        if ($fields[$gateField] -notin @('not-run', 'passed', 'failed')) {
            Add-ComparisonError 'hard-gate' "$caseId has an invalid $gateField value."
        }
    }
    foreach ($identityField in @(
            'draft-old-exact-identity',
            'draft-general-exact-identity',
            'old-general-exact-identity')) {
        if ($fields[$identityField] -notin @('yes', 'no')) {
            Add-ComparisonError 'no-churn' "$caseId has an invalid $identityField value."
        }
    }
    if ($fields['manual-option'] -cne 'allowed' -or
        $fields.preference -notin @('uncollected', 'a', 'b', 'c', 'tie-ab', 'tie-ac', 'tie-bc', 'all', 'neither', 'manual') -or
        $fields['first-edit-category'] -notin @('uncollected', 'none', 'opening', 'certainty', 'mechanism', 'structure', 'detail', 'tone', 'closure', 'authority', 'other') -or
        $fields['edit-target'] -notin @('uncollected', 'a', 'b', 'c', 'manual', 'none') -or
        $fields.impact -notin @('low', 'high') -or
        $fields.state -notin @('sealed', 'answered', 'resolved') -or
        $fields.resolution -notin @('pending', 'accepted', 'rejected', 'tolerance', 'evidence-gap')) {
        Add-ComparisonError 'invalid-state' "$caseId contains an unsupported state value."
    }
    foreach ($usabilityField in @(
            'option-a-usability',
            'option-b-usability',
            'option-c-usability')) {
        if ($fields[$usabilityField] -notin @('uncollected', 'ready', 'minor-edit', 'major-edit', 'unusable')) {
            Add-ComparisonError 'invalid-state' "$caseId has an invalid $usabilityField value."
        }
    }
    foreach ($outcomeField in @(
            'draft-outcome',
            'old-profile-outcome',
            'general-writing-outcome')) {
        if ($fields[$outcomeField] -notin @('uncollected', 'win', 'tie', 'loss')) {
            Add-ComparisonError 'invalid-state' "$caseId has an invalid $outcomeField value."
        }
    }

    $hasIdentity = @(
        $fields['draft-old-exact-identity'],
        $fields['draft-general-exact-identity'],
        $fields['old-general-exact-identity']) -contains 'yes'
    if ($RequirePresentationReady) {
        if ($fields['option-a-hard-gates'] -cne 'passed' -or
            $fields['option-b-hard-gates'] -cne 'passed' -or
            $fields['option-c-hard-gates'] -cne 'passed') {
            Add-ComparisonError 'hard-gate' "$caseId is not ready until all three options pass safety checks."
        }
        if ($hasIdentity) {
            Add-ComparisonError 'no-churn' "$caseId contains identical options and must be replaced rather than rated."
        }
        if ($fields.state -cne 'sealed' -or
            $fields.preference -cne 'uncollected' -or
            $fields['draft-outcome'] -cne 'uncollected' -or
            $fields['old-profile-outcome'] -cne 'uncollected' -or
            $fields['general-writing-outcome'] -cne 'uncollected') {
            Add-ComparisonError 'unsealed-case' "$caseId must be sealed and uncollected before presentation."
        }
    }

    if ($RequireResolved) {
        if ($hasIdentity) {
            Add-ComparisonError 'no-churn' "$caseId contains identical options and cannot count toward the resolved comparison."
        }
        if ($fields['option-a-hard-gates'] -cne 'passed' -or
            $fields['option-b-hard-gates'] -cne 'passed' -or
            $fields['option-c-hard-gates'] -cne 'passed') {
            Add-ComparisonError 'hard-gate' "$caseId cannot resolve with a failed or unrun safety check."
        }
        if ($fields.state -cne 'resolved' -or
            $fields.preference -eq 'uncollected' -or
            $fields['option-a-usability'] -eq 'uncollected' -or
            $fields['option-b-usability'] -eq 'uncollected' -or
            $fields['option-c-usability'] -eq 'uncollected' -or
            $fields['first-edit-category'] -eq 'uncollected' -or
            $fields['edit-target'] -eq 'uncollected' -or
            $fields.resolution -eq 'pending') {
            Add-ComparisonError 'unresolved-result' "$caseId is not fully resolved."
        }
        $expectedOutcomes = @{
            draft = 'loss'
            'old-profile' = 'loss'
            'general-writing' = 'loss'
        }
        if ($fields.preference -in @('a', 'b', 'c')) {
            $winner = Get-ConditionForOption $fields $fields.preference
            if ($null -ne $winner) { $expectedOutcomes[$winner] = 'win' }
        }
        elseif ($fields.preference -match '^tie-(?<first>[abc])(?<second>[abc])$') {
            foreach ($option in @(
                    $Matches.first,
                    $Matches.second)) {
                $condition = Get-ConditionForOption $fields $option
                if ($null -ne $condition) { $expectedOutcomes[$condition] = 'tie' }
            }
        }
        elseif ($fields.preference -eq 'all') {
            foreach ($condition in @('draft', 'old-profile', 'general-writing')) {
                $expectedOutcomes[$condition] = 'tie'
            }
        }
        elseif ($fields.preference -eq 'manual' -and
            $fields['edit-target'] -in @('a', 'b', 'c')) {
            $winner = Get-ConditionForOption $fields $fields['edit-target']
            if ($null -ne $winner) { $expectedOutcomes[$winner] = 'win' }
        }
        foreach ($condition in @('draft', 'old-profile', 'general-writing')) {
            if ($fields["$condition-outcome"] -cne $expectedOutcomes[$condition]) {
                Add-ComparisonError 'outcome-mismatch' "$caseId $condition-outcome does not match the blinded preference and edit target."
            }
        }
        $preferredOptions = @()
        if ($fields.preference -in @('a', 'b', 'c')) {
            $preferredOptions = @($fields.preference)
        }
        elseif ($fields.preference -match '^tie-(?<first>[abc])(?<second>[abc])$') {
            $preferredOptions = @($Matches.first, $Matches.second)
        }
        elseif ($fields.preference -eq 'all') {
            $preferredOptions = @('a', 'b', 'c')
        }
        elseif ($fields.preference -eq 'manual' -and
            $fields['edit-target'] -in @('a', 'b', 'c')) {
            $preferredOptions = @($fields['edit-target'])
        }
        $draftPreferred = $fields['draft-option'] -in $preferredOptions
        $oldPreferred = $fields['old-profile-option'] -in $preferredOptions
        if ($draftPreferred -and -not $oldPreferred) {
            $draftPairWins++
        }
        elseif ($oldPreferred -and -not $draftPreferred) {
            $draftPairLosses++
        }
        elseif (-not $draftPreferred -and -not $oldPreferred) {
            $draftRank = Get-UsabilityRank $fields["option-$($fields['draft-option'])-usability"]
            $oldRank = Get-UsabilityRank $fields["option-$($fields['old-profile-option'])-usability"]
            if ($draftRank -lt $oldRank) { $draftPairWins++ }
            elseif ($oldRank -lt $draftRank) { $draftPairLosses++ }
        }
    }
}

if (@(Compare-Object $expectedBriefKinds $actualBriefKinds -SyncWindow 0).Count -gt 0) {
    Add-ComparisonError 'invalid-brief' 'The comparison must contain each required brief kind exactly once and in order.'
}
if ($RequireResolved -and
    ($draftPairWins -lt 3 -or $draftPairLosses -gt 1)) {
    Add-ComparisonError 'comparison-threshold' 'The draft must beat the old profile in at least three cases, and the old profile may beat the draft in no more than one case.'
}

$privacyChecks = @(
    @{ Category = 'private-identifier'; Pattern = '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'; Message = 'Email addresses are not allowed.' },
    @{ Category = 'external-reference'; Pattern = '(?i)https?://|mailto:|www\.'; Message = 'External references are not allowed.' },
    @{ Category = 'absolute-path'; Pattern = '(?m)(?:[A-Za-z]:\\|/(?:Users|home|mnt|tmp|var|etc)/)'; Message = 'Absolute paths are not allowed.' },
    @{ Category = 'raw-output'; Pattern = '(?m)^```|^>\s|^Option [ABC]:|^Draft:|^Old profile:|^General writing:'; Message = 'Raw comparison text does not belong in the retained manifest.' },
    @{ Category = 'unresolved-template'; Pattern = '\{\{[^}]+\}\}'; Message = 'Template placeholders must be resolved.' })
foreach ($check in $privacyChecks) {
    if ($content -match $check.Pattern) {
        Add-ComparisonError $check.Category $check.Message
    }
}
foreach ($literal in @($ForbiddenLiteral | Where-Object { $_ })) {
    if ($content.Contains($literal, [System.StringComparison]::OrdinalIgnoreCase)) {
        Add-ComparisonError 'private-identifier' 'A caller-supplied forbidden literal is present.'
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "OK user voice three-way comparison: $comparisonPath"