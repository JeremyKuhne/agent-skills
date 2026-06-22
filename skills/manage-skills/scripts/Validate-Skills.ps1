<#
.SYNOPSIS
    Validates Agent Skills (SKILL.md) against the agentskills.io specification. A
    dependency-free PowerShell check based on `agentskills/skills-ref` (frontmatter),
    plus the spec's length recommendation and Claude's no-XML-tags rule.

.DESCRIPTION
    For each skill directory, checks the SKILL.md against the Agent Skills
    spec (https://agentskills.io/specification):

      - Only the allowed fields are present: name, description, license,
        compatibility, metadata, allowed-tools.
      - name: required; <= 64 chars; NFKC-normalized; lowercase; letters, digits,
        and hyphens only; no leading/trailing or consecutive hyphen; matches the
        directory name.
      - description: required; non-empty; <= 1024 chars; no XML-style tags (the
        name and description are injected into the agent's skill-metadata block).
      - compatibility: if present, a string <= 500 chars.
      - yaml: no unquoted ':' in a scalar value that a strict YAML parser
        (skills-ref uses strictyaml) would reject; our lenient parser would miss it.
      - length: SKILL.md is at most 500 lines (the spec's progressive-disclosure
        recommendation, "Keep your main SKILL.md under 500 lines").

    The length and no-XML-tags checks go beyond skills-ref, which validates
    frontmatter only; the colon check restores parity with its strict YAML parser.

    The frontmatter parser is intentionally minimal - flat scalars plus a single
    level of `metadata:` mapping, which is the shape these skills use. It is not a
    general YAML parser; for arbitrary YAML use the reference `skills-ref` tool.

    Exits 0 when every skill is valid, 1 otherwise.

.PARAMETER Path
    One or more paths. Each may be a skill directory (contains SKILL.md) or a
    parent directory whose immediate subdirectories are skills (e.g. skills/).
    Defaults to the current directory.

.PARAMETER Quiet
    Print only failures.

.EXAMPLE
    pwsh Validate-Skills.ps1 skills/
    Validate every skill directory under skills/.

.EXAMPLE
    pwsh Validate-Skills.ps1 skills/manage-skills
    Validate a single skill directory.
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Position = 0)] [string[]] $Path,
    [switch] $Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$MaxName = 64
$MaxDescription = 1024
$MaxCompatibility = 500
$MaxSkillLines = 500
# Allowed frontmatter fields per the Agent Skills spec (skills-ref validator.py).
$AllowedFields = @('name', 'description', 'license', 'compatibility', 'metadata', 'allowed-tools')

function Get-SkillMd ([string] $dir) {
    foreach ($n in 'SKILL.md', 'skill.md') {
        $p = Join-Path $dir $n
        if (Test-Path -LiteralPath $p -PathType Leaf) { return $p }
    }
    return $null
}

# Parse SKILL.md frontmatter into a case-sensitive ordered map. Supports flat
# scalars and one level of block mapping (the `metadata:` block); not general YAML.
function Read-Frontmatter ([string] $content) {
    if (-not $content.StartsWith('---')) { throw 'SKILL.md must start with YAML frontmatter (---)' }
    $parts = $content.Split([string[]]@('---'), 3, [System.StringSplitOptions]::None)
    if ($parts.Count -lt 3) { throw 'SKILL.md frontmatter not properly closed with ---' }

    $map = New-Object System.Collections.Specialized.OrderedDictionary ([System.StringComparer]::Ordinal)
    $currentMapKey = $null
    foreach ($line in ($parts[1] -split "\r?\n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.TrimStart().StartsWith('#')) { continue }

        if ($currentMapKey -and $line -match '^\s+\S') {
            $kv = $line.Trim()
            $idx = $kv.IndexOf(':')
            if ($idx -lt 0) { throw "Invalid YAML in frontmatter near: $kv" }
            $k = $kv.Substring(0, $idx).Trim()
            $v = $kv.Substring($idx + 1).Trim() -replace '^(["''])(.*)\1$', '$2'
            $map[$currentMapKey][$k] = $v
            continue
        }

        $idx = $line.IndexOf(':')
        if ($idx -lt 0) { throw "Invalid YAML in frontmatter near: $line" }
        $k = $line.Substring(0, $idx).Trim()
        $v = $line.Substring($idx + 1).Trim()
        if ($v -eq '') {
            $map[$k] = New-Object System.Collections.Specialized.OrderedDictionary ([System.StringComparer]::Ordinal)
            $currentMapKey = $k
        }
        else {
            $map[$k] = ($v -replace '^(["''])(.*)\1$', '$2')
            $currentMapKey = $null
        }
    }
    return $map
}

# Count physical lines in SKILL.md (matches editor line numbers / Get-Content).
function Measure-SkillLineCount ([string] $content) {
    if ([string]::IsNullOrEmpty($content)) { return 0 }
    $n = ($content -split "\r?\n").Count
    if ($content.EndsWith("`n")) { $n-- }
    return $n
}

# Flag unquoted frontmatter scalar values whose text holds a ':' followed by
# whitespace (or a trailing ':'). A strict YAML parser - strictyaml, which
# skills-ref uses - reads that as a mapping indicator and fails to parse. Our own
# parser splits on the first ':' and would silently miss it. Quote the value or
# use a block scalar (>-).
function Test-FrontmatterColons ([string] $content) {
    $found = [System.Collections.Generic.List[string]]::new()
    $parts = $content.Split([string[]]@('---'), 3, [System.StringSplitOptions]::None)
    if ($parts.Count -lt 3) { return $found.ToArray() }
    foreach ($line in ($parts[1] -split "\r?\n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.TrimStart().StartsWith('#')) { continue }
        $idx = $line.IndexOf(':')
        if ($idx -lt 0) { continue }
        $key = $line.Substring(0, $idx).Trim()
        $val = $line.Substring($idx + 1).Trim()
        if ($val -eq '') { continue }
        if ($val -match '^["''>|]') { continue }
        if ($val -match ':(\s|$)') {
            $found.Add("Field '$key' value has an unquoted ':' that breaks strict YAML parsers (e.g. skills-ref); quote the value or use a block scalar.")
        }
    }
    return $found.ToArray()
}

function Test-SkillName ($name, [string] $dir) {
    if ($null -eq $name -or $name -isnot [string] -or [string]::IsNullOrWhiteSpace($name)) {
        "Field 'name' must be a non-empty string"
        return
    }
    $name = $name.Trim().Normalize([System.Text.NormalizationForm]::FormKC)

    if ($name.Length -gt $MaxName) {
        "Skill name '$name' exceeds $MaxName character limit ($($name.Length) chars)"
    }
    if ($name -cne $name.ToLowerInvariant()) {
        "Skill name '$name' must be lowercase"
    }
    if ($name.StartsWith('-') -or $name.EndsWith('-')) {
        'Skill name cannot start or end with a hyphen'
    }
    if ($name.Contains('--')) {
        'Skill name cannot contain consecutive hyphens'
    }
    $invalid = $false
    foreach ($c in $name.ToCharArray()) { if (-not ([char]::IsLetterOrDigit($c) -or $c -eq '-')) { $invalid = $true; break } }
    if ($invalid) {
        "Skill name '$name' contains invalid characters. Only letters, digits, and hyphens are allowed."
    }
    if ($dir) {
        $leaf = Split-Path -Leaf $dir
        if ($leaf.Normalize([System.Text.NormalizationForm]::FormKC) -cne $name) {
            "Directory name '$leaf' must match skill name '$name'"
        }
    }
}

function Test-SkillDescription ($description) {
    if ($null -eq $description -or $description -isnot [string] -or [string]::IsNullOrWhiteSpace($description)) {
        "Field 'description' must be a non-empty string"
        return
    }
    if ($description.Length -gt $MaxDescription) {
        "Description exceeds $MaxDescription character limit ($($description.Length) chars)"
    }
    if ($description -match '</?[A-Za-z][^<>]*>') {
        "Description must not contain XML-style tags (found '$($Matches[0])'). The name and description are injected into the agent's skill-metadata XML block; reword (e.g. 'of T') or use backticks."
    }
}

function Test-SkillCompatibility ($compatibility) {
    if ($compatibility -isnot [string]) {
        "Field 'compatibility' must be a string"
        return
    }
    if ($compatibility.Length -gt $MaxCompatibility) {
        "Compatibility exceeds $MaxCompatibility character limit ($($compatibility.Length) chars)"
    }
}

function Test-SkillDir ([string] $dir) {
    $errors = [System.Collections.Generic.List[string]]::new()

    $resolved = Resolve-Path -LiteralPath $dir -ErrorAction SilentlyContinue
    if (-not $resolved) { return @("Path does not exist: $dir") }
    $dir = $resolved.Path
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return @("Not a directory: $dir") }

    $md = Get-SkillMd $dir
    if (-not $md) { return @('Missing required file: SKILL.md') }

    $raw = Get-Content -LiteralPath $md -Raw
    try {
        $fm = Read-Frontmatter $raw
    }
    catch {
        return @($_.Exception.Message)
    }

    Test-FrontmatterColons $raw | ForEach-Object { $errors.Add($_) }

    $extra = @($fm.Keys | Where-Object { $_ -cnotin $AllowedFields })
    if ($extra.Count) {
        $errors.Add("Unexpected fields in frontmatter: $(($extra | Sort-Object) -join ', '). Only $(($AllowedFields | Sort-Object) -join ', ') are allowed.")
    }

    if (-not $fm.Contains('name')) { $errors.Add('Missing required field in frontmatter: name') }
    else { Test-SkillName $fm['name'] $dir | ForEach-Object { $errors.Add($_) } }

    if (-not $fm.Contains('description')) { $errors.Add('Missing required field in frontmatter: description') }
    else { Test-SkillDescription $fm['description'] | ForEach-Object { $errors.Add($_) } }

    if ($fm.Contains('compatibility')) { Test-SkillCompatibility $fm['compatibility'] | ForEach-Object { $errors.Add($_) } }

    $lineCount = Measure-SkillLineCount $raw
    if ($lineCount -gt $MaxSkillLines) {
        $errors.Add("SKILL.md is $lineCount lines; keep it under the recommended $MaxSkillLines-line limit (move detail into references/ or sibling files).")
    }

    return $errors.ToArray()
}

# ---------------------------------------------------------------------------

if (-not $Path -or $Path.Count -eq 0) {
    $Path = @('.')
}

$targets = [System.Collections.Generic.List[string]]::new()
foreach ($p in $Path) {
    if (Get-SkillMd $p) {
        $targets.Add((Resolve-Path -LiteralPath $p).Path)
    }
    elseif (Test-Path -LiteralPath $p -PathType Container) {
        Get-ChildItem -LiteralPath $p -Directory |
            Where-Object { Get-SkillMd $_.FullName } |
            ForEach-Object { $targets.Add($_.FullName) }
    }
    else {
        $targets.Add($p)
    }
}

$ordered = @($targets | Sort-Object -Unique)
if ($ordered.Count -eq 0) {
    Write-Host 'No skills found.' -ForegroundColor Yellow
    exit 1
}

$failed = 0
foreach ($t in $ordered) {
    $rel = [System.IO.Path]::GetRelativePath((Get-Location).Path, $t)
    $errs = @(Test-SkillDir $t)
    if ($errs.Count -eq 0) {
        if (-not $Quiet) { Write-Host "  OK    $rel" -ForegroundColor Green }
    }
    else {
        $failed++
        Write-Host "  FAIL  $rel" -ForegroundColor Red
        foreach ($e in $errs) { Write-Host "          - $e" -ForegroundColor Red }
    }
}

Write-Host ''
if ($failed -gt 0) {
    Write-Host "$failed of $($ordered.Count) skill(s) failed validation." -ForegroundColor Red
    exit 1
}
Write-Host "All $($ordered.Count) skill(s) valid." -ForegroundColor Green
exit 0
