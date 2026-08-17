#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $MaintenanceRoot,

    [string[]] $ExpectedAbsentPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$errors = [System.Collections.Generic.List[string]]::new()
function Add-CleanupError([string] $category, [string] $message) {
    $errors.Add("[$category] $message")
}

$rootInput = $ExecutionContext.SessionState.Path.
    GetUnresolvedProviderPathFromPSPath($MaintenanceRoot)
if (-not (Test-Path -LiteralPath $rootInput -PathType Container)) {
    throw "The maintenance root does not exist: '$MaintenanceRoot'."
}
$root = (Resolve-Path -LiteralPath $rootInput).Path
$comparison = if ($IsWindows) {
    [System.StringComparison]::OrdinalIgnoreCase
}
else { [System.StringComparison]::Ordinal }
$rootPrefix = $root.TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar) +
    [System.IO.Path]::DirectorySeparatorChar

foreach ($expected in @($ExpectedAbsentPath | Where-Object { $_ })) {
    $candidate = if ([System.IO.Path]::IsPathRooted($expected)) {
        [System.IO.Path]::GetFullPath($expected)
    }
    else { [System.IO.Path]::GetFullPath((Join-Path $root $expected)) }
    if (-not $candidate.StartsWith($rootPrefix, $comparison)) {
        Add-CleanupError 'scope' "Expected-absent path escapes the maintenance root: '$expected'."
    }
    elseif (Test-Path -LiteralPath $candidate) {
        Add-CleanupError 'transient-retained' "Expected transient path still exists: '$expected'."
    }
}

$forbiddenPathPattern = '(?i)(?:^|/)(?:artifacts|before-after|diffs|edits|evaluation-artifacts|model-output|options|preference-responses|raw-output|scoring|scratch|transcripts)(?:/|$)|\.(?:bak|eml|mbox|msg|ost|pst|tmp|zip)$'
$rawContentPattern = '(?im)^(?:Option [ABC]:|Before:|After:|User edit:|Scoring key:|Raw output:)\s*\S'
$files = @(Get-ChildItem -LiteralPath $root -File -Recurse -Force |
    Where-Object {
        $relative = [System.IO.Path]::GetRelativePath($root, $_.FullName).
            Replace('\', '/')
        $relative -notmatch '(?i)(?:^|/)(?:\.git|\.github|\.private-voice)(?:/|$)'
    })
foreach ($file in $files) {
    $relative = [System.IO.Path]::GetRelativePath($root, $file.FullName).
        Replace('\', '/')
    if ($relative -match $forbiddenPathPattern) {
        Add-CleanupError 'transient-retained' "Prohibited transient path remains: '$relative'."
        continue
    }
    if ($file.Length -gt 2MB) {
        Add-CleanupError 'unreviewed-large-file' "Maintenance file exceeds the 2 MB inspection limit: '$relative'."
        continue
    }
    try {
        $content = [System.IO.File]::ReadAllText($file.FullName)
        if ($content -match $rawContentPattern) {
            Add-CleanupError 'raw-output' "Retained file contains a raw option, edit, or scoring block: '$relative'."
        }
    }
    catch [System.Text.DecoderFallbackException] { }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "OK user voice transient cleanup: $root"