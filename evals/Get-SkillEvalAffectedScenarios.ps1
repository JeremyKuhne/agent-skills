#Requires -Version 7.2
[CmdletBinding()]
param(
    [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string] $ScenarioPath = (Join-Path $PSScriptRoot 'scenarios/create-pr.json'),
    [Parameter(Mandatory)]
    [string] $BaselineSummaryPath,
    [string[]] $ScenarioId,
    [switch] $AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'SkillEval.psm1') -Force
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
if (-not [System.IO.Path]::IsPathRooted($ScenarioPath)) {
    $ScenarioPath = Join-Path $RepoRoot $ScenarioPath
}
if (-not [System.IO.Path]::IsPathRooted($BaselineSummaryPath)) {
    $BaselineSummaryPath = Join-Path $RepoRoot $BaselineSummaryPath
}
$affected = @(Get-SkillEvalAffectedScenarioIds `
        -RepoRoot $RepoRoot `
        -ScenarioPath $ScenarioPath `
        -BaselineSummaryPath $BaselineSummaryPath `
        -ScenarioId $ScenarioId)
if ($AsJson) {
    ConvertTo-Json -InputObject $affected
}
else {
    $affected
}