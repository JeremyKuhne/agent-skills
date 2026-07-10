#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('tool', 'library', 'multi-target')]
    [string] $Archetype,

    [Parameter(Mandatory)]
    [ValidateSet('mstest', 'xunit')]
    [string] $TestRunner,

    [string] $Framework = 'net10.0',
    [string] $FrameworkLegacy = 'net481',
    [string] $SdkVersion,
    [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-CheckedCommand ([string] $label, [scriptblock] $command) {
    $output = & $command 2>&1
    if ($LASTEXITCODE -ne 0) {
        $tail = @($output | Select-Object -Last 60) -join "`n"
        throw "$label failed (exit $LASTEXITCODE):`n$tail"
    }
}

$scaffold = Join-Path $RepoRoot 'skills/engineering-baseline/scripts/New-DotnetRepo.ps1'
$caseName = "Canary$($Archetype -replace '-', '')$($TestRunner.Substring(0, 1).ToUpperInvariant())$($TestRunner.Substring(1))"
$temporaryParent = Join-Path ([System.IO.Path]::GetTempPath()) "agent-scaffold-$([guid]::NewGuid().ToString('N'))"
$temporaryRoot = Join-Path $temporaryParent 'repo'

try {
    New-Item -ItemType Directory -Path $temporaryParent | Out-Null
    if ($SdkVersion) {
        $sdkSelection = @{
            sdk = @{
                version = $SdkVersion
                rollForward = 'disable'
                allowPrerelease = $SdkVersion.Contains('-')
            }
        }
        ($sdkSelection | ConvertTo-Json -Depth 3) + "`n" |
            Set-Content -LiteralPath (Join-Path $temporaryParent 'global.json') -Encoding utf8NoBOM -NoNewline
    }

    $scaffoldArguments = @{
        Root = $temporaryRoot
        Name = $caseName
        Archetype = $Archetype
        PackageId = "Canary.$caseName"
        Description = "Engineering baseline $Archetype $TestRunner canary."
        Owner = 'canary-owner'
        Framework = $Framework
        TestRunner = $TestRunner
        Skills = @()
    }
    if ($Archetype -eq 'tool') { $scaffoldArguments.ToolCommandName = $caseName.ToLowerInvariant() }
    if ($Archetype -eq 'multi-target') { $scaffoldArguments.FrameworkLegacy = $FrameworkLegacy }

    Push-Location $temporaryParent
    try {
        & $scaffold @scaffoldArguments
    }
    finally {
        Pop-Location
    }

    if ($SdkVersion) {
        $generatedSdkVersion = [string](Get-Content (Join-Path $temporaryRoot 'global.json') -Raw | ConvertFrom-Json).sdk.version
        if ($generatedSdkVersion -ne $SdkVersion) {
            throw "Generated global.json pins '$generatedSdkVersion'; expected '$SdkVersion'."
        }
    }

    Push-Location $temporaryRoot
    $savedCi = $env:CI
    try {
        & git init --quiet
        if ($LASTEXITCODE -ne 0) { throw 'git init failed' }
        & git config user.email 'canary@example.invalid'
        & git config user.name 'Scaffold Canary'
        & git config core.autocrlf false
        & git remote add origin "https://github.com/canary-owner/$caseName.git"
        & git add -A
        & git commit --quiet -m 'Initial scaffold'
        if ($LASTEXITCODE -ne 0) { throw 'initial canary commit failed' }

        $env:CI = 'true'
        & ./tools/Sync-AgentInstructions.ps1 -Check
        Invoke-CheckedCommand 'locked restore' { dotnet restore --locked-mode --nologo }
        Invoke-CheckedCommand 'Release build' { dotnet build -c Release --no-restore --nologo }
        Invoke-CheckedCommand 'Release test' { dotnet test -c Release }

        $packageOutput = Join-Path $temporaryRoot 'artifacts/canary-packages'
        $projectPath = Join-Path $temporaryRoot "src/$caseName/$caseName.csproj"
        Invoke-CheckedCommand 'Release pack' { dotnet pack $projectPath -c Release --no-restore --nologo -o $packageOutput }
        @(Get-ChildItem $packageOutput -Filter '*.nupkg' -File).Count | ForEach-Object {
            if ($_ -ne 1) { throw "Expected one package, found $_." }
        }

        $unresolvedTokens = @(Get-ChildItem $temporaryRoot -File -Recurse |
            Where-Object { $_.FullName -notmatch '[\\/](?:\.git|artifacts)[\\/]' } |
            Select-String -Pattern '\{\{[A-Z][A-Z0-9_]*\}\}')
        if ($unresolvedTokens.Count -gt 0) {
            throw "Generated files contain unresolved template tokens: $($unresolvedTokens.Path -join ', ')"
        }

        Write-Host "Scaffold canary passed: $Archetype / $TestRunner on $([System.Runtime.InteropServices.RuntimeInformation]::OSDescription)."
    }
    finally {
        $env:CI = $savedCi
        Pop-Location
    }
}
finally {
    Remove-Item $temporaryParent -Recurse -Force -ErrorAction SilentlyContinue
}