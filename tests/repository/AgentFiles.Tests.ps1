#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:MirrorValidator = Join-Path $script:RepoRoot 'tools/Validate-AgentFiles.ps1'
    $script:LinkValidator = Join-Path $script:RepoRoot 'tools/Test-AgentFileLinks.ps1'
    $script:Pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
    $script:MirrorHeader = '<!-- DO NOT EDIT. Generated mirror of /AGENTS.md. Edit AGENTS.md and run: ./tools/Validate-AgentFiles.ps1 -Fix -->'

    function Write-FixtureFile (
        [string] $Root,
        [string] $RelativePath,
        [string] $Content) {
        $path = Join-Path $Root $RelativePath
        [System.IO.Directory]::CreateDirectory((Split-Path $path -Parent)) | Out-Null
        [System.IO.File]::WriteAllText($path, $Content)
        $path
    }

    function New-AgentFileFixture ([string] $Name, [string] $AgentsContent) {
        $root = Join-Path $TestDrive $Name
        [System.IO.Directory]::CreateDirectory($root) | Out-Null
        Write-FixtureFile $root 'AGENTS.md' $AgentsContent | Out-Null
        $root
    }

    function Invoke-AgentFileTool (
        [string] $Path,
        [string[]] $Arguments) {
        $output = @(& $script:Pwsh -NoProfile -File $Path @Arguments 2>&1)
        [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = $output -join [Environment]::NewLine
        }
    }
}

Describe 'Agent instruction mirror' {
    It 'rewrites repository-relative links for the .github mirror' {
        $source = "# Fixture`n`n[Root](docs/guide.md)`n[GitHub](.github/workflows/ci.yml)`n[External](https://example.com/path)`n[Mail](mailto:test@example.com)`n[Anchor](#fixture)`n[Absolute](/docs/guide.md)`n"
        $root = New-AgentFileFixture 'rewrite' $source

        $result = Invoke-AgentFileTool $script:MirrorValidator @('-RepoRoot', $root, '-Fix')

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $actual = [System.IO.File]::ReadAllText((Join-Path $root '.github/copilot-instructions.md'))
        $expectedBody = "# Fixture`n`n[Root](../docs/guide.md)`n[GitHub](workflows/ci.yml)`n[External](https://example.com/path)`n[Mail](mailto:test@example.com)`n[Anchor](#fixture)`n[Absolute](/docs/guide.md)`n"
        $actual | Should -BeExactly "$($script:MirrorHeader)`n$expectedBody"
    }

    It 'fails when the mirror is missing or stale' {
        $root = New-AgentFileFixture 'drift' "# Fixture`n"

        $missing = Invoke-AgentFileTool $script:MirrorValidator @('-RepoRoot', $root)
        $missing.ExitCode | Should -Be 1
        $missing.Output | Should -Match 'is missing'

        $fixed = Invoke-AgentFileTool $script:MirrorValidator @('-RepoRoot', $root, '-Fix')
        $fixed.ExitCode | Should -Be 0 -Because $fixed.Output
        [System.IO.File]::AppendAllText(
            (Join-Path $root '.github/copilot-instructions.md'),
            "stale`n")

        $stale = Invoke-AgentFileTool $script:MirrorValidator @('-RepoRoot', $root)
        $stale.ExitCode | Should -Be 1
        $stale.Output | Should -Match 'is out of sync'
    }

    It 'repairs drift and is byte-for-byte idempotent' {
        $root = New-AgentFileFixture 'idempotence' "# Fixture`n"
        Write-FixtureFile $root '.github/copilot-instructions.md' "stale`n" | Out-Null

        $first = Invoke-AgentFileTool $script:MirrorValidator @('-RepoRoot', $root, '-Fix')
        $first.ExitCode | Should -Be 0 -Because $first.Output
        $mirrorPath = Join-Path $root '.github/copilot-instructions.md'
        $firstHash = (Get-FileHash -LiteralPath $mirrorPath -Algorithm SHA256).Hash

        $second = Invoke-AgentFileTool $script:MirrorValidator @('-RepoRoot', $root, '-Fix')
        $second.ExitCode | Should -Be 0 -Because $second.Output
        $secondHash = (Get-FileHash -LiteralPath $mirrorPath -Algorithm SHA256).Hash

        $secondHash | Should -BeExactly $firstHash
    }

    It 'preserves CRLF line endings from the source' {
        $root = New-AgentFileFixture 'crlf' "# Fixture`r`n`r`nText.`r`n"

        $result = Invoke-AgentFileTool $script:MirrorValidator @('-RepoRoot', $root, '-Fix')

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $actual = [System.IO.File]::ReadAllText((Join-Path $root '.github/copilot-instructions.md'))
        $actual | Should -Not -Match '(?<!\r)\n'
        $actual | Should -BeExactly "$($script:MirrorHeader)`r`n# Fixture`r`n`r`nText.`r`n"
    }

    It 'rejects source whitespace that would propagate into the mirror' {
        $cases = @(
            @{ Name = 'tab'; Content = "#`tFixture`n"; Error = 'tab character' },
            @{ Name = 'trailing'; Content = "# Fixture  `n"; Error = 'trailing whitespace' },
            @{ Name = 'blank'; Content = "# Fixture`n  `n"; Error = 'whitespace-only line' },
            @{ Name = 'newlines'; Content = "# Fixture`n`n"; Error = 'exactly one newline' }
        )

        foreach ($case in $cases) {
            $root = New-AgentFileFixture "whitespace-$($case.Name)" $case.Content
            $result = Invoke-AgentFileTool $script:MirrorValidator @('-RepoRoot', $root, '-Fix')

            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match $case.Error
        }
    }
}

Describe 'Agent customization links' {
    It 'resolves links from both source and generated locations' {
        $root = New-AgentFileFixture 'valid-links' "# Fixture`n`n[Guide](docs/guide.md)`n"
        Write-FixtureFile $root 'docs/guide.md' "# Guide`n" | Out-Null
        Write-FixtureFile $root 'skills/sample/SKILL.md' "# Sample`n`n[Root](../../AGENTS.md)`n`n``[Ignored](missing-inline.md)```n`n``````md`n[Ignored](missing-fenced.md)`n```````n" | Out-Null
        $mirror = Invoke-AgentFileTool $script:MirrorValidator @('-RepoRoot', $root, '-Fix')
        $mirror.ExitCode | Should -Be 0 -Because $mirror.Output

        $result = Invoke-AgentFileTool $script:LinkValidator @('-RepoRoot', $root)

        $result.ExitCode | Should -Be 0 -Because $result.Output
    }

    It 'reports broken relative links with their source location' {
        $root = New-AgentFileFixture 'broken-links' "# Fixture`n`n[Missing](docs/missing.md)`n"

        $result = Invoke-AgentFileTool $script:LinkValidator @('-RepoRoot', $root)

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'AGENTS\.md:3: docs/missing\.md'
    }
}

Describe 'Agent file CI contract' {
    It 'validates the mirror and all Markdown links in the existing validation job' {
        $workflow = Get-Content -LiteralPath (
            Join-Path $script:RepoRoot '.github/workflows/ci.yml') -Raw

        $workflow | Should -Match '(?ms)^      - name: Validate agent instruction mirror\r?\n        shell: pwsh\r?\n        run: \./tools/Validate-AgentFiles\.ps1\r?$'

        $linkStep = [regex]::Match(
            $workflow,
            '(?ms)^      - name: Link check\r?\n(?<body>.*?)(?=^      - name:|\z)')
        $linkStep.Success | Should -BeTrue
        $linkStep.Value | Should -Match 'lycheeverse/lychee-action@'
        $linkStep.Value | Should -Match '--offline'
        $linkStep.Value | Should -Match '"\*\*/\*\.md"'
    }
}
