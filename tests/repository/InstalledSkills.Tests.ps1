#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:SkillsRoot = Join-Path $script:RepoRoot 'skills'
    $script:ValidatorPath = Join-Path $script:SkillsRoot 'manage-skills/scripts/Validate-Skills.ps1'

    function Get-DirectRequiredSkills ([string] $skillPath) {
        $content = Get-Content -LiteralPath $skillPath -Raw
        $match = [regex]::Match($content, '(?m)^\s+requires:\s*(?<value>[^\r\n]+)\r?$')
        if (-not $match.Success -or $match.Groups['value'].Value.Trim() -eq 'none') { return @() }
        return @($match.Groups['value'].Value -split ',' | ForEach-Object { $_.Trim() })
    }

    function Get-RequiredSkillClosure ([string] $skillName, [string] $skillsRoot) {
        $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

        function Add-Requirements ([string] $currentSkillName) {
            $skillPath = Join-Path $skillsRoot "$currentSkillName/SKILL.md"
            if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) {
                throw "Required skill '$currentSkillName' does not exist under $skillsRoot."
            }
            foreach ($requiredName in (Get-DirectRequiredSkills $skillPath)) {
                if ($visited.Add($requiredName)) {
                    Add-Requirements $requiredName
                }
            }
        }

        Add-Requirements $skillName
        return @($visited)
    }

    function Get-BrokenRelativeLinks ([string] $artifactRoot) {
        $broken = [System.Collections.Generic.List[string]]::new()
        $artifactFullPath = [System.IO.Path]::GetFullPath($artifactRoot)
        $artifactPrefix = $artifactFullPath.TrimEnd([char]'\', [char]'/') + [System.IO.Path]::DirectorySeparatorChar
        $pathComparison = if ($IsWindows) {
            [System.StringComparison]::OrdinalIgnoreCase
        }
        else {
            [System.StringComparison]::Ordinal
        }
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
                    $broken.Add("$relativeFile -> $target (escapes installed artifact)")
                }
                elseif (-not (Test-Path -LiteralPath $resolvedPath)) {
                    $broken.Add("$relativeFile -> $target")
                }
            }
        }
        return $broken.ToArray()
    }
}

Describe 'Installed skill artifacts' {
    It 'expands the complete transitive required-skill closure' {
        $skillsRoot = Join-Path $TestDrive 'required-skills'
        foreach ($skill in @(
                @{ Name = 'root'; Requires = 'middle' }
                @{ Name = 'middle'; Requires = 'leaf' }
                @{ Name = 'leaf'; Requires = 'none' }
            )) {
            $skillDirectory = Join-Path $skillsRoot $skill.Name
            New-Item -ItemType Directory -Path $skillDirectory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $skillDirectory 'SKILL.md') -NoNewline -Value "---`nname: $($skill.Name)`ndescription: Fixture.`nmetadata:`n  requires: $($skill.Requires)`n---`n"
        }

        @(Get-RequiredSkillClosure 'root' $skillsRoot | Sort-Object) |
            Should -Be @('leaf', 'middle')
    }

    It 'rejects a sibling path that only shares the artifact-root prefix' {
        $artifactRoot = Join-Path $TestDrive 'artifact'
        $siblingRoot = Join-Path $TestDrive 'artifact-sibling'
        New-Item -ItemType Directory -Path $artifactRoot, $siblingRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $artifactRoot 'SKILL.md') -NoNewline -Value '[escape](../artifact-sibling/target.md)'
        Set-Content -LiteralPath (Join-Path $siblingRoot 'target.md') -NoNewline -Value '# Existing target'

        $brokenLinks = @(Get-BrokenRelativeLinks $artifactRoot)
        $brokenLinks.Count | Should -Be 1
        $brokenLinks[0] | Should -Match 'escapes installed artifact'
    }

    It 'rejects a differently-cased sibling on a case-sensitive file system' -Skip:$IsWindows {
        $artifactRoot = Join-Path $TestDrive 'artifact'
        $siblingRoot = Join-Path $TestDrive 'Artifact'
        New-Item -ItemType Directory -Path $artifactRoot, $siblingRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $artifactRoot 'SKILL.md') -NoNewline -Value '[escape](../Artifact/target.md)'
        Set-Content -LiteralPath (Join-Path $siblingRoot 'target.md') -NoNewline -Value '# Existing target'

        $brokenLinks = @(Get-BrokenRelativeLinks $artifactRoot)
        $brokenLinks.Count | Should -Be 1
        $brokenLinks[0] | Should -Match 'escapes installed artifact'
    }

    It 'installs every core with only declared requirements and keeps it self-contained' {
        Get-Command gh -ErrorAction Stop | Should -Not -BeNullOrEmpty
        & gh skill --help *> $null
        $LASTEXITCODE | Should -Be 0 -Because 'gh 2.90 or later with the skill command is required'

        foreach ($sourceDirectory in (Get-ChildItem -LiteralPath $script:SkillsRoot -Directory | Sort-Object Name)) {
            $skillPath = Join-Path $sourceDirectory.FullName 'SKILL.md'
            if (-not (Test-Path -LiteralPath $skillPath)) { continue }

            $installRoot = Join-Path $TestDrive $sourceDirectory.Name
            New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
            $installNames = @($sourceDirectory.Name) + @(Get-RequiredSkillClosure $sourceDirectory.Name $script:SkillsRoot)
            foreach ($installName in ($installNames | Sort-Object -Unique)) {
                & gh skill install $script:RepoRoot $installName --from-local --dir $installRoot --agent github-copilot --force *> $null
                $LASTEXITCODE | Should -Be 0 -Because "$($sourceDirectory.Name) must install with declared requirement '$installName'"
            }

            $installedPrimary = Join-Path $installRoot $sourceDirectory.Name
            foreach ($sourceFile in (Get-ChildItem $sourceDirectory.FullName -File -Recurse)) {
                $relativePath = [System.IO.Path]::GetRelativePath($sourceDirectory.FullName, $sourceFile.FullName)
                Test-Path -LiteralPath (Join-Path $installedPrimary $relativePath) |
                    Should -BeTrue -Because "$($sourceDirectory.Name) install must include $relativePath"
            }

            $validatorOutput = & pwsh -NoProfile -File $script:ValidatorPath $installRoot -RequirePortfolioMetadata -Quiet 2>&1
            $LASTEXITCODE | Should -Be 0 -Because "$($sourceDirectory.Name) installed metadata must be valid: $validatorOutput"

            $brokenLinks = @(Get-BrokenRelativeLinks $installRoot)
            $brokenLinks.Count | Should -Be 0 -Because "$($sourceDirectory.Name) has artifact-external or missing links: $($brokenLinks -join '; ')"
        }
    }
}