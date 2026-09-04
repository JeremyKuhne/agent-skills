#Requires -Version 7.2
[CmdletBinding()]
param(
    [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string[]] $ScenarioPath = @(
        'evals/scenarios/technical-writing.json',
        'evals/scenarios/create-pr.json',
        'evals/scenarios/manage-skills.json',
        'evals/scenarios/publishing-workflows.json',
        'evals/scenarios/user-voice.json',
        'evals/scenarios/create-skill-repo.json'
    ),
    [string] $OutputDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) "agent-skills-matrix-$([guid]::NewGuid().ToString('N'))"),
    [string] $Model = 'gpt-5.4',
    [ValidateRange(0, 100)]
    [int] $RunCount = 0,
    [ValidateRange(1, 60)]
    [int] $TimeoutMinutes = 5,
    [ValidateRange(1, 32)]
    [int] $MaxConcurrency = 8,
    [ValidateRange(1, 240)]
    [int] $MatrixTimeoutMinutes = 60,
    [switch] $ReportOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
Import-Module (Join-Path $PSScriptRoot 'SkillEval.psm1') -Force
$resolvedScenarioPaths = @($ScenarioPath | ForEach-Object {
        $path = if ([System.IO.Path]::IsPathRooted($_)) {
            $_
        }
        else { Join-Path $RepoRoot $_ }
        (Resolve-Path -LiteralPath $path).Path
    })
$documentNames = @($resolvedScenarioPaths | ForEach-Object {
        [System.IO.Path]::GetFileNameWithoutExtension($_)
    })
if (@($documentNames | Sort-Object -Unique).Count -ne $documentNames.Count) {
    throw 'Scenario document filenames must be unique within a matrix.'
}
if ($MaxConcurrency -lt $resolvedScenarioPaths.Count) {
    throw "Matrix concurrency $MaxConcurrency must be at least the document count $($resolvedScenarioPaths.Count)."
}

$workloads = for ($index = 0; $index -lt $resolvedScenarioPaths.Count; $index++) {
    $scenarios = @(Get-SkillEvalScenarios -Path $resolvedScenarioPaths[$index])
    $workItemCount = if ($RunCount -gt 0) {
        $scenarios.Count * $RunCount
    }
    else {
        ($scenarios | Measure-Object -Property runCount -Sum).Sum
    }
    [pscustomobject]@{
        Name = $documentNames[$index]
        WorkItemCount = [int]$workItemCount
    }
}
$allocations = @(Get-SkillEvalWorkerAllocation `
        -Workload $workloads `
        -MaxConcurrency $MaxConcurrency)
$allocationByName = @{}
foreach ($allocation in $allocations) {
    $allocationByName[[string]$allocation.Name] = [int]$allocation.Workers
}

$outputPath = if ([System.IO.Path]::IsPathRooted($OutputDirectory)) {
    [System.IO.Path]::GetFullPath($OutputDirectory)
}
else { [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $OutputDirectory)) }
if (Test-Path -LiteralPath $outputPath) {
    if (@(Get-ChildItem -LiteralPath $outputPath -Force).Count -gt 0) {
        throw "Matrix output directory is not empty: $outputPath"
    }
}
else {
    New-Item -ItemType Directory -Path $outputPath | Out-Null
}

$workItems = for ($index = 0; $index -lt $resolvedScenarioPaths.Count; $index++) {
    [pscustomobject]@{
        Index = $index
        Name = $documentNames[$index]
        ScenarioPath = $resolvedScenarioPaths[$index]
        OutputDirectory = Join-Path $outputPath $documentNames[$index]
        LogPath = Join-Path $outputPath "$($documentNames[$index]).log"
        Workers = $allocationByName[$documentNames[$index]]
    }
}
$pwshPath = [string]@(Get-Command pwsh -CommandType Application -All -ErrorAction Stop)[0].Source
$runnerPath = Join-Path $PSScriptRoot 'Invoke-SkillEvals.ps1'
$matrixTimeoutMilliseconds = $MatrixTimeoutMinutes * 60 * 1000
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$processResults = @($workItems | ForEach-Object -Parallel {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $using:pwshPath
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $arguments = [System.Collections.Generic.List[string]]::new()
        foreach ($argument in @(
                '-NoProfile',
                '-File', $using:runnerPath,
                '-RepoRoot', $using:RepoRoot,
                '-ScenarioPath', $_.ScenarioPath,
                '-OutputDirectory', $_.OutputDirectory,
                '-Model', $using:Model,
                '-TimeoutMinutes', [string]$using:TimeoutMinutes,
                '-MaxConcurrency', [string]$_.Workers,
                '-ReportOnly')) {
            $arguments.Add([string]$argument)
        }
        if ($using:RunCount -gt 0) {
            $arguments.Add('-RunCount')
            $arguments.Add([string]$using:RunCount)
        }
        foreach ($argument in $arguments) {
            $startInfo.ArgumentList.Add($argument)
        }
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        $started = $process.Start()
        if (-not $started) {
            throw "Could not start matrix document '$($_.Name)'."
        }
        $standardOutput = $process.StandardOutput.ReadToEndAsync()
        $standardError = $process.StandardError.ReadToEndAsync()
        $completed = $process.WaitForExit($using:matrixTimeoutMilliseconds)
        if (-not $completed) {
            $process.Kill($true)
            $process.WaitForExit()
        }
        @(
            $standardOutput.GetAwaiter().GetResult()
            $standardError.GetAwaiter().GetResult()) -join [Environment]::NewLine |
            Set-Content -LiteralPath $_.LogPath
        [pscustomobject]@{
            Index = $_.Index
            Name = $_.Name
            ExitCode = if ($completed) { $process.ExitCode } else { -1 }
            TimedOut = -not $completed
            OutputDirectory = $_.OutputDirectory
            LogPath = $_.LogPath
            Workers = $_.Workers
        }
    } -ThrottleLimit $workItems.Count)
$stopwatch.Stop()
if ($processResults.Count -ne $workItems.Count) {
    throw "Expected $($workItems.Count) matrix document results but received $($processResults.Count)."
}

$documents = [System.Collections.Generic.List[object]]::new()
foreach ($processResult in @($processResults | Sort-Object Index)) {
    $summaryPath = Join-Path $processResult.OutputDirectory 'summary.json'
    if (-not (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
        throw "Matrix document '$($processResult.Name)' did not produce a summary; see '$($processResult.LogPath)'."
    }
    $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
    $documents.Add([pscustomobject]@{
            Name = $processResult.Name
            ScenarioPath = $resolvedScenarioPaths[$processResult.Index]
            Workers = $processResult.Workers
            ExitCode = $processResult.ExitCode
            TimedOut = $processResult.TimedOut
            LogPath = $processResult.LogPath
            SummaryPath = $summaryPath
            Summary = $summary
        })
}
$candidateRevisions = @($documents.Summary.CandidateRevision | Sort-Object -Unique)
$scorerRevisions = @($documents.Summary.ScorerRevision | Sort-Object -Unique)
if ($candidateRevisions.Count -ne 1 -or $scorerRevisions.Count -ne 1) {
    throw "Matrix revisions differ: candidate=$($candidateRevisions.Count), scorer=$($scorerRevisions.Count)."
}
$summary = [pscustomobject]@{
    SchemaVersion = 1
    GeneratedAtUtc = [DateTime]::UtcNow.ToString('O')
    Model = $Model
    MaxConcurrency = $MaxConcurrency
    MatrixTimeoutMinutes = $MatrixTimeoutMinutes
    WallTimeMilliseconds = $stopwatch.ElapsedMilliseconds
    DocumentCount = $documents.Count
    ScenarioCount = ($documents.Summary | Measure-Object -Property ScenarioCount -Sum).Sum
    RunCount = ($documents.Summary | Measure-Object -Property RunCount -Sum).Sum
    PassedCount = ($documents.Summary | Measure-Object -Property PassedCount -Sum).Sum
    FailedCount = ($documents.Summary | Measure-Object -Property FailedCount -Sum).Sum
    SafetyFailureCount = ($documents.Summary | Measure-Object -Property SafetyFailureCount -Sum).Sum
    InfrastructureFailureCount = ($documents.Summary | Measure-Object -Property InfrastructureFailureCount -Sum).Sum
    CandidateRevision = $candidateRevisions[0]
    ScorerRevision = $scorerRevisions[0]
    Documents = @($documents | ForEach-Object {
            [pscustomobject]@{
                Name = $_.Name
                Workers = $_.Workers
                ExitCode = $_.ExitCode
                TimedOut = $_.TimedOut
                ScenarioCount = $_.Summary.ScenarioCount
                RunCount = $_.Summary.RunCount
                PassedCount = $_.Summary.PassedCount
                FailedCount = $_.Summary.FailedCount
                SafetyFailureCount = $_.Summary.SafetyFailureCount
                InfrastructureFailureCount = $_.Summary.InfrastructureFailureCount
                WallTimeMilliseconds = $_.Summary.WallTimeMilliseconds
                SummaryPath = $_.SummaryPath
                LogPath = $_.LogPath
            }
        })
}
$summary | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath (Join-Path $outputPath 'summary.json')
$summary.Documents |
    Select-Object Name, Workers, RunCount, PassedCount, FailedCount, WallTimeMilliseconds |
    Format-Table -AutoSize
Write-Host "Matrix runs: $($summary.RunCount); passed: $($summary.PassedCount); failed: $($summary.FailedCount); safety failures: $($summary.SafetyFailureCount); infrastructure failures: $($summary.InfrastructureFailureCount); wall time: $($summary.WallTimeMilliseconds) ms."
Write-Host "Matrix reports: $outputPath"
if (@($summary.Documents | Where-Object { $_.TimedOut -or $_.ExitCode -ge 2 }).Count -gt 0) {
    exit 3
}
exit (Get-SkillEvalExitCode -Summary $summary -ReportOnly:$ReportOnly)
