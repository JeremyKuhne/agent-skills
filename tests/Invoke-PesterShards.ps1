#Requires -Version 7.2
[CmdletBinding()]
param(
    [string[]] $Path = @($PSScriptRoot),
    [string] $OutputDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) "agent-skills-pester-$([guid]::NewGuid().ToString('N'))"),
    [ValidateRange(1, 32)]
    [int] $MaxConcurrency = 4,
    [ValidateRange(1, 240)]
    [int] $ShardTimeoutMinutes = 30,
    [version] $PesterVersion = '5.7.1',
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
    $configuration.Run.PassThru = $true
    $configuration.Output.Verbosity = 'Normal'
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $result = Invoke-Pester -Configuration $configuration
    $stopwatch.Stop()
    [pscustomobject]@{
        Path = (Resolve-Path -LiteralPath $ShardPath).Path
        PassedCount = $result.PassedCount
        FailedCount = $result.FailedCount
        SkippedCount = $result.SkippedCount
        TotalCount = $result.TotalCount
        DurationMilliseconds = $stopwatch.ElapsedMilliseconds
    } | ConvertTo-Json | Set-Content -LiteralPath $ResultPath
    if ($result.FailedCount -gt 0) { exit 1 }
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

$pwshPath = [string]@(Get-Command pwsh -CommandType Application -All -ErrorAction Stop)[0].Source
$scriptPath = $PSCommandPath
$pesterVersionText = $PesterVersion.ToString()
$shardTimeoutMilliseconds = $ShardTimeoutMinutes * 60 * 1000
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$processResults = @($scheduledWorkItems | ForEach-Object -Parallel {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $using:pwshPath
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        foreach ($argument in @(
                '-NoProfile',
                '-File', $using:scriptPath,
                '-ShardPath', $_.Path,
                '-ResultPath', $_.ResultPath,
                '-PesterVersion', $using:pesterVersionText,
                '-PathPrefix', [string]$using:PathPrefix)) {
            $startInfo.ArgumentList.Add($argument)
        }
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        $started = $process.Start()
        if (-not $started) { throw "Could not start Pester shard '$($_.Path)'." }
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
        $output | Set-Content -LiteralPath $_.LogPath
        [pscustomobject]@{
            Index = $_.Index
            ExitCode = if ($completed) { $process.ExitCode } else { -1 }
            TimedOut = -not $completed
            ResultPath = $_.ResultPath
            LogPath = $_.LogPath
        }
    } -ThrottleLimit $MaxConcurrency)
$stopwatch.Stop()

$shards = [System.Collections.Generic.List[object]]::new()
foreach ($processResult in @($processResults | Sort-Object Index)) {
    if (Test-Path -LiteralPath $processResult.ResultPath -PathType Leaf) {
        $shard = Get-Content -LiteralPath $processResult.ResultPath -Raw |
            ConvertFrom-Json
        $shard | Add-Member -NotePropertyName ExitCode -NotePropertyValue $processResult.ExitCode
        $shard | Add-Member -NotePropertyName TimedOut -NotePropertyValue $processResult.TimedOut
        $shard | Add-Member -NotePropertyName LogPath -NotePropertyValue $processResult.LogPath
    }
    else {
        $shard = [pscustomobject]@{
            Path = $orderedTestFiles[$processResult.Index]
            PassedCount = 0
            FailedCount = 1
            SkippedCount = 0
            TotalCount = 1
            DurationMilliseconds = 0
            ExitCode = $processResult.ExitCode
            TimedOut = $processResult.TimedOut
            LogPath = $processResult.LogPath
        }
    }
    $shards.Add($shard)
}

$summary = [pscustomobject]@{
    SchemaVersion = 1
    GeneratedAtUtc = [DateTime]::UtcNow.ToString('O')
    PesterVersion = $PesterVersion.ToString()
    MaxConcurrency = $MaxConcurrency
    ShardTimeoutMinutes = $ShardTimeoutMinutes
    ShardCount = $shards.Count
    WallTimeMilliseconds = $stopwatch.ElapsedMilliseconds
    PassedCount = ($shards | Measure-Object -Property PassedCount -Sum).Sum
    FailedCount = ($shards | Measure-Object -Property FailedCount -Sum).Sum
    SkippedCount = ($shards | Measure-Object -Property SkippedCount -Sum).Sum
    TotalCount = ($shards | Measure-Object -Property TotalCount -Sum).Sum
    Shards = $shards.ToArray()
}
$summary | ConvertTo-Json -Depth 10 |
    Set-Content -LiteralPath (Join-Path $resolvedOutputDirectory 'summary.json')
$summary.Shards |
    Select-Object Path, PassedCount, FailedCount, SkippedCount, DurationMilliseconds |
    Format-Table -AutoSize
Write-Host "Pester shards: $($summary.ShardCount); passed: $($summary.PassedCount); failed: $($summary.FailedCount); skipped: $($summary.SkippedCount); wall time: $($summary.WallTimeMilliseconds) ms."
Write-Host "Pester shard reports: $resolvedOutputDirectory"
if ($summary.FailedCount -gt 0 -or
    @($summary.Shards | Where-Object { $_.ExitCode -ne 0 -or $_.TimedOut }).Count -gt 0) {
    throw 'One or more Pester shards failed.'
}
$global:LASTEXITCODE = 0