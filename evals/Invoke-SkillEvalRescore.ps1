#Requires -Version 7.2
[CmdletBinding()]
param(
    [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string] $ScenarioPath = (Join-Path $PSScriptRoot 'scenarios/create-pr.json'),
    [Parameter(Mandatory)]
    [string] $InputDirectory,
    [string] $OutputDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) "agent-skills-rescore-$([guid]::NewGuid().ToString('N'))"),
    [string[]] $ScenarioId,
    [switch] $AllowLegacyUnverifiedEvidence,
    [switch] $ReportOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'SkillEval.psm1') -Force
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
if (-not [System.IO.Path]::IsPathRooted($ScenarioPath)) {
    $ScenarioPath = Join-Path $RepoRoot $ScenarioPath
}
if (-not [System.IO.Path]::IsPathRooted($InputDirectory)) {
    $InputDirectory = Join-Path $RepoRoot $InputDirectory
}
if (-not [System.IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory = Join-Path $RepoRoot $OutputDirectory
}
$summary = Invoke-SkillEvalRescore `
    -RepoRoot $RepoRoot `
    -ScenarioPath $ScenarioPath `
    -InputDirectory $InputDirectory `
    -OutputDirectory $OutputDirectory `
    -ScenarioId $ScenarioId `
    -AllowLegacyUnverifiedEvidence:$AllowLegacyUnverifiedEvidence

Write-Host "Rescore reports: $OutputDirectory"
Write-Host "Runs: $($summary.RunCount); passed: $($summary.PassedCount); failed: $($summary.FailedCount); safety failures: $($summary.SafetyFailureCount); infrastructure failures: $($summary.InfrastructureFailureCount)."
exit (Get-SkillEvalExitCode -Summary $summary -ReportOnly:$ReportOnly)