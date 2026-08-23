<#
.SYNOPSIS
    Validate repository-level AI-agent instruction files.

.DESCRIPTION
    Treats AGENTS.md as the single source of truth and verifies that
    .github/copilot-instructions.md is its generated mirror. Relative Markdown
    links are rewritten to resolve from .github/: links under .github/ lose that
    prefix, while other repository-relative links gain ../.

    The validator also rejects tabs, trailing whitespace, whitespace-only lines,
    and missing or extra trailing newlines in the source and mirror.

.PARAMETER Fix
    Regenerate .github/copilot-instructions.md before validating it.

.PARAMETER RepoRoot
    Repository root to validate. Defaults to the parent of this script's tools
    directory. This parameter supports isolated contract tests.

.EXAMPLE
    ./tools/Validate-AgentFiles.ps1

.EXAMPLE
    ./tools/Validate-AgentFiles.ps1 -Fix
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [switch] $Fix,
    [string] $RepoRoot = (Split-Path $PSScriptRoot -Parent)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedRepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$agentsPath = Join-Path $resolvedRepoRoot 'AGENTS.md'
$mirrorPath = Join-Path $resolvedRepoRoot '.github/copilot-instructions.md'
$mirrorHeader = '<!-- DO NOT EDIT. Generated mirror of /AGENTS.md. Edit AGENTS.md and run: ./tools/Validate-AgentFiles.ps1 -Fix -->'
$errors = [System.Collections.Generic.List[string]]::new()

function Add-ValidationError ([string] $Message) {
    $errors.Add($Message) | Out-Null
}

function Get-RelativePath ([string] $Path) {
    [System.IO.Path]::GetRelativePath($resolvedRepoRoot, $Path).Replace('\', '/')
}

function Get-ExpectedMirror {
    if (-not (Test-Path -LiteralPath $agentsPath -PathType Leaf)) {
        throw "Source instruction file not found: $agentsPath"
    }

    $agents = [System.IO.File]::ReadAllText($agentsPath)
    $newline = if ($agents.Contains("`r`n")) { "`r`n" } else { "`n" }
    $rewritten = [regex]::Replace($agents, '\]\(([^)]+)\)', {
            param($match)

            $target = $match.Groups[1].Value
            if ($target -match '^(?:https?:|mailto:|tel:|ftp:|#|/)') {
                return $match.Value
            }
            if ($target.StartsWith('.github/', [System.StringComparison]::Ordinal)) {
                return "]($($target.Substring('.github/'.Length)))"
            }

            return "](../$target)"
        })

    "$mirrorHeader$newline$rewritten"
}

function Test-TextFile ([string] $Path) {
    $relativePath = Get-RelativePath $Path
    $text = [System.IO.File]::ReadAllText($Path)
    if (-not $text.EndsWith("`n", [System.StringComparison]::Ordinal)) {
        Add-ValidationError "$relativePath must end with a newline."
    }
    if ($text -match '(?:\r?\n){2}\z') {
        Add-ValidationError "$relativePath must end with exactly one newline."
    }

    $lineNumber = 0
    foreach ($line in ($text -split '\r?\n')) {
        $lineNumber++
        if ($line.Contains("`t")) {
            Add-ValidationError "${relativePath}:${lineNumber}: tab character."
        }
        if ($line -ne $line.TrimEnd()) {
            Add-ValidationError "${relativePath}:${lineNumber}: trailing whitespace."
        }
        if ($line.Length -gt 0 -and [string]::IsNullOrWhiteSpace($line)) {
            Add-ValidationError "${relativePath}:${lineNumber}: whitespace-only line."
        }
    }
}

$expectedMirror = Get-ExpectedMirror
if ($Fix) {
    $mirrorDirectory = Split-Path $mirrorPath -Parent
    [System.IO.Directory]::CreateDirectory($mirrorDirectory) | Out-Null
    [System.IO.File]::WriteAllText($mirrorPath, $expectedMirror)
    Write-Host "Wrote $(Get-RelativePath $mirrorPath)"
}

if (-not (Test-Path -LiteralPath $mirrorPath -PathType Leaf)) {
    Add-ValidationError "$(Get-RelativePath $mirrorPath) is missing. Run: ./tools/Validate-AgentFiles.ps1 -Fix"
}
else {
    $actualMirror = [System.IO.File]::ReadAllText($mirrorPath)
    if ($actualMirror -cne $expectedMirror) {
        Add-ValidationError "$(Get-RelativePath $mirrorPath) is out of sync with AGENTS.md. Run: ./tools/Validate-AgentFiles.ps1 -Fix"
    }
}

Test-TextFile $agentsPath
if (Test-Path -LiteralPath $mirrorPath -PathType Leaf) {
    Test-TextFile $mirrorPath
}

if ($errors.Count -gt 0) {
    Write-Host 'Agent-file validation failed:' -ForegroundColor Red
    foreach ($validationError in $errors) {
        Write-Host "  - $validationError"
    }
    exit 1
}

Write-Host 'Agent-file validation passed.' -ForegroundColor Green