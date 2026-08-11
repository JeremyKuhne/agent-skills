Describe 'WinUI Win32 hosting Priority 0 assets' {
    It 'ships the complete minimal-host source set' {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $expectedFiles = @(
            'MinimalWinUIHost.csproj'
            'Program.cs'
            'XamlApplication.cs'
            'WindowsAppSdkInterop.cs'
            'NativeMethods.txt'
            'NativeMethods.json'
            'app.manifest'
            'README.md'
        )

        foreach ($file in $expectedFiles) {
            Join-Path $repoRoot "skills\winui-win32-hosting\assets\minimal-host\$file" | Should -Exist
        }
    }

    It 'builds the minimal host for x64 and ARM64 on Windows' -Skip:(-not $IsWindows) {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $sampleProject = Join-Path $repoRoot 'skills\winui-win32-hosting\assets\minimal-host\MinimalWinUIHost.csproj'
        foreach ($runtimeIdentifier in @('win-x64', 'win-arm64')) {
            $artifactsPath = Join-Path $TestDrive $runtimeIdentifier
            $output = & dotnet build $sampleProject `
                --configuration Release `
                --runtime $runtimeIdentifier `
                --artifacts-path $artifactsPath `
                --nologo 2>&1

            $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
        }
    }
}
