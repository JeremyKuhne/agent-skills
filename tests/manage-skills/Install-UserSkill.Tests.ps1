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

    function Get-TestEnvironmentSnapshot {
        param([Parameter(Mandatory)] [string[]] $Name)

        $snapshot = @{}
        foreach ($item in $Name) {
            $snapshot[$item] = [pscustomobject]@{
                Exists = Test-Path -LiteralPath "Env:$item"
                Value = [Environment]::GetEnvironmentVariable(
                    $item,
                    [EnvironmentVariableTarget]::Process)
            }
        }
        return $snapshot
    }

    function Restore-TestEnvironment {
        param([Parameter(Mandatory)] [hashtable] $Snapshot)

        foreach ($item in $Snapshot.GetEnumerator()) {
            if ($item.Value.Exists) {
                [Environment]::SetEnvironmentVariable(
                    $item.Key,
                    $item.Value.Value,
                    [EnvironmentVariableTarget]::Process)
            }
            else {
                Remove-Item -LiteralPath "Env:$($item.Key)" `
                    -Force `
                    -ErrorAction SilentlyContinue
            }
        }
    }

    function New-GitInstallerSkill {
        param(
            [Parameter(Mandatory)] [string] $CaseName,
            [AllowEmptyString()] [string] $RemoteUrl = ''
        )

        $source = New-InstallerSkill -CaseName $CaseName
        $repository = Split-Path -Parent $source
        & git -C $repository init --quiet
        if (-not [string]::IsNullOrWhiteSpace($RemoteUrl)) {
            & git -C $repository remote add origin $RemoteUrl
        }
        return $source
    }

    function Set-InstallerGhFixture {
        param(
            [AllowNull()] [object] $Output,
            [int] $ExitCode = 0
        )

        $global:InstallerGhOutput = $Output
        $global:InstallerGhExitCode = $ExitCode
        $global:InstallerGhArguments = $null
        Set-Item -Path Function:\global:gh -Value {
            $global:InstallerGhArguments = @($args)
            Write-Output $global:InstallerGhOutput
            $global:LASTEXITCODE = $global:InstallerGhExitCode
        }
    }

    function Remove-InstallerGhFixture {
        Remove-Item Function:\gh -Force -ErrorAction SilentlyContinue
        Remove-Variable InstallerGhOutput -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable InstallerGhExitCode -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable InstallerGhArguments -Scope Global -ErrorAction SilentlyContinue
    }

    $tokens = $null
    $parseErrors = $null
    $installerAst = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:InstallerPath,
        [ref] $tokens,
        [ref] $parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Installer test harness could not parse '$($script:InstallerPath)'."
    }

    $functionAsts = @($installerAst.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
            }, $true))
    foreach ($name in @('Invoke-GitInspection', 'Get-GitRepositoryInspection')) {
        $matchingFunctions = @($functionAsts | Where-Object Name -EQ $name)
        if ($matchingFunctions.Count -ne 1) {
            throw "Installer test harness expected one '$name' declaration."
        }
        Set-Item -Path "Function:\$name" -Value $matchingFunctions[0].Body.GetScriptBlock()
    }
}

Describe 'Get-GitRepositoryInspection' {
    It 'accepts Git nonrepository diagnostic: <CaseName>' -ForEach @(
        @{
            CaseName = 'ordinary parent search'
            Diagnostic = 'fatal: not a git repository (or any of the parent directories): .git'
        }
        @{
            CaseName = 'mount boundary with LF'
            Diagnostic = "fatal: not a git repository (or any parent up to mount point /mount)`nStopping at filesystem boundary (GIT_DISCOVERY_ACROSS_FILESYSTEM not set)."
        }
        @{
            CaseName = 'mount boundary with CRLF'
            Diagnostic = "fatal: not a git repository (or any parent up to mount point /mount)`r`nStopping at filesystem boundary (GIT_DISCOVERY_ACROSS_FILESYSTEM not set)."
        }
    ) {
        Mock Invoke-GitInspection {
            [pscustomobject]@{
                ExitCode = 128
                StandardOutput = ''
                StandardError = $Diagnostic
            }
        }

        $inspection = Get-GitRepositoryInspection `
            -Path $TestDrive `
            -GitPath 'synthetic-git' `
            -BoundaryName 'source'

        $inspection.IsRepository | Should -BeFalse
        $inspection.Root | Should -BeNullOrEmpty
    }

    It 'rejects an unrelated exit 128 Git diagnostic' {
        Mock Invoke-GitInspection {
            [pscustomobject]@{
                ExitCode = 128
                StandardOutput = ''
                StandardError = "fatal: detected dubious ownership in repository at '/mount/source'"
            }
        }

        {
            Get-GitRepositoryInspection `
                -Path $TestDrive `
                -GitPath 'synthetic-git' `
                -BoundaryName 'source'
        } | Should -Throw '*dubious ownership*'
    }
}

Describe 'Install-UserSkill.ps1' {
    AfterEach {
        Remove-InstallerGhFixture
    }

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

    It 'rejects a Git repository at the exact destination without replacing it' {
        $source = New-InstallerSkill -CaseName 'destination-repository'
        $targetHome = Join-Path $TestDrive 'destination-repository-home'
        $destinationRoot = Join-Path $targetHome '.copilot/skills'
        $destination = Join-Path $destinationRoot 'sample-skill'
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        [System.IO.File]::WriteAllText(
            (Join-Path $destination 'original.txt'),
            'preserve me',
            [System.Text.UTF8Encoding]::new($false))
        & git -C $destination init --quiet

        {
            & $script:InstallerPath `
                -SourceSkillPath $source `
                -ProfileRoot $targetHome `
                -Private `
                -Force
        } | Should -Throw '*destination is inside a Git worktree*'

        Test-Path (Join-Path $destination '.git') -PathType Container |
            Should -BeTrue
        [System.IO.File]::ReadAllText((Join-Path $destination 'original.txt')) |
            Should -Be 'preserve me'
        @(Get-ChildItem $destinationRoot -Force | Where-Object {
                $_.Name -match '^\.sample-skill\.install-|^sample-skill\.backup-'
            }).Count | Should -Be 0
    }

    It 'rejects a file at the exact destination without replacing it' {
        $source = New-InstallerSkill -CaseName 'destination-file'
        $targetHome = Join-Path $TestDrive 'destination-file-home'
        $destinationRoot = Join-Path $targetHome '.copilot/skills'
        $destination = Join-Path $destinationRoot 'sample-skill'
        New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
        [System.IO.File]::WriteAllText(
            $destination,
            'preserve destination file',
            [System.Text.UTF8Encoding]::new($false))

        {
            & $script:InstallerPath `
                -SourceSkillPath $source `
                -ProfileRoot $targetHome `
                -Force
        } | Should -Throw '*destination path is blocked by a file*'

        Test-Path $destination -PathType Leaf | Should -BeTrue
        [System.IO.File]::ReadAllText($destination) |
            Should -Be 'preserve destination file'
        @(Get-ChildItem $destinationRoot -Force | Where-Object {
                $_.Name -match '^\.sample-skill\.install-|^sample-skill\.backup-'
            }).Count | Should -Be 0
    }

    It 'fails closed when source Git inspection is denied' {
        $source = New-InstallerSkill -CaseName 'source-inspection-error'
        $repository = Split-Path -Parent $source
        & git -C $repository init --quiet
        $targetHome = Join-Path $TestDrive 'source-inspection-error-home'
        New-Item -ItemType Directory -Path $targetHome | Out-Null
        $environment = Get-TestEnvironmentSnapshot -Name @(
            'GIT_TEST_ASSUME_DIFFERENT_OWNER',
            'GIT_CONFIG_GLOBAL',
            'GIT_CONFIG_NOSYSTEM')

        try {
            [Environment]::SetEnvironmentVariable(
                'GIT_TEST_ASSUME_DIFFERENT_OWNER',
                '1',
                [EnvironmentVariableTarget]::Process)
            [Environment]::SetEnvironmentVariable(
                'GIT_CONFIG_GLOBAL',
                (Join-Path $TestDrive 'source-inspection-error.gitconfig'),
                [EnvironmentVariableTarget]::Process)
            [Environment]::SetEnvironmentVariable(
                'GIT_CONFIG_NOSYSTEM',
                '1',
                [EnvironmentVariableTarget]::Process)

            {
                & $script:InstallerPath `
                    -SourceSkillPath $source `
                    -ProfileRoot $targetHome `
                    -Private `
                    -WhatIf
            } | Should -Throw '*could not inspect the source repository boundary*dubious ownership*'
        }
        finally {
            Restore-TestEnvironment -Snapshot $environment
        }

        Test-Path (Join-Path $targetHome '.copilot') | Should -BeFalse
    }

    It 'fails closed when destination Git inspection is denied' {
        $source = New-InstallerSkill -CaseName 'destination-inspection-error'
        $targetHome = Join-Path $TestDrive 'destination-inspection-error-home'
        New-Item -ItemType Directory -Path $targetHome | Out-Null
        & git -C $targetHome init --quiet
        $environment = Get-TestEnvironmentSnapshot -Name @(
            'GIT_TEST_ASSUME_DIFFERENT_OWNER',
            'GIT_CONFIG_GLOBAL',
            'GIT_CONFIG_NOSYSTEM')

        try {
            [Environment]::SetEnvironmentVariable(
                'GIT_TEST_ASSUME_DIFFERENT_OWNER',
                '1',
                [EnvironmentVariableTarget]::Process)
            [Environment]::SetEnvironmentVariable(
                'GIT_CONFIG_GLOBAL',
                (Join-Path $TestDrive 'destination-inspection-error.gitconfig'),
                [EnvironmentVariableTarget]::Process)
            [Environment]::SetEnvironmentVariable(
                'GIT_CONFIG_NOSYSTEM',
                '1',
                [EnvironmentVariableTarget]::Process)

            {
                & $script:InstallerPath `
                    -SourceSkillPath $source `
                    -ProfileRoot $targetHome `
                    -WhatIf
            } | Should -Throw '*could not inspect the destination repository boundary*dubious ownership*'
        }
        finally {
            Restore-TestEnvironment -Snapshot $environment
        }

        Test-Path (Join-Path $targetHome '.copilot') | Should -BeFalse
    }

    It 'accepts a private local source after Git reports no repository' {
        $source = New-InstallerSkill -CaseName 'local-private-source'
        $targetHome = Join-Path $TestDrive 'local-private-source-home'
        New-Item -ItemType Directory -Path $targetHome | Out-Null

        {
            & $script:InstallerPath `
                -SourceSkillPath $source `
                -ProfileRoot $targetHome `
                -Private `
                -WhatIf
        } | Should -Not -Throw

        Test-Path (Join-Path $targetHome '.copilot') | Should -BeFalse
    }

    It 'ignores ambient Git repository selectors during boundary inspection' {
        $source = New-InstallerSkill -CaseName 'ambient-git-source'
        $unrelatedRepository = Join-Path $TestDrive 'ambient-git-repository'
        New-Item -ItemType Directory -Path $unrelatedRepository | Out-Null
        & git -C $unrelatedRepository init --quiet
        & git -C $unrelatedRepository remote add origin `
            https://github.com/example/unrelated.git
        $targetHome = Join-Path $TestDrive 'ambient-git-source-home'
        New-Item -ItemType Directory -Path $targetHome | Out-Null
        $environment = Get-TestEnvironmentSnapshot -Name @(
            'GIT_DIR',
            'GIT_WORK_TREE')
        Set-InstallerGhFixture -Output '{"nameWithOwner":"example/unrelated","visibility":"PRIVATE"}'

        try {
            [Environment]::SetEnvironmentVariable(
                'GIT_DIR',
                (Join-Path $unrelatedRepository '.git'),
                [EnvironmentVariableTarget]::Process)
            [Environment]::SetEnvironmentVariable(
                'GIT_WORK_TREE',
                $unrelatedRepository,
                [EnvironmentVariableTarget]::Process)

            {
                & $script:InstallerPath `
                    -SourceSkillPath $source `
                    -ProfileRoot $targetHome `
                    -Private `
                    -WhatIf
            } | Should -Not -Throw
            $global:InstallerGhArguments | Should -BeNullOrEmpty
        }
        finally {
            Remove-InstallerGhFixture
            Restore-TestEnvironment -Snapshot $environment
        }
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

    It 'rejects a synchronized-folder root that is not fully qualified' {
        $source = New-InstallerSkill -CaseName 'relative-sync-root'
        $targetHome = Join-Path $TestDrive 'relative-sync-root-home'
        New-Item -ItemType Directory -Path $targetHome | Out-Null
        $originalOneDrive = $env:OneDrive
        $env:OneDrive = if ($IsWindows) { 'C:sync' } else { 'sync' }

        try {
            {
                & $script:InstallerPath `
                    -SourceSkillPath $source `
                    -ProfileRoot $targetHome `
                    -Private `
                    -WhatIf
            } | Should -Throw '*Root path must be fully qualified*'
        }
        finally {
            $env:OneDrive = $originalOneDrive
        }
    }

    It 'rejects a private source under the <Variable> sync root' -ForEach @(
        @{ Variable = 'OneDrive' }
        @{ Variable = 'OneDriveConsumer' }
        @{ Variable = 'OneDriveCommercial' }
        @{ Variable = 'Dropbox' }
        @{ Variable = 'GoogleDrive' }
    ) {
        $source = New-InstallerSkill -CaseName "source-sync-$Variable"
        $syncRoot = Split-Path -Parent $source
        $targetHome = Join-Path $TestDrive "source-sync-$Variable-home"
        New-Item -ItemType Directory -Path $targetHome | Out-Null
        $syncVariables = @(
            'OneDrive',
            'OneDriveConsumer',
            'OneDriveCommercial',
            'Dropbox',
            'GoogleDrive')
        $environment = Get-TestEnvironmentSnapshot -Name $syncVariables

        try {
            foreach ($name in $syncVariables) {
                [Environment]::SetEnvironmentVariable(
                    $name,
                    $null,
                    [EnvironmentVariableTarget]::Process)
            }
            [Environment]::SetEnvironmentVariable(
                $Variable,
                $syncRoot,
                [EnvironmentVariableTarget]::Process)

            {
                & $script:InstallerPath `
                    -SourceSkillPath $source `
                    -ProfileRoot $targetHome `
                    -Private `
                    -WhatIf
            } | Should -Throw '*source is under a synchronized folder*'
        }
        finally {
            Restore-TestEnvironment -Snapshot $environment
        }

        Test-Path (Join-Path $targetHome '.copilot') | Should -BeFalse
    }

    It 'rejects a skill collection without a top-level SKILL.md' {
        $nestedSkill = New-InstallerSkill -CaseName 'skill-collection'
        $collection = Split-Path -Parent $nestedSkill
        $targetHome = Join-Path $TestDrive 'skill-collection-home'
        $destination = Join-Path $targetHome '.copilot/skills/skill-collection'
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        [System.IO.File]::WriteAllText(
            (Join-Path $destination 'original.txt'),
            'preserve collection target',
            [System.Text.UTF8Encoding]::new($false))

        {
            & $script:InstallerPath `
                -SourceSkillPath $collection `
                -ProfileRoot $targetHome `
                -Force
        } | Should -Throw '*must contain a top-level SKILL.md*'

        [System.IO.File]::ReadAllText((Join-Path $destination 'original.txt')) |
            Should -Be 'preserve collection target'
        Test-Path (Join-Path $destination 'sample-skill') | Should -BeFalse
    }

    It 'passes the explicit github.com source despite unrelated repository and host overrides' {
        $source = New-GitInstallerSkill `
            -CaseName 'private-source' `
            -RemoteUrl 'https://github.com/example/private-source.git'
        $targetHome = Join-Path $TestDrive 'private-source-home'
        New-Item -ItemType Directory -Path $targetHome | Out-Null
        $environment = Get-TestEnvironmentSnapshot -Name @('GH_REPO', 'GH_HOST')
        Set-InstallerGhFixture -Output '{"nameWithOwner":"example/private-source","visibility":"PRIVATE"}'
        try {
            [Environment]::SetEnvironmentVariable(
                'GH_REPO',
                'example/unrelated-private',
                [EnvironmentVariableTarget]::Process)
            [Environment]::SetEnvironmentVariable(
                'GH_HOST',
                'github.enterprise.invalid',
                [EnvironmentVariableTarget]::Process)

            {
                & $script:InstallerPath `
                    -SourceSkillPath $source `
                    -ProfileRoot $targetHome `
                    -Private `
                    -WhatIf
            } | Should -Not -Throw

            $global:InstallerGhArguments -join ' ' |
                Should -Be 'repo view https://github.com/example/private-source --json nameWithOwner,visibility'
        }
        finally {
            Remove-InstallerGhFixture
            Restore-TestEnvironment -Snapshot $environment
        }
    }

    It 'rejects a <Visibility> Git repository in private mode' -ForEach @(
        @{ Visibility = 'PUBLIC' }
        @{ Visibility = 'INTERNAL' }
    ) {
        $source = New-GitInstallerSkill `
            -CaseName "non-private-$($Visibility.ToLowerInvariant())" `
            -RemoteUrl 'https://github.com/example/non-private.git'
        $targetHome = Join-Path $TestDrive "non-private-$($Visibility.ToLowerInvariant())-home"
        New-Item -ItemType Directory -Path $targetHome | Out-Null
        Set-InstallerGhFixture -Output (
            "{`"nameWithOwner`":`"example/non-private`",`"visibility`":`"$Visibility`"}")

        try {
            {
                & $script:InstallerPath `
                    -SourceSkillPath $source `
                    -ProfileRoot $targetHome `
                    -Private `
                    -WhatIf
            } | Should -Throw "*$Visibility repository*"
        }
        finally {
            Remove-InstallerGhFixture
        }
    }

    It 'rejects repository metadata for a different source identity' {
        $source = New-GitInstallerSkill `
            -CaseName 'mismatched-source' `
            -RemoteUrl 'https://github.com/example/reviewed-source.git'
        $targetHome = Join-Path $TestDrive 'mismatched-source-home'
        New-Item -ItemType Directory -Path $targetHome | Out-Null
        Set-InstallerGhFixture -Output '{"nameWithOwner":"example/unrelated-private","visibility":"PRIVATE"}'

        try {
            {
                & $script:InstallerPath `
                    -SourceSkillPath $source `
                    -ProfileRoot $targetHome `
                    -Private `
                    -WhatIf
            } | Should -Throw '*identity*does not match*reviewed source*'
        }
        finally {
            Remove-InstallerGhFixture
        }
    }

    It 'rejects failed or malformed GitHub repository metadata: <CaseName>' -ForEach @(
        @{
            CaseName = 'command failure'
            Output = 'synthetic gh failure'
            ExitCode = 1
            Expected = '*visibility could not be verified*'
        }
        @{
            CaseName = 'malformed JSON'
            Output = 'not-json'
            ExitCode = 0
            Expected = '*malformed repository metadata*'
        }
    ) {
        $source = New-GitInstallerSkill `
            -CaseName "metadata-$($CaseName -replace ' ', '-')" `
            -RemoteUrl 'https://github.com/example/metadata-source.git'
        $targetHome = Join-Path $TestDrive "metadata-$($CaseName -replace ' ', '-')-home"
        New-Item -ItemType Directory -Path $targetHome | Out-Null
        Set-InstallerGhFixture -Output $Output -ExitCode $ExitCode

        try {
            {
                & $script:InstallerPath `
                    -SourceSkillPath $source `
                    -ProfileRoot $targetHome `
                    -Private `
                    -WhatIf
            } | Should -Throw $Expected
        }
        finally {
            Remove-InstallerGhFixture
        }
    }

    It 'rejects a private Git source with no remote' {
        $source = New-GitInstallerSkill -CaseName 'missing-remote'
        $targetHome = Join-Path $TestDrive 'missing-remote-home'
        New-Item -ItemType Directory -Path $targetHome | Out-Null
        Set-InstallerGhFixture -Output '{"nameWithOwner":"example/source","visibility":"PRIVATE"}'

        try {
            {
                & $script:InstallerPath `
                    -SourceSkillPath $source `
                    -ProfileRoot $targetHome `
                    -Private `
                    -WhatIf
            } | Should -Throw '*does not have a remote*'
        }
        finally {
            Remove-InstallerGhFixture
        }
    }

    It 'rejects a private Git source with an unsupported remote host' {
        $source = New-GitInstallerSkill `
            -CaseName 'unsupported-remote' `
            -RemoteUrl 'https://gitlab.example.com/example/source.git'
        $targetHome = Join-Path $TestDrive 'unsupported-remote-home'
        New-Item -ItemType Directory -Path $targetHome | Out-Null
        Set-InstallerGhFixture -Output '{"nameWithOwner":"example/source","visibility":"PRIVATE"}'

        try {
            {
                & $script:InstallerPath `
                    -SourceSkillPath $source `
                    -ProfileRoot $targetHome `
                    -Private `
                    -WhatIf
            } | Should -Throw '*unsupported remote*'
        }
        finally {
            Remove-InstallerGhFixture
        }
    }

    It 'rejects a private Git source with ambiguous remote identities' {
        $source = New-GitInstallerSkill `
            -CaseName 'ambiguous-remotes' `
            -RemoteUrl 'https://github.com/example/source-one.git'
        $repository = Split-Path -Parent $source
        & git -C $repository remote add upstream `
            https://github.com/example/source-two.git
        $targetHome = Join-Path $TestDrive 'ambiguous-remotes-home'
        New-Item -ItemType Directory -Path $targetHome | Out-Null
        Set-InstallerGhFixture -Output '{"nameWithOwner":"example/source-one","visibility":"PRIVATE"}'

        try {
            {
                & $script:InstallerPath `
                    -SourceSkillPath $source `
                    -ProfileRoot $targetHome `
                    -Private `
                    -WhatIf
            } | Should -Throw '*ambiguous GitHub remote identities*'
        }
        finally {
            Remove-InstallerGhFixture
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

    It 'requires git for repository boundary checks' {
        $source = New-InstallerSkill -CaseName 'missing-git'
        $targetHome = Join-Path $TestDrive 'missing-git-home'
        New-Item -ItemType Directory -Path $targetHome | Out-Null
        $originalPath = $env:PATH

        try {
            $env:PATH = ''
            {
                & $script:InstallerPath `
                    -SourceSkillPath $source `
                    -ProfileRoot $targetHome `
                    -WhatIf
            } | Should -Throw '*Git is required to verify source and destination repository boundaries*'
        }
        finally {
            $env:PATH = $originalPath
        }
    }

    It 'reports a file that blocks a destination root during preflight' {
        $source = New-InstallerSkill -CaseName 'blocked-root'
        $targetHome = Join-Path $TestDrive 'blocked-root-home'
        New-Item -ItemType Directory -Path $targetHome | Out-Null
        $blocker = Join-Path $targetHome '.claude'
        [System.IO.File]::WriteAllText(
            $blocker,
            'block',
            [System.Text.UTF8Encoding]::new($false))

        {
            & $script:InstallerPath `
                -SourceSkillPath $source `
                -TargetHost claude-code `
                -ProfileRoot $targetHome
        } | Should -Throw "*destination path is blocked by a file: '$blocker'*"

        Test-Path $blocker -PathType Leaf | Should -BeTrue
        [System.IO.File]::ReadAllText($blocker) | Should -Be 'block'
    }

    It 'restores an existing destination when a later target commit fails' {
        $source = New-InstallerSkill -CaseName 'rollback'
        $targetHome = Join-Path $TestDrive 'rollback-home'
        New-Item -ItemType Directory -Path $targetHome | Out-Null
        & $script:InstallerPath `
            -SourceSkillPath $source `
            -ProfileRoot $targetHome |
            Out-Null

        $copilotRoot = Join-Path $targetHome '.copilot/skills'
        $copilotDestination = Join-Path $copilotRoot 'sample-skill'
        $claudeRoot = Join-Path $targetHome '.claude/skills'
        $claudeDestination = Join-Path $claudeRoot 'sample-skill'
        $installedSkill = Join-Path $copilotDestination 'SKILL.md'
        $originalHash = (Get-FileHash $installedSkill).Hash
        [System.IO.File]::WriteAllText(
            (Join-Path $source 'SKILL.md'),
            "---`nname: sample-skill`ndescription: Updated rollback fixture.`n---`n`n# Updated`n",
            [System.Text.UTF8Encoding]::new($false))

        Mock Move-Item {
            if ($Destination -eq $claudeDestination) {
                throw 'Injected second-target commit failure.'
            }

            [System.IO.Directory]::Move($LiteralPath, $Destination)
        }

        {
            & $script:InstallerPath `
                -SourceSkillPath $source `
                -TargetHost github-copilot, claude-code `
                -ProfileRoot $targetHome `
                -Force
        } | Should -Throw '*Injected second-target commit failure*'

        (Get-FileHash $installedSkill).Hash | Should -Be $originalHash
        (Get-FileHash (Join-Path $source 'SKILL.md')).Hash |
            Should -Not -Be $originalHash
        Test-Path $claudeDestination | Should -BeFalse
        foreach ($root in @($copilotRoot, $claudeRoot)) {
            @(Get-ChildItem $root -Force -ErrorAction SilentlyContinue | Where-Object {
                    $_.Name -match '^\.sample-skill\.install-|^sample-skill\.backup-'
                }).Count | Should -Be 0
        }
    }
}
