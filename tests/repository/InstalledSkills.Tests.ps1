#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:SkillsRoot = Join-Path $script:RepoRoot 'skills'
    $script:ValidatorPath = Join-Path $script:SkillsRoot 'manage-skills/scripts/Validate-Skills.ps1'

    function Get-RequiredSkills ([string] $skillPath) {
        $content = Get-Content -LiteralPath $skillPath -Raw
        $match = [regex]::Match($content, '(?m)^\s+requires:\s*(?<value>[^\r\n]+)\r?$')
        if (-not $match.Success -or $match.Groups['value'].Value.Trim() -eq 'none') { return @() }
        return @($match.Groups['value'].Value -split ',' | ForEach-Object { $_.Trim() })
    }

    function Get-BrokenRelativeLinks ([string] $artifactRoot) {
        $broken = [System.Collections.Generic.List[string]]::new()
        $artifactFullPath = [System.IO.Path]::GetFullPath($artifactRoot)
        foreach ($markdownFile in (Get-ChildItem -LiteralPath $artifactRoot -Filter '*.md' -File -Recurse)) {
            $content = Get-Content -LiteralPath $markdownFile.FullName -Raw
            foreach ($match in [regex]::Matches($content, '\[[^\]]*\]\((?<target>[^)\s]+)(?:\s+"[^"]*")?\)')) {
                $target = $match.Groups['target'].Value
                if ($target -match '^(?:https?://|mailto:|#)') { continue }

                $pathPart = [uri]::UnescapeDataString(($target -split '#', 2)[0])
                if ([string]::IsNullOrWhiteSpace($pathPart)) { continue }
                $resolvedPath = [System.IO.Path]::GetFullPath((Join-Path $markdownFile.DirectoryName $pathPart))
                $relativeFile = [System.IO.Path]::GetRelativePath($artifactRoot, $markdownFile.FullName)
                if (-not $resolvedPath.StartsWith($artifactFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
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
    It 'installs every core with only declared requirements and keeps it self-contained' {
        Get-Command gh -ErrorAction Stop | Should -Not -BeNullOrEmpty
        & gh skill --help *> $null
        $LASTEXITCODE | Should -Be 0 -Because 'gh 2.90 or later with the skill command is required'

        foreach ($sourceDirectory in (Get-ChildItem -LiteralPath $script:SkillsRoot -Directory | Sort-Object Name)) {
            $skillPath = Join-Path $sourceDirectory.FullName 'SKILL.md'
            if (-not (Test-Path -LiteralPath $skillPath)) { continue }

            $installRoot = Join-Path $TestDrive $sourceDirectory.Name
            New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
            $installNames = @($sourceDirectory.Name) + @(Get-RequiredSkills $skillPath)
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