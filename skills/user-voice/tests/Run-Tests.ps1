#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
$tests = @(
    'Test-WorkflowContracts.ps1',
    'Test-SourceCapability.ps1',
    'Test-EvidenceTransport.ps1',
    'Test-TargetedAnalysis.ps1',
    'Test-NuanceMatrix.ps1',
    'Test-Elicitation.ps1',
    'Test-ThreeWayComparison.ps1',
    'Test-LifecycleOutputs.ps1',
    'Test-RepositoryPath.ps1')

foreach ($test in $tests) {
    Write-Host "RUN $test"
    & $pwsh -NoProfile -File (Join-Path $PSScriptRoot $test)
    if ($LASTEXITCODE -ne 0) {
        throw "User voice test failed: $test"
    }
}

Write-Host "OK user voice workflow tests: $($tests.Count)"
