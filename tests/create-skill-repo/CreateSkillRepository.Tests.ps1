#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:Scaffold = Join-Path $script:RepoRoot (
        '.agents/skills/create-skill-repo/scripts/New-SkillRepository.ps1')
    $script:Decisions = Join-Path $script:RepoRoot (
        '.agents/skills/create-skill-repo/decisions.md')
}

Describe 'Decision interview' {
    It 'explains repository roles to a first-time skill user' {
        $content = Get-Content -LiteralPath $script:Decisions -Raw

        $content | Should -Match 'A skill is a directory of instructions'
        $content | Should -Match 'original, editable skill directories'
        $content | Should -Match 'pinned copy records a specific version'
        $content | Should -Match 'process is called vendoring'
        $content | Should -Match 'does not publish anything remotely'
        $content | Should -Match 'Author and share skills \(source\)'
        $content | Should -Match 'Use existing skills \(consumer\)'
        $content | Should -Match 'Do both \(hybrid'
    }

    It 'offers a computed sibling destination before custom path entry' {
        $content = Get-Content -LiteralPath $script:Decisions -Raw

        $content.IndexOf('## 2. Name and intended use') |
            Should -BeLessThan $content.IndexOf('## 3. Destination')
        $content | Should -Match 'current repository''s parent'
        $content | Should -Match 'N:\\repos\\team-skills.*recommended'
        $content | Should -Match 'Choose another folder'
        $content | Should -Match 'Do not lead with "Enter an absolute path\."'
    }

    It 'explains how upstream order affects future skill discovery' {
        $content = Get-Content -LiteralPath $script:Decisions -Raw

        $content | Should -Match 'does not search for or install anything during'
        $content | Should -Match 'find, add, or update a skill'
        $content | Should -Match 'Search each configured repository or catalog in the saved order'
        $content | Should -Match '(?s)does not.*automatically choose the first name match'
        $content | Should -Match 'Use the recommended search order'
        $content | Should -Match 'Customize where skills are found'
        $content | Should -Match 'Do not expose a private source URL in public output'
    }
}

Describe 'New-SkillRepository' {
    It 'creates a minimal local-only source without remote guidance' {
        $root = Join-Path $TestDrive 'minimal source'

        & $script:Scaffold -Root $root -Name local-skills `
            -Description 'Local skills.' -Role source -Infrastructure minimal `
            -Visibility local -Audience person -License none -SkipGit

        Test-Path (Join-Path $root 'skills/README.md') | Should -BeTrue
        Test-Path (Join-Path $root '.agents') | Should -BeFalse
        Test-Path (Join-Path $root 'LICENSE') | Should -BeFalse
        Test-Path (Join-Path $root 'REMOTE-SETUP.md') | Should -BeFalse
        Test-Path (Join-Path $root 'tools') | Should -BeFalse
        $readme = Get-Content -LiteralPath (Join-Path $root 'README.md') -Raw
        $readme | Should -Match 'local-only'
        $readme | Should -Not -Match 'github\.com|gh skill install'
        $readme | Should -Not -Match '(?m)^## (?:Validate|Continuous integration|Distribution)$'
    }

    It 'creates and self-validates a hybrid repository from a path with spaces' {
        $root = Join-Path $TestDrive 'validated hybrid repo'

        & $script:Scaffold -Root $root -Name validated-skills `
            -Description 'Validated skills.' -Role hybrid `
            -Infrastructure validated -Visibility local -Audience team `
            -Owner Example -SkipGit

        Test-Path (Join-Path $root 'skills/README.md') | Should -BeTrue
        Test-Path (Join-Path $root '.agents/skills/README.md') | Should -BeTrue
        { & (Join-Path $root 'tools/Validate-Repository.ps1') } |
            Should -Not -Throw
    }

    It 'adds Team CI without unselected distribution manifests' {
        $root = Join-Path $TestDrive 'private consumer'

        & $script:Scaffold -Root $root -Name private-skills `
            -Description 'Private runtime skills.' -Role consumer `
            -Infrastructure team-ci -Visibility private -Audience organization `
            -Owner Example -SkipGit

        Test-Path (Join-Path $root '.github/workflows/skills.yml') | Should -BeTrue
        Test-Path (Join-Path $root '.github/workflows/skill-drift.yml') | Should -BeTrue
        Test-Path (Join-Path $root 'REMOTE-SETUP.md') | Should -BeTrue
        Test-Path (Join-Path $root 'plugin.json') | Should -BeFalse
        Test-Path (Join-Path $root '.mcp.json') | Should -BeFalse
        Get-Content (Join-Path $root 'README.md') -Raw |
            Should -Match 'github\.com/Example/private-skills.*private'
    }

    It 'adds only selected distribution surfaces and evaluations' {
        $root = Join-Path $TestDrive 'distribution source'

        & $script:Scaffold -Root $root -Name public-skills `
            -Description 'Public "agent" skills.' -Role source `
            -Infrastructure distribution -Visibility public -Audience public `
            -Owner Example `
            -DistributionSurfaces direct,plugin,marketplace,agents,mcp `
            -IncludeEvaluations `
            -SkipGit

        Test-Path (Join-Path $root 'plugin.json') | Should -BeTrue
        Test-Path (Join-Path $root '.github/workflows/release.yml') | Should -BeTrue
        Test-Path (Join-Path $root '.github/plugin/marketplace.json') | Should -BeTrue
        Test-Path (Join-Path $root 'agents') | Should -BeTrue
        Test-Path (Join-Path $root '.mcp.json') | Should -BeTrue
        Test-Path (Join-Path $root 'evals/scenarios/repository.json') | Should -BeTrue

        $plugin = Get-Content (Join-Path $root 'plugin.json') -Raw | ConvertFrom-Json
        $marketplace = Get-Content (
            Join-Path $root '.github/plugin/marketplace.json') -Raw | ConvertFrom-Json
        $mcp = Get-Content (Join-Path $root '.mcp.json') -Raw | ConvertFrom-Json
        $plugin.description | Should -Be 'Public "agent" skills.'
        $plugin.agents | Should -Be 'agents/'
        $plugin.mcpServers | Should -Be '.mcp.json'
        $marketplace.plugins[0].version | Should -Be $plugin.version
        $mcp.PSObject.Properties.Name | Should -Contain 'mcpServers'

        foreach ($workflow in Get-ChildItem (
                Join-Path $root '.github/workflows') -Filter '*.yml') {
            foreach ($line in Get-Content $workflow.FullName |
                Where-Object { $_ -match '\buses:' }) {
                $line | Should -Match '@[0-9a-f]{40}\s+#\s+v\d'
            }
        }
        { & (Join-Path $root 'tools/Validate-Repository.ps1') } |
            Should -Not -Throw
        $generatedTests = Invoke-Pester (Join-Path $root 'tests') -PassThru
        $generatedTests.FailedCount | Should -Be 0
        { & (Join-Path $root 'tests/Invoke-PluginSmoke.ps1') } |
            Should -Not -Throw
    }

    It 'creates only the documented Claude runtime root for Claude-only consumers' {
        $root = Join-Path $TestDrive 'claude consumer'

        & $script:Scaffold -Root $root -Name claude-skills `
            -Description 'Claude runtime skills.' -Role consumer `
            -Infrastructure validated -Visibility local -Audience person `
            -Clients claude-code -SkipGit

        Test-Path (Join-Path $root '.claude/skills/README.md') | Should -BeTrue
        Test-Path (Join-Path $root '.agents') | Should -BeFalse
        { & (Join-Path $root 'tools/Validate-Repository.ps1') } |
            Should -Not -Throw
    }

    It 'rejects relative links that escape the generated repository' {
        $root = Join-Path $TestDrive 'link boundary'
        $outside = Join-Path $TestDrive 'outside.md'
        Set-Content -LiteralPath $outside -Value '# Outside'

        & $script:Scaffold -Root $root -Name bounded-skills `
            -Description 'Bounded skills.' -Role source `
            -Infrastructure validated -Visibility local -Audience person `
            -SkipGit
        Set-Content -LiteralPath (Join-Path $root 'escape.md') `
            -Value '[Outside](../outside.md)'

        { & (Join-Path $root 'tools/Test-SkillLinks.ps1') } |
            Should -Throw '*relative link escapes the repository*'
    }

    It 'vendors an explicit closure to every selected runtime root with overlays' {
        $root = Join-Path $TestDrive 'multi-client skills'
        $global:CreateSkillRepoSourceRoot = $script:RepoRoot
        function global:gh {
            if ($args[0] -eq 'skill' -and $args[1] -eq '--help') { return }
            if ($args[0] -ne 'skill' -or $args[1] -ne 'install') {
                throw "Unexpected fake gh arguments: $args"
            }
            $skill = $args[3]
            $directoryIndex = [Array]::IndexOf($args, '--dir')
            $destination = $args[$directoryIndex + 1]
            Copy-Item `
                -LiteralPath (Join-Path $global:CreateSkillRepoSourceRoot "skills/$skill") `
                -Destination (Join-Path $destination $skill) `
                -Recurse
        }

        try {
            & $script:Scaffold -Root $root -Name multi-client-skills `
                -Description 'Multi-client runtime skills.' -Role hybrid `
                -Infrastructure minimal -Visibility private -Audience organization `
                -Owner Example -Clients github-copilot,claude-code `
                -SelectedSkills manage-skills `
                -ResolvedSkills manage-skills,agent-files-review,technical-writing `
                -SkillsRef v0.15.0 `
                -UpstreamSources 'local installations','Contoso/InternalSkills','JeremyKuhne/agent-skills' `
                -PrivateUpstreamSources 'Contoso/InternalSkills' -SkipGit
        } finally {
            Remove-Item Function:\gh -ErrorAction SilentlyContinue
            Remove-Variable CreateSkillRepoSourceRoot -Scope Global -ErrorAction SilentlyContinue
        }

        foreach ($runtimeRoot in @('.agents/skills', '.claude/skills')) {
            foreach ($skill in @('manage-skills', 'agent-files-review', 'technical-writing')) {
                Test-Path (Join-Path $root "$runtimeRoot/$skill/SKILL.md") |
                    Should -BeTrue
            }
            $overlay = Get-Content (
                Join-Path $root "$runtimeRoot/manage-skills/overlay.md") -Raw
            $overlay | Should -Match 'core-pin: v0\.15\.0'
            $overlay | Should -Match 'Contoso/InternalSkills \(private source\)'
            $overlay.IndexOf('Contoso/InternalSkills') |
                Should -BeLessThan $overlay.IndexOf('JeremyKuhne/agent-skills')
        }
        Test-Path (Join-Path $root 'PENDING-SKILL-INSTALLS.md') | Should -BeFalse
        Test-Path (Join-Path $root 'PENDING-MANAGE-SKILLS-OVERLAY.md') |
            Should -BeFalse
        $readme = Get-Content (Join-Path $root 'README.md') -Raw
        $readme | Should -Match 'Authenticated readers with repository access'
        $readme | Should -Match '(?s)```pwsh\r?\ngh auth status\r?\ngh skill install'
        $readme | Should -Match '\| `github-copilot` \| `\.agents/skills/` \|'
        $readme | Should -Match '\| `claude-code` \| `\.claude/skills/` \|'
        $readme | Should -Match '\| `manage-skills` \| direct \| `v0\.15\.0` \|'
        $readme | Should -Match '\| `technical-writing` \| dependency \| `v0\.15\.0` \|'
        $readme | Should -Not -Match '\$_|\$SkillsRef|\$\(Get-ClientRoot'
    }

    It 'rejects private upstream disclosure and missing licenses for public output' {
        $privateRoot = Join-Path $TestDrive 'public private upstream'
        $unlicensedRoot = Join-Path $TestDrive 'public unlicensed'

        {
            & $script:Scaffold -Root $privateRoot -Name public-private `
                -Description 'Public skills.' -Role source -Infrastructure minimal `
                -Visibility public -Audience public -Owner Example `
                -UpstreamSources 'Contoso/InternalSkills','JeremyKuhne/agent-skills' `
                -PrivateUpstreamSources 'Contoso/InternalSkills' -SkipGit
        } | Should -Throw '*Private upstream sources cannot be written into a public scaffold*'
        Test-Path $privateRoot | Should -BeFalse

        {
            & $script:Scaffold -Root $unlicensedRoot -Name public-unlicensed `
                -Description 'Public skills.' -Role source -Infrastructure minimal `
                -Visibility public -Audience public -Owner Example -License none `
                -SkipGit
        } | Should -Throw '*public scaffold requires a license*'
        Test-Path $unlicensedRoot | Should -BeFalse
    }

    It 'records exact pending install commands as valid Markdown' {
        $root = Join-Path $TestDrive 'pending installs'
        $shimRoot = Join-Path $TestDrive 'gh shim'
        New-Item -ItemType Directory -Path $shimRoot | Out-Null
        if ($IsWindows) {
            Set-Content -LiteralPath (Join-Path $shimRoot 'gh.cmd') -Value @'
@echo off
if "%1 %2"=="skill --help" exit /b 0
exit /b 1
'@
        } else {
            $shimPath = Join-Path $shimRoot 'gh'
            Set-Content -LiteralPath $shimPath -Value @'
#!/usr/bin/env sh
if [ "$1 $2" = "skill --help" ]; then exit 0; fi
exit 1
'@
            & chmod +x $shimPath
        }
        $oldPath = $env:PATH
        try {
            $env:PATH = "$shimRoot;$oldPath"
            & $script:Scaffold -Root $root -Name pending-skills `
                -Description 'Pending skills.' -Role consumer `
                -Infrastructure validated -Visibility local -Audience person `
                -Clients github-copilot,claude-code `
                -SelectedSkills manage-skills `
                -ResolvedSkills manage-skills,agent-files-review,technical-writing `
                -SkillsRef v0.15.0 `
                -UpstreamSources 'local installations','Contoso/InternalSkills','JeremyKuhne/agent-skills' `
                -PrivateUpstreamSources 'Contoso/InternalSkills' -SkipGit
        } finally {
            $env:PATH = $oldPath
        }

        $pending = Get-Content (Join-Path $root 'PENDING-SKILL-INSTALLS.md') -Raw
        $pending | Should -Match '(?s)```pwsh\r?\ngh skill install.*--force\r?\n```'
        $pendingOverlay = Get-Content (
            Join-Path $root 'PENDING-MANAGE-SKILLS-OVERLAY.md') -Raw
        $pendingOverlay | Should -Match '`\.agents/skills/manage-skills/overlay\.md`'
        $pendingOverlay | Should -Match '`\.claude/skills/manage-skills/overlay\.md`'
        $pendingOverlay | Should -Match 'Contoso/InternalSkills \(private source\)'
        $pendingOverlay | Should -Match '(?s)```markdown\r?\n---\r?\ncore: manage-skills'
        { & (Join-Path $root 'tools/Validate-Repository.ps1') } |
            Should -Not -Throw
        $generatedTests = Invoke-Pester (Join-Path $root 'tests') -PassThru
        $generatedTests.FailedCount | Should -Be 0
    }

    It 'rejects infrastructure combinations that cannot provide their contract' {
        $consumerDistribution = Join-Path $TestDrive 'consumer distribution'
        $lowTierEvaluations = Join-Path $TestDrive 'low tier evaluations'

        {
            & $script:Scaffold -Root $consumerDistribution `
                -Name consumer-distribution -Description 'Consumer.' `
                -Role consumer -Infrastructure distribution -Visibility private `
                -Audience team -Owner Example -SkipGit
        } | Should -Throw '*Distribution infrastructure requires a source or hybrid*'
        Test-Path $consumerDistribution | Should -BeFalse

        {
            & $script:Scaffold -Root $lowTierEvaluations `
                -Name low-evals -Description 'Low evaluations.' `
                -Role source -Infrastructure validated -Visibility local `
                -Audience person -IncludeEvaluations -SkipGit
        } | Should -Throw '*evaluations require Team CI or Distribution*'
        Test-Path $lowTierEvaluations | Should -BeFalse
    }

    It 'rejects a non-empty destination without changing it' {
        $root = Join-Path $TestDrive 'occupied'
        New-Item -ItemType Directory -Path $root | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'keep.txt') -Value 'keep'

        {
            & $script:Scaffold -Root $root -Name occupied `
                -Description 'Occupied.' -Role source -Infrastructure minimal `
                -Visibility local -SkipGit
        } | Should -Throw '*not empty*'

        Get-Content -LiteralPath (Join-Path $root 'keep.txt') | Should -Be 'keep'
        @(Get-ChildItem -LiteralPath $root -Force).Count | Should -Be 1
    }

    It 'requires an immutable pin and complete declared closure' {
        $missingClosure = Join-Path $TestDrive 'missing closure'
        $missingPin = Join-Path $TestDrive 'missing pin'
        $missingDependency = Join-Path $TestDrive 'missing dependency'

        {
            & $script:Scaffold -Root $missingClosure -Name missing-closure `
                -Description 'Missing closure.' -Role consumer `
                -Infrastructure minimal -Visibility local `
                -SelectedSkills manage-skills -SkipGit
        } | Should -Throw '*ResolvedSkills*complete transitive requirement closure*'
        Test-Path $missingClosure | Should -BeFalse

        {
            & $script:Scaffold -Root $missingPin -Name missing-pin `
                -Description 'Missing pin.' -Role consumer `
                -Infrastructure minimal -Visibility local `
                -SelectedSkills manage-skills `
                -ResolvedSkills manage-skills,agent-files-review,technical-writing `
                -SkipGit
        } | Should -Throw '*SkillsRef*'
        Test-Path $missingPin | Should -BeFalse

        {
            & $script:Scaffold -Root $missingDependency -Name missing-dependency `
                -Description 'Missing dependency.' -Role consumer `
                -Infrastructure minimal -Visibility local `
                -SelectedSkills manage-skills `
                -ResolvedSkills agent-files-review -SkillsRef v1.0.0 -SkipGit
        } | Should -Throw '*must contain directly selected*'
        Test-Path $missingDependency | Should -BeFalse
    }

    It 'contains no executable GitHub repository creation command' {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:Scaffold,
            [ref] $tokens,
            [ref] $errors)
        $errors.Count | Should -Be 0
        $remoteCommands = @($ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'gh' -and
                    $node.Extent.Text -match '\brepo\s+create\b'
                }, $true))
        $remoteCommands.Count | Should -Be 0
    }
}