using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace PowerShellToolchain.Tests;

[TestClass]
public sealed class PowerShellRequirementPolicyTests
{
    private static readonly ToolchainManifest Manifest = new(
        SchemaVersion: 1,
        TestMinimumVersion: "7.4",
        PesterCompatibilityMinimumVersion: "6.2.0",
        PesterExecutionVersion: "6.2.0");

    public static IEnumerable<object[]> RejectedScripts
    {
        get
        {
            yield return ["missing-host", "#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }"];
            yield return ["lower-host", ValidScript.Replace("7.4", "7.2")];
            yield return ["higher-host", ValidScript.Replace("7.4", "7.5")];
            yield return ["duplicate-host", $"#Requires -Version 7.4\n{ValidScript}"];
            yield return ["missing-pester", "#Requires -Version 7.4"];
            yield return ["exact-instead-of-floor", ValidScript.Replace("ModuleVersion", "RequiredVersion")];
            yield return ["lower-pester", ValidScript.Replace("6.2.0", "6.1.0")];
            yield return ["higher-pester", ValidScript.Replace("6.2.0", "6.3.0")];
            yield return ["duplicate-pester", $"#Requires -Modules Pester\n{ValidScript}"];
            yield return ["dynamic-pester", "#Requires -Version 7.4\n#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = $version }"];
            yield return ["syntax-error", $"{ValidScript}\nfunction Broken {{"];
        }
    }

    private const string ValidScript = """
        #Requires -Version 7.4
        #Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

        Describe 'Fixture' {
            It 'passes' { $true | Should -BeTrue }
        }
        """;

    [TestMethod]
    public void ValidateTestRequirements_AcceptedRequirements_Passes()
    {
        PowerShellToolchainPolicy.ValidateTestRequirements(ValidScript, Manifest);
        PowerShellToolchainPolicy.ValidateTestRequirements(
            ValidScript.Replace(
                "ModuleName = 'Pester'; ModuleVersion = '6.2.0'",
                "ModuleVersion = \"6.2.0\"; ModuleName = \"Pester\""),
            Manifest);
    }

    [TestMethod]
    [DynamicData(nameof(RejectedScripts))]
    public void ValidateTestRequirements_RejectedRequirements_ThrowsPolicyException(
        string name,
        string script)
    {
        _ = name;

        Assert.ThrowsExactly<ToolchainPolicyException>(
            () => PowerShellToolchainPolicy.ValidateTestRequirements(script, Manifest));
    }
}