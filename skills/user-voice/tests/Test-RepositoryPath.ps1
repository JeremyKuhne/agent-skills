#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$skillRoot = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $skillRoot 'scripts/Test-UserVoiceRepository.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "user-voice-repository-$([guid]::NewGuid().ToString('N'))"
$repository = Join-Path $testRoot 'repository'
$outside = Join-Path $testRoot 'outside'
$pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
$git = Get-Command git -CommandType Application -ErrorAction Stop |
    Select-Object -First 1

try {
    New-Item -ItemType Directory -Path $repository | Out-Null
    New-Item -ItemType Directory -Path $outside | Out-Null
    & $git.Source -C $repository init --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Could not initialize test repository.' }
    [System.IO.File]::WriteAllText(
        (Join-Path $repository 'safe.md'),
        "# Safe test content`n",
        [System.Text.UTF8Encoding]::new($false))

    $output = @(& $pwsh -NoProfile -File $validator `
            -RepositoryPath $repository `
            -ContentPath ([System.IO.Path]::GetFullPath($repository)) 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "The absolute repository root was rejected:`n$($output -join "`n")"
    }

    if ($IsWindows -and $repository.Length -gt 1 -and $repository[1] -eq ':') {
        $driveRelativeContent = "$($repository[0]):safe.md"
        $output = @(& $pwsh -NoProfile -File $validator `
                -RepositoryPath $repository `
                -ContentPath $driveRelativeContent 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "The drive-relative content path was not resolved against the repository:`n$($output -join "`n")"
        }

        $output = @(& $pwsh -NoProfile -File $validator `
                -RepositoryPath $repository `
                -ContentPath '\safe.md' 2>&1)
        if ($LASTEXITCODE -eq 0) {
            throw 'A root-relative content path outside the repository was accepted.'
        }
    }

    $output = @(& $pwsh -NoProfile -File $validator `
            -RepositoryPath $repository `
            -ContentPath $outside 2>&1)
    if ($LASTEXITCODE -eq 0) {
        throw 'A content path outside the repository was accepted.'
    }

    Write-Host 'OK repository path acceptance tests'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
