// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace PowerShellToolchain.Tests;

/// <summary>
///  Tests shard-runner host requirements and the typed, manifest-pinned Pester-version parameter.
/// </summary>
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

    /// <summary>
    ///  Provides runners with invalid host declarations, missing or invalid Pester-version parameters,
    ///  and a PowerShell syntax-error fixture.
    /// </summary>
    /// <value>Rows containing a case name and runner script that must fail metadata validation.</value>
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

    /// <summary>
    ///  Verifies that a PowerShell 7.4 runner with a typed Pester-version default of 6.2.0 is accepted
    ///  with type and parameter-name casing variations and alternate default-value quotes.
    /// </summary>
    [TestMethod]
    public void ValidateRunnerMetadataAcceptedMetadataPasses()
    {
        PowerShellToolchainPolicy.ValidateRunnerMetadata(ValidRunner, Manifest);
        PowerShellToolchainPolicy.ValidateRunnerMetadata(
            ValidRunner
                .Replace("[version]", "[Version]")
                .Replace("$PesterVersion", "$pesterVersion")
                .Replace("'6.2.0'", "\"6.2.0\""),
            Manifest);
    }

    /// <summary>
    ///  Verifies that each invalid runner-metadata or syntax fixture is rejected with
    ///  <see cref="ToolchainPolicyException"/>.
    /// </summary>
    /// <param name="name">The descriptive label identifying the rejected runner fixture.</param>
    /// <param name="script">The runner script with invalid metadata or PowerShell syntax to validate.</param>
    [TestMethod]
    [DynamicData(nameof(RejectedRunners))]
    public void ValidateRunnerMetadataRejectedMetadataThrowsPolicyException(
        string name,
        string script)
    {
        _ = name;

        Assert.ThrowsExactly<ToolchainPolicyException>(
            () => PowerShellToolchainPolicy.ValidateRunnerMetadata(script, Manifest));
    }
}