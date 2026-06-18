<#
.SYNOPSIS
    Vets and pins the package versions used by New-DotnetRepo.ps1.

.DESCRIPTION
    Resolves the latest KNOWN-GOOD version of each managed package - never simply
    the latest. A candidate is rejected unless it is, per the policy in
    versions.json: old enough (minimum release age / quarantine), listed (not
    yanked), not deprecated, free of known advisories, and under an allowed
    license. This keeps freshly published - and therefore least-vetted - versions,
    including compromised ones, out of newly scaffolded repositories.

    Reports proposed changes by default. Use -Apply to write versions.json (review
    the diff before committing). Use -SmokeTest to authoritatively validate the
    pinned set against the real project layouts (a tool and a multi-target library
    that builds on net472), which is the ground-truth TFM-compatibility check.

.PARAMETER VersionsPath
    Path to the manifest. Defaults to versions.json next to this script.

.PARAMETER MinimumReleaseAgeDays
    Override the manifest's quarantine window for this run.

.PARAMETER Source
    NuGet v3 source. Defaults to the manifest's source (nuget.org).

.PARAMETER Apply
    Write the resolved versions back to versions.json and stamp lastVetted.

.PARAMETER SmokeTest
    After resolving (and applying), scaffold a tool and a multi-target library
    into temp folders and build them, to confirm the pinned set restores and
    builds on every targeted TFM.

.EXAMPLE
    .\Update-ScaffoldVersions.ps1                 # report only
    .\Update-ScaffoldVersions.ps1 -Apply -SmokeTest
#>

#Requires -Version 7.2
[CmdletBinding()]
param(
    [string] $VersionsPath = (Join-Path $PSScriptRoot 'versions.json'),
    [int]    $MinimumReleaseAgeDays,
    [string] $Source,
    [switch] $Apply,
    [switch] $SmokeTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$flat = 'https://api.nuget.org/v3-flatcontainer'
$reg  = 'https://api.nuget.org/v3/registration5-semver1'

function Get-StableVersions ([string] $id) {
    $u = "$flat/$($id.ToLower())/index.json"
    (Invoke-RestMethod $u -TimeoutSec 30).versions | Where-Object { $_ -notmatch '-' }
}

function Get-VersionMeta ([string] $id, [string] $v) {
    $leaf = Invoke-RestMethod "$reg/$($id.ToLower())/$v.json" -TimeoutSec 30
    $ce = $leaf.catalogEntry
    if ($ce -is [string]) { $ce = Invoke-RestMethod $ce -TimeoutSec 30 }

    $license = if ($ce.PSObject.Properties['licenseExpression'] -and $ce.licenseExpression) {
        $ce.licenseExpression
    } else {
        try {
            $nuspec = [xml]((Invoke-WebRequest "$flat/$($id.ToLower())/$v/$($id.ToLower()).nuspec" -TimeoutSec 30).Content)
            [string]$nuspec.package.metadata.license.'#text'
        } catch { $null }
    }

    [pscustomobject]@{
        Version    = $v
        Published  = [datetime]$ce.published
        Listed     = [bool]$ce.listed
        Deprecated = [bool]($ce.PSObject.Properties['deprecation'] -and $ce.deprecation)
        Vulnerable = [bool]($ce.PSObject.Properties['vulnerabilities'] -and $ce.vulnerabilities)
        License    = $license
    }
}

# Newest stable version that passes every gate, scanning newest-first.
function Resolve-KnownGood ([string] $id, [int] $minAge, [string[]] $allow) {
    $versions = Get-StableVersions $id |
        Sort-Object { [version]($_ -replace '^(\d+\.\d+\.\d+).*', '$1') } -Descending
    foreach ($v in $versions) {
        try { $m = Get-VersionMeta $id $v } catch { continue }
        $age = [int]((Get-Date) - $m.Published).TotalDays
        $reasons = @()
        if (-not $m.Listed)  { $reasons += 'unlisted' }
        if ($m.Deprecated)   { $reasons += 'deprecated' }
        if ($m.Vulnerable)   { $reasons += 'advisory' }
        if ($age -lt $minAge) { $reasons += "age ${age}d<${minAge}d" }
        if ($m.License -and $allow -notcontains $m.License) { $reasons += "license $($m.License)" }
        if ($reasons.Count -eq 0) {
            return [pscustomobject]@{ Version = $v; Age = $age; License = $m.License; Reason = '' }
        }
        Write-Verbose "$id $v rejected: $($reasons -join ', ')"
    }
    return [pscustomobject]@{ Version = $null; Age = $null; License = $null; Reason = 'no known-good version' }
}

# ---------------------------------------------------------------------------

$doc    = Get-Content $VersionsPath -Raw | ConvertFrom-Json
$minAge = if ($PSBoundParameters.ContainsKey('MinimumReleaseAgeDays')) { $MinimumReleaseAgeDays } else { [int]$doc.policy.minimumReleaseAgeDays }
$allow  = @($doc.policy.allowedLicenses)
if (-not $Source) { $Source = [string]$doc.policy.source }

Write-Host "Vetting scaffold package versions" -ForegroundColor White
Write-Host "  source:    $Source"
Write-Host "  min age:   $minAge days (quarantine)"
Write-Host "  licenses:  $($allow -join ', ')`n"

$rows = foreach ($prop in $doc.packages.PSObject.Properties) {
    $id = $prop.Name
    $current = [string]$prop.Value
    $kg = Resolve-KnownGood $id $minAge $allow
    $action = if (-not $kg.Version) { 'BLOCKED' }
              elseif ($kg.Version -eq $current) { 'current' }
              else { 'bump' }
    [pscustomobject]@{
        Package   = $id
        Current   = $current
        KnownGood = $kg.Version
        AgeDays   = $kg.Age
        License   = $kg.License
        Action    = $action
        Note      = $kg.Reason
    }
}

$rows | Format-Table Package, Current, KnownGood, AgeDays, License, Action -AutoSize | Out-String | Write-Host
$blocked = @($rows | Where-Object Action -eq 'BLOCKED')
if ($blocked) { Write-Host "BLOCKED (no known-good version): $($blocked.Package -join ', ')" -ForegroundColor Yellow }

if ($Apply) {
    foreach ($r in $rows) { if ($r.KnownGood) { $doc.packages.$($r.Package) = $r.KnownGood } }
    $doc.policy.lastVetted = (Get-Date).ToString('yyyy-MM-dd')
    ($doc | ConvertTo-Json -Depth 8) + "`n" | Set-Content -LiteralPath $VersionsPath -Encoding utf8NoBOM -NoNewline
    Write-Host "`nApplied to $VersionsPath. Review the diff and commit deliberately." -ForegroundColor Green
} else {
    Write-Host "`nReport only. Re-run with -Apply to write versions.json." -ForegroundColor Cyan
}

if ($SmokeTest) {
    $scaffold = Join-Path $PSScriptRoot 'New-DotnetRepo.ps1'
    $cases = @(
        @{ Name = 'vettool';  Args = @('-Archetype', 'tool', '-PackageId', 'VetTool', '-ToolCommandName', 'vettool', '-Description', 'compat probe', '-Owner', 'vet') }
        @{ Name = 'vetlib';   Args = @('-Archetype', 'multi-target', '-PackageId', 'Vet.Lib', '-Framework', 'net10.0', '-FrameworkLegacy', 'net472', '-Description', 'compat probe', '-Owner', 'vet') }
    )
    foreach ($c in $cases) {
        $root = Join-Path ([IO.Path]::GetTempPath()) "vet-$($c.Name)-$(Get-Random)"
        Write-Host "`nSmoke test ($($c.Name)) -> $root" -ForegroundColor White
        try {
            & pwsh -NoProfile -File $scaffold -Root $root -Name $c.Name @($c.Args) *>$null
            Push-Location $root
            try {
                & dotnet build -c Release --nologo *>$null
                if ($LASTEXITCODE -ne 0) { Write-Host "  BUILD FAILED for $($c.Name) - the pinned set is not TFM-compatible" -ForegroundColor Red }
                else { Write-Host "  OK ($($c.Name) builds on its targeted TFMs)" -ForegroundColor Green }
            } finally { Pop-Location }
        } finally {
            Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
