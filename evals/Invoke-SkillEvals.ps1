#Requires -Version 7.2
[CmdletBinding()]
param(
    [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string] $ScenarioPath = (Join-Path $PSScriptRoot 'scenarios/create-pr.json'),
    [string] $OutputDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) "agent-skills-evals-$([guid]::NewGuid().ToString('N'))"),
    [string] $Model = 'gpt-5.4',
    [string[]] $ScenarioId,
    [ValidateRange(0, 100)]
    [int] $RunCount = 0,
    [ValidateRange(1, 60)]
    [int] $TimeoutMinutes = 5,
    [switch] $IsolateCopilotHome,
    [switch] $ReportOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'SkillEval.psm1') -Force
$parameters = @{
    RepoRoot = $RepoRoot
    ScenarioPath = $ScenarioPath
    OutputDirectory = $OutputDirectory
    Model = $Model
    ScenarioId = $ScenarioId
    RunCount = $RunCount
    TimeoutMinutes = $TimeoutMinutes
    IsolateCopilotHome = $IsolateCopilotHome
}
$summary = Invoke-SkillEvalSuite @parameters

Write-Host "Evaluation reports: $OutputDirectory"
Write-Host "Runs: $($summary.RunCount); passed: $($summary.PassedCount); failed: $($summary.FailedCount); safety failures: $($summary.SafetyFailureCount); infrastructure failures: $($summary.InfrastructureFailureCount)."
exit (Get-SkillEvalExitCode -Summary $summary -ReportOnly:$ReportOnly)