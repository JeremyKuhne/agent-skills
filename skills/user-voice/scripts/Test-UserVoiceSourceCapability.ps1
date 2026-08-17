#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Path,

    [datetime] $AsOfDate = [datetime]::UtcNow.Date
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$errors = [System.Collections.Generic.List[string]]::new()
function Add-CapabilityError([string] $category, [string] $message) {
    $errors.Add("[$category] $message")
}

function Get-ListFields([string] $section) {
    $fields = @{}
    foreach ($match in [regex]::Matches(
            $section,
            '(?m)^- (?<key>[a-z][a-z0-9-]*):\s*(?<value>[^\r\n]*)\r?$')) {
        $key = $match.Groups['key'].Value
        if ($fields.ContainsKey($key)) {
            Add-CapabilityError 'unexpected-field' "Duplicate field '$key'."
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
            Add-CapabilityError 'unexpected-field' "$sectionName field '$key' is missing or empty."
        }
    }
    foreach ($key in $fields.Keys) {
        if ($key -notin $expected) {
            Add-CapabilityError 'unexpected-field' "Unexpected $sectionName field '$key'."
        }
    }
}

$declarationPath = $ExecutionContext.SessionState.Path.
    GetUnresolvedProviderPathFromPSPath($Path)
if (-not (Test-Path -LiteralPath $declarationPath -PathType Leaf)) {
    throw "The capability declaration does not exist: '$Path'."
}
$content = [System.IO.File]::ReadAllText($declarationPath)

$headings = @([regex]::Matches($content, '(?m)^#{1,2} .+$'))
if ($headings.Count -eq 0 -or
    $headings[0].Value.TrimEnd("`r") -cne '# User voice source capability declaration') {
    Add-CapabilityError 'unexpected-heading' 'The declaration title is missing or malformed.'
}
foreach ($heading in @($headings | Select-Object -Skip 1)) {
    if ($heading.Value.TrimEnd("`r") -cnotmatch '^## category-[0-9]{3}$') {
        Add-CapabilityError 'unexpected-heading' "Unexpected declaration heading '$($heading.Value.TrimEnd("`r"))'."
    }
}

$headerMatch = [regex]::Match(
    $content,
    '(?ms)\A# User voice source capability declaration\r?\n(?<body>.*?)(?=^## category-[0-9]{3}\r?$|\z)')
if (-not $headerMatch.Success) {
    Add-CapabilityError 'unexpected-field' 'The declaration header is missing or malformed.'
    $header = @{}
}
else {
    $header = Get-ListFields $headerMatch.Groups['body'].Value
    Test-ExactFields $header @(
        'declaration-schema-version',
        'client',
        'client-version',
        'reviewed-on',
        'expires-on') 'Declaration header'
}

if ($header.ContainsKey('declaration-schema-version') -and
    $header['declaration-schema-version'] -cne '1') {
    Add-CapabilityError 'unsupported-schema' 'declaration-schema-version must be 1.'
}
foreach ($field in @('client', 'client-version')) {
    if ($header.ContainsKey($field) -and
        $header[$field] -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') {
        Add-CapabilityError 'unexpected-field' "$field must be a generic 1-64 character identifier."
    }
}

$reviewed = $null
$expires = $null
foreach ($dateField in @('reviewed-on', 'expires-on')) {
    if ($header.ContainsKey($dateField)) {
        $parsed = [datetime]::MinValue
        if (-not [datetime]::TryParseExact(
                $header[$dateField],
                'yyyy-MM-dd',
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::None,
                [ref] $parsed)) {
            Add-CapabilityError 'invalid-date' "$dateField must use yyyy-MM-dd."
        }
        elseif ($dateField -eq 'reviewed-on') { $reviewed = $parsed.Date }
        else { $expires = $parsed.Date }
    }
}
if ($null -ne $reviewed -and $reviewed -gt $AsOfDate.Date) {
    Add-CapabilityError 'invalid-date' 'reviewed-on cannot be in the future.'
}
if ($null -ne $expires -and $expires -lt $AsOfDate.Date) {
    Add-CapabilityError 'expired' 'The capability declaration has expired.'
}
if ($null -ne $reviewed -and $null -ne $expires -and
    ($expires - $reviewed).TotalDays -gt 30) {
    Add-CapabilityError 'invalid-date' 'Capability declarations cannot remain valid for more than 30 days.'
}

$expectedCategoryFields = @(
    'source-category',
    'access',
    'account-boundary',
    'source-display',
    'model-exposure',
    'return-methods',
    'exclusions',
    'verification')
$categoryMatches = @([regex]::Matches(
        $content,
        '(?ms)^## (?<id>category-[0-9]{3})\r?\n(?<body>.*?)(?=^## |\z)'))
if ($categoryMatches.Count -eq 0) {
    Add-CapabilityError 'missing-category' 'At least one source category is required.'
}
$categoryIds = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal)
$sourceCategories = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::Ordinal)
foreach ($categoryMatch in $categoryMatches) {
    $categoryId = $categoryMatch.Groups['id'].Value
    if (-not $categoryIds.Add($categoryId)) {
        Add-CapabilityError 'duplicate-category' "Duplicate category '$categoryId'."
    }
    $fields = Get-ListFields $categoryMatch.Groups['body'].Value
    Test-ExactFields $fields $expectedCategoryFields $categoryId
    if (@($expectedCategoryFields | Where-Object { -not $fields.ContainsKey($_) }).Count -gt 0) {
        continue
    }

    if ($fields['source-category'] -cnotmatch '^[a-z][a-z0-9-]{2,40}$' -or
        -not $sourceCategories.Add($fields['source-category'])) {
        Add-CapabilityError 'invalid-category' "$categoryId source-category is invalid or duplicated."
    }
    if ($fields.access -notin @('none', 'metadata', 'content', 'metadata-and-content') -or
        $fields['account-boundary'] -notin @('none', 'public-unauthenticated', 'current-connected-account', 'workspace-only', 'user-provided') -or
        $fields['source-display'] -notin @('yes', 'no') -or
        $fields['model-exposure'] -notin @('none', 'local-only', 'current-provider') -or
        $fields.verification -notin @('unverified', 'tool-observed', 'user-provided')) {
        Add-CapabilityError 'invalid-capability' "$categoryId contains an unsupported capability value."
    }

    $methods = @($fields['return-methods'] -split ',\s*')
    if ($methods.Count -eq 0 -or
        @($methods | Where-Object { $_ -notin @('none', 'direct', 'raw-markdown', 'attachment', 'm365') }).Count -gt 0 -or
        @($methods | Sort-Object -Unique).Count -ne $methods.Count) {
        Add-CapabilityError 'invalid-capability' "$categoryId return-methods are invalid or duplicated."
    }

    if ($fields.access -eq 'none' -or $fields.verification -eq 'unverified') {
        if ($fields.access -ne 'none' -or
            $fields['account-boundary'] -ne 'none' -or
            $fields['source-display'] -ne 'no' -or
            $fields['model-exposure'] -ne 'none' -or
            $methods.Count -ne 1 -or $methods[0] -ne 'none') {
            Add-CapabilityError 'unverified-access' "$categoryId unverified or unavailable access must fail closed to none."
        }
    }
    elseif ($fields['account-boundary'] -eq 'none' -or
        $fields['source-display'] -ne 'yes' -or
        $fields['model-exposure'] -eq 'none' -or
        'none' -in $methods) {
        Add-CapabilityError 'incomplete-capability' "$categoryId usable access lacks an account boundary, source display, model exposure, or return method."
    }
}

$privacyChecks = @(
    @{ Category = 'private-identifier'; Pattern = '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'; Message = 'Email addresses are not allowed.' },
    @{ Category = 'external-reference'; Pattern = '(?i)https?://|mailto:|www\.'; Message = 'External references are not allowed.' },
    @{ Category = 'absolute-path'; Pattern = '(?m)(?:[A-Za-z]:\\|/(?:Users|home|mnt|tmp|var|etc)/)'; Message = 'Absolute paths are not allowed.' },
    @{ Category = 'unresolved-template'; Pattern = '\{\{[^}]+\}\}'; Message = 'Template placeholders must be resolved.' })
foreach ($check in $privacyChecks) {
    if ($content -match $check.Pattern) {
        Add-CapabilityError $check.Category $check.Message
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "OK user voice source capability: $declarationPath"
