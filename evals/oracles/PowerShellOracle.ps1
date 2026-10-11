#Requires -Version 7.4
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('powershell-record-array', 'powershell-child-outcome')]
    [string] $CaseId,
    [Parameter(Mandatory)]
    [string] $ArtifactPath,
    [Parameter(Mandatory)]
    [string] $WorkDirectory,
    [Parameter(Mandatory)]
    [string] $ReceiptPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$checks = [System.Collections.Generic.List[object]]::new()
$loadError = $null
try { $null = . $ArtifactPath }
catch { $loadError = $_ }

function Require([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Check([string] $Id, [scriptblock] $Action) {
    try {
        if ($null -ne $loadError) { throw $loadError }
        $null = & $Action
        $checks.Add([pscustomobject]@{ id = $Id; status = 'passed'; evidence = 'Observed contract assertion passed.' })
    }
    catch {
        $checks.Add([pscustomobject]@{ id = $Id; status = 'failed'; evidence = $_.ToString() })
    }
}

function Expect-Error([scriptblock] $Action) {
    $observed = $false
    try { $null = & $Action }
    catch { $observed = $true }
    Require $observed 'Expected an explicit error, not a success-shaped default.'
}

if ($CaseId -eq 'powershell-record-array') {
    function Records([string] $Json, [int] $Count) {
        $path = Join-Path $WorkDirectory 'records with spaces.json'
        [IO.File]::WriteAllText($path, $Json, [Text.UTF8Encoding]::new($false))
        $output = @(Get-Records -Path $path -ErrorAction Stop)
        Require ($output.Count -eq 1 -and $output[0] -is [pscustomobject]) 'Expected exactly one PSCustomObject.'
        $record = $output[0]
        Require ($null -ne $record.PSObject.Properties['Count'] -and
            $null -ne $record.PSObject.Properties['Records']) 'Missing Count or Records property.'
        Require (($record.Count -is [int] -or $record.Count -is [long]) -and
            $record.Count -eq $Count) 'Count is not the exact numeric record count.'
        Require ($record.Records -is [Array] -and $record.Records.Count -eq $Count) 'Records lost its required array shape.'
        return $record
    }

    Check 'zero-array' {
        $command = Get-Command Get-Records -CommandType Function -ErrorAction Stop
        $parameter = $command.Parameters['Path']
        Require ($null -ne $parameter -and $parameter.ParameterType -eq [string] -and
            @($parameter.Attributes | Where-Object { $_ -is [Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count -gt 0) `
            'Get-Records must declare a mandatory string Path parameter.'
        $null = Records '{"records":[]}' 0
    }
    Check 'single-array' {
        $value = Records '{"records":[{"id":1,"text":"one value"}]}' 1
        Require ($value.Records[0].id -eq 1 -and $value.Records[0].text -ceq 'one value') 'Single record values changed.'
    }
    Check 'multiple-array' {
        $value = Records '{"records":[{"id":1},false,null,4]}' 4
        Require ($value.Records[0].id -eq 1 -and $value.Records[1] -is [bool] -and
            -not $value.Records[1] -and $null -eq $value.Records[2] -and
            $value.Records[3] -eq 4) 'Record order, false, null, or numeric values changed.'
    }
    foreach ($case in @(
            @{ Id = 'missing-property-error'; Json = '{}' }
            @{ Id = 'malformed-json-error'; Json = '{"records":[' })) {
        Check $case.Id {
            $path = Join-Path $WorkDirectory 'invalid.json'
            [IO.File]::WriteAllText($path, $case.Json)
            Expect-Error { Get-Records -Path $path -ErrorAction Stop }
        }
    }
    Check 'wrong-property-type-error' {
        foreach ($json in @('{"records":{}}', '{"records":null}', '{"records":false}',
                '{"records":1}', '{"records":"text"}', '[]', 'null')) {
            $path = Join-Path $WorkDirectory 'wrong-type.json'
            [IO.File]::WriteAllText($path, $json)
            Expect-Error { Get-Records -Path $path -ErrorAction Stop }
        }
    }
    Check 'missing-file-error' {
        Expect-Error { Get-Records -Path (Join-Path $WorkDirectory 'does-not-exist.json') -ErrorAction Stop }
    }
}
else {
    $childPath = Join-Path $WorkDirectory 'checked child.ps1'
    [IO.File]::WriteAllText($childPath, @'
param([string] $Mode, [string] $Value)
[Console]::Error.Write('separate diagnostic')
if ($Mode -eq 'echo') {
    [Console]::Out.Write((@{ received = $Value } | ConvertTo-Json -Compress))
}
elseif ($Mode -eq 'malformed') { [Console]::Out.Write('not JSON') }
else { [Console]::Out.Write($Value) }
if ($Mode -eq 'failure') { exit 7 }
exit 0
'@)
    $executable = [Environment]::ProcessPath
    function Invoke-Child([string] $Mode, [string] $Value) {
        Invoke-CheckedChild -Executable $executable -Arguments @(
            '-NoLogo', '-NoProfile', '-NonInteractive', '-File', $childPath,
            '-Mode', $Mode, '-Value', $Value) -ErrorAction Stop
    }
    function Child([string] $Mode, [string] $Value) {
        $output = @(Invoke-Child $Mode $Value)
        Require ($output.Count -eq 1 -and $output[0] -is [pscustomobject]) 'Expected exactly one PSCustomObject.'
        $result = $output[0]
        Require ($null -ne $result.PSObject.Properties['Data'] -and
            $null -ne $result.PSObject.Properties['ErrorText'] -and
            $null -ne $result.PSObject.Properties['ExitCode']) 'Missing Data, ErrorText, or ExitCode.'
        Require (($result.ExitCode -is [int] -or $result.ExitCode -is [long]) -and
            $result.ExitCode -eq 0) 'Success did not report numeric exit 0.'
        return $result
    }
    Check 'exit-zero-json' {
        $command = Get-Command Invoke-CheckedChild -CommandType Function -ErrorAction Stop
        $parameter = $command.Parameters['Executable']
        Require ($null -ne $parameter -and $parameter.ParameterType -eq [string] -and
            @($parameter.Attributes | Where-Object { $_ -is [Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count -gt 0) `
            'Invoke-CheckedChild must declare a mandatory string Executable parameter.'
        Require ($null -ne $command.Parameters['Arguments'] -and
            $command.Parameters['Arguments'].ParameterType -eq [string[]]) 'Arguments must be string[].'
        $object = Child 'json' '{"answer":42}'
        Require ($object.Data.answer -eq 42) 'JSON object data changed.'
        $array = Child 'json' '[]'
        Require ($array.Data -is [Array] -and $array.Data.Count -eq 0) 'Empty JSON array changed.'
        $nullValue = Child 'json' 'null'
        Require ($null -eq $nullValue.Data) 'JSON null changed.'
        $falseValue = Child 'json' 'false'
        Require ($falseValue.Data -is [bool] -and -not $falseValue.Data) 'JSON false changed.'
        $zero = Child 'json' '0'
        Require (($zero.Data -is [int] -or $zero.Data -is [long]) -and $zero.Data -eq 0) 'JSON zero changed.'
        $text = Child 'json' '""'
        Require ($text.Data -is [string] -and $text.Data.Length -eq 0) 'Empty JSON string changed.'
    }
    Check 'argument-with-spaces' {
        $result = Child 'echo' 'two words with "quotes"'
        Require ($result.Data.received -ceq 'two words with "quotes"') 'Native argument boundaries or quotes changed.'
    }
    Check 'stderr-separate' {
        $result = Child 'echo' 'data'
        Require ($result.ErrorText -ceq 'separate diagnostic') 'stderr was lost or merged into stdout.'
        Require ($result.Data.received -ceq 'data') 'stdout was not independently parsed.'
    }
    Check 'nonzero-valid-json-error' { Expect-Error { Invoke-Child 'failure' '{"answer":42}' } }
    Check 'malformed-json-error' {
        Expect-Error { Invoke-Child 'malformed' 'unused' }
        Expect-Error { Invoke-Child 'json' '{"answer":42} {"answer":43}' }
    }
    Check 'caller-environment-unchanged' {
        $before = [Environment]::GetEnvironmentVariables('Process')
        $null = Child 'echo' 'data'
        Expect-Error { Invoke-Child 'failure' '{"answer":42}' }
        $after = [Environment]::GetEnvironmentVariables('Process')
        Require ($before.Count -eq $after.Count) 'The wrapper changed the caller environment variable count.'
        foreach ($name in $before.Keys) {
            Require ($after.Contains($name) -and $before[$name] -ceq $after[$name]) "The wrapper changed caller variable '$name'."
        }
    }
}
[pscustomobject]@{ schemaVersion = 1; caseId = $CaseId; checks = $checks.ToArray() } |
    ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $ReceiptPath -Encoding utf8
