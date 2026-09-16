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

        Import-Module Pester -RequiredVersion $PesterVersion
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
            yield return ["missing-import-pin", ValidRunner.Replace(" -RequiredVersion $PesterVersion", "")];
            yield return ["literal-import-pin", ValidRunner.Replace(
                "Import-Module Pester -RequiredVersion $PesterVersion",
                "Import-Module Pester -RequiredVersion '6.2.0'")];
            yield return ["pester-is-not-module-name", ValidRunner.Replace(
                "Import-Module Pester -RequiredVersion $PesterVersion",
                "Import-Module Other -Function Pester -RequiredVersion $PesterVersion")];
            yield return ["ambiguous-module-name", ValidRunner.Replace(
                "Import-Module Pester -RequiredVersion $PesterVersion",
                "Import-Module Other -Name Pester -RequiredVersion $PesterVersion")];
            yield return ["alias-import", ValidRunner.Replace("Import-Module", "ipmo")];
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
                .Replace(
                    "Import-Module Pester -RequiredVersion $PesterVersion",
                    "IMPORT-MODULE pester -requiredversion $pesterVersion"),
            Manifest);
        PowerShellToolchainPolicy.ValidateRunnerRequirements(
            ValidRunner.Replace(
            "Import-Module Pester -RequiredVersion $PesterVersion",
            "Import-Module -Name Pester -RequiredVersion $PesterVersion"),
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