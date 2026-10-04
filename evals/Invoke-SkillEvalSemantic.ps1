#Requires -Version 7.4
[CmdletBinding(PositionalBinding = $false)]
param(
    [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string] $ScenarioPath = (Join-Path $PSScriptRoot 'scenarios\technical-writing.json'),
    [Parameter(Mandatory)]
    [string] $InputDirectory,
    [string] $OutputDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) "agent-skills-content-$([guid]::NewGuid().ToString('N'))"),
    [string[]] $ScenarioId,
    [string] $ContentCliPath,
    [switch] $ReportOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SkillEvalContent.psm1') -Force
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
foreach ($name in @('ScenarioPath', 'InputDirectory', 'OutputDirectory')) {
    $value = Get-Variable -Name $name -ValueOnly
    if (-not [System.IO.Path]::IsPathRooted($value)) {
        Set-Variable -Name $name -Value (Join-Path $RepoRoot $value)
    }
}
$arguments = @(
    'rescore',
    '--repo-root', $RepoRoot,
    '--scenario', $ScenarioPath,
    '--input-directory', $InputDirectory,
    '--output-directory', $OutputDirectory,
    '--report-only', $ReportOnly.IsPresent.ToString().ToLowerInvariant()
)
if ($ScenarioId) { $arguments += @('--scenario-ids', ($ScenarioId -join ',')) }
$receipt = Invoke-SkillEvalContentCli -Arguments $arguments -CliPath $ContentCliPath
if ([string]::IsNullOrWhiteSpace($receipt.StandardOutput)) {
    throw "Content evaluation failed (exit $($receipt.ExitCode)): $($receipt.StandardError)"
}
$summary = ConvertFrom-Json -InputObject $receipt.StandardOutput -ErrorAction Stop
if ($receipt.ExitCode -notin @(0, 1, 2, 3)) {
    throw "Unexpected content evaluator exit $($receipt.ExitCode): $($receipt.StandardError)"
}
Write-Host "Content reports: $OutputDirectory"
Write-Host "Runs: $($summary.runCount); useful passes: $($summary.usefulPassedCount); pending: $($summary.pendingCount); quality failures: $($summary.usefulFailedCount); safety failures: $($summary.safetyFailureCount); infrastructure failures: $($summary.infrastructureFailureCount)."
exit $receipt.ExitCode
