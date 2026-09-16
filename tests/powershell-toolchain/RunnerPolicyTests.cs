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
        if (-not [string]::IsNullOrWhiteSpace($ShardPath)) {
            Microsoft.PowerShell.Core\Import-Module Pester -RequiredVersion $RequiredPesterVersion
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
            yield return ["wrong-default", ValidRunner.Replace("'6.2.0'", "'6.1.0'")];
            yield return ["dynamic-default", ValidRunner.Replace("'6.2.0'", "$env:PESTER_VERSION")];
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
            yield return ["function-shadowed-import", ValidRunner.Replace(
                "if (-not [string]::IsNullOrWhiteSpace($ShardPath)) {",
                "function Import-Module { }\nif (-not [string]::IsNullOrWhiteSpace($ShardPath)) {")];
            yield return ["dot-sourced-command", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion\n    . $scriptPath")];
            yield return ["invoke-expression-import", ValidRunner.Replace(
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion",
                "Microsoft.PowerShell.Core\\Import-Module Pester -RequiredVersion $RequiredPesterVersion\n    Invoke-Expression 'Import-Module Other'")];
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
            yield return ["top-level-import", """
                #Requires -Version 7.4
                [CmdletBinding()]
                param([version] $PesterVersion = '6.2.0')

                New-Variable -Name RequiredPesterVersion -Value $PesterVersion -Option Constant -ErrorAction Stop
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