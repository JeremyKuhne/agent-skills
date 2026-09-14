#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '6.2.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot 'SkillArtifactTestHelpers.ps1')
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:SkillsRoot = Join-Path $script:RepoRoot 'skills'
    $script:AgentsRoot = Join-Path $script:RepoRoot 'agents'

    function Get-SkillRecord ([string] $skillDirectory) {
        $skillPath = Join-Path $skillDirectory 'SKILL.md'
        $content = Get-Content -LiteralPath $skillPath -Raw
        $nameMatch = [regex]::Match($content, '(?m)^name:\s*(?<value>[^\r\n]+)\r?$')
        if (-not $nameMatch.Success) { throw "Could not parse name from $skillPath" }

        $metadata = @{}
        $insideMetadata = $false
        foreach ($line in ($content -split "\r?\n")) {
            if ($line -ceq 'metadata:') {
                $insideMetadata = $true
                continue
            }
            if (-not $insideMetadata) { continue }
            if ($line -match '^\s+(?<key>[a-z][a-z-]*):\s*(?<value>.*)$') {
                $metadata[$Matches.key] = $Matches.value.Trim()
                continue
            }
            if ($line -match '^\S') { break }
        }

        [pscustomobject]@{
            Name = $nameMatch.Groups['value'].Value.Trim()
            Directory = $skillDirectory
            Path = $skillPath
            Metadata = $metadata
        }
    }

    function Get-RelationshipNames ([string] $value) {
        if ([string]::IsNullOrWhiteSpace($value) -or $value -eq 'none') { return @() }
        return @($value -split ',' | ForEach-Object { $_.Trim() })
    }

    $script:SkillRecords = @(Get-ChildItem -LiteralPath $script:SkillsRoot -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') } |
        Sort-Object Name |
        ForEach-Object { Get-SkillRecord $_.FullName })
    $script:SkillNames = @($script:SkillRecords.Name)
}

Describe 'PowerShell toolchain contract' {
    BeforeAll {
        $script:ToolchainManifestPath = Join-Path $script:RepoRoot 'tools/powershell-toolchain.json'
        $script:ToolchainValidatorPath = Join-Path $script:RepoRoot 'tools/Test-PowerShellToolchain.ps1'
        $script:Toolchain = Get-Content -LiteralPath $script:ToolchainManifestPath -Raw |
            ConvertFrom-Json

        function New-ToolchainFixture ([string] $Name) {
            $fixtureRoot = Join-Path $TestDrive $Name
            foreach ($relativePath in @(
                    'tools',
                    'tests',
                    'docs',
                    '.github/workflows',
                    '.agents/skills/create-skill-repo',
                    'skills/dotnet-file-creation',
                    'skills/windows-acls')) {
                [IO.Directory]::CreateDirectory((Join-Path $fixtureRoot $relativePath)) |
                    Out-Null
            }
            Copy-Item -LiteralPath $script:ToolchainManifestPath `
                -Destination (Join-Path $fixtureRoot 'tools/powershell-toolchain.json')
            Set-Content -LiteralPath (Join-Path $fixtureRoot 'global.json') -Value @'
{
    "sdk": {
        "version": "10.0.100",
        "rollForward": "latestFeature",
        "allowPrerelease": false
    }
}
'@
            Set-Content -LiteralPath (Join-Path $fixtureRoot 'Directory.Build.props') -Value @'
<Project>
    <PropertyGroup>
        <LangVersion>14.0</LangVersion>
    </PropertyGroup>
</Project>
'@
            Set-Content -LiteralPath (Join-Path $fixtureRoot '.github/workflows/ci.yml') `
                -Value @(
                'jobs:',
                '  dotnet-pipes:',
                '    runs-on: matrix',
                '    steps:',
                '      - uses: actions/setup-dotnet',
                '        with:',
                '          dotnet-version: 10.0.x',
                '  scaffold-linux:',
                '    runs-on: ubuntu-24.04-arm',
                '    steps:',
                '      - uses: actions/setup-dotnet',
                '        with:',
                '          dotnet-version: 10.0.x',
                '      - name: Validate PowerShell toolchain',
                '        shell: pwsh',
                '        run: ./tools/Test-PowerShellToolchain.ps1',
                '  scaffold-windows:',
                '    runs-on: windows-latest',
                '    steps:',
                '      - uses: actions/setup-dotnet',
                '        with:',
                '          dotnet-version: 10.0.x',
                '      - name: Validate PowerShell toolchain',
                '        shell: pwsh',
                '        run: ./tools/Test-PowerShellToolchain.ps1')
            Set-Content -LiteralPath (Join-Path $fixtureRoot '.github/workflows/full-ci.yml') `
                -Value @(
                'on:',
                '  schedule:',
                "    - cron: '0 0 * * 1'",
                'jobs:',
                '  scaffold-linux:',
                '    runs-on: ubuntu-24.04-arm',
                '    steps:',
                '      - uses: actions/setup-dotnet',
                '        with:',
                '          dotnet-version: 10.0.x',
                '      - name: Validate PowerShell toolchain',
                '        shell: pwsh',
                '        run: ./tools/Test-PowerShellToolchain.ps1',
                '  scaffold-linux-x64:',
                '    runs-on: ubuntu-latest',
                '    steps:',
                '      - uses: actions/setup-dotnet',
                '        with:',
                '          dotnet-version: 10.0.x',
                '      - name: Validate PowerShell toolchain',
                '        shell: pwsh',
                '        run: ./tools/Test-PowerShellToolchain.ps1',
                '  scaffold-windows:',
                '    runs-on: windows-latest',
                '    steps:',
                '      - uses: actions/setup-dotnet',
                '        with:',
                '          dotnet-version: 10.0.x',
                '      - name: Validate PowerShell toolchain',
                '        shell: pwsh',
                '        run: ./tools/Test-PowerShellToolchain.ps1',
                '  scaffold-preview:',
                '    runs-on: windows-latest',
                '    steps:',
                '      - uses: actions/setup-dotnet',
                '        with:',
                '          dotnet-version: 11.0.x',
                '          dotnet-quality: preview',
                '      - name: Validate PowerShell toolchain',
                '        shell: pwsh',
                '        run: ./tools/Test-PowerShellToolchain.ps1')
            Set-Content -LiteralPath (Join-Path $fixtureRoot 'tests/Valid.Tests.ps1') -Value @(
                '#Requires -Version 7.4',
                "#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '6.2.0' }",
                "Describe 'Valid' { It 'is never run' { `$true | Should -BeTrue } }")
            Set-Content -LiteralPath (Join-Path $fixtureRoot 'tests/Invoke-PesterShards.ps1') `
                -Value @(
                '#Requires -Version 7.4',
                '[CmdletBinding()]',
                "param([version] `$PesterVersion = '6.2.0')")
            Set-Content -LiteralPath (
                Join-Path $fixtureRoot '.agents/skills/create-skill-repo/SKILL.md') `
                -Value 'Requires PowerShell 7.4 and Pester 6.2.0.'
            foreach ($relativePath in @(
                    'skills/dotnet-file-creation/SKILL.md',
                    'skills/windows-acls/SKILL.md')) {
                Set-Content -LiteralPath (Join-Path $fixtureRoot $relativePath) `
                    -Value 'Requires PowerShell 7.4 and Pester 6.2 or later.'
            }
            return $fixtureRoot
        }
    }

    It 'runs the toolchain validator before Pester in <Path>' -ForEach @(
        @{ Path = 'CONTRIBUTING.md' }
        @{ Path = 'RELEASING.md' }
        @{ Path = 'AGENTS.md' }
        @{ Path = '.github/copilot-instructions.md' }
    ) {
        $content = Get-Content -LiteralPath (Join-Path $script:RepoRoot $Path) -Raw
        $validatorIndex = $content.IndexOf('./tools/Test-PowerShellToolchain.ps1')
        $runnerIndex = $content.IndexOf('./tests/Invoke-PesterShards.ps1 -Path ./tests')

        $validatorIndex | Should -BeGreaterOrEqual 0
        $runnerIndex | Should -BeGreaterThan $validatorIndex
    }

    It 'records the accepted versions and host lanes' {
        $script:Toolchain.schemaVersion | Should -Be 1
        $script:Toolchain.powerShell.minimumVersion | Should -BeExactly '7.4'
        $script:Toolchain.modules.Pester | Should -BeExactly '6.2.0'
        $script:Toolchain.modules.PSScriptAnalyzer | Should -BeExactly '1.25.0'
        $script:Toolchain.dotnet.sdkVersion | Should -BeExactly '10.0.x'
        $script:Toolchain.dotnet.previewSdkVersion | Should -BeExactly '11.0.x'
        $script:Toolchain.dotnet.languageVersion | Should -BeExactly '14.0'
        @($script:Toolchain.hosts.PSObject.Properties.Name | Sort-Object) |
            Should -Be @('primary', 'scheduled', 'windows')
        $script:Toolchain.hosts.primary.minimumPowerShellVersion |
            Should -BeExactly '7.4'
        $script:Toolchain.hosts.windows.minimumPowerShellVersion |
            Should -BeExactly '7.4'
        $script:Toolchain.hosts.scheduled.minimumPowerShellVersion |
            Should -BeExactly '7.4'
        $script:Toolchain.hosts.scheduled.channel | Should -BeExactly 'latest-stable'
    }

    It 'rejects a manifest minimum above the running PowerShell version' {
        $fixtureRoot = New-ToolchainFixture 'runtime-below-manifest-minimum'
        $manifestPath = Join-Path $fixtureRoot 'tools/powershell-toolchain.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw |
            ConvertFrom-Json -AsHashtable
        $requiredVersion = '{0}.{1}' -f $PSVersionTable.PSVersion.Major,
            ($PSVersionTable.PSVersion.Minor + 1)
        $manifest.powerShell.minimumVersion = $requiredVersion
        foreach ($lane in @('primary', 'windows', 'scheduled')) {
            $manifest.hosts[$lane].minimumPowerShellVersion = $requiredVersion
        }
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*requires PowerShell $requiredVersion or later*"
    }

    It 'keeps checked toolchain copies aligned with the manifest' {
        { & $script:ToolchainValidatorPath -RepositoryRoot $script:RepoRoot } |
            Should -Not -Throw
    }

    It 'rejects a quoted schema version' {
        $fixtureRoot = New-ToolchainFixture 'quoted-schema'
        $manifestPath = Join-Path $fixtureRoot 'tools/powershell-toolchain.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw |
            ConvertFrom-Json -AsHashtable
        $manifest.schemaVersion = '1'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*schemaVersion must be the integer 1*'
    }

    It 'rejects a non-object hosts manifest value' {
        $fixtureRoot = New-ToolchainFixture 'null-hosts'
        $manifestPath = Join-Path $fixtureRoot 'tools/powershell-toolchain.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw |
            ConvertFrom-Json -AsHashtable
        $manifest.hosts = $null
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*Manifest 'hosts' must be an object*"
    }

    It 'rejects a non-object host lane value' {
        $fixtureRoot = New-ToolchainFixture 'null-host-lane'
        $manifestPath = Join-Path $fixtureRoot 'tools/powershell-toolchain.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw |
            ConvertFrom-Json -AsHashtable
        $manifest.hosts.primary = $null
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*Manifest host 'primary' must be an object*"
    }

    It 'rejects invalid host PowerShell version <Value> for <Lane>' -ForEach @(
        @{ Lane = 'primary'; Value = 'banana'; Error = '*minimum PowerShell version must be numeric*' }
        @{ Lane = 'primary'; Value = '7.2'; Error = '*must be at least 7.4*' }
        @{ Lane = 'scheduled'; Value = 'banana'; Error = '*minimum PowerShell version must be numeric*' }
    ) {
        $fixtureRoot = New-ToolchainFixture "host-$Lane-$($Value.Replace('.', '-'))"
        $manifestPath = Join-Path $fixtureRoot 'tools/powershell-toolchain.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw |
            ConvertFrom-Json -AsHashtable
        $manifest.hosts[$Lane].minimumPowerShellVersion = $Value
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw $Error
    }

    It 'rejects a scheduled host without the latest-stable channel' {
        $fixtureRoot = New-ToolchainFixture 'scheduled-channel-drift'
        $manifestPath = Join-Path $fixtureRoot 'tools/powershell-toolchain.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw |
            ConvertFrom-Json -AsHashtable
        $manifest.hosts.scheduled.channel = 'pinned'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*scheduled host channel must be 'latest-stable'*"
    }

    It 'rejects a workflow host that drifts from the manifest' {
        $fixtureRoot = New-ToolchainFixture 'workflow-host-drift'
        $workflowPath = Join-Path $fixtureRoot '.github/workflows/ci.yml'
        (Get-Content -LiteralPath $workflowPath -Raw).Replace(
            'runs-on: ubuntu-24.04-arm', 'runs-on: ubuntu-latest') |
            Set-Content -LiteralPath $workflowPath

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*job 'scaffold-linux' must run on manifest host 'ubuntu-24.04-arm'*"
    }

    It 'rejects a host job that omits the PowerShell minimum validation' {
        $fixtureRoot = New-ToolchainFixture 'workflow-powershell-validation'
        $workflowPath = Join-Path $fixtureRoot '.github/workflows/ci.yml'
        (Get-Content -LiteralPath $workflowPath -Raw).Replace(
            '        run: ./tools/Test-PowerShellToolchain.ps1', '') |
            Set-Content -LiteralPath $workflowPath

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*job 'scaffold-linux' must validate the manifest PowerShell minimum in a pwsh step*"
    }

    It 'rejects a host job with a bare validation script line' {
        $fixtureRoot = New-ToolchainFixture 'workflow-bare-powershell-validation'
        $workflowPath = Join-Path $fixtureRoot '.github/workflows/ci.yml'
        (Get-Content -LiteralPath $workflowPath -Raw).Replace(
            '        run: ./tools/Test-PowerShellToolchain.ps1',
            '      ./tools/Test-PowerShellToolchain.ps1') |
            Set-Content -LiteralPath $workflowPath

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*job 'scaffold-linux' must validate the manifest PowerShell minimum in a pwsh step*"
    }

    It 'rejects a host job with a non-PowerShell validation shell' {
        $fixtureRoot = New-ToolchainFixture 'workflow-powershell-shell-drift'
        $workflowPath = Join-Path $fixtureRoot '.github/workflows/ci.yml'
        (Get-Content -LiteralPath $workflowPath -Raw).Replace(
            '        shell: pwsh', '        shell: bash') |
            Set-Content -LiteralPath $workflowPath

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*job 'scaffold-linux' must validate the manifest PowerShell minimum in a pwsh step*"
    }

    It 'accepts a host validation step whose <Key> key starts the mapping' -ForEach @(
        @{
            Key = 'shell'
            Replacement = @(
                '      - shell: pwsh',
                '        run: ./tools/Test-PowerShellToolchain.ps1') -join "`n"
        }
        @{
            Key = 'run'
            Replacement = @(
                '      - run: ./tools/Test-PowerShellToolchain.ps1',
                '        shell: pwsh') -join "`n"
        }
    ) {
        $fixtureRoot = New-ToolchainFixture "workflow-$Key-first-validation"
        foreach ($workflowName in @('ci.yml', 'full-ci.yml')) {
            $workflowPath = Join-Path $fixtureRoot ".github/workflows/$workflowName"
            $content = Get-Content -LiteralPath $workflowPath -Raw
            $content = [regex]::Replace(
                $content,
                '(?m)^\s{6}- name: Validate PowerShell toolchain\r?\n' +
                    '\s{8}shell: pwsh\r?\n' +
                    '\s{8}run: \./tools/Test-PowerShellToolchain\.ps1\r?$',
                $Replacement)
            $content | Should -Match "(?m)^\s{6}- ${Key}:"
            Set-Content -LiteralPath $workflowPath -Value $content
        }

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'accepts a host validation step with a <Kind> run scalar' -ForEach @(
        @{ Kind = 'literal'; Indicator = '|' }
        @{ Kind = 'folded'; Indicator = '>-' }
    ) {
        $fixtureRoot = New-ToolchainFixture "workflow-$Kind-validation"
        foreach ($workflowName in @('ci.yml', 'full-ci.yml')) {
            $workflowPath = Join-Path $fixtureRoot ".github/workflows/$workflowName"
            $content = Get-Content -LiteralPath $workflowPath -Raw
            $replacement = @(
                "        run: $Indicator",
                '          ./tools/Test-PowerShellToolchain.ps1') -join "`n"
            $content = [regex]::Replace(
                $content,
                '(?m)^\s{8}run: \./tools/Test-PowerShellToolchain\.ps1\r?$',
                $replacement)
            $content | Should -Match "(?m)^\s{8}run: $([regex]::Escape($Indicator))"
            Set-Content -LiteralPath $workflowPath -Value $content
        }

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'accepts a host validation step with a comment on <Key>' -ForEach @(
        @{
            Key = 'run'
            Pattern = 'run: ./tools/Test-PowerShellToolchain.ps1'
        }
        @{
            Key = 'shell'
            Pattern = 'shell: pwsh'
        }
    ) {
        $fixtureRoot = New-ToolchainFixture "workflow-commented-$Key"
        foreach ($workflowName in @('ci.yml', 'full-ci.yml')) {
            $workflowPath = Join-Path $fixtureRoot ".github/workflows/$workflowName"
            $content = Get-Content -LiteralPath $workflowPath -Raw
            $content = $content.Replace($Pattern, "$Pattern # exact host check")
            $content | Should -Match "(?m)^\s+$([regex]::Escape($Pattern)) #"
            Set-Content -LiteralPath $workflowPath -Value $content
        }

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'accepts a host validation step with a <Kind> shell scalar' -ForEach @(
        @{ Kind = 'single-quoted'; Value = "'pwsh'" }
        @{ Kind = 'double-quoted'; Value = '"pwsh"' }
    ) {
        $fixtureRoot = New-ToolchainFixture "workflow-$Kind-shell"
        foreach ($workflowName in @('ci.yml', 'full-ci.yml')) {
            $workflowPath = Join-Path $fixtureRoot ".github/workflows/$workflowName"
            $content = Get-Content -LiteralPath $workflowPath -Raw
            $content = $content.Replace('shell: pwsh', "shell: $Value")
            $content | Should -Match "(?m)^\s+shell: $([regex]::Escape($Value))"
            Set-Content -LiteralPath $workflowPath -Value $content
        }

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'rejects a nested shell value when the step shell is not pwsh' {
        $fixtureRoot = New-ToolchainFixture 'workflow-nested-shell-key'
        foreach ($workflowName in @('ci.yml', 'full-ci.yml')) {
            $workflowPath = Join-Path $fixtureRoot ".github/workflows/$workflowName"
            $content = Get-Content -LiteralPath $workflowPath -Raw
            $content = $content.Replace(
                '        shell: pwsh',
                "        env:`n          shell: pwsh`n        shell: bash")
            Set-Content -LiteralPath $workflowPath -Value $content
        }

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*must validate the manifest PowerShell minimum in a pwsh step*"
    }

    It 'rejects a nested run value when the step has no validation command' {
        $fixtureRoot = New-ToolchainFixture 'workflow-nested-run-key'
        foreach ($workflowName in @('ci.yml', 'full-ci.yml')) {
            $workflowPath = Join-Path $fixtureRoot ".github/workflows/$workflowName"
            $content = Get-Content -LiteralPath $workflowPath -Raw
            $content = $content.Replace(
                '        run: ./tools/Test-PowerShellToolchain.ps1',
                "        env:`n          run: ./tools/Test-PowerShellToolchain.ps1`n        run: Write-Output skipped")
            Set-Content -LiteralPath $workflowPath -Value $content
        }

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*must validate the manifest PowerShell minimum in a pwsh step*"
    }

    It 'ignores Pester text in nested workflow values after an inline run' {
        $fixtureRoot = New-ToolchainFixture 'workflow-nested-command-values'
        $workflowPath = Join-Path $fixtureRoot '.github/workflows/nested-values.yml'
        Set-Content -LiteralPath $workflowPath -Value @(
            'jobs:',
            '  test:',
            '    steps:',
            '      - run: Write-Output ok',
            '        env:',
            '          run: Import-Module Pester -RequiredVersion 5.7.1',
            '          TEST_COMMAND: Invoke-Pester ./tests',
            ('          MODULE_SPEC: "@{ ModuleName = ''Pester''; ' +
                'RequiredVersion = ''5.7.1'' }"'))

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'ignores Pester commands in a nested workflow sequence outside steps' {
        $fixtureRoot = New-ToolchainFixture 'workflow-nested-run-sequence'
        $workflowPath = Join-Path $fixtureRoot '.github/workflows/nested-sequence.yml'
        Set-Content -LiteralPath $workflowPath -Value @(
            'jobs:',
            '  test:',
            '    strategy:',
            '      matrix:',
            '        include:',
            ('          - run: Import-' +
                'Module Pester -RequiredVersion 5.7.1; Invoke-Pester ./tests'),
            '    steps:',
            '      - run: Write-Output ok')

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'validates a step run after a nested sequence' {
        $fixtureRoot = New-ToolchainFixture 'workflow-run-after-nested-sequence'
        $workflowPath = Join-Path $fixtureRoot '.github/workflows/nested-before-run.yml'
        Set-Content -LiteralPath $workflowPath -Value @(
            'jobs:',
            '  test:',
            '    steps:',
            '      - env:',
            '          VALUES:',
            '            - one',
            ('        run: Import-' +
                'Module Pester -RequiredVersion 5.7.1'))

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*copies Pester version '5.7.1'*"
    }

    It 'rejects a host job whose validation command is only in nested metadata' {
        $fixtureRoot = New-ToolchainFixture 'workflow-nested-validation-metadata'
        $workflowPath = Join-Path $fixtureRoot '.github/workflows/ci.yml'
        $content = Get-Content -LiteralPath $workflowPath -Raw
        $content = [regex]::Replace(
            $content,
            '(?m)^  scaffold-linux:\r?\n' +
                '    runs-on: ubuntu-24\.04-arm\r?\n' +
                '    steps:\r?$',
            @(
                '  scaffold-linux:',
                '    runs-on: ubuntu-24.04-arm',
                '    strategy:',
                '      matrix:',
                '        include:',
                '          - shell: pwsh',
                '            run: ./tools/Test-PowerShellToolchain.ps1',
                '    steps:') -join "`n",
            1)
        $content = [regex]::Replace(
            $content,
            '(?m)^      - name: Validate PowerShell toolchain\r?\n' +
                '        shell: pwsh\r?\n' +
                '        run: \./tools/Test-PowerShellToolchain\.ps1\r?$',
            '      - run: Write-Output skipped',
            1)
        Set-Content -LiteralPath $workflowPath -Value $content

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*job 'scaffold-linux' must validate the manifest PowerShell minimum in a pwsh step*"
    }

    It 'accepts a block validation command with a trailing comment' {
        $fixtureRoot = New-ToolchainFixture 'workflow-block-command-comment'
        foreach ($workflowName in @('ci.yml', 'full-ci.yml')) {
            $workflowPath = Join-Path $fixtureRoot ".github/workflows/$workflowName"
            $content = Get-Content -LiteralPath $workflowPath -Raw
            $content = $content.Replace(
                '        run: ./tools/Test-PowerShellToolchain.ps1',
                "        run: |`n          ./tools/Test-PowerShellToolchain.ps1 # validate")
            Set-Content -LiteralPath $workflowPath -Value $content
        }

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'rejects a workflow SDK that drifts from the manifest' {
        $fixtureRoot = New-ToolchainFixture 'workflow-sdk-drift'
        $workflowPath = Join-Path $fixtureRoot '.github/workflows/ci.yml'
        (Get-Content -LiteralPath $workflowPath -Raw).Replace(
            'dotnet-version: 10.0.x', 'dotnet-version: 9.0.x') |
            Set-Content -LiteralPath $workflowPath

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*job 'dotnet-pipes' must use manifest .NET SDK '10.0.x'*"
    }

    It 'rejects a second setup-dotnet version that drifts from the manifest' {
        $fixtureRoot = New-ToolchainFixture 'workflow-second-sdk-drift'
        $workflowPath = Join-Path $fixtureRoot '.github/workflows/ci.yml'
        $content = Get-Content -LiteralPath $workflowPath -Raw
        $replacement = @(
            '      - uses: actions/setup-dotnet',
            '        with:',
            '          dotnet-version: 10.0.x',
            '      - uses: actions/setup-dotnet',
            '        with:',
            '          dotnet-version: 9.0.x') -join "`n"
        $content = [regex]::Replace(
            $content,
            '(?m)^\s{6}- uses: actions/setup-dotnet\r?\n' +
                '\s{8}with:\r?\n' +
                '\s{10}dotnet-version: 10\.0\.x\r?$',
            $replacement,
            1)
        Set-Content -LiteralPath $workflowPath -Value $content

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*job 'dotnet-pipes' must use manifest .NET SDK '10.0.x'*"
    }

    It 'rejects a preview workflow SDK that drifts from the manifest' {
        $fixtureRoot = New-ToolchainFixture 'workflow-preview-sdk-drift'
        $workflowPath = Join-Path $fixtureRoot '.github/workflows/full-ci.yml'
        (Get-Content -LiteralPath $workflowPath -Raw).Replace(
            'dotnet-version: 11.0.x', 'dotnet-version: 12.0.x') |
            Set-Content -LiteralPath $workflowPath

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*job 'scaffold-preview' must use manifest .NET SDK '11.0.x'*"
    }

    It 'rejects a global SDK that drifts from the manifest' {
        $fixtureRoot = New-ToolchainFixture 'global-sdk-drift'
        $globalJsonPath = Join-Path $fixtureRoot 'global.json'
        $globalJson = Get-Content -LiteralPath $globalJsonPath -Raw |
            ConvertFrom-Json -AsHashtable
        $globalJson.sdk.version = '9.0.100'
        $globalJson | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $globalJsonPath

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*sdk.version must select manifest SDK '10.0.x'*"
    }

    It 'rejects malformed global SDK version <Value>' -ForEach @(
        @{ Value = '10.0' }
        @{ Value = '10.0.100.1' }
    ) {
        $fixtureRoot = New-ToolchainFixture "global-sdk-$($Value.Replace('.', '-'))"
        $globalJsonPath = Join-Path $fixtureRoot 'global.json'
        $globalJson = Get-Content -LiteralPath $globalJsonPath -Raw |
            ConvertFrom-Json -AsHashtable
        $globalJson.sdk.version = $Value
        $globalJson | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $globalJsonPath

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*sdk.version must be an exact three-part numeric SDK version*'
    }

    It 'rejects a C# language version that drifts from the manifest' {
        $fixtureRoot = New-ToolchainFixture 'language-version-drift'
        $propsPath = Join-Path $fixtureRoot 'Directory.Build.props'
        (Get-Content -LiteralPath $propsPath -Raw).Replace(
            '<LangVersion>14.0</LangVersion>', '<LangVersion>latest</LangVersion>') |
            Set-Content -LiteralPath $propsPath

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*must set LangVersion '14.0'*"
    }

    It 'rejects a drifted Pester test requirement' {
        $fixtureRoot = New-ToolchainFixture 'test-pester-drift'
        $testPath = Join-Path $fixtureRoot 'tests/Valid.Tests.ps1'
        (Get-Content -LiteralPath $testPath -Raw).Replace(
            "RequiredVersion = '6.2.0'", "RequiredVersion = '6.1.0'") |
            Set-Content -LiteralPath $testPath

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*must require Pester 6.2.0 exactly*'
    }

    It 'accepts a lowercase Pester test requirement' {
        $fixtureRoot = New-ToolchainFixture 'lowercase-test-requirement'
        $testPath = Join-Path $fixtureRoot 'tests/Valid.Tests.ps1'
        (Get-Content -LiteralPath $testPath -Raw).Replace(
            "ModuleName = 'Pester'", "ModuleName = 'pester'") |
            Set-Content -LiteralPath $testPath

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'rejects a drifted Pester test runtime requirement' {
        $fixtureRoot = New-ToolchainFixture 'test-runtime-drift'
        $testPath = Join-Path $fixtureRoot 'tests/Valid.Tests.ps1'
        (Get-Content -LiteralPath $testPath -Raw).Replace(
            '#Requires -Version 7.4', '#Requires -Version 7.2') |
            Set-Content -LiteralPath $testPath

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*must require PowerShell 7.4 exactly*'
    }

    It 'rejects a drifted generated-test runtime requirement' {
        $fixtureRoot = New-ToolchainFixture 'template-runtime-drift'
        $templatePath = Join-Path $fixtureRoot '.agents/Generated.Tests.ps1.tmpl'
        Set-Content -LiteralPath $templatePath -Value @(
            '#Requires -Version 7.2',
            "#Requires -Modules @{ ModuleName = 'Pester'; RequiredVersion = '6.2.0' }",
            "Describe 'Generated' { It 'is never run' { `$true | Should -BeTrue } }")

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*must require PowerShell 7.4 exactly*'
    }

    It 'rejects a drifted shard-runner runtime requirement' {
        $fixtureRoot = New-ToolchainFixture 'runner-runtime-drift'
        $runnerPath = Join-Path $fixtureRoot 'tests/Invoke-PesterShards.ps1'
        (Get-Content -LiteralPath $runnerPath -Raw).Replace(
            '#Requires -Version 7.4', '#Requires -Version 7.2') |
            Set-Content -LiteralPath $runnerPath

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*'tests/Invoke-PesterShards.ps1' must require PowerShell 7.4 exactly*"
    }

    It 'rejects a shard runner without a parameter block' {
        $fixtureRoot = New-ToolchainFixture 'runner-missing-parameters'
        $runnerPath = Join-Path $fixtureRoot 'tests/Invoke-PesterShards.ps1'
        Set-Content -LiteralPath $runnerPath -Value '#Requires -Version 7.4'

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*PesterVersion default must be '6.2.0'*"
    }

    It 'rejects a shard-runner <Kind> PesterVersion default' -ForEach @(
        @{ Kind = 'stale cast'; Default = "[version]'5.7.1'" }
        @{ Kind = 'environment-backed'; Default = '$env:PESTER_VERSION' }
    ) {
        $fixtureRoot = New-ToolchainFixture "runner-$($Kind.Replace(' ', '-'))-default"
        $runnerPath = Join-Path $fixtureRoot 'tests/Invoke-PesterShards.ps1'
        Set-Content -LiteralPath $runnerPath -Value @(
            '#Requires -Version 7.4',
            '[CmdletBinding()]',
            ("param([version] `$Pester" + "Version = $Default)"))

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*PesterVersion default must be '6.2.0'*"
    }

    It 'rejects a drifted copied Pester version in <Kind>' -ForEach @(
        @{
            Kind = 'module command'
            Path = '.github/workflows/drift.yml'
            Content = ('Install-' + 'Module Pester -RequiredVersion ' + ('6.' + '1.0'))
            Version = ('6.' + '1.0')
        }
        @{
            Kind = 'runner invocation'
            Path = 'evals/drift.md'
            Content = './tests/Invoke-PesterShards.ps1 -Pester' +
                'Version ' + ('6.' + '1.0')
            Version = ('6.' + '1.0')
        }
        @{
            Kind = 'runner default'
            Path = 'tools/Drift.ps1'
            Content = "[version] `$Pester" + "Version = '$('6.' + '1.0')'"
            Version = ('6.' + '1.0')
        }
        @{
            Kind = 'module requirement'
            Path = '.agents/Drift.ps1.tmpl'
            Content = "#Requires -Modules @{ Module$('Name') = 'Pester'; RequiredVersion = '$('6.' + '1.0')' }"
            Version = ('6.' + '1.0')
        }
        @{
            Kind = 'module command suffix'
            Path = '.github/workflows/suffix.yml'
            Content = ('Import-' + 'Module Pester -RequiredVersion ' + ('6.2.0' + '.1'))
            Version = ('6.2.0' + '.1')
        }
        @{
            Kind = 'runner invocation suffix'
            Path = 'evals/suffix.md'
            Content = './tests/Invoke-PesterShards.ps1 -Pester' +
                'Version ' + ('6.2.0' + '.1')
            Version = ('6.2.0' + '.1')
        }
        @{
            Kind = 'colon-attached runner invocation'
            Path = 'evals/colon.md'
            Content = './tests/Invoke-PesterShards.ps1 -Pester' +
                'Version:' + ('5.7' + '.1')
            Version = ('5.7' + '.1')
        }
        @{
            Kind = 'continued runner invocation'
            Path = 'evals/continued.md'
            Content = @(
                ('./tests/Invoke-PesterShards.ps1 -Pester' +
                    'Version ' + [char]96)
                ('    ' + ('5.7' + '.1')))
            Version = ('5.7' + '.1')
        }
        @{
            Kind = 'runner default suffix'
            Path = 'tools/Suffix.ps1'
            Content = "[version] `$Pester" + "Version = '$('6.2.0' + '.1')'"
            Version = ('6.2.0' + '.1')
        }
    ) {
        $fixtureRoot = New-ToolchainFixture "copied-$($Kind.Replace(' ', '-'))"
        $driftPath = Join-Path $fixtureRoot $Path
        [IO.Directory]::CreateDirectory((Split-Path -Parent $driftPath)) | Out-Null
        Set-Content -LiteralPath $driftPath -Value $Content

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*copies Pester version '$Version'*"
    }

    It 'ignores a copied Pester version inside a PowerShell <Kind>' -ForEach @(
        @{
            Kind = 'comment'
            Content = '# ./tests/Invoke-PesterShards.ps1 -Pester' +
                'Version 5.7.1'
        }
        @{
            Kind = 'string'
            Content = "`$text = './tests/Invoke-PesterShards.ps1 -Pester" +
                "Version 5.7.1'"
        }
    ) {
        $fixtureRoot = New-ToolchainFixture "copied-version-$Kind"
        Set-Content -LiteralPath (Join-Path $fixtureRoot '.agents/Example.ps1') `
            -Value $Content

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'rejects a stale generated runner version inside a here-string' {
        $fixtureRoot = New-ToolchainFixture 'generated-runner-version'
        $generatorPath = Join-Path $fixtureRoot '.agents/Generator.ps1'
        Set-Content -LiteralPath $generatorPath -Value @(
            "`$text = @'",
            ('./tests/Invoke-PesterShards.ps1 -Pester' + 'Version 5.7.1'),
            "'@")

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*copies Pester version '5.7.1'*"
    }

    It 'accepts an escaped quoted PesterVersion in a workflow scalar' {
        $fixtureRoot = New-ToolchainFixture 'workflow-escaped-runner-version'
        $workflowPath = Join-Path $fixtureRoot '.github/workflows/quoted-version.yml'
        Set-Content -LiteralPath $workflowPath -Value @(
            'jobs:', '  test:', '    steps:',
            ('      - run: "./tests/Invoke-PesterShards.ps1 -Pester' +
                'Version \"6.2.0\""'))

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'ignores a copied Pester version in workflow <Kind>' -ForEach @(
        @{
            Kind = 'comment'
            Command = '# PesterVersion = ''5.7.1'''
        }
        @{
            Kind = 'string'
            Command = 'Write-Output "PesterVersion = ''5.7.1''"'
        }
    ) {
        $fixtureRoot = New-ToolchainFixture "workflow-version-$Kind"
        $workflowPath = Join-Path $fixtureRoot '.github/workflows/version-text.yml'
        Set-Content -LiteralPath $workflowPath -Value @(
            'jobs:', '  test:', '    steps:', '      - run: |',
            "          $Command")

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'rejects nonliteral Pester module pin <Value>' -ForEach @(
        @{ Name = 'environment'; Value = '$env:PESTER_VERSION' }
        @{ Name = 'four-part'; Value = ('6.2.0' + '.1') }
    ) {
        $fixtureRoot = New-ToolchainFixture "module-value-$Name"
        $driftPath = Join-Path $fixtureRoot '.github/workflows/drift.yml'
        [IO.Directory]::CreateDirectory((Split-Path -Parent $driftPath)) | Out-Null
        Set-Content -LiteralPath $driftPath -Value (
            'Import-' + "Module Pester -RequiredVersion $Value")

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*copies Pester version '$Value'*"
    }

    It 'rejects an unverifiable Pester module name in <Form>' -ForEach @(
        @{ Form = 'positional'; Command = 'Import-Module $moduleName -RequiredVersion 5.7.1' }
        @{ Form = 'named'; Command = 'Import-Module -Name $moduleName -RequiredVersion 5.7.1' }
    ) {
        $fixtureRoot = New-ToolchainFixture "dynamic-module-name-$Form"
        $driftPath = Join-Path $fixtureRoot '.agents/Drift.ps1'
        Set-Content -LiteralPath $driftPath -Value @(
            '$moduleName = $env:PESTER_MODULE',
            ($Command.Replace('Import-Module', ('Import-' + 'Module'))))

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*must use a static module name*'
    }

    It 'rejects an unpinned statically assigned Pester module name' {
        $fixtureRoot = New-ToolchainFixture 'assigned-pester-module-name'
        $scriptPath = Join-Path $fixtureRoot '.agents/Drift.ps1'
        Set-Content -LiteralPath $scriptPath -Value @(
            "`$moduleName = 'Pester'",
            'Import-Module $moduleName')

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*invokes Pester without -RequiredVersion 6.2.0*'
    }

    It '<Expectation> a statically assigned Pester module with version <Version>' -ForEach @(
        @{ Expectation = 'accepts'; Version = '6.2.0'; Error = $null }
        @{
            Expectation = 'rejects'
            Version = '5.7.1'
            Error = "*copies Pester version '5.7.1'*"
        }
    ) {
        $fixtureRoot = New-ToolchainFixture "assigned-pester-version-$Version"
        $scriptPath = Join-Path $fixtureRoot '.agents/AssignedModule.ps1'
        Set-Content -LiteralPath $scriptPath -Value @(
            "`$moduleName = 'Pester'",
            "Import-Module `$moduleName -RequiredVersion $Version",
            'Invoke-Pester ./tests')

        if ($null -eq $Error) {
            { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
                Should -Not -Throw
        }
        else {
            { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
                Should -Throw $Error
        }
    }

    It 'rejects a stale Pester import through the ipmo alias' {
        $fixtureRoot = New-ToolchainFixture 'stale-ipmo-alias'
        Set-Content -LiteralPath (Join-Path $fixtureRoot '.agents/Alias.ps1') `
            -Value 'ipmo Pester -RequiredVersion 5.7.1'

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*copies Pester version '5.7.1'*"
    }

    It 'accepts a pinned Pester import through the ipmo alias' {
        $fixtureRoot = New-ToolchainFixture 'pinned-ipmo-alias'
        Set-Content -LiteralPath (Join-Path $fixtureRoot '.agents/Alias.ps1') `
            -Value @(
                'ipmo Pester -RequiredVersion 6.2.0',
                'Invoke-Pester ./tests')

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'rejects a <Form> wildcard target that can resolve to Pester' -ForEach @(
        @{
            Form = 'floating'
            Command = 'Import-' + 'Module Pester*'
        }
        @{
            Form = 'versioned'
            Command = 'Import-' +
                'Module Pester* -RequiredVersion 5.7.1'
        }
    ) {
        $fixtureRoot = New-ToolchainFixture "wildcard-module-$Form"
        Set-Content -LiteralPath (Join-Path $fixtureRoot '.agents/Drift.ps1') `
            -Value $Command

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*must use the exact module name 'Pester'*"
    }

    It 'rejects an unpinned Pester target in a static <Form>' -ForEach @(
        @{
            Form = 'comma array'
            Command = 'Import-Module Pester,Other'
        }
        @{
            Form = 'array expression'
            Command = "Import-Module @('Other','Pester')"
        }
    ) {
        $fixtureRoot = New-ToolchainFixture "static-array-$($Form.Replace(' ', '-'))"
        Set-Content -LiteralPath (Join-Path $fixtureRoot '.agents/Drift.ps1') `
            -Value $Command

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*invokes Pester without -RequiredVersion 6.2.0*'
    }

    It 'rejects a splatted <Command> module invocation' -ForEach @(
        @{ Command = 'Import-Module' }
        @{ Command = 'Install-Module' }
    ) {
        $fixtureRoot = New-ToolchainFixture "splatted-$Command"
        $scriptPath = Join-Path $fixtureRoot '.agents/Drift.ps1'
        Set-Content -LiteralPath $scriptPath -Value @(
            "`$arguments = @{ Name = 'Pester'; RequiredVersion = '5.7.1' }",
            "$Command @arguments")

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*must not use splatting for module validation*'
    }

    It 'rejects a reordered stale Pester module pin' {
        $fixtureRoot = New-ToolchainFixture 'reordered-module-pin'
        $driftPath = Join-Path $fixtureRoot '.github/workflows/drift.yml'
        [IO.Directory]::CreateDirectory((Split-Path -Parent $driftPath)) | Out-Null
        Set-Content -LiteralPath $driftPath -Value (
            'Install-' + 'Module -RequiredVersion ' + ('5.7' + '.1') + ' -Name Pester')

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*copies Pester version '5.7.1'*"
    }

    It 'rejects an attached-name stale Pester module pin' {
        $fixtureRoot = New-ToolchainFixture 'attached-module-name'
        $driftPath = Join-Path $fixtureRoot '.github/workflows/drift.yml'
        [IO.Directory]::CreateDirectory((Split-Path -Parent $driftPath)) | Out-Null
        Set-Content -LiteralPath $driftPath -Value (
            'Install-' + 'Module -Name:Pester -RequiredVersion ' + ('5.7' + '.1'))

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*copies Pester version '5.7.1'*"
    }

    It 'rejects a stale lowercase Pester module pin in <Form>' -ForEach @(
        @{ Form = 'positional'; Command = 'Import-' + 'Module pester -RequiredVersion ' + ('5.7' + '.1') }
        @{ Form = 'named'; Command = 'Install-' + 'Module -Name pester -RequiredVersion ' + ('5.7' + '.1') }
    ) {
        $fixtureRoot = New-ToolchainFixture "lowercase-pester-$Form"
        $driftPath = Join-Path $fixtureRoot '.github/workflows/drift.yml'
        [IO.Directory]::CreateDirectory((Split-Path -Parent $driftPath)) | Out-Null
        Set-Content -LiteralPath $driftPath -Value $Command

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*copies Pester version '5.7.1'*"
    }

    It 'rejects a stale second module command on one line' {
        $fixtureRoot = New-ToolchainFixture 'multiple-module-commands'
        $driftPath = Join-Path $fixtureRoot '.github/workflows/drift.yml'
        [IO.Directory]::CreateDirectory((Split-Path -Parent $driftPath)) | Out-Null
        Set-Content -LiteralPath $driftPath -Value (
            'Install-Module Other; Install-' +
            'Module Pester -RequiredVersion ' + ('5.7' + '.1'))

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*copies Pester version '5.7.1'*"
    }

    It 'rejects a stale module command nested in <Kind> control flow' -ForEach @(
        @{
            Kind = 'script'
            Path = '.agents/Drift.ps1'
            Content = 'if ($true) { Import-' +
                "Module Pester -RequiredVersion $('5.7' + '.1') }"
        }
        @{
            Kind = 'workflow'
            Path = '.github/workflows/drift.yml'
            Content = @(
                'jobs:',
                '    test:',
                '        steps:',
                '            - run: |',
                ('                if ($true) { Import-' +
                    'Module Pester -RequiredVersion 5.7.1 }'))
        }
    ) {
        $fixtureRoot = New-ToolchainFixture "nested-$Kind-module-command"
        $driftPath = Join-Path $fixtureRoot $Path
        [IO.Directory]::CreateDirectory((Split-Path -Parent $driftPath)) | Out-Null
        Set-Content -LiteralPath $driftPath -Value $Content

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*copies Pester version '5.7.1'*"
    }

    It 'rejects a stale double-quoted module name and version' {
        $fixtureRoot = New-ToolchainFixture 'double-quoted-module-command'
        $driftPath = Join-Path $fixtureRoot '.agents/Drift.ps1'
        Set-Content -LiteralPath $driftPath -Value (
            'Import-' + 'Module "Pester" -RequiredVersion "' +
            ('5.7' + '.1') + '"')

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*copies Pester version '5.7.1'*"
    }

    It 'ignores non-executing <Kind> module command text in a script' -ForEach @(
        @{ Kind = 'comment'; Content = '# Import-Module Pester -RequiredVersion 5.7.1' }
        @{ Kind = 'string'; Content = "`$text = 'Import-Module Pester -RequiredVersion 5.7.1'" }
        @{
            Kind = 'function'
            Content = 'function Import-Tests { Import-' +
                'Module Pester -RequiredVersion 5.7.1 }'
        }
        @{
            Kind = 'assigned scriptblock'
            Content = '$importTests = { Import-' +
                'Module Pester -RequiredVersion 5.7.1 }'
        }
    ) {
        $fixtureRoot = New-ToolchainFixture "script-$Kind-module-command"
        Set-Content -LiteralPath (Join-Path $fixtureRoot '.agents/Example.ps1') `
            -Value $Content

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'ignores a deferred Pester module command in <Kind>' -ForEach @(
        @{
            Kind = 'workflow function'
            Path = '.github/workflows/deferred.yml'
            Content = @(
                'jobs:', '  test:', '    steps:', '      - run: |',
                ('          function Import-Tests { Import-' +
                    'Module Pester -RequiredVersion 5.7.1 }'))
        }
        @{
            Kind = 'Markdown assigned scriptblock'
            Path = 'docs/deferred.md'
            Content = @(
                '```pwsh',
                ('$importTests = { Import-' +
                    'Module Pester -RequiredVersion 5.7.1 }'),
                '```')
        }
    ) {
        $fixtureRoot = New-ToolchainFixture "deferred-$($Kind.Replace(' ', '-'))"
        $path = Join-Path $fixtureRoot $Path
        [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
        Set-Content -LiteralPath $path -Value $Content

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'rejects a stale generated module command inside a here-string' {
        $fixtureRoot = New-ToolchainFixture 'generated-module-command'
        $generatorPath = Join-Path $fixtureRoot '.agents/Generator.ps1'
        Set-Content -LiteralPath $generatorPath -Value @(
            "`$text = @'",
            ('Import-' + 'Module Pester -RequiredVersion ' + ('5.7' + '.1')),
            "'@")

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*copies Pester version '5.7.1'*"
    }

    It '<Expectation> a continued module command in <Kind>' -ForEach @(
        @{
            Kind = 'Markdown fence'
            Path = 'docs/continued-pinned.md'
            Version = '6.2.0'
            Expectation = 'accepts'
            Error = $null
        }
        @{
            Kind = 'indented Markdown'
            Path = 'docs/continued-indented-pinned.md'
            Version = '6.2.0'
            Expectation = 'accepts'
            Error = $null
        }
        @{
            Kind = 'generated here-string'
            Path = '.agents/ContinuedPinned.ps1'
            Version = '6.2.0'
            Expectation = 'accepts'
            Error = $null
        }
        @{
            Kind = 'Markdown fence'
            Path = 'docs/continued-stale.md'
            Version = '5.7.1'
            Expectation = 'rejects'
            Error = "*copies Pester version '5.7.1'*"
        }
        @{
            Kind = 'indented Markdown'
            Path = 'docs/continued-indented-stale.md'
            Version = '5.7.1'
            Expectation = 'rejects'
            Error = "*copies Pester version '5.7.1'*"
        }
        @{
            Kind = 'generated here-string'
            Path = '.agents/ContinuedStale.ps1'
            Version = '5.7.1'
            Expectation = 'rejects'
            Error = "*copies Pester version '5.7.1'*"
        }
    ) {
        $fixtureRoot = New-ToolchainFixture (
            "continued-$($Kind.Replace(' ', '-'))-$Version")
        $path = Join-Path $fixtureRoot $Path
        [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
        $commandLine = 'Import-' + 'Module Pester ' + [char]96
        $content = switch ($Kind) {
            'Markdown fence' {
                @('```pwsh', $commandLine, "    -RequiredVersion $Version", '```')
            }
            'indented Markdown' {
                @("    $commandLine", "        -RequiredVersion $Version")
            }
            'generated here-string' {
                @("`$text = @'", $commandLine,
                    "    -RequiredVersion $Version", "'@")
            }
        }
        Set-Content -LiteralPath $path -Value $content

        if ($null -eq $Error) {
            { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
                Should -Not -Throw
        }
        else {
            { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
                Should -Throw $Error
        }
    }

    It 'rejects ModuleVersion as an exact Pester requirement' {
        $fixtureRoot = New-ToolchainFixture 'minimum-module-version'
        $driftPath = Join-Path $fixtureRoot '.agents/Drift.ps1.tmpl'
        Set-Content -LiteralPath $driftPath -Value (
            "#Requires -Modules @{ Module$('Name') = 'Pester'; Module" +
            "Version = '6.2.0' }")

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*must use RequiredVersion for its Pester module requirement*'
    }

    It 'ignores a Pester module requirement inside a PowerShell <Kind>' -ForEach @(
        @{
            Kind = 'comment'
            Content = '# @{ ModuleName = ''Pester''; ModuleVersion = ''5.7.1'' }'
        }
        @{
            Kind = 'string'
            Content = '$text = "@{ ModuleName = ''Pester''; ' +
                'ModuleVersion = ''5.7.1'' }"'
        }
    ) {
        $fixtureRoot = New-ToolchainFixture "module-requirement-$Kind"
        Set-Content -LiteralPath (Join-Path $fixtureRoot '.agents/Example.ps1') `
            -Value $Content

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'rejects a stale generated module requirement inside a here-string' {
        $fixtureRoot = New-ToolchainFixture 'generated-module-requirement'
        $generatorPath = Join-Path $fixtureRoot '.agents/Generator.ps1'
        Set-Content -LiteralPath $generatorPath -Value @(
            "`$text = @'",
            ('#Requires -Modules @{ ModuleName = ''Pester''; ' +
                'RequiredVersion = ''5.7.1'' }'),
            "'@")

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*copies Pester version '5.7.1'*"
    }

    It 'rejects a stale multiline Pester module requirement' {
        $fixtureRoot = New-ToolchainFixture 'multiline-module-requirement'
        $templatePath = Join-Path $fixtureRoot '.agents/Drift.ps1.tmpl'
        Set-Content -LiteralPath $templatePath -Value @(
            '$requirement = @{',
            "    ModuleName = 'Pester'",
            "    RequiredVersion = '5.7.1'",
            '}')

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*copies Pester version '5.7.1'*"
    }

    It 'rejects a dynamic RequiredVersion for a static Pester requirement' {
        $fixtureRoot = New-ToolchainFixture 'dynamic-module-requirement-version'
        $scriptPath = Join-Path $fixtureRoot '.agents/Drift.ps1'
        Set-Content -LiteralPath $scriptPath -Value @(
            "`$version = '6.2.0'",
            '$requirement = @{',
            "    ModuleName = 'Pester'",
            '    RequiredVersion = $version',
            '}')

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*must use a static RequiredVersion for its Pester module requirement*'
    }

    It 'rejects an unverifiable <Kind> module requirement name' -ForEach @(
        @{ Kind = 'dynamic'; Value = '$moduleName' }
        @{ Kind = 'wildcard'; Value = "'Pester*'" }
    ) {
        $fixtureRoot = New-ToolchainFixture "unverifiable-$Kind-requirement-name"
        $scriptPath = Join-Path $fixtureRoot '.agents/Drift.ps1'
        Set-Content -LiteralPath $scriptPath -Value @(
            "`$moduleName = 'Pester'",
            ('$requirement = @{ ModuleName = ' + $Value +
                "; RequiredVersion = '5.7.1' }"))

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*Pester module requirement must use the exact static ModuleName*'
    }

    It 'rejects a stale Pester module requirement in <Kind>' -ForEach @(
        @{
            Kind = 'Markdown fence'
            Path = 'docs/module-requirement.md'
            Content = @(
                '```pwsh',
                '$requirement = @{',
                "    RequiredVersion = '5.7.1'",
                "    ModuleName = 'Pester'",
                '}',
                '```')
        }
        @{
            Kind = 'workflow block'
            Path = '.github/workflows/module-requirement.yml'
            Content = @(
                'jobs:', '  test:', '    steps:', '      - run: |',
                ('          #Requires -Modules @{ RequiredVersion = ' +
                    "'5.7.1'; ModuleName = 'Pester' }"))
        }
        @{
            Kind = 'indented Markdown'
            Path = 'docs/indented-module-requirement.md'
            Content = @(
                '    $requirement = @{',
                "        RequiredVersion = '5.7.1'",
                "        ModuleName = 'Pester'",
                '    }')
        }
    ) {
        $fixtureRoot = New-ToolchainFixture (
            "scoped-requirement-$($Kind.Replace(' ', '-'))")
        $path = Join-Path $fixtureRoot $Path
        [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
        Set-Content -LiteralPath $path -Value $Content

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*copies Pester version '5.7.1'*"
    }

    It 'rejects a quoted ModuleName key in <Kind>' -ForEach @(
        @{
            Kind = 'Markdown fence'
            Path = 'docs/quoted-module-key.md'
            Content = @(
                '```pwsh',
                ('$requirement = @{ ''ModuleName'' = ''Pester''; ' +
                    'RequiredVersion = ''5.7.1'' }'),
                '```')
        }
        @{
            Kind = 'workflow block'
            Path = '.github/workflows/quoted-module-key.yml'
            Content = @(
                'jobs:', '  test:', '    steps:', '      - run: |',
                ('          $requirement = @{ ''ModuleName'' = ''Pester''; ' +
                    'RequiredVersion = ''5.7.1'' }'))
        }
    ) {
        $fixtureRoot = New-ToolchainFixture (
            "quoted-module-key-$($Kind.Replace(' ', '-'))")
        $path = Join-Path $fixtureRoot $Path
        [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
        Set-Content -LiteralPath $path -Value $Content

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*copies Pester version '5.7.1'*"
    }

    It 'rejects a reversed-order stale Pester module requirement' {
        $fixtureRoot = New-ToolchainFixture 'reversed-module-requirement'
        $driftPath = Join-Path $fixtureRoot '.agents/Drift.ps1.tmpl'
        Set-Content -LiteralPath $driftPath -Value (
            "#Requires -Modules @{ RequiredVersion = '$('5.7' + '.1')'; " +
            "Module$('Name') = 'Pester' }")

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*copies Pester version '5.7.1'*"
    }

    It 'accepts lowercase RequiredVersion in a Pester module requirement' {
        $fixtureRoot = New-ToolchainFixture 'lowercase-required-version'
        $testPath = Join-Path $fixtureRoot 'tests/Valid.Tests.ps1'
        (Get-Content -LiteralPath $testPath -Raw).Replace(
            'RequiredVersion', 'requiredversion') |
            Set-Content -LiteralPath $testPath

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'accepts a positional Pester module name after parameter arguments' {
        $fixtureRoot = New-ToolchainFixture 'reordered-positional-module-name'
        $scriptPath = Join-Path $fixtureRoot '.agents/Example.ps1'
        Set-Content -LiteralPath $scriptPath -Value (
            'Import-' + 'Module -RequiredVersion 6.2.0 Pester')

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'rejects an unpinned Pester <Action>' -ForEach @(
        @{ Action = 'installation'; Command = ('Install-' + 'Module Pester -Force') }
        @{ Action = 'import'; Command = ('Import-' + 'Module Pester -Force') }
    ) {
        $fixtureRoot = New-ToolchainFixture "unpinned-$Action"
        $driftPath = Join-Path $fixtureRoot '.github/workflows/drift.yml'
        [IO.Directory]::CreateDirectory((Split-Path -Parent $driftPath)) | Out-Null
        Set-Content -LiteralPath $driftPath -Value $Command

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*invokes Pester without -RequiredVersion 6.2.0*'
    }

    It 'rejects floating Invoke-Pester guidance in a root file' {
        $fixtureRoot = New-ToolchainFixture 'floating-invoke'
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'CONTRIBUTING.md') -Value (
            'Run `Invoke-' + 'Pester ./tests`.')

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw ('*invokes Invoke-' +
                'Pester without a preceding pinned Pester import*')
    }

    It 'ignores non-executing <Kind> Invoke-Pester text' -ForEach @(
        @{
            Kind = 'workflow comment'
            Path = '.github/workflows/comment.yml'
            Content = @(
                'jobs:', '  test:', '    steps:', '      - run: |',
                ('          # Invoke-' + 'Pester is documented here'))
        }
        @{
            Kind = 'workflow string'
            Path = '.github/workflows/string.yml'
            Content = @(
                'jobs:', '  test:', '    steps:', '      - run: |',
                ("          Write-Output 'Invoke-" + "Pester is documented here'"))
        }
        @{
            Kind = 'Markdown prose'
            Path = 'docs/mention.md'
            Content = 'The Invoke-' + 'Pester command runs the test suite.'
        }
        @{
            Kind = 'Markdown fenced comment'
            Path = 'docs/comment.md'
            Content = @('```pwsh', ('# Invoke-' + 'Pester is documented here'), '```')
        }
    ) {
        $fixtureRoot = New-ToolchainFixture "non-executing-$($Kind.Replace(' ', '-'))"
        $path = Join-Path $fixtureRoot $Path
        [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
        Set-Content -LiteralPath $path -Value $Content

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'ignores a module command in ordinary Markdown prose' {
        $fixtureRoot = New-ToolchainFixture 'markdown-module-prose'
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'CONTRIBUTING.md') `
            -Value ('Import-' +
                'Module Pester -RequiredVersion 5.7.1 is legacy prose.')

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'rejects an import in a different <Kind> Markdown code block' -ForEach @(
        @{ Kind = 'backtick'; Indent = ''; Open = '```pwsh'; Close = '```' }
        @{ Kind = 'indented backtick'; Indent = '    '; Open = '```pwsh'; Close = '```' }
        @{ Kind = 'indented tilde'; Indent = '    '; Open = '~~~pwsh'; Close = '~~~' }
        @{ Kind = 'long backtick'; Indent = ''; Open = '````pwsh'; Close = '````' }
    ) {
        $fixtureRoot = New-ToolchainFixture "markdown-$($Kind.Replace(' ', '-'))-scope"
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'CONTRIBUTING.md') -Value @(
            "$Indent$Open",
            "$Indent Import-Module Pester -RequiredVersion 6.2.0",
            "$Indent$Close",
            "$Indent$Open",
            "$Indent Invoke-Pester ./tests",
            "$Indent$Close")

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw ('*invokes Invoke-' +
                'Pester without a preceding pinned Pester import*')
    }

    It 'rejects an unpinned Invoke-Pester command in an indented Markdown block' {
        $fixtureRoot = New-ToolchainFixture 'markdown-indented-code'
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'CONTRIBUTING.md') `
            -Value ('    Invoke-' + 'Pester ./tests')

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw ('*invokes Invoke-' +
                'Pester without a preceding pinned Pester import*')
    }

        It 'rejects a pinned import in a different workflow step' {
                $fixtureRoot = New-ToolchainFixture 'workflow-step-scope'
                $workflowPath = Join-Path $fixtureRoot '.github/workflows/drift.yml'
                [IO.Directory]::CreateDirectory((Split-Path -Parent $workflowPath)) | Out-Null
                Set-Content -LiteralPath $workflowPath -Value @'
jobs:
    test:
        steps:
            - run: Import-Module Pester -RequiredVersion 6.2.0
            - run: Invoke-Pester ./tests
'@

                { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
                        Should -Throw ('*invokes Invoke-' +
                                'Pester without a preceding pinned Pester import*')
        }

        It 'rejects a pinned import after the workflow invocation' {
                $fixtureRoot = New-ToolchainFixture 'workflow-import-order'
                $workflowPath = Join-Path $fixtureRoot '.github/workflows/drift.yml'
                [IO.Directory]::CreateDirectory((Split-Path -Parent $workflowPath)) | Out-Null
                Set-Content -LiteralPath $workflowPath -Value @'
jobs:
    test:
        steps:
            - run: |
                    Invoke-Pester ./tests
                    Import-Module Pester -RequiredVersion 6.2.0
'@

                { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
                        Should -Throw ('*invokes Invoke-' +
                                'Pester without a preceding pinned Pester import*')
        }

    It 'rejects a non-executing <Kind> import before the workflow invocation' -ForEach @(
        @{ Kind = 'commented'; Import = '# Import-Module Pester -RequiredVersion 6.2.0' }
        @{ Kind = 'quoted'; Import = "Write-Output 'Import-Module Pester -RequiredVersion 6.2.0'" }
        @{ Kind = 'function'; Import = 'function Import-PesterForLater { Import-Module Pester -RequiredVersion 6.2.0 }' }
    ) {
        $fixtureRoot = New-ToolchainFixture "workflow-$Kind-import"
        $workflowPath = Join-Path $fixtureRoot '.github/workflows/drift.yml'
        [IO.Directory]::CreateDirectory((Split-Path -Parent $workflowPath)) | Out-Null
        Set-Content -LiteralPath $workflowPath -Value @(
            'jobs:',
            '  test:',
            '    steps:',
            '      - run: |',
            "          $Import",
            '          Invoke-Pester ./tests')

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw ('*invokes Invoke-' +
                'Pester without a preceding pinned Pester import*')
    }

    It 'rejects an import in a scriptblock passed as command data' {
        $fixtureRoot = New-ToolchainFixture 'workflow-scriptblock-data-import'
        $workflowPath = Join-Path $fixtureRoot '.github/workflows/scriptblock-data.yml'
        Set-Content -LiteralPath $workflowPath -Value @(
            'jobs:', '  test:', '    steps:', '      - run: |',
            ('          Write-Output { Import-' +
                'Module Pester -RequiredVersion 6.2.0 }'),
            ('          Invoke-' + 'Pester ./tests'))

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw ('*invokes Invoke-' +
                'Pester without a preceding pinned Pester import*')
    }

    It 'accepts a pinned import with its nested invocation in <Kind>' -ForEach @(
        @{
            Kind = 'workflow'
            Path = '.github/workflows/nested-pinned.yml'
            Content = @(
                'jobs:', '  test:', '    steps:', '      - run: |',
                ('          1..1 | ForEach-Object { Import-' +
                    'Module Pester -RequiredVersion 6.2.0; Invoke-' +
                    'Pester ./tests }'))
        }
        @{
            Kind = 'Markdown fence'
            Path = 'docs/nested-pinned.md'
            Content = @(
                '```pwsh',
                ('1..1 | ForEach-Object { Import-' +
                    'Module Pester -RequiredVersion 6.2.0; Invoke-' +
                    'Pester ./tests }'),
                '```')
        }
    ) {
        $fixtureRoot = New-ToolchainFixture "nested-pinned-$($Kind.Replace(' ', '-'))"
        $path = Join-Path $fixtureRoot $Path
        [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
        Set-Content -LiteralPath $path -Value $Content

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'rejects an unpinned nested Invoke-Pester command in <Kind>' -ForEach @(
        @{
            Kind = 'workflow'
            Path = '.github/workflows/nested.yml'
            Content = @(
                'jobs:', '  test:', '    steps:', '      - run: |',
                ('          1..1 | ForEach-Object { Invoke-' + 'Pester ./tests }'))
        }
        @{
            Kind = 'Markdown fence'
            Path = 'docs/nested.md'
            Content = @(
                '```pwsh',
                ('1..1 | ForEach-Object { Invoke-' + 'Pester ./tests }'),
                '```')
        }
    ) {
        $fixtureRoot = New-ToolchainFixture "nested-invoke-$($Kind.Replace(' ', '-'))"
        $path = Join-Path $fixtureRoot $Path
        [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
        Set-Content -LiteralPath $path -Value $Content

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw ('*invokes Invoke-' +
                'Pester without a preceding pinned Pester import*')
    }

    It 'rejects an unpinned nested Invoke-Pester through <Alias>' -ForEach @(
        @{ Alias = '%' }
        @{ Alias = 'ForEach' }
        @{ Alias = '?' }
        @{ Alias = 'where' }
    ) {
        $fixtureRoot = New-ToolchainFixture (
            "nested-alias-$($Alias.Replace('%', 'percent').Replace('?', 'question'))")
        $scriptPath = Join-Path $fixtureRoot '.agents/AliasBlock.ps1'
        Set-Content -LiteralPath $scriptPath -Value (
            '1..1 | ' + $Alias + ' { Invoke-Pester ./tests }')

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw ('*invokes Invoke-' +
                'Pester without a preceding pinned Pester import*')
    }

    It 'rejects an unpinned assignment RHS Invoke-Pester command in <Kind>' -ForEach @(
        @{
            Kind = 'workflow'
            Path = '.github/workflows/assignment.yml'
            Content = @(
                'jobs:', '  test:', '    steps:', '      - run: |',
                ('          $result = Invoke-' + 'Pester ./tests'))
        }
        @{
            Kind = 'Markdown fence'
            Path = 'docs/assignment.md'
            Content = @(
                '```pwsh',
                ('$result = Invoke-' + 'Pester ./tests'),
                '```')
        }
    ) {
        $fixtureRoot = New-ToolchainFixture "assignment-invoke-$($Kind.Replace(' ', '-'))"
        $path = Join-Path $fixtureRoot $Path
        [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
        Set-Content -LiteralPath $path -Value $Content

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw ('*invokes Invoke-' +
                'Pester without a preceding pinned Pester import*')
    }

    It 'rejects a stale Pester command in quoted workflow <Kind>' -ForEach @(
        @{
            Kind = 'module setup'
            Command = 'Import-' + 'Module Pester -RequiredVersion 5.7.1'
            Error = "*copies Pester version '5.7.1'*"
        }
        @{
            Kind = 'invocation'
            Command = 'Invoke-' + 'Pester ./tests'
            Error = '*invokes Invoke-Pester without a preceding pinned Pester import*'
        }
    ) {
        $fixtureRoot = New-ToolchainFixture "quoted-workflow-$($Kind.Replace(' ', '-'))"
        $workflowPath = Join-Path $fixtureRoot '.github/workflows/quoted.yml'
        [IO.Directory]::CreateDirectory((Split-Path -Parent $workflowPath)) | Out-Null
        Set-Content -LiteralPath $workflowPath -Value @(
            'jobs:', '  test:', '    steps:', "      - run: '$Command'")

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw $Error
    }

    It 'rejects a stale module command in a <Kind> run scalar with a comment' -ForEach @(
        @{ Kind = 'single-quoted'; Quote = "'" }
        @{ Kind = 'double-quoted'; Quote = '"' }
    ) {
        $fixtureRoot = New-ToolchainFixture "commented-$Kind-workflow"
        $workflowPath = Join-Path $fixtureRoot '.github/workflows/quoted.yml'
        [IO.Directory]::CreateDirectory((Split-Path -Parent $workflowPath)) | Out-Null
        $command = 'Import-' + 'Module Pester -RequiredVersion 5.7.1'
        Set-Content -LiteralPath $workflowPath -Value @(
            'jobs:', '  test:', '    steps:',
            "      - run: $Quote$command$Quote # exact setup")

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*copies Pester version '5.7.1'*"
    }

    It 'rejects an unpinned invocation after escaped text in a quoted workflow scalar' {
        $fixtureRoot = New-ToolchainFixture 'quoted-workflow-escaped-prefix'
        $workflowPath = Join-Path $fixtureRoot '.github/workflows/quoted.yml'
        [IO.Directory]::CreateDirectory((Split-Path -Parent $workflowPath)) | Out-Null
        Set-Content -LiteralPath $workflowPath -Value @(
            'jobs:', '  test:', '    steps:',
            ('      - run: "Write-Output \"x\"; Invoke-' +
                'Pester ./tests"'))

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw ('*invokes Invoke-' +
                'Pester without a preceding pinned Pester import*')
    }

    It 'rejects an unpinned call-operator Invoke-Pester command' {
        $fixtureRoot = New-ToolchainFixture 'workflow-call-operator-invocation'
        $workflowPath = Join-Path $fixtureRoot '.github/workflows/call-operator.yml'
        [IO.Directory]::CreateDirectory((Split-Path -Parent $workflowPath)) | Out-Null
        Set-Content -LiteralPath $workflowPath -Value @(
            'jobs:', '  test:', '    steps:',
            ('      - run: & ''Invoke-' + 'Pester'' ./tests'))

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw ('*invokes Invoke-' +
                'Pester without a preceding pinned Pester import*')
    }

        It 'accepts an inline workflow step with a preceding pinned import' {
                $fixtureRoot = New-ToolchainFixture 'inline-workflow-step'
                $workflowPath = Join-Path $fixtureRoot '.github/workflows/inline.yml'
                [IO.Directory]::CreateDirectory((Split-Path -Parent $workflowPath)) | Out-Null
                Set-Content -LiteralPath $workflowPath -Value @'
jobs:
    test:
        steps:
            - run: Import-Module Pester -RequiredVersion 6.2.0; Invoke-Pester ./tests
'@

                { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
                        Should -Not -Throw
        }

            It 'accepts a folded workflow <Indicator> with a pinned import' -ForEach @(
                @{ Indicator = '>'; Name = 'folded' }
                @{ Indicator = '>-'; Name = 'folded-strip' }
            ) {
                $fixtureRoot = New-ToolchainFixture "workflow-$Name"
                $workflowPath = Join-Path $fixtureRoot '.github/workflows/folded.yml'
                [IO.Directory]::CreateDirectory((Split-Path -Parent $workflowPath)) | Out-Null
                Set-Content -LiteralPath $workflowPath -Value @(
                    'jobs:', '  test:', '    steps:', "      - run: $Indicator",
                    ('          Import-' + 'Module Pester'),
                    '          -RequiredVersion 6.2.0;',
                    ('          Invoke-' + 'Pester ./tests'))

                { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
                    Should -Not -Throw
            }

    It 'accepts the shard runner validated Pester version variable' {
        $fixtureRoot = New-ToolchainFixture 'runner-version-variable'
        $runnerPath = Join-Path $fixtureRoot 'tests/Invoke-PesterShards.ps1'
        Set-Content -LiteralPath $runnerPath -Value @(
            '#Requires -Version 7.4',
            '[CmdletBinding()]',
            "param([version] `$PesterVersion = '6.2.0')",
            ('Import-' + 'Module Pester -RequiredVersion $PesterVersion'),
            ('Invoke-' + 'Pester'))

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'accepts a static double-quoted pinned import' {
        $fixtureRoot = New-ToolchainFixture 'double-quoted-pinned-import'
        $workflowPath = Join-Path $fixtureRoot '.github/workflows/inline.yml'
        [IO.Directory]::CreateDirectory((Split-Path -Parent $workflowPath)) | Out-Null
        Set-Content -LiteralPath $workflowPath -Value @'
jobs:
    test:
        steps:
            - run: Import-Module "Pester" -RequiredVersion "6.2.0"; Invoke-Pester ./tests
'@

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'accepts a pinned import and invocation in one inline Markdown span' {
        $fixtureRoot = New-ToolchainFixture 'markdown-inline-pinned-invocation'
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'CONTRIBUTING.md') `
            -Value ('Run `Import-' +
                'Module Pester -RequiredVersion 6.2.0; Invoke-' +
                'Pester ./tests`.')

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'rejects an import in a different inline Markdown span' {
        $fixtureRoot = New-ToolchainFixture 'markdown-separate-inline-spans'
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'CONTRIBUTING.md') `
            -Value ('Run `Import-' +
                'Module Pester -RequiredVersion 6.2.0` and then `Invoke-' +
                'Pester ./tests`.')

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw ('*invokes Invoke-' +
                'Pester without a preceding pinned Pester import*')
    }

    It 'keeps a fenced import when the block contains inline-code delimiters' {
        $fixtureRoot = New-ToolchainFixture 'markdown-inline-code-in-fence'
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'CONTRIBUTING.md') -Value @'
```pwsh
Import-Module Pester -RequiredVersion 6.2.0
# The literal form is `Invoke-Pester`.
Invoke-Pester ./tests
```
'@

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'rejects a fenced comment whose inline text resembles a pinned import' {
        $fixtureRoot = New-ToolchainFixture 'markdown-fenced-inline-comment'
        Set-Content -LiteralPath (Join-Path $fixtureRoot 'CONTRIBUTING.md') -Value @'
```pwsh
# `Import-Module Pester -RequiredVersion 6.2.0`
Invoke-Pester ./tests
```
'@

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw ('*invokes Invoke-' +
                'Pester without a preceding pinned Pester import*')
    }

    It 'accepts a pinned generated command inside a here-string' {
        $fixtureRoot = New-ToolchainFixture 'generated-here-string'
        $generatorPath = Join-Path $fixtureRoot '.agents/Generator.ps1'
        Set-Content -LiteralPath $generatorPath -Value @(
            "`$text = @'",
            ('Import-' + 'Module Pester -RequiredVersion 6.2.0'),
            ('Invoke-' + 'Pester ./tests'),
            "'@")

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'ignores non-executing <Kind> Invoke-Pester text inside a here-string' -ForEach @(
        @{ Kind = 'comment'; Content = '# Invoke-' + 'Pester ./tests' }
        @{
            Kind = 'string'
            Content = "Write-Output 'Invoke-" + "Pester ./tests'"
        }
    ) {
        $fixtureRoot = New-ToolchainFixture "generated-here-string-$Kind"
        $generatorPath = Join-Path $fixtureRoot '.agents/Generator.ps1'
        Set-Content -LiteralPath $generatorPath -Value @(
            "`$text = @'",
            $Content,
            "'@")

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'ignores comment text resembling a here-string opener' {
        $fixtureRoot = New-ToolchainFixture 'comment-here-string-opener'
        $generatorPath = Join-Path $fixtureRoot '.agents/Generator.ps1'
        Set-Content -LiteralPath $generatorPath -Value @(
            ('Import-' + 'Module Pester -RequiredVersion 6.2.0'),
            "# delimiter example: @'",
            ('Invoke-' + 'Pester'))

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'ignores non-executing <Kind> Invoke-Pester text in a script' -ForEach @(
        @{ Kind = 'comment'; Content = '# Invoke-Pester is documented here' }
        @{ Kind = 'string'; Content = "`$message = 'Invoke-Pester is documented here'" }
        @{
            Kind = 'function'
            Content = 'function Invoke-Tests { Invoke-' + 'Pester ./tests }'
        }
        @{
            Kind = 'assigned scriptblock'
            Content = '$tests = { Invoke-' + 'Pester ./tests }'
        }
    ) {
        $fixtureRoot = New-ToolchainFixture "script-$Kind-invoke"
        $scriptPath = Join-Path $fixtureRoot '.agents/Example.ps1'
        Set-Content -LiteralPath $scriptPath -Value $Content

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'rejects an unpinned executable Invoke-Pester in a script' {
        $fixtureRoot = New-ToolchainFixture 'script-executable-invoke'
        $scriptPath = Join-Path $fixtureRoot '.agents/Example.ps1'
        Set-Content -LiteralPath $scriptPath -Value ('Invoke-' + 'Pester ./tests')

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw ('*invokes Invoke-' +
                'Pester without a preceding pinned Pester import*')
    }

    It 'rejects an unpinned generated command inside a here-string' {
        $fixtureRoot = New-ToolchainFixture 'generated-here-string-unpinned'
        $scriptPath = Join-Path $fixtureRoot '.agents/Generator.ps1'
        Set-Content -LiteralPath $scriptPath -Value @(
            "`$text = @'",
            ('Invoke-' + 'Pester ./tests'),
            "'@")

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw ('*invokes Invoke-' +
                'Pester without a preceding pinned Pester import*')
    }

    It 'rejects stale Pester copies in current docs but permits named historical evidence' {
        $fixtureRoot = New-ToolchainFixture 'documentation-drift'
        $currentDoc = Join-Path $fixtureRoot 'docs/current.md'
        Set-Content -LiteralPath $currentDoc -Value (
            './tests/Invoke-PesterShards.ps1 -Pester' +
            'Version ' + ('5.7' + '.1'))

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw "*current.md*copies Pester version '5.7.1'*"

        Remove-Item -LiteralPath $currentDoc
        Set-Content -LiteralPath (
            Join-Path $fixtureRoot 'docs/pr-review-effectiveness-plan.md') -Value (
            './tests/Invoke-PesterShards.ps1 -Pester' +
            'Version ' + ('5.7' + '.1'))
        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Not -Throw
    }

    It 'rejects drifted repository guidance <Requirement>' -ForEach @(
        @{
            Requirement = 'PowerShell'
            Content = 'Requires PowerShell 7.2 and Pester 6.2.0.'
            Error = '*must name PowerShell 7.4*'
        }
        @{
            Requirement = 'Pester'
            Content = 'Requires PowerShell 7.4 and Pester 6.1.0.'
            Error = '*must name Pester 6.2.0*'
        }
        @{
            Requirement = 'PowerShell suffix'
            Content = 'Requires PowerShell 7.40 and Pester 6.2.0.'
            Error = '*must name PowerShell 7.4*'
        }
        @{
            Requirement = 'Pester suffix'
            Content = 'Requires PowerShell 7.4 and Pester 6.2.01.'
            Error = '*must name Pester 6.2.0*'
        }
    ) {
        $fixtureRoot = New-ToolchainFixture "repository-guidance-$Requirement"
        Set-Content -LiteralPath (
            Join-Path $fixtureRoot '.agents/skills/create-skill-repo/SKILL.md') `
            -Value $Content

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw $Error
    }

    It 'rejects repository-specific Pester pins in portable guidance <Path>' -ForEach @(
        @{ Path = 'skills/dotnet-file-creation/SKILL.md' }
        @{ Path = 'skills/windows-acls/SKILL.md' }
    ) {
        $fixtureRoot = New-ToolchainFixture (
            "portable-guidance-$([IO.Path]::GetFileName((Split-Path -Parent $Path)))")
        Set-Content -LiteralPath (Join-Path $fixtureRoot $Path) `
            -Value ('Requires PowerShell 7.4 and Pester 6.2 or later; this ' +
                'source repository pins its test entry points to Pester 6.2.0.')

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*must keep repository-specific Pester pins out of the portable core*'
    }

    It 'derives the portable Pester floor from the manifest' {
        $fixtureRoot = New-ToolchainFixture 'portable-pester-floor'
        $manifestPath = Join-Path $fixtureRoot 'tools/powershell-toolchain.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw |
            ConvertFrom-Json -AsHashtable
        $manifest.modules.Pester = '6.3.0'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath
        $testPath = Join-Path $fixtureRoot 'tests/Valid.Tests.ps1'
        (Get-Content -LiteralPath $testPath -Raw).Replace(
            "RequiredVersion = '6.2.0'", "RequiredVersion = '6.3.0'") |
            Set-Content -LiteralPath $testPath
        Set-Content -LiteralPath (
            Join-Path $fixtureRoot '.agents/skills/create-skill-repo/SKILL.md') `
            -Value 'Requires PowerShell 7.4 and Pester 6.3.0.'

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*must name Pester 6.3 or later*'
    }

    It 'uses the derived Pester floor when portable guidance is missing' {
        $fixtureRoot = New-ToolchainFixture 'missing-portable-guidance'
        $manifestPath = Join-Path $fixtureRoot 'tools/powershell-toolchain.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw |
            ConvertFrom-Json -AsHashtable
        $manifest.modules.Pester = '6.3.0'
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath
        $testPath = Join-Path $fixtureRoot 'tests/Valid.Tests.ps1'
        (Get-Content -LiteralPath $testPath -Raw).Replace(
            "RequiredVersion = '6.2.0'", "RequiredVersion = '6.3.0'") |
            Set-Content -LiteralPath $testPath
        Set-Content -LiteralPath (
            Join-Path $fixtureRoot '.agents/skills/create-skill-repo/SKILL.md') `
            -Value 'Requires PowerShell 7.4 and Pester 6.3.0.'
        Set-Content -LiteralPath (
            Join-Path $fixtureRoot 'skills/windows-acls/SKILL.md') `
            -Value 'Requires PowerShell 7.4 and Pester 6.3 or later.'
        Remove-Item -LiteralPath (
            Join-Path $fixtureRoot 'skills/dotnet-file-creation/SKILL.md')

        { & $script:ToolchainValidatorPath -RepositoryRoot $fixtureRoot } |
            Should -Throw '*must name PowerShell 7.4 and Pester 6.3 or later*'
    }
}

Describe 'Pester shard runner' {
    BeforeAll {
        $script:ShardRunner = Join-Path $script:RepoRoot 'tests/Invoke-PesterShards.ps1'
        $script:ShardPwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })

        function Invoke-ShardFixture (
            [string] $Name,
            [string] $Content,
            [string] $ReportedResult,
            [string[]] $RunnerArguments,
            [switch] $IncludeHealthy) {
            $root = Join-Path $TestDrive $Name
            [System.IO.Directory]::CreateDirectory($root) | Out-Null
            $fixturePath = Join-Path $root 'Fixture.Tests.ps1'
            [System.IO.File]::WriteAllText($fixturePath, $Content)
            if ($PSBoundParameters.ContainsKey('ReportedResult')) {
                [System.IO.File]::WriteAllText(
                    (Join-Path $root 'reported-result.json'), $ReportedResult)
            }
            $testPath = $fixturePath
            if ($IncludeHealthy) {
                [System.IO.File]::WriteAllText((Join-Path $root 'Healthy.Tests.ps1'), @'
Describe 'Healthy fixture' {
    It 'passes' { $true | Should -BeTrue }
}
'@)
                $testPath = $root
            }
            $reportDirectory = Join-Path $root 'reports'
            $output = @(& $script:ShardPwsh -NoProfile -File $script:ShardRunner `
                    -Path $testPath -OutputDirectory $reportDirectory `
                    -MaxConcurrency 2 -PesterVersion 6.2.0 @RunnerArguments 2>&1)
            $exitCode = $LASTEXITCODE
            $summary = Get-Content -LiteralPath (Join-Path $reportDirectory 'summary.json') -Raw |
                ConvertFrom-Json
            [pscustomobject]@{
                ExitCode = $exitCode
                Output = $output -join [Environment]::NewLine
                Summary = $summary
                Log = if (Test-Path -LiteralPath $summary.Shards[0].LogPath -PathType Leaf) {
                    Get-Content -LiteralPath $summary.Shards[0].LogPath -Raw
                }
                else { '' }
            }
        }
    }

    It 'reports a healthy shard with real test counts' {
        $run = Invoke-ShardFixture 'healthy' @'
Describe 'Healthy fixture' {
    It 'passes' { $true | Should -BeTrue }
}
'@

        $run.ExitCode | Should -Be 0 -Because $run.Output
        $run.Summary.SchemaVersion | Should -Be 2
        $run.Summary.Result | Should -Be 'Passed'
        $run.Summary.ShardCount | Should -Be 1
        $run.Summary.PassedCount | Should -Be 1
        $run.Summary.FailedCount | Should -Be 0
        $run.Summary.TotalCount | Should -Be 1
        $run.Summary.CountsComplete | Should -BeTrue
        $run.Summary.InfrastructureFailureCount | Should -Be 0
        $run.Summary.Shards[0].ExitCode | Should -Be 0
    }

    It 'fails when discovery fails before any tests are counted' {
        $run = Invoke-ShardFixture 'discovery-failure' @'
BeforeDiscovery { throw 'Synthetic discovery failure.' }
Describe 'Unreachable fixture' {
    It 'cannot run' { $true | Should -BeTrue }
}
'@

        $run.ExitCode | Should -Not -Be 0 -Because $run.Output
        $run.Summary.FailedCount | Should -Be 0
        $run.Summary.TotalCount | Should -Be 0
        $run.Summary.FailedContainersCount | Should -Be 1
        $run.Summary.Shards[0].ExitCode | Should -Not -Be 0
        $run.Log | Should -Match 'Synthetic discovery failure'
    }

    It 'reports an assertion failure as a failed test, not an infrastructure failure' {
        $run = Invoke-ShardFixture 'assertion-failure' @'
Describe 'Assertion fixture' {
    It 'fails' { $false | Should -BeTrue }
}
'@

        $run.ExitCode | Should -Not -Be 0
        $run.Summary.FailedCount | Should -Be 1
        $run.Summary.TotalCount | Should -Be 1
        $run.Summary.InfrastructureFailureCount | Should -Be 0
        $run.Summary.CountsComplete | Should -BeTrue
    }

    It 'fails when block setup fails' {
        $run = Invoke-ShardFixture 'setup-failure' @'
Describe 'Setup fixture' {
    BeforeAll { throw 'Synthetic setup failure.' }
    It 'cannot run' { $true | Should -BeTrue }
}
'@

        $run.ExitCode | Should -Not -Be 0
        $run.Summary.FailedBlocksCount | Should -Be 1
        $run.Log | Should -Match 'Synthetic setup failure'
    }

    It 'fails teardown even when every test passed' {
        $run = Invoke-ShardFixture 'teardown-failure' @'
Describe 'Teardown fixture' {
    AfterAll { throw 'Synthetic teardown failure.' }
    It 'passes' { $true | Should -BeTrue }
}
'@

        $run.ExitCode | Should -Not -Be 0
        $run.Summary.PassedCount | Should -Be 1
        $run.Summary.FailedCount | Should -Be 0
        $run.Summary.FailedBlocksCount | Should -Be 1
    }

    It 'rejects empty discovery with an explicit reason' {
        $run = Invoke-ShardFixture 'empty-discovery' "Describe 'Empty fixture' { }"

        $run.ExitCode | Should -Not -Be 0
        $run.Summary.TotalCount | Should -BeNullOrEmpty
        $run.Summary.FailedCount | Should -BeNullOrEmpty
        $run.Summary.CountsComplete | Should -BeFalse
        $run.Summary.Shards[0].Error | Should -Match 'No Pester tests were discovered'
    }

    It 'rejects empty ForEach data as empty discovery' {
        $run = Invoke-ShardFixture 'empty-foreach' @'
Describe 'Empty data fixture' {
    It 'has case <Name>' -ForEach @() { $true | Should -BeTrue }
}
'@

        $run.ExitCode | Should -Not -Be 0
        $run.Summary.TotalCount | Should -Be 0
        $run.Summary.FailedContainersCount | Should -Be 1
        $run.Summary.InfrastructureFailureCount | Should -Be 0
        $run.Summary.CountsComplete | Should -BeTrue
        $run.Summary.Shards[0].Result | Should -Be 'Failed'
        $run.Log | Should -Match 'AllowNullOrEmptyForEach'
    }

    It 'keeps intentional skips distinct from empty discovery' {
        $run = Invoke-ShardFixture 'skipped' @'
Describe 'Skipped fixture' {
    It 'is intentionally skipped' -Skip { throw 'Must not run.' }
}
'@

        $run.ExitCode | Should -Be 0 -Because $run.Output
        $run.Summary.PassedCount | Should -Be 0
        $run.Summary.SkippedCount | Should -Be 1
        $run.Summary.TotalCount | Should -Be 1
        $run.Summary.CountsComplete | Should -BeTrue
    }

    It 'fails a child without a result without inventing test counts' {
        $run = Invoke-ShardFixture 'missing-result' @'
BeforeDiscovery { [System.Environment]::Exit(0) }
'@

        $run.ExitCode | Should -Not -Be 0
        $run.Summary.PassedCount | Should -BeNullOrEmpty
        $run.Summary.FailedCount | Should -BeNullOrEmpty
        $run.Summary.TotalCount | Should -BeNullOrEmpty
        $run.Summary.InfrastructureFailureCount | Should -Be 1
        $run.Summary.CountsComplete | Should -BeFalse
        $run.Summary.Shards[0].ExitCode | Should -Be 0
        $run.Summary.Shards[0].Error | Should -Match 'did not produce a result'
    }

    It 'rejects an invalid child result: <Kind>' -ForEach @(
        @{ Kind = 'malformed-json'; ReportedResult = '{' }
        @{ Kind = 'missing-fields'; ReportedResult = '{}' }
    ) {
        $run = Invoke-ShardFixture $Kind -ReportedResult $ReportedResult -Content @'
BeforeDiscovery {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'reported-result.json') `
        -Destination (Join-Path $PSScriptRoot 'reports/shard-0.json')
    [System.Environment]::Exit(0)
}
'@

        $run.ExitCode | Should -Not -Be 0
        $run.Summary.FailedCount | Should -BeNullOrEmpty
        $run.Summary.TotalCount | Should -BeNullOrEmpty
        $run.Summary.InfrastructureFailureCount | Should -Be 1
        $run.Summary.CountsComplete | Should -BeFalse
        $run.Summary.Shards[0].Error | Should -Match 'Invalid Pester shard result'
    }

    It 'rejects a contradictory child result: <Kind>' -ForEach @(
        @{ Kind = 'wrong-path'; Overrides = @{ Path = 'wrong.Tests.ps1' }; CountsComplete = $false }
        @{ Kind = 'negative-count'; Overrides = @{ PassedCount = -1 }; CountsComplete = $false }
        @{ Kind = 'counts-mismatch'; Overrides = @{ TotalCount = 2 }; CountsComplete = $false }
        @{ Kind = 'passing-container-failure'; Overrides = @{ FailedContainersCount = 1 }; CountsComplete = $false }
        @{ Kind = 'failed-without-evidence'; Overrides = @{ Result = 'Failed' }; CountsComplete = $false }
        @{ Kind = 'failed-with-zero-exit'; Overrides = @{ Result = 'Failed'; PassedCount = 0; FailedCount = 1 }; CountsComplete = $false }
        @{ Kind = 'not-run'; Overrides = @{ PassedCount = 0; NotRunCount = 1 }; CountsComplete = $false }
        @{ Kind = 'inconclusive'; Overrides = @{ PassedCount = 0; InconclusiveCount = 1 }; CountsComplete = $false }
    ) {
        $reported = [ordered]@{
            Path = Join-Path (Join-Path $TestDrive $Kind) 'Fixture.Tests.ps1'
            Result = 'Passed'
            PassedCount = 1
            FailedCount = 0
            SkippedCount = 0
            NotRunCount = 0
            InconclusiveCount = 0
            TotalCount = 1
            FailedBlocksCount = 0
            FailedContainersCount = 0
            DurationMilliseconds = 0
        }
        foreach ($property in $Overrides.Keys) { $reported[$property] = $Overrides[$property] }
        $run = Invoke-ShardFixture $Kind -ReportedResult ($reported | ConvertTo-Json) -Content @'
BeforeDiscovery {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'reported-result.json') `
        -Destination (Join-Path $PSScriptRoot 'reports/shard-0.json')
    [System.Environment]::Exit(0)
}
'@

        $run.ExitCode | Should -Not -Be 0
        $run.Summary.Result | Should -Be 'Failed'
        $run.Summary.InfrastructureFailureCount | Should -Be 1
        $run.Summary.CountsComplete | Should -Be $CountsComplete
        $run.Summary.Shards[0].Error | Should -Not -BeNullOrEmpty
    }

    It 'rejects a passing report when the process exits unsuccessfully' {
        $reported = [ordered]@{
            Path = Join-Path (Join-Path $TestDrive 'nonzero-exit') 'Fixture.Tests.ps1'
            Result = 'Passed'
            PassedCount = 1
            FailedCount = 0
            SkippedCount = 0
            NotRunCount = 0
            InconclusiveCount = 0
            TotalCount = 1
            FailedBlocksCount = 0
            FailedContainersCount = 0
            DurationMilliseconds = 0
        }
        $run = Invoke-ShardFixture 'nonzero-exit' -ReportedResult ($reported | ConvertTo-Json) -Content @'
BeforeDiscovery {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'reported-result.json') `
        -Destination (Join-Path $PSScriptRoot 'reports/shard-0.json')
    [System.Environment]::Exit(23)
}
'@

        $run.ExitCode | Should -Not -Be 0
        $run.Summary.PassedCount | Should -BeNullOrEmpty
        $run.Summary.FailedCount | Should -BeNullOrEmpty
        $run.Summary.CountsComplete | Should -BeFalse
        $run.Summary.InfrastructureFailureCount | Should -Be 1
        $run.Summary.Shards[0].ExitCode | Should -Be 23
        $run.Summary.Shards[0].Error | Should -Match 'successful shard process'
    }

    It 'retains healthy shard evidence without presenting incomplete totals as complete' {
        $run = Invoke-ShardFixture 'mixed-results' -IncludeHealthy -Content @'
BeforeDiscovery { [System.Environment]::Exit(0) }
'@

        $run.ExitCode | Should -Not -Be 0
        $run.Summary.ShardCount | Should -Be 2
        $run.Summary.FailedShardCount | Should -Be 1
        $run.Summary.InfrastructureFailureCount | Should -Be 1
        $run.Summary.CountsComplete | Should -BeFalse
        $run.Summary.TotalCount | Should -BeNullOrEmpty
        $healthyShard = @($run.Summary.Shards | Where-Object Result -EQ 'Passed')
        $healthyShard.Count | Should -Be 1
        $healthyShard[0].PassedCount | Should -Be 1
    }

    It 'reports a worker process startup failure through the normal summary' {
        $missingPowerShell = Join-Path $TestDrive 'missing/pwsh.exe'
        $run = Invoke-ShardFixture 'process-start-failure' `
            -RunnerArguments @('-PowerShellPath', $missingPowerShell) -Content @'
Describe 'Unreachable fixture' {
    It 'cannot run' { $true | Should -BeTrue }
}
'@

        $run.ExitCode | Should -Not -Be 0
        $run.Summary.Result | Should -Be 'Failed'
        $run.Summary.InfrastructureFailureCount | Should -Be 1
        $run.Summary.CountsComplete | Should -BeFalse
        $run.Summary.TotalCount | Should -BeNullOrEmpty
        $run.Summary.Shards[0].Error | Should -Match 'worker failed'
        $run.Summary.Shards[0].LogPath | Should -Not -BeNullOrEmpty
    }

    It 'kills and reports a child that exceeds its timeout' {
        $run = Invoke-ShardFixture 'timeout' `
            -RunnerArguments @('-ShardTimeoutSeconds', '3') -Content @'
Describe 'Timeout fixture' {
    It 'never completes' { [System.Threading.Thread]::Sleep([System.Threading.Timeout]::Infinite) }
}
'@

        $run.ExitCode | Should -Not -Be 0
        $run.Summary.Result | Should -Be 'Failed'
        $run.Summary.InfrastructureFailureCount | Should -Be 1
        $run.Summary.CountsComplete | Should -BeFalse
        $run.Summary.Shards[0].TimedOut | Should -BeTrue
        $run.Summary.Shards[0].ExitCode | Should -Be -1
        $run.Summary.Shards[0].Error | Should -Match 'timed out'
    }

    It 'rejects a failed report written before the child times out' {
        $reported = [ordered]@{
            Path = Join-Path (Join-Path $TestDrive 'timeout-with-report') 'Fixture.Tests.ps1'
            Result = 'Failed'
            PassedCount = 0
            FailedCount = 1
            SkippedCount = 0
            NotRunCount = 0
            InconclusiveCount = 0
            TotalCount = 1
            FailedBlocksCount = 0
            FailedContainersCount = 0
            DurationMilliseconds = 0
        }
        $run = Invoke-ShardFixture 'timeout-with-report' `
            -ReportedResult ($reported | ConvertTo-Json) `
            -RunnerArguments @('-ShardTimeoutSeconds', '3') -Content @'
BeforeDiscovery {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'reported-result.json') `
        -Destination (Join-Path $PSScriptRoot 'reports/shard-0.json')
    [System.Threading.Thread]::Sleep([System.Threading.Timeout]::Infinite)
}
'@

        $run.ExitCode | Should -Not -Be 0
        $run.Summary.Result | Should -Be 'Failed'
        $run.Summary.CountsComplete | Should -BeFalse
        $run.Summary.TotalCount | Should -BeNullOrEmpty
        $run.Summary.Shards[0].TimedOut | Should -BeTrue
        $run.Summary.Shards[0].Error | Should -Match 'incomplete shard worker'
    }

    It 'rejects a failed report when the worker fails after the child exits' {
        $reported = [ordered]@{
            Path = Join-Path (Join-Path $TestDrive 'worker-error-with-report') 'Fixture.Tests.ps1'
            Result = 'Failed'
            PassedCount = 0
            FailedCount = 1
            SkippedCount = 0
            NotRunCount = 0
            InconclusiveCount = 0
            TotalCount = 1
            FailedBlocksCount = 0
            FailedContainersCount = 0
            DurationMilliseconds = 0
        }
        $run = Invoke-ShardFixture 'worker-error-with-report' `
            -ReportedResult ($reported | ConvertTo-Json) -Content @'
BeforeDiscovery {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'reported-result.json') `
        -Destination (Join-Path $PSScriptRoot 'reports/shard-0.json')
    New-Item -ItemType Directory -Path (Join-Path $PSScriptRoot 'reports/shard-0.log') | Out-Null
    [System.Environment]::Exit(1)
}
'@

        $run.ExitCode | Should -Not -Be 0
        $run.Summary.Result | Should -Be 'Failed'
        $run.Summary.CountsComplete | Should -BeFalse
        $run.Summary.TotalCount | Should -BeNullOrEmpty
        $run.Summary.Shards[0].ExitCode | Should -Be 1
        $run.Summary.Shards[0].Error | Should -Match 'incomplete shard worker'
    }
}

Describe 'Skill catalog contracts' {
    AfterEach {
        $fixturePath = Join-Path $TestDrive '[provenance-bearing-user-voice]'
        if (Test-Path -LiteralPath $fixturePath) {
            Remove-Item -LiteralPath $fixturePath -Recurse -Force
        }
    }

    It 'ships the shared installed-artifact test helper' {
        Test-Path -LiteralPath (
            Join-Path $PSScriptRoot 'SkillArtifactTestHelpers.ps1') -PathType Leaf |
            Should -BeTrue
    }

    It 'ships the scalable evaluation and deterministic test entry points' {
        foreach ($relativePath in @(
                'evals/Get-SkillEvalAffectedScenarios.ps1',
                'evals/Invoke-SkillEvalMatrix.ps1',
                'evals/Invoke-SkillEvalRescore.ps1',
                'evals/Invoke-SkillEvals.ps1',
                'evals/SkillEval.psm1',
                'evals/SkillEvalScorer.ps1',
                'tests/Invoke-PesterShards.ps1')) {
            Test-Path -LiteralPath (Join-Path $script:RepoRoot $relativePath) `
                -PathType Leaf | Should -BeTrue
        }
    }

    It 'contains exactly one catalog link for every source skill' {
        $catalog = Get-Content -LiteralPath (Join-Path $script:SkillsRoot 'README.md') -Raw
        $inventory = ($catalog -split [regex]::Escape('<!-- portfolio-matrix:start -->'), 2)[0]
        $catalogNames = @([regex]::Matches($inventory, '\]\(\./(?<name>[a-z0-9-]+)/SKILL\.md\)') |
            ForEach-Object { $_.Groups['name'].Value })

        @($catalogNames | Group-Object | Where-Object Count -ne 1).Count | Should -Be 0
        @(Compare-Object ($script:SkillNames | Sort-Object) ($catalogNames | Sort-Object)).Count | Should -Be 0
    }

    It 'makes repository creation discoverable without cataloging the local workflow' {
        $readme = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'README.md') -Raw
        $catalog = Get-Content -LiteralPath (Join-Path $script:SkillsRoot 'README.md') -Raw
        $localWorkflow = Join-Path $script:RepoRoot (
            '.agents/skills/create-skill-repo/SKILL.md')

        Test-Path -LiteralPath $localWorkflow -PathType Leaf | Should -BeTrue
        $readme | Should -Match 'If you want to create a skill repository'
        $readme | Should -Match '\]\(\.agents/skills/create-skill-repo/SKILL\.md\)'
        $readme | Should -Match 'intentionally absent from the \[shared skill\s+catalog\]'
        $catalog | Should -Not -Match 'create-skill-repo'
    }

    It 'keeps the generated portfolio matrix current' {
        $generator = Join-Path $script:RepoRoot 'tools/Update-SkillCatalog.ps1'
        $output = & pwsh -NoProfile -File $generator 2>&1
        $LASTEXITCODE | Should -Be 0 -Because "$output"
    }

    It 'generates the portfolio matrix byte-for-byte idempotently' {
        $generator = Join-Path $script:RepoRoot 'tools/Update-SkillCatalog.ps1'
        $temporarySkills = Join-Path $TestDrive 'catalog-idempotency'
        Copy-Item -LiteralPath $script:SkillsRoot -Destination $temporarySkills -Recurse

        & pwsh -NoProfile -File $generator -SkillsRoot $temporarySkills -Apply *> $null
        $LASTEXITCODE | Should -Be 0
        $firstHash = (Get-FileHash (Join-Path $temporarySkills 'README.md') -Algorithm SHA256).Hash

        & pwsh -NoProfile -File $generator -SkillsRoot $temporarySkills -Apply *> $null
        $LASTEXITCODE | Should -Be 0
        $secondHash = (Get-FileHash (Join-Path $temporarySkills 'README.md') -Algorithm SHA256).Hash

        $secondHash | Should -Be $firstHash
    }

    It 'ignores an end marker that appears before the portfolio start marker' {
        $generator = Join-Path $script:RepoRoot 'tools/Update-SkillCatalog.ps1'
        $temporarySkills = Join-Path $TestDrive 'catalog-marker-order'
        Copy-Item -LiteralPath $script:SkillsRoot -Destination $temporarySkills -Recurse
        $catalogPath = Join-Path $temporarySkills 'README.md'
        $catalog = Get-Content -LiteralPath $catalogPath -Raw
        Set-Content -LiteralPath $catalogPath -NoNewline -Value "<!-- portfolio-matrix:end -->`n$catalog"

        $output = & pwsh -NoProfile -File $generator -SkillsRoot $temporarySkills 2>&1
        $LASTEXITCODE | Should -Be 0 -Because "$output"
    }

    It 'resolves every required and related skill to a source core' {
        foreach ($record in $script:SkillRecords) {
            foreach ($relationshipField in @('requires', 'related')) {
                foreach ($relationshipName in (Get-RelationshipNames $record.Metadata[$relationshipField])) {
                    $relationshipName | Should -Not -Be $record.Name -Because "$($record.Name) cannot reference itself"
                    $script:SkillNames | Should -Contain $relationshipName -Because "$($record.Name) metadata.$relationshipField must resolve"
                }
            }
        }
    }

    It 'requires technical-writing for every remote-write workflow' {
        $remoteWriteRecords = @($script:SkillRecords | Where-Object { $_.Metadata.risk -eq 'remote-write' })

        @($remoteWriteRecords.Name | Sort-Object) | Should -Be @(
            'address-pr-feedback',
            'create-pr',
            'engineering-baseline',
            'manage-skills')
        foreach ($record in $remoteWriteRecords) {
            Get-RelationshipNames $record.Metadata.requires |
                Should -Contain 'technical-writing' -Because "$($record.Name) publishes human-facing text"
        }
    }

    It 'permits public-source provenance while keeping personalized content private' {
        $userVoice = @($script:SkillRecords | Where-Object Name -eq 'user-voice')
        $userVoice.Count | Should -Be 1
        $userVoice[0].Metadata.risk | Should -Be 'local-write'
        Get-RelationshipNames $userVoice[0].Metadata.requires |
            Should -Contain 'manage-skills'

        Test-Path -LiteralPath (Join-Path $script:SkillsRoot 'user-voice-profile') |
            Should -BeFalse
        $technicalWriting = @($script:SkillRecords | Where-Object Name -eq 'technical-writing')[0]
        Get-RelationshipNames $technicalWriting.Metadata.requires |
            Should -Not -Contain 'user-voice-profile'
        Get-RelationshipNames $technicalWriting.Metadata.related |
            Should -Contain 'user-voice'

        Get-SkillArtifactPrivacyContent $userVoice[0].Directory |
            Should -Not -Match '(?i)jeremy[- ]kuhne|JeremyKuhne'

        $installedFixture = Join-Path $TestDrive '[provenance-bearing-user-voice]'
        New-Item -ItemType Directory -Path $installedFixture | Out-Null
        $fixtureSkillPath = Join-Path $installedFixture 'SKILL.md'
                $fixtureContent = @(
                        '---'
                        'name: user-voice'
                        'description: Generic lifecycle fixture.'
                        'metadata:'
                        '  github-path: skills/user-voice'
                        '  github-pinned: 0123456789012345678901234567890123456789'
                        '  github-ref: 0123456789012345678901234567890123456789'
                        '  github-repo: https://github.com/JeremyKuhne/agent-skills'
                        '  github-tree-sha: 0123456789012345678901234567890123456789'
                        '---'
                        ''
                        '# User voice'
                        ''
                        'Generic lifecycle content.'
                ) -join "`n"
        [System.IO.File]::WriteAllText($fixtureSkillPath, $fixtureContent)
        (Get-SkillArtifactDocument $fixtureSkillPath).Frontmatter |
            Should -Match 'JeremyKuhne'
        Get-SkillArtifactPrivacyContent $installedFixture |
            Should -Not -Match 'JeremyKuhne'

        Add-Content -LiteralPath $fixtureSkillPath `
            -Value "`nPrivate profile subject: JeremyKuhne"
        Get-SkillArtifactPrivacyContent $installedFixture |
            Should -Match 'JeremyKuhne'

        [System.IO.File]::WriteAllText($fixtureSkillPath, $fixtureContent)
        [System.IO.File]::WriteAllText(
            (Join-Path $installedFixture 'private-resource.md'),
            'Private profile subject: JeremyKuhne')
        Get-SkillArtifactPrivacyContent $installedFixture |
            Should -Match 'JeremyKuhne'
    }

    It 'has an acyclic required-skill graph' {
        $recordsByName = @{}
        foreach ($record in $script:SkillRecords) { $recordsByName[$record.Name] = $record }
        $states = @{}
        $visitRequirement = $null
        $visitRequirement = {
            param([string] $skillName)

            if ($states[$skillName] -eq 'visited') { return }
            if ($states[$skillName] -eq 'visiting') { throw "Required-skill cycle includes '$skillName'." }

            $states[$skillName] = 'visiting'
            foreach ($requiredName in (Get-RelationshipNames $recordsByName[$skillName].Metadata.requires)) {
                & $visitRequirement $requiredName
            }
            $states[$skillName] = 'visited'
        }
        foreach ($skillName in $script:SkillNames) {
            { & $visitRequirement $skillName } | Should -Not -Throw
        }
    }
}


Describe 'Agent contracts' {
    It 'catalogs every agent exactly once' {
        $agentFiles = @(Get-ChildItem -LiteralPath $script:AgentsRoot -Filter '*.agent.md' -File | Sort-Object Name)
        $catalog = Get-Content -LiteralPath (Join-Path $script:AgentsRoot 'README.md') -Raw
        $catalogFiles = @([regex]::Matches($catalog, '\]\(\./(?<file>[a-z0-9-]+\.agent\.md)\)') |
            ForEach-Object { $_.Groups['file'].Value })

        @($catalogFiles | Group-Object | Where-Object Count -ne 1).Count | Should -Be 0
        @(Compare-Object $agentFiles.Name ($catalogFiles | Sort-Object)).Count | Should -Be 0
    }

    It 'gives every agent a description and recognized tool identifiers' {
        $allowedTools = @('search', 'read', 'edit', 'web', 'execute', 'web/fetch', 'search/usages', 'search/changes', 'read/problems')
        foreach ($agentFile in (Get-ChildItem -LiteralPath $script:AgentsRoot -Filter '*.agent.md' -File)) {
            $content = Get-Content -LiteralPath $agentFile.FullName -Raw
            $frontmatterMatch = [regex]::Match($content, '\A---\r?\n(?<body>.*?)\r?\n---', 'Singleline')
            $frontmatterMatch.Success | Should -BeTrue -Because "$($agentFile.Name) needs YAML frontmatter"
            $frontmatter = $frontmatterMatch.Groups['body'].Value
            $frontmatter | Should -Match '(?m)^description:\s*\S'

            $toolsMatch = [regex]::Match($frontmatter, '(?m)^tools:\s*\[(?<tools>[^\]]*)\]\s*$')
            $toolsMatch.Success | Should -BeTrue -Because "$($agentFile.Name) tools must use the supported inline-list form"
            $tools = @($toolsMatch.Groups['tools'].Value -split ',' |
                ForEach-Object { $_.Trim().Trim("'", '"') } |
                Where-Object { $_ })
            foreach ($tool in $tools) { $allowedTools | Should -Contain $tool }
        }
    }
}

Describe 'Distribution manifest contracts' {
    BeforeAll {
        $script:Plugin = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'plugin.json') -Raw | ConvertFrom-Json
        $script:Marketplace = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/plugin/marketplace.json') -Raw | ConvertFrom-Json
        $script:Mcp = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.mcp.json') -Raw | ConvertFrom-Json
    }

    It 'uses a valid plugin identity and semantic version' {
        $script:Plugin.name | Should -Match '^[a-z0-9]+(?:-[a-z0-9]+)*$'
        $script:Plugin.version | Should -Match '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$'
        $script:Plugin.license | Should -Be 'MIT'
        $script:Plugin.author.name | Should -Not -BeNullOrEmpty
        $script:Plugin.author.url | Should -Match '^https://'
        $script:Plugin.repository | Should -Match '^https://'
        @($script:Plugin.keywords).Count | Should -BeGreaterThan 0
    }

    It 'points every plugin component at an existing artifact' {
        foreach ($componentPath in @($script:Plugin.skills) + @($script:Plugin.agents) + @($script:Plugin.mcpServers)) {
            Test-Path -LiteralPath (Join-Path $script:RepoRoot $componentPath) | Should -BeTrue
        }
        $script:SkillRecords.Count | Should -BeGreaterThan 0
        @(Get-ChildItem -LiteralPath $script:AgentsRoot -Filter '*.agent.md' -File).Count | Should -BeGreaterThan 0
    }

    It 'keeps the marketplace entry aligned with plugin.json' {
        $entry = @($script:Marketplace.plugins) | Where-Object name -eq $script:Plugin.name
        @($entry).Count | Should -Be 1
        $entry.version | Should -Be $script:Plugin.version
        $entry.source | Should -Be './'
        $script:Marketplace.metadata.version | Should -Be $script:Plugin.version
    }

    It 'uses typed and pinned MCP server definitions' {
        foreach ($serverProperty in $script:Mcp.mcpServers.PSObject.Properties) {
            $server = $serverProperty.Value
            @('http', 'stdio') | Should -Contain $server.type
            if ($server.type -eq 'http') {
                $server.url | Should -Match '^https://'
            }
            else {
                $server.command | Should -Not -BeNullOrEmpty
                @($server.args | Where-Object { $_ -match '@\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$' }).Count |
                    Should -BeGreaterThan 0 -Because "$($serverProperty.Name) must pin an executable package version"
            }
        }
    }

    It 'matches an exact release tag when HEAD is tagged' {
        $tagsAtHead = @(& git -C $script:RepoRoot tag --points-at HEAD |
            Where-Object { $_ -match '^v\d+\.\d+\.\d+$' })
        $LASTEXITCODE | Should -Be 0
        foreach ($tag in $tagsAtHead) {
            $tag.TrimStart('v') | Should -Be $script:Plugin.version
        }
    }
}

Describe 'Workflow pin contracts' {
    It 'pins repository CI actions to immutable SHAs with readable version comments' {
        foreach ($workflow in (Get-ChildItem (Join-Path $script:RepoRoot '.github/workflows') -Filter '*.yml' -File)) {
            foreach ($line in (Get-Content -LiteralPath $workflow.FullName | Where-Object { $_ -match '\buses:' })) {
                $line | Should -Match '@[0-9a-f]{40}\s+#\s+v\d'
            }
        }
    }

    It 'keeps scaffold action placeholders paired with concrete version comments' {
        $templateRoot = Join-Path $script:RepoRoot 'skills/engineering-baseline/scripts/template/.github/workflows'
        foreach ($workflow in (Get-ChildItem $templateRoot -Filter '*.tmpl' -File)) {
            foreach ($line in (Get-Content -LiteralPath $workflow.FullName | Where-Object { $_ -match '\buses:' })) {
                $line | Should -Match '@<SHA>\s+#\s+v\d'
            }
        }
    }
}

Describe 'Workflow execution contracts' {
    BeforeAll {
        $script:CiWorkflow = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/ci.yml') -Raw
        $script:FullCiWorkflow = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/full-ci.yml') -Raw
        $script:AllWorkflowText = @(Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot '.github/workflows') -Filter '*.yml' -File |
            Sort-Object Name |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"

        function Get-WorkflowJobBody ([string] $workflow, [string] $jobName) {
            $escapedJobName = [regex]::Escape($jobName)
            $match = [regex]::Match(
                $workflow,
                "(?ms)^  ${escapedJobName}:\r?\n(?<body>.*?)(?=^  [a-z0-9-]+:\r?$|\z)")
            if (-not $match.Success) { throw "Workflow job '$jobName' was not found." }
            return $match.Groups['body'].Value
        }
    }

    It 'limits ordinary CI to main, release tags, and main pull requests' {
        $script:CiWorkflow | Should -Match "(?ms)^on:\r?\n  push:\r?\n    branches: \[main\]\r?\n    tags: \['v\*'\]\r?\n  pull_request:\r?\n    branches: \[main\]"
    }

    It 'runs release-critical artifact gates for tag pushes' {
        foreach ($jobName in @('validate', 'scaffold-linux', 'scaffold-windows')) {
            Get-WorkflowJobBody $script:CiWorkflow $jobName |
                Should -Not -Match "startsWith\(github\.ref, 'refs/tags/'\)" -Because "$jobName must run against the tagged commit"
        }
    }

    It 'runs the full stable Linux scaffold matrix on the weekly schedule' {
        $script:FullCiWorkflow | Should -Match '(?m)^  schedule:\s*$'
        foreach ($jobName in @('scaffold-linux', 'scaffold-linux-x64')) {
            Get-WorkflowJobBody $script:FullCiWorkflow $jobName |
                Should -Not -Match "github\.event_name == 'workflow_dispatch'" -Because "$jobName is part of scheduled Full CI"
        }
    }

    It 'runs affected filesystem fact tests in ordinary Windows CI' {
        $windowsJob = Get-WorkflowJobBody $script:CiWorkflow 'scaffold-windows'

        $windowsJob | Should -Match ([regex]::Escape(
                "'tests/windows-acls', 'tests/dotnet-file-creation'"))
        $windowsJob | Should -Match ([regex]::Escape(
                "'^(skills|tests)/(windows-acls|dotnet-file-creation)/'"))
        $windowsJob | Should -Match "if: steps\.windows-filesystem\.outputs\.affected == 'true'"
    }

    It 'builds and tests the dotnet-pipes sample on Windows and Linux' {
        $pipesJob = Get-WorkflowJobBody $script:CiWorkflow 'dotnet-pipes'

        $pipesJob | Should -Match ([regex]::Escape('runs-on: ${{ matrix.os }}'))
        $pipesJob | Should -Match ([regex]::Escape('os: [ubuntu-24.04-arm, windows-latest]'))
        $pipesJob | Should -Match ([regex]::Escape(
            'dotnet test --project ./tests/dotnet-pipes/DotNetPipes.Tests.csproj'))
        $pipesJob | Should -Match '--configuration Release'
        $pipesJob | Should -Not -Match '--nologo'
    }

    It 'exercises a pinned synthetic consumer on tag pushes' {
        $validateJob = Get-WorkflowJobBody $script:CiWorkflow 'validate'

        $validateJob | Should -Match 'Invoke-SyntheticConsumer\.ps1'
        $validateJob | Should -Match '-SourceRepository \$env:SOURCE_REPOSITORY'
        $validateJob | Should -Match '-Pin \$env:SOURCE_PIN'
    }

    It 'keeps real model evaluations out of GitHub Actions' {
        $script:AllWorkflowText | Should -Not -Match 'Invoke-SkillEvals\.ps1'
        $script:AllWorkflowText | Should -Not -Match 'COPILOT_GITHUB_TOKEN'
        $script:AllWorkflowText | Should -Not -Match '(?m)^\s+copilot\s+(?:-p|--prompt)\b'
    }
}
