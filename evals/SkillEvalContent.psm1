#Requires -Version 7.2
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-SkillEvalContentCliPath {
    [CmdletBinding(PositionalBinding = $false)]
    param(
        [string] $CliPath = (Join-Path $PSScriptRoot '..\tools\skill-evaluation\SkillEvaluation.Cli\bin\Release\net10.0\SkillEvaluation.Cli.dll')
    )

    if (-not (Test-Path -LiteralPath $CliPath -PathType Leaf)) {
        throw "Content evaluator is not built: '$CliPath'. Restore and build tools\skill-evaluation\SkillEvaluation.Cli\SkillEvaluation.Cli.csproj in Release first."
    }
    return (Resolve-Path -LiteralPath $CliPath).Path
}

function Invoke-SkillEvalContentCli {
    [CmdletBinding(PositionalBinding = $false)]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string[]] $Arguments,
        [string] $CliPath,
        [ValidateRange(1, 3600)]
        [int] $TimeoutSeconds = 120
    )

    $resolvedCliPath = if ([string]::IsNullOrWhiteSpace($CliPath)) {
        Get-SkillEvalContentCliPath
    }
    else { Get-SkillEvalContentCliPath -CliPath $CliPath }
    $dotnetPath = (Get-Command dotnet -CommandType Application -ErrorAction Stop).Source
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $dotnetPath
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
    $startInfo.ArgumentList.Add($resolvedCliPath)
    foreach ($argument in $Arguments) { $startInfo.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $started = $false
    try {
        $started = $process.Start()
        if (-not $started) { throw 'The content evaluator process did not start.' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill($true)
            $process.WaitForExit()
            throw "The content evaluator timed out after $TimeoutSeconds seconds."
        }
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            StandardOutput = $stdout.GetAwaiter().GetResult()
            StandardError = $stderr.GetAwaiter().GetResult()
        }
    }
    finally {
        if ($started -and -not $process.HasExited) {
            $process.Kill($true)
            $process.WaitForExit()
        }
        $process.Dispose()
    }
}

Export-ModuleMember -Function Get-SkillEvalContentCliPath, Invoke-SkillEvalContentCli
