// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace PowerShellToolchain.Tests;

/// <summary>
///  Tests retained PowerShell test-script host and Pester minimum-version requirements.
/// </summary>
[TestClass]
public sealed class PowerShellRequirementPolicyTests
{
    private static readonly ToolchainManifest Manifest = new(
        SchemaVersion: 1,
        TestMinimumVersion: "7.4",
        PesterCompatibilityMinimumVersion: "6.2.0",
        PesterExecutionVersion: "6.2.0");

    private const string ValidScript = """
        #Requires -Version 7.4
        #Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

        Describe 'Fixture' {
            It 'passes' { $true | Should -BeTrue }
        }
        """;

    /// <summary>
    ///  Provides scripts with missing, duplicated, mismatched, or nonliteral requirements and a
    ///  PowerShell syntax-error fixture.
    /// </summary>
    /// <value>
    ///  Rows containing a case name and script that violates the PowerShell 7.4 requirement,
    ///  the Pester 6.2.0 module-version floor, or PowerShell syntax.
    /// </value>
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

    /// <summary>
    ///  Verifies that PowerShell 7.4 and Pester 6.2.0 minimum requirements are accepted with canonical
    ///  module fields and with reordered, double-quoted module fields.
    /// </summary>
    [TestMethod]
    public void ValidateTestRequirementsAcceptedRequirementsPasses()
    {
        PowerShellToolchainPolicy.ValidateTestRequirements(ValidScript, Manifest);
        PowerShellToolchainPolicy.ValidateTestRequirements(
            ValidScript.Replace(
                "ModuleName = 'Pester'; ModuleVersion = '6.2.0'",
                "ModuleVersion = \"6.2.0\"; ModuleName = \"Pester\""),
            Manifest);
    }

    /// <summary>
    ///  Verifies that each invalid requirement or syntax fixture is rejected with
    ///  <see cref="ToolchainPolicyException"/>.
    /// </summary>
    /// <param name="name">The descriptive label identifying the rejected script fixture.</param>
    /// <param name="script">The script with invalid requirements or PowerShell syntax to validate.</param>
    [TestMethod]
    [DynamicData(nameof(RejectedScripts))]
    public void ValidateTestRequirementsRejectedRequirementsThrowsPolicyException(
        string name,
        string script)
    {
        _ = name;

        Assert.ThrowsExactly<ToolchainPolicyException>(
            () => PowerShellToolchainPolicy.ValidateTestRequirements(script, Manifest));
    }
}