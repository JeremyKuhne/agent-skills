#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:InstallerPath = (Resolve-Path (
            Join-Path $PSScriptRoot '..' '..' 'skills' 'manage-skills' 'scripts' 'Install-UserSkill.ps1')).Path

    function New-InstallerSkill {
        param(
            [Parameter(Mandatory)] [string] $CaseName,
            [string] $Name = 'sample-skill',
            [string] $Description = 'Sample skill for installer tests.'
        )

        $caseRoot = Join-Path $TestDrive $CaseName
        $skillRoot = Join-Path $caseRoot $Name
        $references = Join-Path $skillRoot 'references'
        New-Item -ItemType Directory -Path $references -Force | Out-Null
        [System.IO.File]::WriteAllText(
            (Join-Path $skillRoot 'SKILL.md'),
            "---`nname: $Name`ndescription: $Description`n---`n`n# $Name`n",
            [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText(
            (Join-Path $references 'detail.md'),
            "# Detail`n",
            [System.Text.UTF8Encoding]::new($false))
        return $skillRoot
    }
}

Describe 'Install-UserSkill.ps1' {
    It 'copies the complete skill into the Copilot user root' {
        $source = New-InstallerSkill -CaseName 'copy'
        $targetHome = Join-Path $TestDrive 'copy-home'
        New-Item -ItemType Directory -Path $targetHome | Out-Null

        $result = @(& $script:InstallerPath `
                -SourceSkillPath $source `
            -ProfileRoot $targetHome)

        $result.Count | Should -Be 1
        $result[0].Hosts | Should -Be 'github-copilot'
        $result[0].Scope | Should -Be 'user'
        $result[0].Mode | Should -Be 'copy'
        $result[0].Private | Should -BeFalse
        $destination = Join-Path $targetHome '.copilot/skills/sample-skill'
        $result[0].Destination | Should -Be $destination
        Test-Path (Join-Path $destination 'SKILL.md') | Should -BeTrue
        Test-Path (Join-Path $destination 'references/detail.md') | Should -BeTrue
        (Get-FileHash (Join-Path $source 'SKILL.md')).Hash |
            Should -Be (Get-FileHash (Join-Path $destination 'SKILL.md')).Hash
    }

    It 'requires Force and replaces an existing copy atomically' {
        $source = New-InstallerSkill -CaseName 'replace'
        $targetHome = Join-Path $TestDrive 'replace-home'
        New-Item -ItemType Directory -Path $targetHome | Out-Null
        & $script:InstallerPath -SourceSkillPath $source -ProfileRoot $targetHome |
            Out-Null

        [System.IO.File]::WriteAllText(
            (Join-Path $source 'SKILL.md'),
            "---`nname: sample-skill`ndescription: Updated installer test skill.`n---`n`n# Updated`n",
            [System.Text.UTF8Encoding]::new($false))

        { & $script:InstallerPath -SourceSkillPath $source -ProfileRoot $targetHome } |
            Should -Throw '*Pass -Force to replace it*'

        & $script:InstallerPath `
            -SourceSkillPath $source `
            -ProfileRoot $targetHome `
            -Force |
            Out-Null

        $destinationRoot = Join-Path $targetHome '.copilot/skills'
        $destination = Join-Path $destinationRoot 'sample-skill/SKILL.md'
        (Get-FileHash (Join-Path $source 'SKILL.md')).Hash |
            Should -Be (Get-FileHash $destination).Hash
        @(Get-ChildItem $destinationRoot -Force | Where-Object {
                $_.Name -match '^\.sample-skill\.install-|^sample-skill\.backup-'
            }).Count | Should -Be 0
    }

    It 'deduplicates host aliases that use the neutral agents root' {
        $source = New-InstallerSkill -CaseName 'deduplicate'
        $targetHome = Join-Path $TestDrive 'deduplicate-home'
        New-Item -ItemType Directory -Path $targetHome | Out-Null

        $result = @(& $script:InstallerPath `
                -SourceSkillPath $source `
                -TargetHost shared-agents, codex `
                -ProfileRoot $targetHome)

        $result.Count | Should -Be 1
        $result[0].Hosts | Should -Be 'shared-agents, codex'
        $result[0].Destination |
            Should -Be (Join-Path $targetHome '.agents/skills/sample-skill')
    }

    It 'requires explicit consent for a private neutral-root copy' {
        $source = New-InstallerSkill -CaseName 'private-shared'
        $targetHome = Join-Path $TestDrive 'private-shared-home'
        New-Item -ItemType Directory -Path $targetHome | Out-Null

        {
            & $script:InstallerPath `
                -SourceSkillPath $source `
                -TargetHost shared-agents `
                -ProfileRoot $targetHome `
                -Private `
                -WhatIf
        } | Should -Throw '*AllowPrivateMultiHostExposure*'
    }

    It 'rejects a public Git repository in private mode' {
        $source = New-InstallerSkill -CaseName 'public-source'
        $repository = Split-Path -Parent $source
        & git -C $repository init --quiet
        & git -C $repository remote add origin https://github.com/example/public.git
        $global:LASTEXITCODE = 0

        function global:gh {
            'PUBLIC'
            $global:LASTEXITCODE = 0
        }

        try {
            $targetHome = Join-Path $TestDrive 'public-source-home'
            New-Item -ItemType Directory -Path $targetHome | Out-Null
            {
                & $script:InstallerPath `
                    -SourceSkillPath $source `
                    -ProfileRoot $targetHome `
                    -Private `
                    -WhatIf
            } | Should -Throw '*PUBLIC repository*'
        }
        finally {
            Remove-Item Function:\gh -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects a source that fails skill validation' {
        $caseRoot = Join-Path $TestDrive 'invalid'
        $source = Join-Path $caseRoot 'invalid-skill'
        New-Item -ItemType Directory -Path $source -Force | Out-Null
        [System.IO.File]::WriteAllText(
            (Join-Path $source 'SKILL.md'),
            "---`nname: another-name`ndescription: Invalid fixture.`n---`n",
            [System.Text.UTF8Encoding]::new($false))
        $targetHome = Join-Path $TestDrive 'invalid-home'
        New-Item -ItemType Directory -Path $targetHome | Out-Null

        {
            & $script:InstallerPath `
                -SourceSkillPath $source `
                -ProfileRoot $targetHome
        } | Should -Throw '*failed validation*'
    }

    It 'rolls back earlier targets when a later target cannot stage' {
        $source = New-InstallerSkill -CaseName 'rollback'
        $targetHome = Join-Path $TestDrive 'rollback-home'
        New-Item -ItemType Directory -Path $targetHome | Out-Null
        [System.IO.File]::WriteAllText(
            (Join-Path $targetHome '.claude'),
            'block',
            [System.Text.UTF8Encoding]::new($false))

        {
            & $script:InstallerPath `
                -SourceSkillPath $source `
                -TargetHost github-copilot, claude-code `
                -ProfileRoot $targetHome
        } | Should -Throw

        Test-Path (Join-Path $targetHome '.copilot') | Should -BeFalse
        Test-Path (Join-Path $targetHome '.claude') -PathType Leaf | Should -BeTrue
    }
}
