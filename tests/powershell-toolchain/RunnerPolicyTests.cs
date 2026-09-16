using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace PowerShellToolchain.Tests;

[TestClass]
public sealed class RunnerPolicyTests
{
    private static readonly ToolchainManifest Manifest = new(
        SchemaVersion: 1,
        TestMinimumVersion: "7.4",
        PesterCompatibilityMinimumVersion: "6.2.0",
        PesterExecutionVersion: "6.2.0");

    private const string ValidRunner = """
        #Requires -Version 7.4
        [CmdletBinding()]
        param([version] $PesterVersion = '6.2.0')

        New-Variable -Name RequiredPesterVersion -Value $PesterVersion -Option Constant -ErrorAction Stop
        if ($RequiredPesterVersion -ne [version]'6.2.0') {
            throw 'Wrong Pester version.'
        }
        if (-not [string]::IsNullOrWhiteSpace($ShardPath)) {
            Microsoft.PowerShell.Core\Import-Module Pester -RequiredVersion $RequiredPesterVersion
            $configuration = Pester\New-PesterConfiguration
            $result = Pester\Invoke-Pester -Configuration $configuration
            if ($result.Result -ne 'Passed' -or $result.TotalCount -eq 0 -or
                $result.NotRunCount -gt 0 -or $result.InconclusiveCount -gt 0) { exit 1 }
            exit 0
        }
        """;

    public static IEnumerable<object[]> RejectedRunners
    {
        get
        {
            yield return ["missing-parameter", ValidRunner.Replace(
                "param([version] $PesterVersion = '6.2.0')",
                "param()")];
            yield return ["untyped-parameter", ValidRunner.Replace("[version] $PesterVersion", "$PesterVersion")];
            yield return ["wrong-default", ValidRunner.Replace(
                "param([version] $PesterVersion = '6.2.0')",
                "param([version] $PesterVersion = '6.1.0')")];
            yield return ["dynamic-default", ValidRunner.Replace(
                "param([version] $PesterVersion = '6.2.0')",
                "param([version] $PesterVersion = $env:PESTER_VERSION)")];
            yield return ["missing-version-guard", ValidRunner.Replace(
                "$RequiredPesterVersion -ne [version]'6.2.0'",
                "$false")];
            yield return ["wrong-version-guard", ValidRunner.Replace(
                "$RequiredPesterVersion -ne [version]'6.2.0'",
                "$RequiredPesterVersion -ne [version]'6.1.0'")];
            yield return ["requires-module", ValidRunner.Replace(
                "#Requires -Version 7.4",
                "#Requires -Version 7.4\n#Requires -Modules Pester")];
            yield return ["using-module", ValidRunner.Replace(
                "#Requires -Version 7.4",
                "using module Pester\n#Requires -Version 7.4")];
            yield return ["nested-requires-module", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "$nested = {\n#Requires -Modules Pester\n$null\n}\n    Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion")];
            yield return ["missing-version-lock", ValidRunner.Replace(
                "New-Variable -Name RequiredPesterVersion -Value $PesterVersion -Option Constant -ErrorAction Stop",
                "")];
            yield return ["literal-version-lock", ValidRunner.Replace(
                "-Value $PesterVersion",
                "-Value '6.2.0'")];
            yield return ["scope-qualified-version-lock", ValidRunner.Replace(
                "-Value $PesterVersion",
                "-Value $global:PesterVersion")];
            yield return ["mutable-version-lock", ValidRunner.Replace(
                "-Option Constant",
                "-Option None")];
            yield return ["late-version-lock", ValidRunner.Replace(
                "New-Variable -Name RequiredPesterVersion -Value $PesterVersion -Option Constant -ErrorAction Stop",
                "$other = $null\nNew-Variable -Name RequiredPesterVersion -Value $PesterVersion -Option Constant -ErrorAction Stop")];
            yield return ["missing-import-pin", ValidRunner.Replace(" -RequiredVersion $RequiredPesterVersion", "")];
            yield return ["literal-import-pin", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion '6.2.0'")];
            yield return ["scope-qualified-import-pin", ValidRunner.Replace(
                "-RequiredVersion $RequiredPesterVersion",
                "-RequiredVersion $global:RequiredPesterVersion")];
            yield return ["unqualified-canonical-import", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester",
                "Import-Module Pester")];
            yield return ["pester-is-not-module-name", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "Microsoft.PowerShell.Core\\Import-Module Other -Function Pester -RequiredVersion $RequiredPesterVersion")];
            yield return ["ambiguous-module-name", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "Microsoft.PowerShell.Core\\Import-Module Other -Name Pester -RequiredVersion $RequiredPesterVersion")];
            yield return ["dynamic-invocation", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "& 'Import-Module' Pester -RequiredVersion $RequiredPesterVersion")];
            yield return ["dynamic-extra-import", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion\n    $name = 'Import-Module'\n    & $name Other")];
            yield return ["module-qualified-extra-import", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion\n    Microsoft.PowerShell.Core\\Import-Module Other")];
            yield return ["alias-rebound-import", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "Set-Alias Load-Module Import-Module\n    Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion\n    Load-Module Other")];
            yield return ["unresolved-import-alias", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion\n    Load-Module Other")];
            yield return ["unrecognized-static-command", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion\n    Get-Location")];
            yield return ["function-shadowed-import", ValidRunner.Replace(
                "if (-not [string]::IsNullOrWhiteSpace($ShardPath)) {",
                "function Import-Module { }\nif (-not [string]::IsNullOrWhiteSpace($ShardPath)) {")];
            yield return ["function-provider-rebinding", ValidRunner.Replace(
                "if (-not [string]::IsNullOrWhiteSpace($ShardPath)) {",
                "${function:Invoke-Pester} = { }\nif (-not [string]::IsNullOrWhiteSpace($ShardPath)) {")];
            yield return ["scoped-function-provider-rebinding", ValidRunner.Replace(
                "if (-not [string]::IsNullOrWhiteSpace($ShardPath)) {",
                "${script:function:Invoke-Pester} = { }\nif (-not [string]::IsNullOrWhiteSpace($ShardPath)) {")];
            yield return ["alias-provider-rebinding", ValidRunner.Replace(
                "if (-not [string]::IsNullOrWhiteSpace($ShardPath)) {",
                "${alias:Run-Tests} = 'Invoke-Pester'\nif (-not [string]::IsNullOrWhiteSpace($ShardPath)) {")];
            yield return ["scoped-alias-provider-rebinding", ValidRunner.Replace(
                "if (-not [string]::IsNullOrWhiteSpace($ShardPath)) {",
                "${global:alias:Run-Tests} = 'Invoke-Pester'\nif (-not [string]::IsNullOrWhiteSpace($ShardPath)) {")];
            yield return ["dot-sourced-command", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion\n    . $scriptPath")];
            yield return ["invoke-expression-import", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion\n    Invoke-Expression 'Import-Module Other'")];
            yield return ["scriptblock-member-invocation", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "[scriptblock]::Create('Microsoft.PowerShell.Core\\Import-Module Other').Invoke()\n    Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion")];
            yield return ["command-info-member-invocation", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "$command = Get-Command Microsoft.PowerShell.Core\\Import-Module\n    $command.ScriptBlock.Invoke()\n    Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion")];
            yield return ["dynamic-member-invocation", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "$member = 'Invoke'\n    $scriptBlock.$member()\n    Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion")];
            yield return ["invoke-return-as-is-member", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "$scriptBlock.InvokeReturnAsIs()\n    Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion")];
            yield return ["nested-function", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "function Import-PesterLater { Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion }")];
            yield return ["nested-condition", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "if ($false) { Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion }")];
            yield return ["wrong-worker-condition", ValidRunner.Replace(
                "-not [string]::IsNullOrWhiteSpace($ShardPath)",
                "$ShardPath")];
            yield return ["worker-import-in-elseif", ValidRunner.Replace(
                "if (-not [string]::IsNullOrWhiteSpace($ShardPath)) {",
                "if ($false) {\n} elseif (-not [string]::IsNullOrWhiteSpace($ShardPath)) {")];
            yield return ["named-begin-end-blocks", ValidRunner.Replace(
                "New-Variable -Name RequiredPesterVersion -Value $PesterVersion -Option Constant -ErrorAction Stop",
                "begin { $null = 'before' }\nend {\n    New-Variable -Name RequiredPesterVersion -Value $PesterVersion -Option Constant -ErrorAction Stop") + "\n}"];
            yield return ["configuration-before-import", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "$early = Pester\\New-PesterConfiguration\n    Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion")];
            yield return ["invoke-before-import", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "Pester\\Invoke-Pester -Configuration $configuration\n    Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion")];
            yield return ["coordinator-pester-command", ValidRunner.Replace(
                "if (-not [string]::IsNullOrWhiteSpace($ShardPath)) {",
                "Pester\\New-PesterConfiguration\nif (-not [string]::IsNullOrWhiteSpace($ShardPath)) {")];
            yield return ["duplicate-configuration-command", ValidRunner.Replace(
                "$result = Pester\\Invoke-Pester -Configuration $configuration",
                "$other = Pester\\New-PesterConfiguration")];
            yield return ["duplicate-invocation-command", ValidRunner.Replace(
                "$configuration = Pester\\New-PesterConfiguration",
                "$other = Pester\\Invoke-Pester -Configuration $configuration")];
            yield return ["top-level-return", ValidRunner.Replace(
                "if (-not [string]::IsNullOrWhiteSpace($ShardPath)) {",
                "return\nif (-not [string]::IsNullOrWhiteSpace($ShardPath)) {")];
            yield return ["top-level-exit", ValidRunner.Replace(
                "if (-not [string]::IsNullOrWhiteSpace($ShardPath)) {",
                "exit 0\nif (-not [string]::IsNullOrWhiteSpace($ShardPath)) {")];
            yield return ["top-level-throw", ValidRunner.Replace(
                "if (-not [string]::IsNullOrWhiteSpace($ShardPath)) {",
                "throw 'stop'\nif (-not [string]::IsNullOrWhiteSpace($ShardPath)) {")];
            yield return ["statement-before-worker", ValidRunner.Replace(
                "if (-not [string]::IsNullOrWhiteSpace($ShardPath)) {",
                "$other = $null\nif (-not [string]::IsNullOrWhiteSpace($ShardPath)) {")];
            yield return ["return-before-import", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "return\n    Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion")];
            yield return ["exit-before-import", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "exit 0\n    Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion")];
            yield return ["failure-exit-code", ValidRunner.Replace(
                ") { exit 1 }",
                ") { exit 0 }")];
            yield return ["inverted-failure-condition", ValidRunner.Replace(
                "$result.Result -ne 'Passed'",
                "$result.Result -eq 'Passed'")];
            yield return ["success-exit-code", ValidRunner.Replace(
                "exit 0",
                "exit 1")];
            yield return ["success-exit-in-failure-branch", ValidRunner.Replace(
                "exit 0",
                "if ($result.Result -ne 'Passed') { exit 0 }")];
            yield return ["configuration-target", ValidRunner.Replace(
                "$configuration = Pester\\New-PesterConfiguration",
                "$other = Pester\\New-PesterConfiguration")];
            yield return ["configuration-argument", ValidRunner.Replace(
                "$configuration = Pester\\New-PesterConfiguration",
                "$configuration = Pester\\New-PesterConfiguration extra")];
            yield return ["configuration-pipeline", ValidRunner.Replace(
                "$configuration = Pester\\New-PesterConfiguration",
                "$configuration = Pester\\New-PesterConfiguration | Out-Null")];
            yield return ["invoke-target", ValidRunner.Replace(
                "$result = Pester\\Invoke-Pester -Configuration $configuration",
                "$other = Pester\\Invoke-Pester -Configuration $configuration")];
            yield return ["invoke-add-assignment", ValidRunner.Replace(
                "$result = Pester\\Invoke-Pester -Configuration $configuration",
                "$result += Pester\\Invoke-Pester -Configuration $configuration")];
            yield return ["invoke-missing-configuration", ValidRunner.Replace(
                "$result = Pester\\Invoke-Pester -Configuration $configuration",
                "$result = Pester\\Invoke-Pester")];
            yield return ["invoke-wrong-configuration", ValidRunner.Replace(
                "$result = Pester\\Invoke-Pester -Configuration $configuration",
                "$result = Pester\\Invoke-Pester -Configuration $other")];
            yield return ["invoke-extra-argument", ValidRunner.Replace(
                "$result = Pester\\Invoke-Pester -Configuration $configuration",
                "$result = Pester\\Invoke-Pester -Configuration $configuration -PassThru")];
            yield return ["new-item-provider-target", ValidRunner.Replace(
                "if (-not [string]::IsNullOrWhiteSpace($ShardPath)) {",
                "New-Item -Path Function:\\Invoke-Pester -Value { }\nif (-not [string]::IsNullOrWhiteSpace($ShardPath)) {")];
            yield return ["set-content-provider-target", ValidRunner.Replace(
                "if (-not [string]::IsNullOrWhiteSpace($ShardPath)) {",
                "Set-Content -LiteralPath Alias:\\Invoke-Pester -Value Write-Host\nif (-not [string]::IsNullOrWhiteSpace($ShardPath)) {")];
            yield return ["top-level-import", """
                #Requires -Version 7.4
                [CmdletBinding()]
                param([version] $PesterVersion = '6.2.0')

                New-Variable -Name RequiredPesterVersion -Value $PesterVersion -Option Constant -ErrorAction Stop
                if ($RequiredPesterVersion -ne [version]'6.2.0') {
                    throw 'Wrong Pester version.'
                }
                Microsoft.PowerShell.Core\Import-Module Pester -RequiredVersion $RequiredPesterVersion
                """];
            yield return ["reassigned-version", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "$PesterVersion = '6.1.0'\n    Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion")];
            yield return ["set-variable-version", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "Set-Variable -Name PesterVersion -Value '6.1.0'\n    Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion")];
            yield return ["module-qualified-set-variable-version", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "Microsoft.PowerShell.Utility\\Set-Variable -Name PesterVersion -Value '6.1.0'\n    Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion")];
            yield return ["remove-variable-version-alias", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "rv PesterVersion\n    Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion")];
            yield return ["incremented-version", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "$PesterVersion++\n    Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion")];
            yield return ["prefix-incremented-version", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "++$PesterVersion\n    Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion")];
            yield return ["decremented-version", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "$PesterVersion--\n    Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion")];
            yield return ["prefix-decremented-version", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "--$PesterVersion\n    Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion")];
            yield return ["duplicate-required-version", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion -RequiredVersion '6.1.0'")];
            yield return ["duplicate-attached-required-version", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion -RequiredVersion:'6.1.0'")];
            yield return ["extra-positional-module", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "Microsoft.PowerShell.Core\\Import-Module Pester Other -RequiredVersion $RequiredPesterVersion")];
            yield return ["second-import", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion\n    Import-Module Other")];
            yield return ["second-alias-import", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion\n    ipmo Pester")];
            yield return ["second-nested-import", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion\n    function Import-Later { Import-Module Pester }")];
            yield return ["second-dead-import", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion\n    if ($false) { Import-Module Pester }")];
            yield return ["alias-import", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester",
                "ipmo Pester")];
            yield return ["syntax-error", $"{ValidRunner}\nfunction Broken {{"];
        }
    }

    [TestMethod]
    public void ValidateRunnerRequirements_AcceptedRunner_Passes()
    {
        PowerShellToolchainPolicy.ValidateRunnerRequirements(ValidRunner, Manifest);
        PowerShellToolchainPolicy.ValidateRunnerRequirements(
            ValidRunner
                .Replace("[version] $PesterVersion", "[Version] $pesterVersion")
                .Replace("-Value $PesterVersion", "-Value $pesterVersion")
                .Replace(
                    "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                    "microsoft.powershell.core\\IMPORT-MODULE pester -requiredversion $requiredPesterVersion"),
            Manifest);
        PowerShellToolchainPolicy.ValidateRunnerRequirements(
            ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "Microsoft.PowerShell.Core\\Import-Module -Name Pester -RequiredVersion $RequiredPesterVersion"),
            Manifest);
    }

    [TestMethod]
    [DynamicData(nameof(RejectedRunners))]
    public void ValidateRunnerRequirements_RejectedRunner_ThrowsPolicyException(
        string name,
        string script)
    {
        _ = name;

        Assert.ThrowsExactly<ToolchainPolicyException>(
            () => PowerShellToolchainPolicy.ValidateRunnerRequirements(script, Manifest));
    }
}