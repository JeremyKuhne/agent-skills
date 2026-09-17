using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace PowerShellToolchain.Tests;

[TestClass]
public sealed class RunnerMetadataPolicyTests
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

        Write-Output $PesterVersion
        """;

    public static IEnumerable<object[]> RejectedRunners
    {
        get
        {
            yield return ["missing-host", ValidRunner.Replace("#Requires -Version 7.4", "")];
            yield return ["lower-host", ValidRunner.Replace("7.4", "7.2")];
            yield return ["higher-host", ValidRunner.Replace("7.4", "7.5")];
            yield return ["duplicate-host", $"#Requires -Version 7.4\n{ValidRunner}"];
            yield return ["missing-parameter", ValidRunner.Replace(
                "param([version] $PesterVersion = '6.2.0')",
                "param()")];
            yield return ["duplicate-parameter", ValidRunner.Replace(
                "param([version] $PesterVersion = '6.2.0')",
                "param([version] $PesterVersion = '6.2.0', [version] $PesterVersion = '6.2.0')")];
            yield return ["untyped-parameter", ValidRunner.Replace("[version] $PesterVersion", "$PesterVersion")];
            yield return ["dynamic-default", ValidRunner.Replace("'6.2.0'", "$env:PESTER_VERSION")];
            yield return ["lower-default", ValidRunner.Replace("'6.2.0'", "'6.1.0'")];
            yield return ["higher-default", ValidRunner.Replace("'6.2.0'", "'6.3.0'")];
            yield return ["syntax-error", $"{ValidRunner}\nfunction Broken {{"];
        }
    }

    [TestMethod]
    public void ValidateRunnerMetadata_AcceptedMetadata_Passes()
    {
        PowerShellToolchainPolicy.ValidateRunnerMetadata(ValidRunner, Manifest);
        PowerShellToolchainPolicy.ValidateRunnerMetadata(
            ValidRunner
                .Replace("[version]", "[Version]")
                .Replace("$PesterVersion", "$pesterVersion")
                .Replace("'6.2.0'", "\"6.2.0\""),
            Manifest);
    }

    [TestMethod]
    [DynamicData(nameof(RejectedRunners))]
    public void ValidateRunnerMetadata_RejectedMetadata_ThrowsPolicyException(
        string name,
        string script)
    {
        _ = name;

        Assert.ThrowsExactly<ToolchainPolicyException>(
            () => PowerShellToolchainPolicy.ValidateRunnerMetadata(script, Manifest));
    }
}