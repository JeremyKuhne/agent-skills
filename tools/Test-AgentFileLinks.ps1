<#
.SYNOPSIS
    Verify relative links in agent customization files.

.DESCRIPTION
    Scans AGENTS.md, its generated Copilot mirror, and Markdown under skills/,
    agents/, and .agents/. Relative link targets must exist in the current
    working tree when resolved from the containing file.

    Fenced and inline code are ignored. External URLs, absolute paths, and
    in-page anchors are outside this check.

.PARAMETER RepoRoot
    Repository root to scan. Defaults to the parent of this script's tools
    directory. This parameter supports isolated contract tests.

.EXAMPLE
    ./tools/Test-AgentFileLinks.ps1
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [string] $RepoRoot = (Split-Path $PSScriptRoot -Parent)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedRepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$scopeEntries = @(
    'AGENTS.md',
    '.github/copilot-instructions.md',
    @{ Directory = 'skills'; Filter = '*.md' },
    @{ Directory = 'agents'; Filter = '*.md' },
    @{ Directory = '.agents'; Filter = '*.md' }
)

function Get-RepoRelativePath ([string] $Path) {
    [System.IO.Path]::GetRelativePath($resolvedRepoRoot, $Path).Replace('\', '/')
}

function Get-ScopeFiles {
    $files = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $scopeEntries) {
        if ($entry -is [string]) {
            $path = Join-Path $resolvedRepoRoot $entry
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                $files.Add((Resolve-Path -LiteralPath $path).Path) | Out-Null
            }
            continue
        }

        $directory = Join-Path $resolvedRepoRoot $entry.Directory
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            continue
        }

        foreach ($file in Get-ChildItem -LiteralPath $directory -Recurse -File -Filter $entry.Filter) {
            $files.Add($file.FullName) | Out-Null
        }
    }

    @($files | Sort-Object -Unique)
}

function Get-LinkPath ([string] $Target) {
    $targetWithoutTitle = $Target.Trim()
    if ($targetWithoutTitle -match '^<([^>]+)>(?:\s+["''].*)?$') {
        $targetWithoutTitle = $Matches[1]
    }
    elseif ($targetWithoutTitle -match '^(\S+)(?:\s+["''].*)?$') {
        $targetWithoutTitle = $Matches[1]
    }

    $path = ($targetWithoutTitle -split '[?#]', 2)[0]
    if ([string]::IsNullOrWhiteSpace($path)) {
        return $null
    }

    [System.Uri]::UnescapeDataString($path)
}

function Test-FileLinks ([string] $Path) {
    $broken = [System.Collections.Generic.List[string]]::new()
    $directory = Split-Path $Path -Parent
    $lineNumber = 0
    $fenceMarker = $null

    foreach ($line in Get-Content -LiteralPath $Path) {
        $lineNumber++
        if ($line -match '^\s*(```|~~~)') {
            $marker = $Matches[1]
            if ($null -eq $fenceMarker) {
                $fenceMarker = $marker
            }
            elseif ($marker -eq $fenceMarker) {
                $fenceMarker = $null
            }
            continue
        }
        if ($null -ne $fenceMarker) {
            continue
        }

        $prose = [regex]::Replace($line, '`[^`]*`', '')
        foreach ($linkMatch in [regex]::Matches($prose, '\]\(([^)]+)\)')) {
            $target = $linkMatch.Groups[1].Value.Trim()
            if (-not $target -or $target -match '^(?:[A-Za-z][A-Za-z0-9+.-]*:|#|/)') {
                continue
            }

            $linkPath = Get-LinkPath $target
            if ($null -eq $linkPath) {
                continue
            }

            $resolvedTarget = Join-Path $directory $linkPath
            if (-not (Test-Path -LiteralPath $resolvedTarget)) {
                $relativePath = Get-RepoRelativePath $Path
                $broken.Add("${relativePath}:${lineNumber}: $target") | Out-Null
            }
        }
    }

    @($broken)
}

$files = @(Get-ScopeFiles)
$brokenLinks = [System.Collections.Generic.List[string]]::new()
foreach ($file in $files) {
    foreach ($brokenLink in (Test-FileLinks $file)) {
        $brokenLinks.Add($brokenLink) | Out-Null
    }
}

if ($brokenLinks.Count -gt 0) {
    Write-Host 'Broken relative links:' -ForegroundColor Red
    foreach ($brokenLink in $brokenLinks) {
        Write-Host "  - $brokenLink"
    }
    exit 1
}

Write-Host "All relative links resolve. ($($files.Count) files scanned.)" -ForegroundColor Green