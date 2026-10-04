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
try {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
    foreach ($name in @('ScenarioPath', 'InputDirectory', 'OutputDirectory')) {
        $value = Get-Variable -Name $name -ValueOnly
        if (-not [System.IO.Path]::IsPathRooted($value)) {
            Set-Variable -Name $name -Value (Join-Path $RepoRoot $value)
        }
    }
}
catch [System.Management.Automation.ItemNotFoundException],
      [System.Management.Automation.DriveNotFoundException],
      [System.Management.Automation.ProviderNotFoundException],
      [System.UnauthorizedAccessException],
      [System.ArgumentException],
      [System.NotSupportedException] {
    [Console]::Error.WriteLine("Content evaluation setup failed: $($_.Exception.Message)")
    exit 3
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
try {
    $receipt = Invoke-SkillEvalContentCli -Arguments $arguments -CliPath $ContentCliPath
}
catch [System.Management.Automation.RuntimeException],
      [System.ComponentModel.Win32Exception],
      [System.IO.IOException],
      [System.UnauthorizedAccessException],
      [System.ArgumentException],
      [System.InvalidOperationException] {
    [Console]::Error.WriteLine("Content evaluation process failed: $($_.Exception.Message)")
    exit 3
}
if ($receipt.ExitCode -notin @(0, 1, 2, 3)) {
    [Console]::Error.WriteLine("Unexpected content evaluator exit $($receipt.ExitCode): $($receipt.StandardError)")
    exit 3
}
if ([string]::IsNullOrWhiteSpace($receipt.StandardOutput)) {
    [Console]::Error.WriteLine("Content evaluation failed (exit $($receipt.ExitCode)): $($receipt.StandardError)")
    exit 3
}
try {
    $summary = ConvertFrom-Json -InputObject $receipt.StandardOutput -NoEnumerate -ErrorAction Stop
    if ($summary -isnot [pscustomobject]) {
        [Console]::Error.WriteLine('Content evaluator summary must be a JSON object.')
        exit 3
    }
    $description = "Runs: $($summary.runCount); useful passes: $($summary.usefulPassedCount); pending: $($summary.pendingCount); quality failures: $($summary.usefulFailedCount); safety failures: $($summary.safetyFailureCount); infrastructure failures: $($summary.infrastructureFailureCount)."
}
catch [System.ArgumentException],
      [System.Management.Automation.PropertyNotFoundException] {
    [Console]::Error.WriteLine("Invalid content evaluator summary: $($_.Exception.Message)")
    exit 3
}
Write-Host "Content reports: $OutputDirectory"
Write-Host $description
exit $receipt.ExitCode
