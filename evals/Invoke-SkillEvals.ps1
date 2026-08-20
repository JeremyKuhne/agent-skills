#Requires -Version 7.2
[CmdletBinding()]
param(
    [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string] $ScenarioPath = (Join-Path $PSScriptRoot 'scenarios/create-pr.json'),
    [string] $OutputDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) "agent-skills-evals-$([guid]::NewGuid().ToString('N'))"),
    [string] $Model = 'gpt-5.4',
    [string[]] $ScenarioId,
    [string] $BaselineSummaryPath,
    [ValidateRange(0, 100)]
    [int] $RunCount = 0,
    [ValidateRange(1, 60)]
    [int] $TimeoutMinutes = 5,
    [ValidateRange(1, 32)]
    [int] $MaxConcurrency = 8,
    [switch] $IsolateCopilotHome = $true,
    [switch] $ReportOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'SkillEval.psm1') -Force
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
if (-not [System.IO.Path]::IsPathRooted($ScenarioPath)) {
    $ScenarioPath = Join-Path $RepoRoot $ScenarioPath
}
if (-not [System.IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory = Join-Path $RepoRoot $OutputDirectory
}
if (-not [string]::IsNullOrWhiteSpace($BaselineSummaryPath) -and
    -not [System.IO.Path]::IsPathRooted($BaselineSummaryPath)) {
    $BaselineSummaryPath = Join-Path $RepoRoot $BaselineSummaryPath
}
if (-not [string]::IsNullOrWhiteSpace($BaselineSummaryPath)) {
    $ScenarioId = @(Get-SkillEvalAffectedScenarioIds `
            -RepoRoot $RepoRoot `
            -ScenarioPath $ScenarioPath `
            -BaselineSummaryPath $BaselineSummaryPath `
            -ScenarioId $ScenarioId)
    if ($ScenarioId.Count -eq 0) {
        Write-Host 'No scenarios are affected by the current inputs.'
        exit 0
    }
}
$parameters = @{
    RepoRoot = $RepoRoot
    ScenarioPath = $ScenarioPath
    OutputDirectory = $OutputDirectory
    Model = $Model
    ScenarioId = $ScenarioId
    RunCount = $RunCount
    TimeoutMinutes = $TimeoutMinutes
    MaxConcurrency = $MaxConcurrency
    IsolateCopilotHome = $IsolateCopilotHome
}
$summary = Invoke-SkillEvalSuite @parameters

Write-Host "Evaluation reports: $OutputDirectory"
Write-Host "Runs: $($summary.RunCount); passed: $($summary.PassedCount); failed: $($summary.FailedCount); safety failures: $($summary.SafetyFailureCount); infrastructure failures: $($summary.InfrastructureFailureCount)."
exit (Get-SkillEvalExitCode -Summary $summary -ReportOnly:$ReportOnly)