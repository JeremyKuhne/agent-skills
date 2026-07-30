#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:CanaryPath = Join-Path $PSScriptRoot 'Invoke-SyntheticConsumer.ps1'
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