#Requires -Version 7.0

function Get-GeneratedSkillProvenanceFieldNames {
    return @(
        'github-path',
        'github-pinned',
        'github-ref',
        'github-repo',
        'github-tree-sha',
        'local-path')
}

function Get-SkillArtifactDocument([string] $SkillPath) {
    $content = [System.IO.File]::ReadAllText($SkillPath).Replace("`r`n", "`n")
    $match = [regex]::Match(
        $content,
        '(?s)\A---\n(?<frontmatter>.*?)\n---(?<body>\n.*|\z)')
    if (-not $match.Success) {
        throw "Could not parse frontmatter from '$SkillPath'."
    }
    return [pscustomobject]@{
        Frontmatter = $match.Groups['frontmatter'].Value
        Body = $match.Groups['body'].Value.TrimStart("`n")
    }
}

function ConvertFrom-SkillArtifactScalar([string] $Value) {
    $trimmed = $Value.Trim()
    if ($trimmed.Length -ge 2 -and
        $trimmed.StartsWith("'") -and $trimmed.EndsWith("'")) {
        return $trimmed.Substring(1, $trimmed.Length - 2).Replace("''", "'")
    }
    if ($trimmed.Length -ge 2 -and
        $trimmed.StartsWith('"') -and $trimmed.EndsWith('"')) {
        return $trimmed | ConvertFrom-Json
    }
    return $trimmed
}

function Read-SkillArtifactFrontmatter([string] $SkillPath) {
    $document = Get-SkillArtifactDocument $SkillPath
    $topLevel = [ordered]@{}
    $metadata = [ordered]@{}
    $insideMetadata = $false
    foreach ($line in ($document.Frontmatter -split "`n")) {
        if ([string]::IsNullOrWhiteSpace($line) -or
            $line.TrimStart().StartsWith('#')) {
            continue
        }
        if ($line -match '^(?<key>[a-z][a-z-]*):\s*(?<value>.*)$') {
            $insideMetadata = $Matches.key -ceq 'metadata'
            if (-not $insideMetadata) {
                $topLevel[$Matches.key] = ConvertFrom-SkillArtifactScalar $Matches.value
            }
            continue
        }
        if ($insideMetadata -and
            $line -match '^\s+(?<key>[a-z][a-z-]*):\s*(?<value>.*)$') {
            $metadata[$Matches.key] = ConvertFrom-SkillArtifactScalar $Matches.value
            continue
        }
        throw "Unsupported frontmatter shape in '$SkillPath': $line"
    }
    return [pscustomobject]@{
        TopLevel = $topLevel
        Metadata = $metadata
    }
}

function Get-SkillArtifactCanonicalFrontmatter([string] $SkillPath) {
    $generatedFields = @(Get-GeneratedSkillProvenanceFieldNames)
    $frontmatter = Read-SkillArtifactFrontmatter $SkillPath
    $entries = [System.Collections.Generic.List[string]]::new()
    foreach ($key in $frontmatter.TopLevel.Keys) {
        $entries.Add("top:$key=$($frontmatter.TopLevel[$key])")
    }
    foreach ($key in $frontmatter.Metadata.Keys) {
        if ($key -notin $generatedFields) {
            $entries.Add("metadata:$key=$($frontmatter.Metadata[$key])")
        }
    }
    return @($entries | Sort-Object)
}

function Get-SkillArtifactProvenance([string] $SkillPath) {
    $generatedFields = @(Get-GeneratedSkillProvenanceFieldNames)
    $metadata = (Read-SkillArtifactFrontmatter $SkillPath).Metadata
    $provenance = [ordered]@{}
    foreach ($key in $metadata.Keys) {
        if ($key -in $generatedFields) {
            $provenance[$key] = $metadata[$key]
        }
    }
    return $provenance
}

function Get-SkillArtifactPrivacyContent([string] $SkillDirectory) {
    $document = Get-SkillArtifactDocument (Join-Path $SkillDirectory 'SKILL.md')
    return @(
        $document.Body
        Get-ChildItem -LiteralPath $SkillDirectory -File -Recurse |
            Where-Object Name -ne 'SKILL.md' |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }
    ) -join "`n"
}

function Get-SkillArtifactMirrorDifferences(
    [string] $SourceDirectory,
    [string] $InstalledDirectory,
    [string[]] $AllowedInstalledFile = @()) {
    $sourceRoot = (Resolve-Path -LiteralPath $SourceDirectory).Path
    $installedRoot = (Resolve-Path -LiteralPath $InstalledDirectory).Path
    $differences = [System.Collections.Generic.List[string]]::new()
    $sourceFiles = @(Get-ChildItem -LiteralPath $sourceRoot -File -Recurse)
    $sourceManifest = @($sourceFiles | ForEach-Object {
            [System.IO.Path]::GetRelativePath(
                $sourceRoot,
                $_.FullName).Replace('\', '/')
        } | Sort-Object)
    $expectedManifest = @(($sourceManifest + @($AllowedInstalledFile)) |
        Sort-Object -Unique)
    $installedManifest = @(Get-ChildItem -LiteralPath $installedRoot -File -Recurse |
        ForEach-Object {
            [System.IO.Path]::GetRelativePath(
                $installedRoot,
                $_.FullName).Replace('\', '/')
        } | Sort-Object)
    foreach ($difference in @(Compare-Object $expectedManifest $installedManifest)) {
        $direction = if ($difference.SideIndicator -eq '=>') {
            'unexpected'
        }
        else { 'missing' }
        $differences.Add("[manifest] $direction '$($difference.InputObject)'")
    }

    foreach ($sourceFile in $sourceFiles) {
        $relativePath = [System.IO.Path]::GetRelativePath(
            $sourceRoot,
            $sourceFile.FullName).Replace('\', '/')
        $installedPath = Join-Path $installedRoot $relativePath
        if (-not (Test-Path -LiteralPath $installedPath -PathType Leaf)) {
            continue
        }
        if ($relativePath -ceq 'SKILL.md') {
            $sourceFrontmatter = @(
                Get-SkillArtifactCanonicalFrontmatter $sourceFile.FullName)
            $installedFrontmatter = @(
                Get-SkillArtifactCanonicalFrontmatter $installedPath)
            foreach ($difference in @(
                    Compare-Object $sourceFrontmatter $installedFrontmatter)) {
                $differences.Add(
                    "[frontmatter] $($difference.SideIndicator) '$($difference.InputObject)'")
            }
            if ((Get-SkillArtifactDocument $sourceFile.FullName).Body -cne
                (Get-SkillArtifactDocument $installedPath).Body) {
                $differences.Add('[body] SKILL.md body differs from source')
            }
            continue
        }
        if ((Get-FileHash -LiteralPath $sourceFile.FullName -Algorithm SHA256).Hash -cne
            (Get-FileHash -LiteralPath $installedPath -Algorithm SHA256).Hash) {
            $differences.Add("[resource] '$relativePath' differs from source")
        }
    }
    return $differences.ToArray()
}