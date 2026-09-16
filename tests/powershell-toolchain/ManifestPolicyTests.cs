using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace PowerShellToolchain.Tests;

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

    public static IEnumerable<object[]> InvalidManifests
    {
        get
        {
            yield return ["malformed", "{"];
            yield return ["missing-root-property", """
                {
                  "schemaVersion": 1,
                  "powerShell": {
                    "testMinimumVersion": "7.4"
                  }
                }
                """];
            yield return ["missing-test-version", ValidManifest.Replace(
                "\"testMinimumVersion\": \"7.4\"",
                "\"removed\": \"7.4\"")];
            yield return ["missing-compatibility-version", """
                                {
                                    "schemaVersion": 1,
                                    "powerShell": {
                                        "testMinimumVersion": "7.4"
                                    },
                                    "pester": {
                                        "executionVersion": "6.2.0"
                                    }
                                }
                                """];
            yield return ["missing-execution-version", """
                                {
                                    "schemaVersion": 1,
                                    "powerShell": {
                                        "testMinimumVersion": "7.4"
                                    },
                                    "pester": {
                                        "compatibilityMinimumVersion": "6.2.0"
                                    }
                                }
                                """];
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
            yield return ["null-object", """
                {
                  "schemaVersion": 1,
                  "powerShell": null,
                  "pester": {
                    "compatibilityMinimumVersion": "6.2.0",
                    "executionVersion": "6.2.0"
                  }
                }
                """];
            yield return ["numeric-version", ValidManifest.Replace("\"7.4\"", "7.4")];
            foreach (string value in new[] { "7", "7.4.0", "07.4", " 7.4", "7.4 ", "v7.4", "7.4-preview", "7.x" })
            {
                yield return [$"test-version-{value}", ValidManifest.Replace("\"7.4\"", $"\"{value}\"")];
            }

            foreach (string value in new[] { "6.2", "6.2.0.0", "06.2.0", " 6.2.0", "6.2.0 ", "v6.2.0", "6.2.0-preview", "6.2.x", "6.3.0" })
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

    [TestMethod]
    public void ParseManifest_AcceptedShape_ReturnsTypedPolicy()
    {
        ToolchainManifest manifest = PowerShellToolchainPolicy.ParseManifest(ValidManifest);

        Assert.AreEqual(1, manifest.SchemaVersion);
        Assert.AreEqual("7.4", manifest.TestMinimumVersion);
        Assert.AreEqual("6.2.0", manifest.PesterCompatibilityMinimumVersion);
        Assert.AreEqual("6.2.0", manifest.PesterExecutionVersion);
    }

    [TestMethod]
    [DynamicData(nameof(InvalidManifests))]
    public void ParseManifest_RejectedShape_ThrowsPolicyException(string name, string json)
    {
        _ = name;

        Assert.ThrowsExactly<ToolchainPolicyException>(
            () => PowerShellToolchainPolicy.ParseManifest(json));
    }
}