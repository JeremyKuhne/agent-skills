// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace PowerShellToolchain.Tests;

/// <summary>
///  Tests strict toolchain-manifest parsing, schema shape, and canonical host and Pester versions.
/// </summary>
[TestClass]
public sealed class ManifestPolicyTests
{
    private const string ValidManifest = """
        {
          "schemaVersion": 1,
          "powerShell": {
            "testMinimumVersion": "7.4"
          },
          "pester": {
            "compatibilityMinimumVersion": "6.2.0",
            "executionVersion": "6.2.0"
          }
        }
        """;

    /// <summary>
    ///  Provides malformed JSON and manifest mutations with invalid properties, schema values,
    ///  or noncanonical or mismatched versions.
    /// </summary>
    /// <value>Rows containing a case name and manifest JSON text that must fail policy parsing.</value>
    public static IEnumerable<object[]> InvalidManifests
    {
        get
        {
            yield return ["malformed", "{"];
            yield return [
                "missing-root-property",
                "{\"schemaVersion\":1,\"powerShell\":{\"testMinimumVersion\":\"7.4\"}}"];

            yield return ["missing-test-version", ValidManifest.Replace(
                "\"testMinimumVersion\": \"7.4\"",
                "\"removed\": \"7.4\"")];

            yield return [
                "missing-compatibility-version",
                "{\"schemaVersion\":1,\"powerShell\":{\"testMinimumVersion\":\"7.4\"},\"pester\":{\"executionVersion\":\"6.2.0\"}}"];

            yield return [
                "missing-execution-version",
                "{\"schemaVersion\":1,\"powerShell\":{\"testMinimumVersion\":\"7.4\"},\"pester\":{\"compatibilityMinimumVersion\":\"6.2.0\"}}"];

            yield return ["unknown-root-property", ValidManifest.Replace("\n}", ",\n  \"extra\": true\n}")];
            yield return ["wrong-case-property", ValidManifest.Replace("\"powerShell\"", "\"powershell\"")];
            yield return ["duplicate-root-property", ValidManifest.Replace("\n}", ",\n  \"schemaVersion\": 1\n}")];
            yield return ["duplicate-nested-property", ValidManifest.Replace(
                "\"testMinimumVersion\": \"7.4\"",
                "\"testMinimumVersion\": \"7.4\",\n    \"testMinimumVersion\": \"7.4\"")];

            yield return ["comment", ValidManifest.Replace("{", "{\n  // comment", StringComparison.Ordinal)];
            yield return ["trailing-comma", ValidManifest.Replace("\n}", ",\n}")];
            yield return ["schema-string", ValidManifest.Replace("\"schemaVersion\": 1", "\"schemaVersion\": \"1\"")];
            yield return ["schema-decimal", ValidManifest.Replace("\"schemaVersion\": 1", "\"schemaVersion\": 1.0")];
            yield return ["schema-exponent", ValidManifest.Replace("\"schemaVersion\": 1", "\"schemaVersion\": 1e0")];
            yield return ["schema-unsupported", ValidManifest.Replace("\"schemaVersion\": 1", "\"schemaVersion\": 2")];
            yield return [
                "null-object",
                "{\"schemaVersion\":1,\"powerShell\":null,\"pester\":{\"compatibilityMinimumVersion\":\"6.2.0\",\"executionVersion\":\"6.2.0\"}}"];

            yield return ["numeric-version", ValidManifest.Replace("\"7.4\"", "7.4")];

            foreach (string value in new[]
                     {
                         "7.3", "7.5", "7", "7.4.0", "07.4", " 7.4", "7.4 ",
                         "v7.4", "7.4-preview", "7.4+build", "7.x"
                     })
            {
                yield return [$"test-version-{value}", ValidManifest.Replace("\"7.4\"", $"\"{value}\"")];
            }

            foreach (string value in new[]
                     {
                         "6.1.0", "6.3.0", "6.2", "6.2.0.0", "06.2.0", " 6.2.0",
                         "6.2.0 ", "v6.2.0", "6.2.0-preview", "6.2.0+build", "6.2.x"
                     })
            {
                yield return [$"compatibility-version-{value}", ValidManifest.Replace(
                    "\"compatibilityMinimumVersion\": \"6.2.0\"",
                    $"\"compatibilityMinimumVersion\": \"{value}\"")];

                yield return [$"execution-version-{value}", ValidManifest.Replace(
                    "\"executionVersion\": \"6.2.0\"",
                    $"\"executionVersion\": \"{value}\"")];
            }
        }
    }

    /// <summary>
    ///  Verifies that the accepted manifest parses as schema 1, PowerShell 7.4, and Pester compatibility
    ///  and execution versions 6.2.0.
    /// </summary>
    [TestMethod]
    public void ParseManifestAcceptedShapeReturnsTypedPolicy()
    {
        ToolchainManifest manifest = PowerShellToolchainPolicy.ParseManifest(ValidManifest);

        Assert.AreEqual(1, manifest.SchemaVersion);
        Assert.AreEqual("7.4", manifest.TestMinimumVersion);
        Assert.AreEqual("6.2.0", manifest.PesterCompatibilityMinimumVersion);
        Assert.AreEqual("6.2.0", manifest.PesterExecutionVersion);
    }

    /// <summary>
    ///  Verifies that each invalid manifest fixture is rejected with <see cref="ToolchainPolicyException"/>.
    /// </summary>
    /// <param name="name">The descriptive label identifying the rejected manifest fixture.</param>
    /// <param name="json">The malformed or policy-invalid manifest JSON text to parse.</param>
    [TestMethod]
    [DynamicData(nameof(InvalidManifests))]
    public void ParseManifestRejectedShapeThrowsPolicyException(string name, string json)
    {
        _ = name;

        Assert.ThrowsExactly<ToolchainPolicyException>(
            () => PowerShellToolchainPolicy.ParseManifest(json));
    }
}