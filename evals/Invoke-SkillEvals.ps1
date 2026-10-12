<#
.SYNOPSIS
    Runs fresh evaluations with an explicit optional skill exposure treatment.
.DESCRIPTION
    SkillCondition defaults to enabled (the existing complete plugin).
    TargetSkill selects only that public core and its hard dependencies, without
    agents, MCP declarations, project skills, or composition fixtures. No-skill
    stages no customization artifacts. Controlled treatments require isolated
    homes; task fixtures, prompts, permissions, and scoring remain unchanged.
    Pair separate fresh output directories with the same scenario IDs, model,
    run count, timeout, and concurrency. Existing routing expectations are not
    baseline quality grades and may intentionally fail under no-skill.
.EXAMPLE
    .\evals\Invoke-SkillEvals.ps1 -Model gpt-6.1-sol -ScenarioPath evals\scenarios\technical-writing.json -ScenarioId technical-writing-routing-explicit-draft -TargetSkill technical-writing -SkillCondition enabled -RunCount 1 -OutputDirectory scratch\pilot-enabled -CopilotPath C:\approved\copilot.exe
    Use the same arguments with -SkillCondition no-skill and a new output directory
    for the matched control. Model execution requires separate explicit approval.
#>
#Requires -Version 7.2
[CmdletBinding()]
param(
    [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string] $ScenarioPath = (Join-Path $PSScriptRoot 'scenarios/create-pr.json'),
    [string] $OutputDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) "agent-skills-evals-$([guid]::NewGuid().ToString('N'))"),
    [string] $Model,
    [string[]] $ScenarioId,
    [string] $BaselineSummaryPath,
    [ValidateRange(0, 100)]
    [int] $RunCount = 0,
    [ValidateRange(1, 60)]
    [int] $TimeoutMinutes = 5,
    [ValidateRange(1, 32)]
    [int] $MaxConcurrency = 8,
    [switch] $IsolateCopilotHome = $true,
    [switch] $ReportOnly,
    [string] $CopilotPath,
    [ValidateSet('enabled', 'no-skill')]
    [string] $SkillCondition = 'enabled',
    [string] $TargetSkill
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Model)) {
    throw 'Specify -Model with an approved model ID before running evaluations.'
}

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
            -Model $Model `
            -SkillCondition $SkillCondition `
            -TargetSkill $TargetSkill `
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
    CopilotPath = $CopilotPath
    ScenarioId = $ScenarioId
    RunCount = $RunCount
    TimeoutMinutes = $TimeoutMinutes
    MaxConcurrency = $MaxConcurrency
    IsolateCopilotHome = $IsolateCopilotHome
    SkillCondition = $SkillCondition
    TargetSkill = $TargetSkill
}
$summary = Invoke-SkillEvalSuite @parameters

Write-Host "Evaluation reports: $OutputDirectory"
Write-Host "Runs: $($summary.RunCount); passed: $($summary.PassedCount); failed: $($summary.FailedCount); safety failures: $($summary.SafetyFailureCount); infrastructure failures: $($summary.InfrastructureFailureCount)."
exit (Get-SkillEvalExitCode -Summary $summary -ReportOnly:$ReportOnly)