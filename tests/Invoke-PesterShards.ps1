#Requires -Version 7.2
[CmdletBinding()]
param(
    [string[]] $Path = @($PSScriptRoot),
    [string] $OutputDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) "agent-skills-pester-$([guid]::NewGuid().ToString('N'))"),
    [ValidateRange(1, 32)]
    [int] $MaxConcurrency = 4,
    [ValidateRange(1, 240)]
    [int] $ShardTimeoutMinutes = 30,
    [ValidateRange(0, 3600)]
    [int] $ShardTimeoutSeconds = 0,
    [version] $PesterVersion = '5.7.1',
    [string] $PowerShellPath,
    [string] $PathPrefix,
    [string] $BaselineSummaryPath,
    [string] $ShardPath,
    [string] $ResultPath
)

$ErrorActionPreference = 'Stop'

if (-not [string]::IsNullOrWhiteSpace($ShardPath)) {
    if ([string]::IsNullOrWhiteSpace($ResultPath)) {
        throw '-ResultPath is required in shard mode.'
    }
    if (-not [string]::IsNullOrWhiteSpace($PathPrefix)) {
        $env:PATH = $PathPrefix + [IO.Path]::PathSeparator + $env:PATH
    }
    Import-Module Pester -RequiredVersion $PesterVersion -Force -ErrorAction Stop
    $configuration = New-PesterConfiguration
    $configuration.Run.Path = (Resolve-Path -LiteralPath $ShardPath).Path
    $configuration.Run.Throw = $false
    $configuration.Run.Exit = $false
    $configuration.Run.PassThru = $true
    $configuration.Output.Verbosity = 'Normal'
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $result = Invoke-Pester -Configuration $configuration
    $stopwatch.Stop()
    [pscustomobject]@{
        Path = (Resolve-Path -LiteralPath $ShardPath).Path
        Result = [string]$result.Result
        PassedCount = $result.PassedCount
        FailedCount = $result.FailedCount
        FailedBlocksCount = $result.FailedBlocksCount
        FailedContainersCount = $result.FailedContainersCount
        SkippedCount = $result.SkippedCount
        NotRunCount = $result.NotRunCount
        InconclusiveCount = $result.InconclusiveCount
        TotalCount = $result.TotalCount
        DurationMilliseconds = $stopwatch.ElapsedMilliseconds
    } | ConvertTo-Json | Set-Content -LiteralPath $ResultPath
    if ($result.Result -ne 'Passed' -or $result.TotalCount -eq 0 -or
        $result.NotRunCount -gt 0 -or $result.InconclusiveCount -gt 0) { exit 1 }
    exit 0
}

$testFiles = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase)
foreach ($inputPath in $Path) {
    $resolvedPath = (Resolve-Path -LiteralPath $inputPath).Path
    if (Test-Path -LiteralPath $resolvedPath -PathType Leaf) {
        if ($resolvedPath -notlike '*.Tests.ps1') {
            throw "Pester shard path is not a *.Tests.ps1 file: $resolvedPath"
        }
        $testFiles.Add($resolvedPath) | Out-Null
    }
    else {
        foreach ($testFile in @(Get-ChildItem -LiteralPath $resolvedPath -Filter '*.Tests.ps1' -File -Recurse)) {
            $testFiles.Add($testFile.FullName) | Out-Null
        }
    }
}
$orderedTestFiles = @($testFiles | Sort-Object)
if ($orderedTestFiles.Count -eq 0) {
    throw 'No Pester test files were found.'
}

$resolvedOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $resolvedOutputDirectory) {
    if (@(Get-ChildItem -LiteralPath $resolvedOutputDirectory -Force).Count -gt 0) {
        throw "Pester output directory is not empty: $resolvedOutputDirectory"
    }
}
else {
    New-Item -ItemType Directory -Path $resolvedOutputDirectory | Out-Null
}
$baselineDurations = @{}
if (-not [string]::IsNullOrWhiteSpace($BaselineSummaryPath)) {
    $baseline = Get-Content `
        -LiteralPath (Resolve-Path -LiteralPath $BaselineSummaryPath).Path `
        -Raw | ConvertFrom-Json
    foreach ($shard in @($baseline.Shards)) {
        $baselineDurations[[string]$shard.Path] = [long]$shard.DurationMilliseconds
    }
}
$workItems = @(for ($index = 0; $index -lt $orderedTestFiles.Count; $index++) {
    [pscustomobject]@{
        Index = $index
        Path = $orderedTestFiles[$index]
        EstimatedDurationMilliseconds = if ($baselineDurations.ContainsKey($orderedTestFiles[$index])) {
            $baselineDurations[$orderedTestFiles[$index]]
        }
        else { 0L }
        ResultPath = Join-Path $resolvedOutputDirectory "shard-$index.json"
        LogPath = Join-Path $resolvedOutputDirectory "shard-$index.log"
    }
})
$scheduledWorkItems = @($workItems |
    Sort-Object @{ Expression = 'EstimatedDurationMilliseconds'; Descending = $true }, Path)

$pwshPath = if ([string]::IsNullOrWhiteSpace($PowerShellPath)) {
    [string]@(Get-Command pwsh -CommandType Application -All -ErrorAction Stop)[0].Source
}
else { [System.IO.Path]::GetFullPath($PowerShellPath) }
$scriptPath = $PSCommandPath
$pesterVersionText = $PesterVersion.ToString()
$shardTimeoutMilliseconds = if ($ShardTimeoutSeconds -gt 0) {
    $ShardTimeoutSeconds * 1000
}
else { $ShardTimeoutMinutes * 60 * 1000 }
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$processResults = @($scheduledWorkItems | ForEach-Object -Parallel {
        $workItem = $_
        $process = $null
        $started = $false
        try {
            $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
            $startInfo.FileName = $using:pwshPath
            $startInfo.UseShellExecute = $false
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            foreach ($argument in @(
                    '-NoProfile',
                    '-File', $using:scriptPath,
                    '-ShardPath', $workItem.Path,
                    '-ResultPath', $workItem.ResultPath,
                    '-PesterVersion', $using:pesterVersionText,
                    '-PathPrefix', [string]$using:PathPrefix)) {
                $startInfo.ArgumentList.Add($argument)
            }
            $process = [System.Diagnostics.Process]::new()
            $process.StartInfo = $startInfo
            $started = $process.Start()
            if (-not $started) { throw "Could not start Pester shard '$($workItem.Path)'." }
            $standardOutput = $process.StandardOutput.ReadToEndAsync()
            $standardError = $process.StandardError.ReadToEndAsync()
            $completed = $process.WaitForExit($using:shardTimeoutMilliseconds)
            if (-not $completed) {
                $process.Kill($true)
                $process.WaitForExit()
            }
            $output = @(
                $standardOutput.GetAwaiter().GetResult()
                $standardError.GetAwaiter().GetResult()) -join [Environment]::NewLine
            $output | Set-Content -LiteralPath $workItem.LogPath
            [pscustomobject]@{
                Index = $workItem.Index
                ExitCode = if ($completed) { $process.ExitCode } else { -1 }
                TimedOut = -not $completed
                ResultPath = $workItem.ResultPath
                LogPath = $workItem.LogPath
                WorkerError = $null
            }
        }
        catch {
            $workerError = "Pester shard worker failed: $($_.Exception.Message)"
            $workerExitCode = $null
            if ($started -and $null -ne $process) {
                try {
                    if (-not $process.HasExited) {
                        $process.Kill($true)
                        $process.WaitForExit()
                    }
                    if ($process.HasExited) { $workerExitCode = $process.ExitCode }
                }
                catch {
                    $workerError += " Cleanup failed: $($_.Exception.Message)"
                }
            }
            try { $workerError | Set-Content -LiteralPath $workItem.LogPath }
            catch { $workerError += " Log write failed: $($_.Exception.Message)" }
            [pscustomobject]@{
                Index = $workItem.Index
                ExitCode = $workerExitCode
                TimedOut = $false
                ResultPath = $workItem.ResultPath
                LogPath = $workItem.LogPath
                WorkerError = $workerError
            }
        }
        finally {
            if ($null -ne $process) { $process.Dispose() }
        }
    } -ThrottleLimit $MaxConcurrency)
$stopwatch.Stop()
$runnerErrors = [System.Collections.Generic.List[string]]::new()
$expectedIndices = @($workItems.Index)
foreach ($unexpectedResult in @($processResults | Where-Object { $_.Index -notin $expectedIndices })) {
    $runnerErrors.Add("Received an unexpected Pester worker result for index '$($unexpectedResult.Index)'.") | Out-Null
}
$normalizedProcessResults = @(foreach ($workItem in $workItems) {
        $matches = @($processResults | Where-Object Index -EQ $workItem.Index)
        if ($matches.Count -eq 1) { $matches[0] }
        else {
            [pscustomobject]@{
                Index = $workItem.Index
                ExitCode = $null
                TimedOut = $false
                ResultPath = $workItem.ResultPath
                LogPath = $workItem.LogPath
                WorkerError = "Expected one Pester worker result but received $($matches.Count)."
            }
        }
    })

$countProperties = @(
    'PassedCount', 'FailedCount', 'SkippedCount', 'NotRunCount',
    'InconclusiveCount', 'TotalCount', 'FailedBlocksCount', 'FailedContainersCount')
$shards = [System.Collections.Generic.List[object]]::new()
foreach ($processResult in @($normalizedProcessResults | Sort-Object Index)) {
    $shard = [pscustomobject]@{
        Path = $orderedTestFiles[$processResult.Index]
        Result = 'Error'
        CountsComplete = $false
        DurationMilliseconds = $null
        ExitCode = $processResult.ExitCode
        TimedOut = $processResult.TimedOut
        LogPath = $processResult.LogPath
        Error = if ([string]::IsNullOrWhiteSpace([string]$processResult.WorkerError)) {
            $null
        }
        else { [string]$processResult.WorkerError }
    }
    foreach ($property in $countProperties) {
        $shard | Add-Member -NotePropertyName $property -NotePropertyValue $null
    }
    if (Test-Path -LiteralPath $processResult.ResultPath -PathType Leaf) {
        try {
            $reported = Get-Content -LiteralPath $processResult.ResultPath -Raw |
                ConvertFrom-Json
            if ($reported -isnot [pscustomobject] -or
                $reported.Path -cne $shard.Path -or
                $reported.Result -cnotin @('Passed', 'Failed')) {
                throw 'Expected a Pester result for the scheduled test file.'
            }
            foreach ($property in @($countProperties) + 'DurationMilliseconds') {
                $value = $reported.$property
                if (($value -isnot [int] -and $value -isnot [long]) -or $value -lt 0) {
                    throw "Missing or invalid nonnegative integer '$property'."
                }
            }
            $accountedTests = $reported.PassedCount + $reported.FailedCount +
                $reported.SkippedCount + $reported.NotRunCount + $reported.InconclusiveCount
            if ($reported.TotalCount -ne $accountedTests) {
                throw 'Pester test counts do not reconcile.'
            }
            if ($reported.Result -eq 'Passed' -and
                ($reported.FailedCount -gt 0 -or $reported.FailedBlocksCount -gt 0 -or
                    $reported.FailedContainersCount -gt 0)) {
                throw 'A passing Pester result contains failures.'
            }
            $failureEvidence = $reported.FailedCount + $reported.FailedBlocksCount +
                $reported.FailedContainersCount + $reported.NotRunCount +
                $reported.InconclusiveCount
            if ($reported.Result -eq 'Failed' -and $failureEvidence -eq 0) {
                throw 'A failed Pester result contains no failure evidence.'
            }
            if ($reported.Result -eq 'Failed' -and $processResult.ExitCode -eq 0) {
                throw 'A failed Pester result came from a successful shard process.'
            }
            foreach ($property in $countProperties) { $shard.$property = $reported.$property }
            $shard.CountsComplete = $true
            $shard.DurationMilliseconds = $reported.DurationMilliseconds
            $shard.Result = $reported.Result
            if ($reported.TotalCount -eq 0 -and $reported.Result -eq 'Passed') {
                $shard.Error = 'No Pester tests were discovered.'
            }
            elseif ($reported.NotRunCount -gt 0 -or $reported.InconclusiveCount -gt 0) {
                $shard.Error = 'Pester left tests not run or inconclusive.'
            }
        }
        catch {
            $shard.Error = "Invalid Pester shard result: $($_.Exception.Message)"
        }
    }
    elseif (-not $shard.Error) {
        $shard.Error = 'Pester shard did not produce a result.'
    }
    if ($processResult.TimedOut) {
        $shard.Error = "Pester shard timed out. $($shard.Error)".TrimEnd()
    }
    elseif ($processResult.ExitCode -ne 0 -and $shard.Result -eq 'Passed' -and -not $shard.Error) {
        $shard.Error = "Pester shard process exited with code $($processResult.ExitCode)."
    }
    if ($shard.Error) { $shard.Result = 'Error' }
    $shards.Add($shard)
}

$countsComplete = $runnerErrors.Count -eq 0 -and
    @($shards | Where-Object { -not $_.CountsComplete }).Count -eq 0
$failedShards = @($shards | Where-Object { $_.Result -ne 'Passed' })
$infrastructureFailureCount = @($shards | Where-Object Error).Count + $runnerErrors.Count
$summary = [pscustomobject]@{
    SchemaVersion = 2
    GeneratedAtUtc = [DateTime]::UtcNow.ToString('O')
    PesterVersion = $PesterVersion.ToString()
    MaxConcurrency = $MaxConcurrency
    ShardTimeoutMinutes = $ShardTimeoutMinutes
    ShardTimeoutSeconds = if ($ShardTimeoutSeconds -gt 0) { $ShardTimeoutSeconds } else { $null }
    ShardTimeoutMilliseconds = $shardTimeoutMilliseconds
    PowerShellPath = $pwshPath
    ShardCount = $shards.Count
    WallTimeMilliseconds = $stopwatch.ElapsedMilliseconds
    Result = if ($failedShards.Count -gt 0 -or $runnerErrors.Count -gt 0) { 'Failed' } else { 'Passed' }
    FailedShardCount = $failedShards.Count
    InfrastructureFailureCount = $infrastructureFailureCount
    RunnerErrors = $runnerErrors.ToArray()
    CountsComplete = $countsComplete
    Shards = $shards.ToArray()
}
foreach ($property in $countProperties) {
    $count = if ($countsComplete) { ($shards | Measure-Object -Property $property -Sum).Sum } else { $null }
    $summary | Add-Member -NotePropertyName $property -NotePropertyValue $count
}
$summary | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath (Join-Path $resolvedOutputDirectory 'summary.json')
$summary.Shards |
    Select-Object Path, Result, PassedCount, FailedCount, SkippedCount, DurationMilliseconds |
    Format-Table -AutoSize
if ($countsComplete) {
    Write-Host "Pester shards: $($summary.ShardCount); passed: $($summary.PassedCount); failed: $($summary.FailedCount); skipped: $($summary.SkippedCount); failed blocks: $($summary.FailedBlocksCount); failed containers: $($summary.FailedContainersCount); wall time: $($summary.WallTimeMilliseconds) ms."
}
else {
    Write-Host "Pester shards: $($summary.ShardCount); test totals unknown because shard results are missing or invalid; wall time: $($summary.WallTimeMilliseconds) ms."
}
Write-Host "Pester shard reports: $resolvedOutputDirectory"
foreach ($shard in $failedShards) {
    Write-Host "Failed shard '$($shard.Path)': $($shard.Result). $($shard.Error) Log: $($shard.LogPath)"
}
foreach ($runnerError in $runnerErrors) { Write-Host "Pester runner error: $runnerError" }
if ($failedShards.Count -gt 0 -or $runnerErrors.Count -gt 0) {
    throw 'One or more Pester shards failed.'
}
$global:LASTEXITCODE = 0