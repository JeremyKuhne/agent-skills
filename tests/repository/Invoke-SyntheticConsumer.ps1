#Requires -Version 7.2
[CmdletBinding()]
param(
    [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path,
    [string] $SourceRepository,
    [string] $Pin,
    [string] $OutputDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) "agent-skills-consumer-$([guid]::NewGuid().ToString('N'))"),
    [switch] $Keep
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($SourceRepository) -xor [string]::IsNullOrWhiteSpace($Pin)) {
    throw 'SourceRepository and Pin must be supplied together.'
}

function Get-PortfolioValue([string] $content, [string] $name) {
    $match = [regex]::Match($content, "(?m)^\s+$([regex]::Escape($name)):\s*(?<value>[^\r\n]+)\r?$")
    if (-not $match.Success) { throw "Portfolio field '$name' was not found." }
    return $match.Groups['value'].Value.Trim()
}

function Get-RelationshipNames([string] $value) {
    if ([string]::IsNullOrWhiteSpace($value) -or $value -eq 'none') { return @() }
    return @($value -split ',' | ForEach-Object { $_.Trim() })
}

function Get-BrokenRelativeLinks([string] $artifactRoot) {
    $broken = [System.Collections.Generic.List[string]]::new()
    $artifactFullPath = [System.IO.Path]::GetFullPath($artifactRoot)
    $artifactPrefix = $artifactFullPath.TrimEnd([char]'\', [char]'/') + [System.IO.Path]::DirectorySeparatorChar
    $pathComparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }

    foreach ($markdownFile in (Get-ChildItem -LiteralPath $artifactRoot -Filter '*.md' -File -Recurse)) {
        $content = Get-Content -LiteralPath $markdownFile.FullName -Raw
        foreach ($match in [regex]::Matches($content, '\[[^\]]*\]\((?<target>[^)\s]+)(?:\s+"[^"]*")?\)')) {
            $target = $match.Groups['target'].Value
            if ($target -match '^(?:https?://|mailto:|#)') { continue }

            $pathPart = [uri]::UnescapeDataString(($target -split '#', 2)[0])
            if ([string]::IsNullOrWhiteSpace($pathPart)) { continue }
            $resolvedPath = [System.IO.Path]::GetFullPath((Join-Path $markdownFile.DirectoryName $pathPart))
            $relativeFile = [System.IO.Path]::GetRelativePath($artifactRoot, $markdownFile.FullName)
            $isArtifactRoot = $resolvedPath.Equals($artifactFullPath, $pathComparison)
            $isInsideArtifact = $resolvedPath.StartsWith($artifactPrefix, $pathComparison)
            if (-not ($isArtifactRoot -or $isInsideArtifact)) {
                $broken.Add("$relativeFile -> $target (escapes consumer artifact)")
            }
            elseif (-not (Test-Path -LiteralPath $resolvedPath)) {
                $broken.Add("$relativeFile -> $target")
            }
        }
    }

    return $broken.ToArray()
}

$resolvedRepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$skillsRoot = Join-Path $resolvedRepoRoot 'skills'
$validatorPath = Join-Path $skillsRoot 'manage-skills/scripts/Validate-Skills.ps1'
$gitPath = [string]@(Get-Command git -CommandType Application -All -ErrorAction Stop)[0].Source
Get-Command gh -ErrorAction Stop | Out-Null

$initialStatus = (& $gitPath -C $resolvedRepoRoot status --porcelain=v1 --untracked-files=all 2>&1) -join "`n"
if ($LASTEXITCODE -ne 0) { throw "Could not read source worktree status:`n$initialStatus" }

$sourceRecords = @(Get-ChildItem -LiteralPath $skillsRoot -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') } |
    Sort-Object Name |
    ForEach-Object {
        $content = Get-Content -LiteralPath (Join-Path $_.FullName 'SKILL.md') -Raw
        [pscustomobject]@{
            Name = $_.Name
            Binding = Get-PortfolioValue $content 'binding'
            Requires = @(Get-RelationshipNames (Get-PortfolioValue $content 'requires'))
        }
    })
if ($sourceRecords.Count -eq 0) { throw 'No source skills were found.' }

$outputDirectoryCreated = $false
try {
    if (Test-Path -LiteralPath $OutputDirectory) {
        throw "Output directory already exists; choose a new path: $OutputDirectory"
    }
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    $outputDirectoryCreated = $true

    $consumerRoot = Join-Path $OutputDirectory 'consumer'
    $installRoot = Join-Path $consumerRoot '.agents/skills'
    New-Item -ItemType Directory -Path $installRoot -Force | Out-Null

    foreach ($record in $sourceRecords) {
        $installOutput = if ($SourceRepository) {
            & gh skill install $SourceRepository "skills/$($record.Name)" --pin $Pin --dir $installRoot --agent github-copilot --force 2>&1
        }
        else {
            & gh skill install $resolvedRepoRoot $record.Name --from-local --dir $installRoot --agent github-copilot --force 2>&1
        }
        if ($LASTEXITCODE -ne 0) {
            throw "Could not install '$($record.Name)':`n$($installOutput -join "`n")"
        }
    }

    $installedNames = @(Get-ChildItem -LiteralPath $installRoot -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') } |
        ForEach-Object Name |
        Sort-Object)
    $sourceNames = @($sourceRecords.Name | Sort-Object)
    $inventoryDifference = @(Compare-Object $sourceNames $installedNames)
    if ($inventoryDifference.Count -gt 0) {
        throw "Installed skill inventory differs from source: $($inventoryDifference | Out-String)"
    }

    foreach ($record in $sourceRecords) {
        foreach ($requiredName in $record.Requires) {
            if ($requiredName -notin $installedNames) {
                throw "Installed '$($record.Name)' is missing required skill '$requiredName'."
            }
        }

        $installedDirectory = Join-Path $installRoot $record.Name
        $installedContent = Get-Content -LiteralPath (Join-Path $installedDirectory 'SKILL.md') -Raw
        if ($SourceRepository) {
            $pinPattern = "(?m)^\s+github-pinned:\s*$([regex]::Escape($Pin))\r?$"
            if ($installedContent -notmatch $pinPattern) {
                throw "Installed '$($record.Name)' does not record pin '$Pin'."
            }
            if ($installedContent -notmatch '(?m)^\s+github-tree-sha:\s*[0-9a-f]{40}\r?$') {
                throw "Installed '$($record.Name)' does not record a source tree SHA."
            }
        }
        elseif ($installedContent -notmatch '(?m)^\s+local-path:\s*\S.*\r?$') {
            throw "Installed '$($record.Name)' does not record its local source path."
        }

        if ($record.Binding -in @('optional-overlay', 'required-overlay')) {
            $overlayPin = if ($SourceRepository) { $Pin } else { 'local-candidate' }
            $overlay = @(
                '---'
                "core: $($record.Name)"
                "core-pin: $overlayPin"
                '---'
                ''
                '# Synthetic consumer binding'
                ''
                'This overlay is generated only for the disposable consumer canary.'
                ''
            )
            Set-Content -LiteralPath (Join-Path $installedDirectory 'overlay.md') -Value $overlay
        }
    }

    $catalogLines = [System.Collections.Generic.List[string]]::new()
    $catalogLines.Add('# Synthetic consumer skills')
    $catalogLines.Add('')
    $catalogLines.Add('| Skill | Requires |')
    $catalogLines.Add('| --- | --- |')
    foreach ($record in $sourceRecords) {
        $requires = if ($record.Requires.Count -eq 0) { '-' } else { $record.Requires -join ', ' }
        $catalogLines.Add("| [$($record.Name)](./$($record.Name)/SKILL.md) | $requires |")
    }
    Set-Content -LiteralPath (Join-Path $installRoot 'README.md') -Value $catalogLines

    $validatorOutput = & pwsh -NoProfile -File $validatorPath $installRoot -RequirePortfolioMetadata -Quiet 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Installed portfolio validation failed:`n$($validatorOutput -join "`n")" }

    foreach ($record in $sourceRecords) {
        $referenceOutput = & npx --yes skills-ref@0.1.5 validate (Join-Path $installRoot $record.Name) 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "skills-ref rejected installed '$($record.Name)':`n$($referenceOutput -join "`n")"
        }
    }

    $brokenLinks = @(Get-BrokenRelativeLinks $installRoot)
    if ($brokenLinks.Count -gt 0) {
        throw "Synthetic consumer has broken or escaping links:`n$($brokenLinks -join "`n")"
    }

    $finalStatus = (& $gitPath -C $resolvedRepoRoot status --porcelain=v1 --untracked-files=all 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "Could not re-read source worktree status:`n$finalStatus" }
    if ($initialStatus -cne $finalStatus) {
        throw "Synthetic consumer changed the source worktree.`nBefore:`n$initialStatus`nAfter:`n$finalStatus"
    }

    $mode = if ($SourceRepository) { "$SourceRepository@$Pin" } else { 'local candidate' }
    $summary = [pscustomobject]@{
        Mode = $mode
        Skills = $installedNames.Count
        Overlays = @(Get-ChildItem -LiteralPath $installRoot -Filter 'overlay.md' -File -Recurse).Count
        BrokenLinks = $brokenLinks.Count
        SourceWorktreeUnchanged = $true
    }
    $summary | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory 'summary.json')
    Write-Host "Synthetic consumer passed: $($summary.Skills) skills, $($summary.Overlays) overlays, $mode."
    return $summary
}
finally {
    if (-not $Keep -and $outputDirectoryCreated) {
        Remove-Item -LiteralPath $OutputDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}