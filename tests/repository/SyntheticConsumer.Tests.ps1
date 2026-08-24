#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:CanaryPath = Join-Path $PSScriptRoot 'Invoke-SyntheticConsumer.ps1'
    $script:GitPath = [string]@(
        Get-Command git -CommandType Application -All -ErrorAction Stop)[0].Source
    . (Join-Path $PSScriptRoot 'SkillArtifactTestHelpers.ps1')
}

Describe 'Synthetic consumer provenance' {
    BeforeAll {
        $script:FixtureRepository = Join-Path $TestDrive 'source-repository'
        $gitOutput = @(& $script:GitPath init --quiet $script:FixtureRepository 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "Could not initialize fixture repository: $gitOutput" }
        Set-Content -LiteralPath (Join-Path $script:FixtureRepository 'fixture.txt') `
            -Value 'fixture'
        $gitOutput = @(& $script:GitPath -C $script:FixtureRepository add fixture.txt 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "Could not stage fixture: $gitOutput" }
        $gitOutput = @(& $script:GitPath -C $script:FixtureRepository `
                -c user.name=Fixture -c user.email=fixture@example.com `
                commit --quiet -m fixture 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "Could not commit fixture: $gitOutput" }
        $script:FixtureSha = [string]@(
            & $script:GitPath -C $script:FixtureRepository rev-parse HEAD)[0]
        $gitOutput = @(& $script:GitPath -C $script:FixtureRepository `
                tag fixture-tag 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "Could not tag fixture: $gitOutput" }
    }

    It 'uses the canonical ref for a tag pin' {
        Get-GitHubSkillRef $script:GitPath $script:FixtureRepository `
            'fixture-tag' | Should -BeExactly 'refs/tags/fixture-tag'
    }

    It 'preserves a commit SHA pin' {
        Get-GitHubSkillRef $script:GitPath $script:FixtureRepository `
            $script:FixtureSha | Should -BeExactly $script:FixtureSha
    }
}

Describe 'Synthetic consumer output ownership' {
    It 'rejects a pre-existing output directory without changing it' {
        $outputDirectory = Join-Path $TestDrive 'existing-output'
        New-Item -ItemType Directory -Path $outputDirectory | Out-Null
        $sentinelPath = Join-Path $outputDirectory 'sentinel.txt'
        Set-Content -LiteralPath $sentinelPath -Value 'preserve me'

        $output = & pwsh -NoProfile -File $script:CanaryPath `
            -RepoRoot $script:RepoRoot `
            -OutputDirectory $outputDirectory 2>&1

        $LASTEXITCODE | Should -Not -Be 0
        $output -join "`n" | Should -Match 'Output directory already exists'
        Test-Path -LiteralPath $sentinelPath -PathType Leaf | Should -BeTrue
        (Get-Content -LiteralPath $sentinelPath -Raw).Trim() | Should -Be 'preserve me'
        @(Get-ChildItem -LiteralPath $outputDirectory -Force).Count | Should -Be 1
    }
}