#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $oracle = Join-Path $repoRoot 'evals' -AdditionalChildPath @('oracles', 'Invoke-SkillQualityOracle.ps1')
    Import-Module (Join-Path $repoRoot 'evals' -AdditionalChildPath @('SkillEvalContent.psm1')) -Force
    $fixtures = @{
        'powershell-record-array' = @{
            Extension = '.ps1'
            Count = 7
            FailedCheck = 'zero-array'
            Good = @'
function Get-Records {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)
    $value = Get-Content -LiteralPath $Path -Raw -Encoding utf8 -ErrorAction Stop |
        ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $value -or $value -isnot [pscustomobject] -or
        $null -eq $value.PSObject.Properties['records'] -or $value.records -isnot [Array]) {
        throw 'Expected an object with a records array.'
    }
    [pscustomobject]@{ Count = $value.records.Count; Records = $value.records }
}
'@
        }
        'powershell-child-outcome' = @{
            Extension = '.ps1'
            Count = 6
            FailedCheck = 'nonzero-valid-json-error'
            Good = @'
function Invoke-CheckedChild {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Executable, [string[]] $Arguments)
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Executable
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw 'Child did not start.' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $exitCode = $process.ExitCode
        $text = $stdout.GetAwaiter().GetResult()
        $errorText = $stderr.GetAwaiter().GetResult()
        if ($exitCode -ne 0) { throw "Child exit: $exitCode" }
        $document = [Text.Json.JsonDocument]::Parse($text)
        $document.Dispose()
        $data = ConvertFrom-Json -InputObject $text -NoEnumerate -ErrorAction Stop
        [pscustomobject]@{ Data = $data; ErrorText = $errorText; ExitCode = $exitCode }
    }
    finally { $process.Dispose() }
}
'@
        }
        'dotnet-preserve-export' = @{
            Extension = '.cs'
            Count = 6
            FailedCheck = 'failed-callback-preserves'
            Good = @'
using System;
using System.IO;
using System.Text;
public static class SaveText
{
    public static void Publish(string destination, Action<TextWriter> write, bool overwrite)
    {
        string pending = Path.Combine(Path.GetDirectoryName(Path.GetFullPath(destination))!,
            "." + Guid.NewGuid().ToString("N") + ".tmp");
        try
        {
            using (StreamWriter writer = new(new FileStream(pending, FileMode.CreateNew, FileAccess.Write, FileShare.None),
                new UTF8Encoding(false)))
            {
                write(writer);
            }
            File.Move(pending, destination, overwrite);
        }
        finally
        {
            if (File.Exists(pending)) { File.Delete(pending); }
        }
    }
}
'@
        }
        'dotnet-disposable-scratch' = @{
            Extension = '.cs'
            Count = 8
            FailedCheck = 'normal-cleanup'
            Good = @'
using System;
using System.IO;
public static class Scratch
{
    public static T WithScratch<T>(Func<string, T> use)
    {
        DirectoryInfo directory = Directory.CreateTempSubdirectory("skill-quality-");
        try { return use(directory.FullName); }
        finally { directory.Delete(recursive: true); }
    }
}
'@
        }
    }
    $fixtures['powershell-record-array'].Bad = $fixtures['powershell-record-array'].Good.Replace(
        'Records = $value.records', 'Records = ($value.records | ForEach-Object { $_ })')
    $fixtures['powershell-child-outcome'].Bad = $fixtures['powershell-child-outcome'].Good.Replace(
        'if ($exitCode -ne 0) { throw "Child exit: $exitCode" }', '# Deliberately accept a failed child.')
    $fixtures['dotnet-preserve-export'].Bad = $fixtures['dotnet-preserve-export'].Good.Replace(
        'write(writer);', 'try { write(writer); } catch (InvalidOperationException) { }')
    $fixtures['dotnet-disposable-scratch'].Bad = $fixtures['dotnet-disposable-scratch'].Good.Replace(
        'directory.Delete(recursive: true);', '_ = directory.Exists;')
}

Describe 'Frozen coding-task executable oracles' {
    It 'accepts the known-good <CaseId> artifact with complete bound evidence' -ForEach @(
        @{ CaseId = 'powershell-record-array' }
        @{ CaseId = 'powershell-child-outcome' }
        @{ CaseId = 'dotnet-preserve-export' }
        @{ CaseId = 'dotnet-disposable-scratch' }
    ) {
        $fixture = $fixtures[$CaseId]
        $path = Join-Path $TestDrive "$CaseId-good$($fixture.Extension)"
        [IO.File]::WriteAllText($path, $fixture.Good)
        $before = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        $output = Join-Path $TestDrive "$CaseId-good-output"
        $result = & $oracle -CaseId $CaseId -ArtifactPath $path -OutputDirectory $output
        $result.outcome | Should -Be 'passed'
        $result.scheduledChecks | Should -Be $fixture.Count
        $result.passedChecks | Should -Be $fixture.Count
        $result.failedChecks | Should -Be 0
        $result.pendingChecks | Should -Be 0
        $result.artifactRevision | Should -BeExactly $before
        $result.oracleRevision | Should -Match '^[0-9A-F]{64}$'
        $result.oracleFiles.Count | Should -Be 5
        foreach ($file in $result.oracleFiles) {
            $owned = Join-Path $output $result.oracleSourceDirectory -AdditionalChildPath @($file['path'])
            (Get-FileHash -LiteralPath $owned -Algorithm SHA256).Hash | Should -BeExactly $file['sha256']
            (Get-FileHash -LiteralPath (Join-Path (Split-Path $oracle -Parent) $file['path']) -Algorithm SHA256).Hash |
                Should -BeExactly $file['sha256']
        }
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash | Should -BeExactly $before
    }

    It 'rejects a single controlled contract defect in <CaseId>' -ForEach @(
        @{ CaseId = 'powershell-record-array' }
        @{ CaseId = 'powershell-child-outcome' }
        @{ CaseId = 'dotnet-preserve-export' }
        @{ CaseId = 'dotnet-disposable-scratch' }
    ) {
        $fixture = $fixtures[$CaseId]
        $fixture.Bad | Should -Not -BeExactly $fixture.Good
        $path = Join-Path $TestDrive "$CaseId-bad$($fixture.Extension)"
        [IO.File]::WriteAllText($path, $fixture.Bad)
        $result = & $oracle -CaseId $CaseId -ArtifactPath $path `
            -OutputDirectory (Join-Path $TestDrive "$CaseId-bad-output")
        $result.outcome | Should -Be 'failed'
        $result.failedChecks | Should -BeGreaterThan 0
        $result.scheduledChecks | Should -Be $fixture.Count
        ($result.checks | Where-Object id -EQ $fixture.FailedCheck).status | Should -Be 'failed'
        ($result.checks | Where-Object id -EQ $fixture.FailedCheck).evidence | Should -Not -BeNullOrEmpty
    }

    It 'records compiler rejection without pretending unexecuted runtime checks passed' {
        $path = Join-Path $TestDrive 'does not compile.cs'
        [IO.File]::WriteAllText($path, 'public static class Scratch { deliberately invalid }')
        $result = & $oracle -CaseId dotnet-disposable-scratch -ArtifactPath $path `
            -OutputDirectory (Join-Path $TestDrive 'compile-error-output')
        $result.outcome | Should -Be 'failed'
        $result.failedChecks | Should -Be 1
        $result.passedChecks | Should -Be 0
        $result.pendingChecks | Should -Be 7
        $result.checks[0].id | Should -Be 'compile'
        $result.checks[0].evidence | Should -Match 'error CS'
    }

    It 'rejects a temporary file leaked only after successful publication' {
        $source = $fixtures['dotnet-preserve-export'].Good.Replace(
            'string pending = Path.Combine', 'bool published = false; string pending = Path.Combine').Replace(
            'File.Move(pending, destination, overwrite);', 'File.Copy(pending, destination, overwrite); published = true;').Replace(
            'if (File.Exists(pending))', 'if (!published && File.Exists(pending))')
        $source | Should -Not -BeExactly $fixtures['dotnet-preserve-export'].Good
        $path = Join-Path $TestDrive 'success-only-leak.cs'
        [IO.File]::WriteAllText($path, $source)
        $result = & $oracle -CaseId dotnet-preserve-export -ArtifactPath $path `
            -OutputDirectory (Join-Path $TestDrive 'success-only-leak-output')
        $result.outcome | Should -Be 'failed'
        ($result.checks | Where-Object id -EQ 'owned-temp-cleanup').status | Should -Be 'failed'
        $result.scheduledChecks | Should -Be 6
    }

    It 'rejects changed source provenance instead of hashing unexecuted edits after the worker' {
        $sourceRoot = Join-Path $TestDrive 'owned-oracle-source'
        $null = New-Item -ItemType Directory -Path $sourceRoot
        foreach ($name in @('Invoke-SkillQualityOracle.ps1', 'PowerShellOracle.ps1', 'FileCreationOracle.cs',
                'Oracle.csproj.template', 'NuGet.Config.template')) {
            Copy-Item -LiteralPath (Join-Path (Split-Path $oracle -Parent) $name) `
                -Destination (Join-Path $sourceRoot $name)
        }
        $mutatedPath = (Join-Path $sourceRoot 'FileCreationOracle.cs').Replace("'", "''")
        $path = Join-Path $TestDrive 'source-mutation.ps1'
        [IO.File]::WriteAllText($path, $fixtures['powershell-record-array'].Good.Replace(
                '$value = Get-Content', "[IO.File]::WriteAllText('$mutatedPath', '// controlled concurrent source edit');`n    " + '$value = Get-Content'))
        $output = Join-Path $TestDrive 'source-mutation-output'
        { & (Join-Path $sourceRoot 'Invoke-SkillQualityOracle.ps1') -CaseId powershell-record-array `
                -ArtifactPath $path -OutputDirectory $output } |
            Should -Throw '*Oracle source closure changed*'
        Test-Path -LiteralPath (Join-Path $output 'oracle.json') | Should -BeFalse
    }

    It 'accepts preserved exports when the callback error is wrapped rather than kept identical' {
        $source = $fixtures['dotnet-preserve-export'].Good.Replace('write(writer);',
            'try { write(writer); } catch (InvalidOperationException exception) { throw new IOException("wrapped callback error", exception); }')
        $path = Join-Path $TestDrive 'wrapped export.cs'
        [IO.File]::WriteAllText($path, $source)
        $result = & $oracle -CaseId dotnet-preserve-export -ArtifactPath $path `
            -OutputDirectory (Join-Path $TestDrive 'wrapped-export-output')
        $result.outcome | Should -Be 'passed'
        $result.passedChecks | Should -Be 6
    }

    It 'rejects missing artifacts and refuses existing output paths' {
        { & $oracle -CaseId powershell-record-array -ArtifactPath (Join-Path $TestDrive 'missing.ps1') `
                -OutputDirectory (Join-Path $TestDrive 'missing-output') } | Should -Throw
        $path = Join-Path $TestDrive 'existing-source.ps1'
        [IO.File]::WriteAllText($path, $fixtures['powershell-record-array'].Good)
        $output = Join-Path $TestDrive 'existing-output'
        $null = New-Item -ItemType Directory -Path $output
        $sentinel = Join-Path $output 'keep.txt'
        [IO.File]::WriteAllText($sentinel, 'keep')
        { & $oracle -CaseId powershell-record-array -ArtifactPath $path -OutputDirectory $output } |
            Should -Throw '*new directory*'
        [IO.File]::ReadAllText($sentinel) | Should -BeExactly 'keep'
    }

    It 'surfaces unavailable compiler infrastructure without a success-shaped oracle result' {
        $path = Join-Path $TestDrive 'infra.cs'
        [IO.File]::WriteAllText($path, $fixtures['dotnet-disposable-scratch'].Good)
        $output = Join-Path $TestDrive 'infra-output'
        { & $oracle -CaseId dotnet-disposable-scratch -ArtifactPath $path -OutputDirectory $output `
                -DotNetPath (Join-Path $TestDrive 'missing-dotnet') } | Should -Throw
        Test-Path -LiteralPath (Join-Path $output 'oracle.json') | Should -BeFalse
    }

    It 'terminates an unresponsive owned worker without reporting a task pass' {
        $path = Join-Path $TestDrive 'slow.ps1'
        [IO.File]::WriteAllText($path, 'function Get-Records { param([string] $Path) Start-Sleep -Seconds 30 }')
        $output = Join-Path $TestDrive 'timeout-output'
        { & $oracle -CaseId powershell-record-array -ArtifactPath $path -OutputDirectory $output `
                -TimeoutSeconds 1 } | Should -Throw '*timed out*'
        Test-Path -LiteralPath (Join-Path $output 'oracle.json') | Should -BeFalse
    }

    It 'projects real synthetic oracle receipts through the public report without inventing model grades' {
        $inputRevision = 'A' * 64
        $expected = @()
        $actual = @()
        foreach ($condition in @('no-skill', 'current')) {
            $source = if ($condition -eq 'no-skill') {
                $fixtures['powershell-record-array'].Good
            }
            else { $fixtures['powershell-record-array'].Bad }
            $path = Join-Path $TestDrive "report-$condition.ps1"
            [IO.File]::WriteAllText($path, $source)
            $result = & $oracle -CaseId powershell-record-array -ArtifactPath $path `
                -OutputDirectory (Join-Path $TestDrive "report-$condition-output")
            $expected += [ordered]@{
                skillId = 'powershell-engineering'; caseId = 'powershell-record-array'
                modelId = 'gpt-6.1-sol'; condition = $condition; repetition = 1
                inputRevision = $inputRevision; artifactRevision = $null
                status = 'scheduled'; safety = 'pending'; infrastructure = 'pending'
                oracleOutcome = $null; hardChecks = @(); usage = $null; elapsedMs = $null
            }
            $actual += [ordered]@{
                skillId = 'powershell-engineering'; caseId = 'powershell-record-array'
                modelId = 'gpt-6.1-sol'; condition = $condition; repetition = 1
                inputRevision = $inputRevision; artifactRevision = $result.artifactRevision
                status = 'completed'; safety = 'passed'; infrastructure = 'passed'
                oracleOutcome = $result.outcome
                hardChecks = @($result.checks | ForEach-Object {
                        [ordered]@{ id = $_.id; name = $_.id; status = $_.status
                            evidence = $_.evidence; why = 'The frozen executable task assertion must hold.' }
                    })
                usage = $null; elapsedMs = $null
            }
        }

        $campaign = [ordered]@{
            schemaVersion = 1; campaignId = 'synthetic-oracle-report-control-not-a-model-run'
            criteriaRevision = $inputRevision; expectedSkillIds = @('powershell-engineering')
            criteria = @(@{ skillId = 'powershell-engineering'; itemId = 'task'; hardGate = $true })
            expectedRunInventory = $expected; actualRunRecords = $actual; judgeRecords = @()
        }
        $path = Join-Path $TestDrive 'oracle campaign.json'
        $campaign | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $path -Encoding utf8
        $cli = Invoke-SkillEvalContentCli -Arguments @('quality-report', '--campaign', $path)
        $cli.ExitCode | Should -Be 0 -Because $cli.StandardError
        $cli.StandardError | Should -BeNullOrEmpty
        $report = $cli.StandardOutput | ConvertFrom-Json -AsHashtable
        $report['completed'] | Should -Be 2
        $report['rows'][0]['outcome'] | Should -Be 'pending'
        $report['rows'][1]['outcome'] | Should -Be 'failed-executable'
        $report['rows'][1]['hardChecks'][0]['status'] | Should -Be 'failed'
        $report['comparisons'][0]['outcome'] | Should -Be 'pending'
        $report['usefulPassedCount'] | Should -Be 0
        $report['calibrationStatus'] | Should -Be 'pending'
    }
}
