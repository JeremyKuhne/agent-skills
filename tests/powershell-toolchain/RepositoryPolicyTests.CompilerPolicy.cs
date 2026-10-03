// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace PowerShellToolchain.Tests;

public sealed partial class RepositoryPolicyTests
{
    private const string ToukiPackage = "KlutzyNinja.Touki";
    private const string ToukiAnalyzerPackage = "KlutzyNinja.Touki.Analyzers";
    private const string RequiredFileHeaderAssignment =
        "file_header_template = Copyright (c) 2025 Jeremy W Kuhne\\n"
            + "SPDX-License-Identifier: MIT\\n"
            + "See LICENSE file in the project root for full license information";

    private static readonly string[] OptInToukiRules =
    [
        "TOUKI0005",
        "TOUKI0012",
        "TOUKI0022",
        "TOUKI0024",
        "TOUKI0027",
        "TOUKI0028",
        "TOUKI0029",
        "TOUKI0041"
    ];

    private const string ValidOwnedCompilerEvaluation = """
        {
          "Properties": {
            "TreatWarningsAsErrors": "true"
          },
          "Items": {
            "PackageReference": [
              { "Identity": "KlutzyNinja.Touki", "Version": "[0.10.0]" },
              { "Identity": "KlutzyNinja.Touki.Analyzers", "Version": "[0.11.1]", "PrivateAssets": "all" }
            ]
          }
        }
        """;

    /// <summary>
    ///  Verifies actual evaluated Release MSBuild settings for each owned managed project: warnings
    ///  as errors, exact Touki version ranges, and private analyzer assets.
    /// </summary>
    /// <param name="projectPath">The repository-relative project path, using backslash separators.</param>
    [TestMethod]
    [DataRow(@"tests\powershell-toolchain\PowerShellToolchain.Tests.csproj")]
    [DataRow(@"tests\dotnet-pipes\DotNetPipes.Tests.csproj")]
    [DataRow(@"tests\dotnet-pipes\anonymous-child\AnonymousPipeChild.csproj")]
    [DataRow(@"tests\dotnet-file-creation\DotNetFileCreation.Tests.csproj")]
    public void OwnedManagedProjectsEvaluatedCompilerPolicyMatchesRequiredSettings(string projectPath)
    {
        using JsonDocument evaluation = EvaluateCompilerPolicy(projectPath);
        AssertEvaluatedCompilerPolicy(evaluation.RootElement, expectsTouki: true, projectPath);
    }

    /// <summary>
    ///  Verifies actual evaluated Release MSBuild settings for distributed samples: warnings as
    ///  errors without either repository-owned Touki package reference.
    /// </summary>
    /// <param name="projectPath">The repository-relative sample project path, using backslash separators.</param>
    [TestMethod]
    [DataRow(@"skills\dotnet-pipes\assets\bounded-echo\BoundedPipeEcho.csproj")]
    [DataRow(@"skills\winui-win32-hosting\assets\minimal-host\MinimalWinUIHost.csproj")]
    public void DistributedSamplesEvaluatedCompilerPolicyExcludesTouki(string projectPath)
    {
        using JsonDocument evaluation = EvaluateCompilerPolicy(projectPath);
        AssertEvaluatedCompilerPolicy(evaluation.RootElement, expectsTouki: false, projectPath);
    }

    /// <summary>
    ///  Verifies the root EditorConfig's exact file-header assignment, eight warning assignments,
    ///  and absence of custom Touki quality or naming options.
    /// </summary>
    [TestMethod]
    public void RootEditorConfigCompilerPolicyMatchesRequiredLiterals()
    {
        AssertEditorConfigCompilerPolicy(
            File.ReadAllLines(Path.Join(RepositoryRoot, ".editorconfig")),
            "Root EditorConfig");
    }

    /// <summary>
    ///  Verifies that structured policy assertions reject disabled warnings as errors, changed or
    ///  unpinned versions, and analyzer assets that are not private.
    /// </summary>
    /// <param name="name">The metadata mutation's diagnostic label.</param>
    /// <param name="packageIndex">The package's zero-based index, or -1 for the warnings-as-errors property.</param>
    /// <param name="propertyName">The evaluated string property to corrupt.</param>
    /// <param name="rejectedValue">The replacement value that must fail policy assertions.</param>
    [TestMethod]
    [DataRow("warnings-as-errors-disabled", -1, "TreatWarningsAsErrors", "false")]
    [DataRow("runtime-version-unpinned", 0, "Version", "0.10.0")]
    [DataRow("runtime-version-changed", 0, "Version", "[0.9.0]")]
    [DataRow("analyzer-version-unpinned", 1, "Version", "0.11.1")]
    [DataRow("analyzer-version-changed", 1, "Version", "[0.10.0]")]
    [DataRow("analyzer-assets-exposed", 1, "PrivateAssets", "compile")]
    public void EvaluatedOwnedCompilerPolicyRejectedMetadataFails(
        string name,
        int packageIndex,
        string propertyName,
        string rejectedValue)
    {
        JsonObject evaluation = CreateOwnedCompilerEvaluation();
        JsonArray references = GetCompilerFixtureReferences(evaluation);
        JsonObject properties = packageIndex < 0
            ? RequireCompilerFixtureNode(evaluation["Properties"]).AsObject()
            : RequireCompilerFixtureNode(references[packageIndex]).AsObject();

        Assert.AreNotEqual(RequireCompilerFixtureNode(properties[propertyName]).GetValue<string>(), rejectedValue, name);
        properties[propertyName] = rejectedValue;

        using JsonDocument document = JsonDocument.Parse(evaluation.ToJsonString());
        Assert.ThrowsExactly<AssertFailedException>(
            () => AssertEvaluatedCompilerPolicy(document.RootElement, expectsTouki: true, name),
            name);
    }

    /// <summary>
    ///  Verifies that each required Touki package must appear exactly once in evaluated references.
    /// </summary>
    /// <param name="packageIndex">The required package's zero-based index in the fixture.</param>
    /// <param name="duplicate">Whether to duplicate the package instead of removing it.</param>
    [TestMethod]
    [DataRow(0, false)]
    [DataRow(1, false)]
    [DataRow(0, true)]
    [DataRow(1, true)]
    public void EvaluatedOwnedCompilerPolicyMissingOrDuplicateReferencesFails(int packageIndex, bool duplicate)
    {
        JsonObject evaluation = CreateOwnedCompilerEvaluation();
        JsonArray references = GetCompilerFixtureReferences(evaluation);
        if (duplicate)
        {
            references.Add(RequireCompilerFixtureNode(references[packageIndex]).DeepClone());
        }
        else
        {
            references.RemoveAt(packageIndex);
        }

        using JsonDocument document = JsonDocument.Parse(evaluation.ToJsonString());
        Assert.ThrowsExactly<AssertFailedException>(() =>
            AssertEvaluatedCompilerPolicy(document.RootElement, expectsTouki: true, "Reference count"));
    }

    /// <summary>
    ///  Verifies that either repository-owned Touki package contaminates the distributed-sample policy.
    /// </summary>
    /// <param name="packageIndex">The zero-based index of the package retained in the sample fixture.</param>
    [TestMethod]
    [DataRow(0)]
    [DataRow(1)]
    public void EvaluatedSampleCompilerPolicyToukiReferenceFails(int packageIndex)
    {
        JsonObject evaluation = CreateOwnedCompilerEvaluation();
        GetCompilerFixtureReferences(evaluation).RemoveAt(1 - packageIndex);

        using JsonDocument document = JsonDocument.Parse(evaluation.ToJsonString());
        Assert.ThrowsExactly<AssertFailedException>(() =>
            AssertEvaluatedCompilerPolicy(document.RootElement, expectsTouki: false, "Sample reference"));
    }

    /// <summary>
    ///  Verifies that package identities containing a Touki name are not mistaken for exact Touki IDs.
    /// </summary>
    [TestMethod]
    public void EvaluatedSampleCompilerPolicyUnrelatedPackageNamesPass()
    {
        JsonObject evaluation = CreateOwnedCompilerEvaluation();
        foreach (JsonNode? reference in GetCompilerFixtureReferences(evaluation))
        {
            JsonObject package = RequireCompilerFixtureNode(reference).AsObject();
            package["Identity"] = $"Example.{RequireCompilerFixtureNode(package["Identity"]).GetValue<string>()}";
        }

        using JsonDocument document = JsonDocument.Parse(evaluation.ToJsonString());
        AssertEvaluatedCompilerPolicy(document.RootElement, expectsTouki: false, "Unrelated package names");
    }

    /// <summary>
    ///  Verifies that duplicate or conflicting assignments and custom Touki options fail the literal
    ///  EditorConfig policy, including casing variations and qualified naming options.
    /// </summary>
    /// <param name="name">The rejected assignment's diagnostic label.</param>
    /// <param name="assignment">The extra physical line appended to otherwise valid compiler-policy lines.</param>
    [TestMethod]
    [DataRow("duplicate-header", RequiredFileHeaderAssignment)]
    [DataRow("duplicate-warning", "dotnet_diagnostic.TOUKI0041.severity = warning")]
    [DataRow("conflicting-severity", "dotnet_diagnostic.TOUKI0041.severity = none")]
    [DataRow("case-variant-severity", "DOTNET_DIAGNOSTIC.touki0041.SEVERITY = none")]
    [DataRow("quality-override", "dotnet_code_quality.TOUKI0020.exclude_nested_types = true")]
    [DataRow("naming-override", "touki_naming_style.tests.capitalization = pascal_case")]
    [DataRow("qualified-naming-override", "dotnet_code_quality.touki_naming_rule.tests.symbols = methods")]
    public void EditorConfigCompilerPolicyRejectedAssignmentsFail(string name, string assignment)
    {
        string[] lines = [.. File.ReadAllLines(Path.Join(RepositoryRoot, ".editorconfig")), assignment];
        Assert.ThrowsExactly<AssertFailedException>(() => AssertEditorConfigCompilerPolicy(lines, name), name);
    }

    /// <summary>
    ///  Verifies that the file-header and opt-in severity assignments cannot be omitted.
    /// </summary>
    /// <param name="key">The required literal key removed from otherwise valid compiler-policy lines.</param>
    [TestMethod]
    [DataRow("file_header_template")]
    [DataRow("dotnet_diagnostic.TOUKI0012.severity")]
    public void EditorConfigCompilerPolicyMissingAssignmentsFail(string key)
    {
        string[] lines = File.ReadAllLines(Path.Join(RepositoryRoot, ".editorconfig"))
            .Where(line => !AssignsLiteralCompilerKey(line, key))
            .ToArray();

        Assert.ThrowsExactly<AssertFailedException>(() => AssertEditorConfigCompilerPolicy(lines, key), key);
    }

    /// <summary>
    ///  Evaluates Release MSBuild properties and package references without restoring or building a project.
    /// </summary>
    /// <param name="projectPath">The repository-relative project path, using backslash separators.</param>
    /// <returns>The parsed MSBuild JSON document, which the caller must dispose.</returns>
    private static JsonDocument EvaluateCompilerPolicy(string projectPath)
    {
        string fullPath = Path.Join(RepositoryRoot, projectPath.Replace('\\', Path.DirectorySeparatorChar));
        Assert.IsTrue(File.Exists(fullPath), $"Compiler-policy project does not exist: {fullPath}");
        ProcessStartInfo startInfo = new("dotnet")
        {
            WorkingDirectory = RepositoryRoot,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false
        };

        startInfo.ArgumentList.Add("msbuild");
        startInfo.ArgumentList.Add(fullPath);
        startInfo.ArgumentList.Add("-property:Configuration=Release");
        startInfo.ArgumentList.Add("-getProperty:TreatWarningsAsErrors");
        startInfo.ArgumentList.Add("-getItem:PackageReference");
        string output = RunRepositoryProcess(startInfo, $"MSBuild evaluation of {projectPath}");
        try
        {
            return JsonDocument.Parse(output);
        }
        catch (JsonException exception)
        {
            throw new InvalidOperationException($"MSBuild returned invalid compiler-policy JSON for {projectPath}.", exception);
        }
    }

    private static JsonObject CreateOwnedCompilerEvaluation()
    {
        return JsonNode.Parse(ValidOwnedCompilerEvaluation) as JsonObject
            ?? throw new InvalidOperationException("The owned-project compiler-policy fixture must be an object.");
    }

    private static JsonNode RequireCompilerFixtureNode(JsonNode? node)
    {
        return node ?? throw new InvalidOperationException("The compiler-policy fixture is missing a required node.");
    }

    private static JsonArray GetCompilerFixtureReferences(JsonObject evaluation)
    {
        JsonObject items = RequireCompilerFixtureNode(evaluation["Items"]).AsObject();
        return RequireCompilerFixtureNode(items["PackageReference"]).AsArray();
    }

    private static void AssertEvaluatedCompilerPolicy(JsonElement evaluation, bool expectsTouki, string subject)
    {
        string? warningsAsErrors = evaluation.GetProperty("Properties")
            .GetProperty("TreatWarningsAsErrors")
            .GetString();

        Assert.IsTrue(
            string.Equals(warningsAsErrors, "true", StringComparison.OrdinalIgnoreCase),
            $"{subject} must evaluate TreatWarningsAsErrors to true.");

        JsonElement[] references = evaluation.GetProperty("Items")
            .GetProperty("PackageReference")
            .EnumerateArray()
            .ToArray();

        if (expectsTouki)
        {
            AssertPinnedToukiReference(references, ToukiPackage, "[0.10.0]", subject);
            AssertPinnedToukiReference(references, ToukiAnalyzerPackage, "[0.11.1]", subject);
            JsonElement analyzer = FindToukiReferences(references, ToukiAnalyzerPackage)[0];
            Assert.IsTrue(
                analyzer.TryGetProperty("PrivateAssets", out JsonElement privateAssets),
                $"{subject} must declare analyzer PrivateAssets.");

            Assert.AreEqual("all", privateAssets.GetString(), $"{subject} analyzer PrivateAssets must be all.");
        }
        else
        {
            Assert.IsEmpty(FindToukiReferences(references, ToukiPackage), $"{subject} must not reference {ToukiPackage}.");
            Assert.IsEmpty(
                FindToukiReferences(references, ToukiAnalyzerPackage),
                $"{subject} must not reference {ToukiAnalyzerPackage}.");
        }
    }

    private static void AssertPinnedToukiReference(
        JsonElement[] references,
        string packageId,
        string expectedVersion,
        string subject)
    {
        JsonElement[] matches = FindToukiReferences(references, packageId);
        Assert.HasCount(1, matches, $"{subject} must reference {packageId} exactly once.");
        Assert.AreEqual(
            expectedVersion,
            matches[0].GetProperty("Version").GetString(),
            $"{subject} must pin {packageId} to {expectedVersion}.");
    }

    private static JsonElement[] FindToukiReferences(JsonElement[] references, string packageId)
    {
        return references.Where(reference => string.Equals(
            reference.GetProperty("Identity").GetString(),
            packageId,
            StringComparison.OrdinalIgnoreCase)).ToArray();
    }

    private static void AssertEditorConfigCompilerPolicy(string[] lines, string subject)
    {
        AssertLiteralCompilerAssignment(lines, "file_header_template", RequiredFileHeaderAssignment, subject);
        foreach (string rule in OptInToukiRules)
        {
            string key = $"dotnet_diagnostic.{rule}.severity";
            AssertLiteralCompilerAssignment(lines, key, $"{key} = warning", subject);
        }

        foreach (string line in lines)
        {
            ReadOnlySpan<char> assignment = line.AsSpan().TrimStart();
            bool toukiOptions = assignment.StartsWith("dotnet_code_quality.TOUKI", StringComparison.OrdinalIgnoreCase)
                || assignment.StartsWith("touki_naming", StringComparison.OrdinalIgnoreCase);

            Assert.IsFalse(
                toukiOptions && assignment.Contains('='),
                $"{subject} must not override Touki quality or naming options: {line}");
        }
    }

    private static void AssertLiteralCompilerAssignment(
        string[] lines,
        string key,
        string expectedLine,
        string subject)
    {
        string[] assignments = lines.Where(line => AssignsLiteralCompilerKey(line, key)).ToArray();
        Assert.HasCount(1, assignments, $"{subject} must assign {key} exactly once.");
        Assert.AreEqual(expectedLine, assignments[0], $"{subject} must retain the exact literal assignment for {key}.");
    }

    private static bool AssignsLiteralCompilerKey(string line, string key)
    {
        ReadOnlySpan<char> assignment = line.AsSpan().TrimStart();
        return assignment.StartsWith(key, StringComparison.OrdinalIgnoreCase)
            && assignment[key.Length..].TrimStart().StartsWith("=", StringComparison.Ordinal);
    }
}
