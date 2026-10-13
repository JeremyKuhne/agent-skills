#Requires -Version 7.4
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('powershell-record-array', 'powershell-child-outcome',
        'dotnet-preserve-export', 'dotnet-disposable-scratch')]
    [string] $CaseId,
    [Parameter(Mandatory)]
    [string] $ArtifactPath,
    [Parameter(Mandatory)]
    [string] $OutputDirectory,
    [string] $DotNetPath,
    [string] $PowerShellPath = [Environment]::ProcessPath,
    [ValidateRange(1, 300)]
    [int] $TimeoutSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $ArtifactPath -ErrorAction Stop).Path
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw 'ArtifactPath must be a file.' }
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) { throw "Oracle output must be a new directory: '$output'." }
$null = New-Item -ItemType Directory -Path $output
$work = Join-Path $output 'work'
$temporary = Join-Path $output 'temporary'
$null = New-Item -ItemType Directory -Path $work, $temporary
$extension = if ($CaseId.StartsWith('powershell-')) { '.ps1' } else { '.cs' }
$snapshot = Join-Path $output "Candidate$extension"
Copy-Item -LiteralPath $source -Destination $snapshot
$artifactRevision = (Get-FileHash -LiteralPath $snapshot -Algorithm SHA256).Hash
$workerReceipt = Join-Path $output 'worker.json'
$oracleSource = Join-Path $output 'oracle-source'
$null = New-Item -ItemType Directory -Path $oracleSource
$oracleFiles = @(foreach ($name in @('Invoke-SkillQualityOracle.ps1', 'PowerShellOracle.ps1', 'FileCreationOracle.cs',
            'Oracle.csproj.template', 'NuGet.Config.template')) {
        $original = Join-Path $PSScriptRoot $name
        $owned = Join-Path $oracleSource $name
        $hash = (Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash
        Copy-Item -LiteralPath $original -Destination $owned
        if ((Get-FileHash -LiteralPath $owned -Algorithm SHA256).Hash -cne $hash) {
            throw 'Oracle source closure changed while taking execution snapshots.'
        }
        [ordered]@{ path = $name; sha256 = $hash }
    })
$oracleRevision = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
        [Text.Encoding]::UTF8.GetBytes(($oracleFiles | ConvertTo-Json -Compress))))

function Run-Child([string] $Executable, [string[]] $Arguments, [string] $Name) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Executable
    $start.WorkingDirectory = $output
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $start.Environment['TEMP'] = $temporary
    $start.Environment['TMP'] = $temporary
    $start.Environment['TMPDIR'] = $temporary
    $start.Environment['DOTNET_CLI_TELEMETRY_OPTOUT'] = '1'
    $start.Environment['DOTNET_SKIP_FIRST_TIME_EXPERIENCE'] = '1'
    foreach ($environmentName in @($start.Environment.Keys)) {
        if ($environmentName -match '(?i)(TOKEN|SECRET|PASSWORD|PASSCODE|API_KEY|PRIVATE_KEY|CREDENTIAL)') {
            $null = $start.Environment.Remove($environmentName)
        }
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $started = $false
    try {
        $started = $process.Start()
        if (-not $started) { throw "Oracle child '$Name' did not start." }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill($true)
            $process.WaitForExit()
            throw "Oracle child '$Name' timed out after $TimeoutSeconds seconds; no task pass is reported."
        }
        $text = $stdout.GetAwaiter().GetResult()
        $errorText = $stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $output "$Name.stdout.txt"), $text)
        [IO.File]::WriteAllText((Join-Path $output "$Name.stderr.txt"), $errorText)
        return [pscustomobject]@{ ExitCode = $process.ExitCode; StandardOutput = $text; StandardError = $errorText }
    }
    finally {
        if ($started -and -not $process.HasExited) {
            $process.Kill($true)
            $process.WaitForExit()
        }
        $process.Dispose()
    }
}

$expected = switch ($CaseId) {
    'powershell-record-array' { @('zero-array', 'single-array', 'multiple-array', 'missing-property-error',
            'wrong-property-type-error', 'malformed-json-error', 'missing-file-error',
            'object-root-error', 'date-string-preserved', 'ordinal-keys-preserved') }
    'powershell-child-outcome' { @('exit-zero-json', 'argument-with-spaces', 'stderr-separate',
            'nonzero-valid-json-error', 'malformed-json-error', 'caller-environment-unchanged') }
    'dotnet-preserve-export' { @('compile', 'publish-new-utf8', 'no-overwrite-preserves',
            'overwrite-publishes', 'failed-callback-preserves', 'owned-temp-cleanup') }
    'dotnet-disposable-scratch' { @('compile', 'owned-os-temp-subdirectory', 'unique-per-call',
            'return-value', 'normal-cleanup', 'exception-cleanup', 'exception-identity', 'unrelated-directory-preserved') }
}
$checks = [System.Collections.Generic.List[object]]::new()
$sdkVersion = $null
if ($extension -eq '.ps1') {
    $child = Run-Child $PowerShellPath @('-NoLogo', '-NoProfile', '-NonInteractive',
        '-File', (Join-Path $oracleSource 'PowerShellOracle.ps1'), '-CaseId', $CaseId,
        '-ArtifactPath', $snapshot, '-WorkDirectory', $work, '-ReceiptPath', $workerReceipt) 'powershell'
}
else {
    if ([string]::IsNullOrWhiteSpace($DotNetPath)) {
        $DotNetPath = [string]@(Get-Command dotnet -CommandType Application -All -ErrorAction Stop)[0].Source
    }
    Copy-Item -LiteralPath (Join-Path $oracleSource 'FileCreationOracle.cs') -Destination (Join-Path $output 'Oracle.cs')
    Copy-Item -LiteralPath (Join-Path $oracleSource 'Oracle.csproj.template') -Destination (Join-Path $output 'Oracle.csproj')
    Copy-Item -LiteralPath (Join-Path $oracleSource 'NuGet.Config.template') -Destination (Join-Path $output 'NuGet.Config')
    @{ sdk = @{ version = '10.0.100'; rollForward = 'latestFeature'; allowPrerelease = $false } } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'global.json') -Encoding utf8
    $sdk = Run-Child $DotNetPath @('--version') 'sdk'
    $sdkVersion = $sdk.StandardOutput.Trim()
    if ($sdk.ExitCode -ne 0 -or $sdkVersion -notmatch '^10\.0\.\d+$') {
        throw "An installed stable .NET 10 SDK is required: $($sdk.StandardError)"
    }
    $build = Run-Child $DotNetPath @('build', 'Oracle.csproj', '--configuration', 'Release', '--nologo') 'build'
    if ($build.ExitCode -ne 0) {
        if ($build.StandardOutput -notmatch '\berror CS\d+\b') {
            throw "Oracle build infrastructure failed: $($build.StandardOutput) $($build.StandardError)"
        }
        $checks.Add([pscustomobject]@{ id = 'compile'; status = 'failed'; evidence = $build.StandardOutput.Trim() })
        foreach ($id in $expected | Where-Object { $_ -ne 'compile' }) {
            $checks.Add([pscustomobject]@{ id = $id; status = 'pending'; evidence = 'Not run: candidate compilation failed.' })
        }
        $child = $null
    }
    else {
        $checks.Add([pscustomobject]@{ id = 'compile'; status = 'passed'; evidence = "Compiled with .NET SDK $sdkVersion, C# 14, offline package sources." })
        $assembly = Join-Path $output 'bin' -AdditionalChildPath @('Release', 'net10.0', 'Oracle.dll')
        $child = Run-Child $DotNetPath @($assembly,
            $CaseId, $work, $workerReceipt) 'dotnet'
    }
}
if ($null -ne $child) {
    if ($child.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $workerReceipt -PathType Leaf)) {
        throw "Oracle worker did not complete: exit $($child.ExitCode); $($child.StandardError)"
    }
    $receipt = Get-Content -LiteralPath $workerReceipt -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    if ($receipt -isnot [Collections.IDictionary] -or $receipt['schemaVersion'] -ne 1 -or
        $receipt['caseId'] -cne $CaseId -or $receipt['checks'] -isnot [Array]) {
        throw 'Oracle worker returned an invalid receipt.'
    }
    foreach ($check in $receipt['checks']) { $checks.Add($check) }
}
$ids = @($checks | ForEach-Object { $_.id })
if ($ids.Count -ne $expected.Count -or @(Compare-Object $expected $ids).Count -ne 0 -or
    @($ids | Sort-Object -Unique).Count -ne $ids.Count) { throw 'Oracle check inventory changed or is incomplete.' }
foreach ($check in $checks) {
    if ($check.status -notin @('passed', 'failed', 'pending') -or [string]::IsNullOrWhiteSpace($check.evidence)) {
        throw 'Oracle check status or evidence is invalid.'
    }
}
if ((Get-FileHash -LiteralPath $snapshot -Algorithm SHA256).Hash -cne $artifactRevision) {
    throw 'The oracle artifact snapshot changed during execution.'
}
$failed = @($checks | Where-Object { $_.status -eq 'failed' }).Count
$pending = @($checks | Where-Object { $_.status -eq 'pending' }).Count
foreach ($file in $oracleFiles) {
    if ((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $file['path']) -Algorithm SHA256).Hash -cne $file['sha256'] -or
        (Get-FileHash -LiteralPath (Join-Path $oracleSource $file['path']) -Algorithm SHA256).Hash -cne $file['sha256']) {
        throw 'Oracle source closure changed during execution.'
    }
}
$report = [pscustomobject]@{
    schemaVersion = 1
    caseId = $CaseId
    artifactRevision = $artifactRevision
    oracleRevision = $oracleRevision
    oracleFiles = @($oracleFiles)
    oracleSourceDirectory = 'oracle-source'
    sdkVersion = $sdkVersion
    powerShellVersion = $PSVersionTable.PSVersion.ToString()
    scheduledChecks = $expected.Count
    passedChecks = @($checks | Where-Object { $_.status -eq 'passed' }).Count
    failedChecks = $failed
    pendingChecks = $pending
    outcome = if ($failed -gt 0) { 'failed' } elseif ($pending -gt 0) { 'pending' } else { 'passed' }
    checks = $checks.ToArray()
    authority = 'Executable task assertions only; no skill qualification or sandbox guarantee.'
}
$report | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $output 'oracle.json') -Encoding utf8
$report
