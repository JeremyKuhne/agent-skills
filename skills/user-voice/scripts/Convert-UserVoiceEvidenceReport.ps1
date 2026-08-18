#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string] $InputPath,

    [Parameter(Mandatory)]
    [string] $OutputPath,

    [ValidateSet('Auto', 'RawMarkdown', 'Attachment', 'M365')]
    [string] $Transport = 'Auto',

    [Parameter(Mandatory)]
    [string] $ConsentId,

    [string] $ConsentSchema = '1',

    [Parameter(Mandatory)]
    [string] $AnalysisProvider,

    [Parameter(Mandatory)]
    [string] $AnalysisHost,

    [Parameter(Mandatory)]
    [string] $ConsentExpiry,

    [string[]] $ForbiddenLiteral,

    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$source = $ExecutionContext.SessionState.Path.
    GetUnresolvedProviderPathFromPSPath($InputPath)
$destination = $ExecutionContext.SessionState.Path.
    GetUnresolvedProviderPathFromPSPath($OutputPath)
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "The evidence report input does not exist: '$InputPath'."
}
if ([System.IO.Path]::GetFullPath($source) -eq
    [System.IO.Path]::GetFullPath($destination)) {
    throw 'InputPath and OutputPath must be different files.'
}
if ((Test-Path -LiteralPath $destination) -and -not $Force) {
    throw "The normalized output already exists: '$OutputPath'. Pass -Force to replace it."
}
$destinationParent = Split-Path -Parent $destination
if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
    throw "The normalized output directory does not exist: '$destinationParent'."
}

$raw = [System.IO.File]::ReadAllText($source).TrimStart([char] 0xFEFF)
$beginMarker = 'USER-VOICE-REPORT-BEGIN'
$endMarker = 'USER-VOICE-REPORT-END'
$beginMatches = @([regex]::Matches(
        $raw,
        "(?m)^$([regex]::Escape($beginMarker))\r?$"))
$endMatches = @([regex]::Matches(
        $raw,
        "(?m)^$([regex]::Escape($endMarker))\r?$"))

$selectedTransport = $Transport
if ($selectedTransport -eq 'Auto') {
    if ($beginMatches.Count -gt 0 -or $endMatches.Count -gt 0) {
        $selectedTransport = 'M365'
    }
    elseif ($raw -match '\A# User voice evidence report\r?\n') {
        $selectedTransport = 'RawMarkdown'
    }
    else {
        throw 'The report does not match a recognized transport. Select a supported transport or regenerate it.'
    }
}

if ($selectedTransport -eq 'M365') {
    if ($beginMatches.Count -ne 1 -or $endMatches.Count -ne 1) {
        throw 'M365 transport requires exactly one begin marker and one end marker.'
    }
    if ($beginMatches[0].Index -ge $endMatches[0].Index) {
        throw 'The M365 report markers are out of order.'
    }
    $start = $beginMatches[0].Index + $beginMatches[0].Length
    $length = $endMatches[0].Index - $start
    $normalized = $raw.Substring($start, $length).Trim("`r", "`n")
}
else {
    if ($beginMatches.Count -gt 0 -or $endMatches.Count -gt 0) {
        throw "$selectedTransport transport cannot contain M365 envelope markers."
    }
    $normalized = $raw.TrimEnd("`r", "`n")
}

if ($normalized -notmatch '\A# User voice evidence report\r?\n') {
    throw 'The normalized report does not start with the required title.'
}

$transportChecks = @(
    @{ Pattern = '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'; Message = 'The transport contains an email address.' },
    @{ Pattern = '(?i)https?://|mailto:|www\.'; Message = 'The transport contains an external reference.' },
    @{ Pattern = '(?m)(?:[A-Za-z]:\\|/(?:Users|home|mnt|tmp|var|etc)/)'; Message = 'The transport contains an absolute path.' },
    @{ Pattern = '(?i)-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|\bgh[pousr]_[A-Za-z0-9_]{20,}\b|\bAKIA[0-9A-Z]{16}\b'; Message = 'The transport contains secret material.' },
    @{ Pattern = '(?i)ignore (?:all |any )?(?:previous|prior) instructions|(?:open|read|fetch|execute|run) (?:the )?(?:file|path|command|script)\b'; Message = 'The transport contains an embedded instruction.' })
foreach ($check in $transportChecks) {
    if ($raw -match $check.Pattern) { throw $check.Message }
}
foreach ($literal in @($ForbiddenLiteral | Where-Object { $_ })) {
    if ($raw.Contains($literal, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'The transport contains a caller-supplied forbidden literal.'
    }
}

$temporary = Join-Path ([System.IO.Path]::GetTempPath()) ".user-voice-report-$([guid]::NewGuid().ToString('N')).md"
try {
    [System.IO.File]::WriteAllText(
        $temporary,
        $normalized + "`n",
        [System.Text.UTF8Encoding]::new($false))
    $pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
    $arguments = @(
        '-NoProfile',
        '-File', (Join-Path $PSScriptRoot 'Test-UserVoiceEvidenceReport.ps1'),
        '-Path', $temporary,
        '-ConsentId', $ConsentId,
        '-ConsentSchema', $ConsentSchema,
        '-AnalysisProvider', $AnalysisProvider,
        '-AnalysisHost', $AnalysisHost,
        '-ConsentExpiry', $ConsentExpiry,
        '-RequiredReportSchema', '2')
    if ($null -ne $ForbiddenLiteral -and $ForbiddenLiteral.Count -gt 0) {
        $arguments += '-ForbiddenLiteral'
        $arguments += $ForbiddenLiteral
    }
    & $pwsh @arguments
    if ($LASTEXITCODE -ne 0) {
        throw 'The normalized evidence report failed validation.'
    }

    if ($PSCmdlet.ShouldProcess($destination, 'Write normalized evidence report')) {
        [System.IO.File]::WriteAllText(
            $destination,
            $normalized + "`n",
            [System.Text.UTF8Encoding]::new($false))
    }
}
finally {
    if (Test-Path -LiteralPath $temporary) {
        Remove-Item -LiteralPath $temporary -Force
    }
}

[pscustomobject]@{
    InputPath = $source
    OutputPath = $destination
    Transport = $selectedTransport
    SchemaVersion = 2
}
