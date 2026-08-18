#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $SourcePath,

    [Parameter(Mandatory)]
    [string] $InstalledPath,

    [string[]] $DiscoveryRoot,

    [string[]] $ForbiddenProfileName,

    [switch] $RequireSingleActiveProfile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-Directory([string] $path, [string] $name) {
    $candidate = $ExecutionContext.SessionState.Path.
        GetUnresolvedProviderPathFromPSPath($path)
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
        throw "$name does not exist: '$path'."
    }
    return (Resolve-Path -LiteralPath $candidate).Path
}

function Get-Manifest([string] $root) {
    $manifest = @{}
    foreach ($file in Get-ChildItem -LiteralPath $root -File -Recurse -Force) {
        $relative = [System.IO.Path]::GetRelativePath($root, $file.FullName).
            Replace('\', '/')
        $manifest[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
    return $manifest
}

$source = Resolve-Directory $SourcePath 'Source profile'
$installed = Resolve-Directory $InstalledPath 'Installed profile'
$comparison = if ($IsWindows) {
    [System.StringComparison]::OrdinalIgnoreCase
}
else { [System.StringComparison]::Ordinal }
if ($source.Equals($installed, $comparison)) {
    throw 'SourcePath and InstalledPath must be separate directories.'
}

$pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
$profileValidator = Join-Path $PSScriptRoot 'Test-UserVoiceProfile.ps1'
foreach ($profile in @($source, $installed)) {
    & $pwsh -NoProfile -File $profileValidator -ProfilePath $profile
    if ($LASTEXITCODE -ne 0) {
        throw "Profile validation failed: '$profile'."
    }
}

$sourceManifest = Get-Manifest $source
$installedManifest = Get-Manifest $installed
$differences = [System.Collections.Generic.List[string]]::new()
foreach ($path in @($sourceManifest.Keys + $installedManifest.Keys | Sort-Object -Unique)) {
    if (-not $sourceManifest.ContainsKey($path)) {
        $differences.Add("unexpected installed file: $path")
    }
    elseif (-not $installedManifest.ContainsKey($path)) {
        $differences.Add("missing installed file: $path")
    }
    elseif ($sourceManifest[$path] -cne $installedManifest[$path]) {
        $differences.Add("hash mismatch: $path")
    }
}
if ($differences.Count -gt 0) {
    throw "Installed manifest does not match source:`n$($differences -join "`n")"
}

$activeProfiles = [System.Collections.Generic.HashSet[string]]::new(
    $(if ($IsWindows) {
            [System.StringComparer]::OrdinalIgnoreCase
        }
        else { [System.StringComparer]::Ordinal }))
foreach ($rootInput in @($DiscoveryRoot | Where-Object { $_ })) {
    $root = $ExecutionContext.SessionState.Path.
        GetUnresolvedProviderPathFromPSPath($rootInput)
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
    foreach ($skillFile in Get-ChildItem -LiteralPath $root -File -Recurse -Filter 'SKILL.md' -Force) {
        $content = [System.IO.File]::ReadAllText($skillFile.FullName)
        $nameMatch = [regex]::Match($content, '(?m)^name:\s*(?<value>[^\s]+)\s*$')
        if ($nameMatch.Success -and
            $nameMatch.Groups['value'].Value -in $ForbiddenProfileName) {
            throw "A forbidden legacy profile is discoverable: '$($nameMatch.Groups['value'].Value)'."
        }
        if ($content -match '(?m)^name:\s*user-voice-profile\s*$') {
            $null = $activeProfiles.Add((Resolve-Path -LiteralPath $skillFile.DirectoryName).Path)
        }
    }
}
if ($RequireSingleActiveProfile) {
    if ($activeProfiles.Count -ne 1 -or -not $activeProfiles.Contains($installed)) {
        throw "Expected exactly one discovered user-voice-profile at the installed path; found $($activeProfiles.Count)."
    }
}

[pscustomobject]@{
    SourcePath = $source
    InstalledPath = $installed
    Files = $sourceManifest.Count
    ActiveProfiles = $activeProfiles.Count
    ManifestMatch = $true
}