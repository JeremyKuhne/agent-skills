#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$skillRoot = Split-Path -Parent $PSScriptRoot
$validator = Join-Path $skillRoot 'scripts/Test-UserVoiceSourceCapability.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "user-voice-capability-$([guid]::NewGuid().ToString('N'))"
$pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })

function Write-TestFile([string] $path, [string] $content) {
    [System.IO.File]::WriteAllText(
        $path,
        $content.TrimEnd("`r", "`n") + "`n",
        [System.Text.UTF8Encoding]::new($false))
}

function Invoke-RequiredSuccess([string] $name, [string] $path) {
    $output = @(& $pwsh -NoProfile -File $validator -Path $path -AsOfDate '2030-01-15' 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "$name failed unexpectedly:`n$($output -join "`n")"
    }
}

function Invoke-RequiredFailure([string] $name, [string] $path) {
    $output = @(& $pwsh -NoProfile -File $validator -Path $path -AsOfDate '2030-01-15' 2>&1)
    if ($LASTEXITCODE -eq 0) {
        throw "$name passed unexpectedly."
    }
}

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $valid = @'
# User voice source capability declaration

- declaration-schema-version: 1
- client: example-client
- client-version: 1.0
- reviewed-on: 2030-01-15
- expires-on: 2030-02-01

## category-001

- source-category: workspace-documents
- access: metadata-and-content
- account-boundary: workspace-only
- source-display: yes
- model-exposure: current-provider
- return-methods: direct, attachment
- exclusions: third-party and excluded-topic material
- verification: tool-observed

## category-002

- source-category: private-email
- access: none
- account-boundary: none
- source-display: no
- model-exposure: none
- return-methods: none
- exclusions: unavailable in this client
- verification: unverified

## category-003

- source-category: public-technical-writing
- access: metadata-and-content
- account-boundary: public-unauthenticated
- source-display: yes
- model-exposure: current-provider
- return-methods: direct
- exclusions: unconfirmed authorship and excluded topics
- verification: tool-observed
'@
    $validPath = Join-Path $testRoot 'valid.md'
    Write-TestFile $validPath $valid
    Invoke-RequiredSuccess 'Verified capability' $validPath

    $expiredPath = Join-Path $testRoot 'expired.md'
    Write-TestFile $expiredPath ($valid.Replace(
            '- expires-on: 2030-02-01',
            '- expires-on: 2030-01-14'))
    Invoke-RequiredFailure 'Expired capability' $expiredPath

    $unverifiedPath = Join-Path $testRoot 'unverified-access.md'
    $unverified = $valid.
        Replace('- source-category: private-email', '- source-category: private-messages').
        Replace('- access: none', '- access: content').
        Replace('- account-boundary: none', '- account-boundary: current-connected-account').
        Replace('- source-display: no', '- source-display: yes').
        Replace('- model-exposure: none', '- model-exposure: current-provider').
        Replace('- return-methods: none', '- return-methods: m365')
    Write-TestFile $unverifiedPath $unverified
    Invoke-RequiredFailure 'Unverified access' $unverifiedPath

    $incompletePath = Join-Path $testRoot 'incomplete.md'
    Write-TestFile $incompletePath ($valid.Replace(
            '- source-display: yes',
            '- source-display: no'))
    Invoke-RequiredFailure 'Incomplete disclosure' $incompletePath

    Write-Host 'OK source capability acceptance tests'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
