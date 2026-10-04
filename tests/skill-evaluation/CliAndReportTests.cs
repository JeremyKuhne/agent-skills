// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using SkillEvaluation.Cli;

namespace SkillEvaluation.Tests;

/// <summary>
///  Verifies CLI outcomes and derived reports preserve evaluation evidence and verdicts.
/// </summary>
[TestClass]
public sealed class CliAndReportTests
{
    /// <summary>
    ///  Verifies invalid invocations report an infrastructure failure without normal output.
    /// </summary>
    /// <param name="args">The invalid CLI arguments.</param>
    [TestMethod]
    [DataRow(new string[] { })]
    [DataRow(new[] { "ground" })]
    [DataRow(new[] { "prepare", "--repo-root", "one", "--repo-root", "two" })]
    [DataRow(new[] { "prepare", "--scenario" })]
    public void InvalidInvocationReportsInfrastructureFailure(string[] args)
    {
        StringWriter output = new();
        StringWriter error = new();
        Assert.AreEqual(3, Program.Run(args, output, error));
        Assert.AreEqual("", output.ToString());
        Assert.Contains("Skill evaluation failed:", error.ToString());
    }

    /// <summary>
    ///  Verifies a literal CLI pass leaves usefulness pending rather than qualified.
    /// </summary>
    [TestMethod]
    public void LiteralCliSuccessIsExplicitlyPendingRatherThanQualified()
    {
        using TestWorkspace workspace = new();
        _ = workspace.Scenario();
        string body = Path.Join(workspace.Root, "body with spaces.md");
        File.WriteAllText(body, "## Summary\n\nPreserve the body.\n\n## Validation\n\nWindows: 14 tests passed.\n");
        StringWriter output = new();
        StringWriter error = new();
        int exit = Program.Run([
            "lint-artifact", "--repo-root", workspace.Root,
            "--scenario", workspace.ScenarioPath, "--scenario-id", "test-case",
            "--target-id", "body", "--input", body], output, error);

        Assert.AreEqual(0, exit, error.ToString());
        JsonElement result = ContractJson.Parse(output.ToString());
        Assert.AreEqual("passed", result.GetProperty("literalStatus").GetString());
        Assert.AreEqual("pending", result.GetProperty("usefulOutcome").GetString());
    }

    /// <summary>
    ///  Verifies profile validation fails when no scenario has a content profile.
    /// </summary>
    [TestMethod]
    public void ValidationWithoutAProfileIsNotSuccess()
    {
        using TestWorkspace workspace = new();
        File.WriteAllText(workspace.ScenarioPath,
            """{"schemaVersion":1,"scenarios":[{"id":"legacy","prompt":"No profile."}]}""");

        StringWriter output = new();
        StringWriter error = new();
        Assert.AreEqual(3, Program.Run([
            "validate-profile", "--repo-root", workspace.Root, "--scenario", workspace.ScenarioPath
        ], output, error));

        Assert.AreEqual("", output.ToString());
        Assert.Contains("No content profile", error.ToString());
    }

    /// <summary>
    ///  Verifies rescoring preserves source verdicts, source files, and pending-run counts.
    /// </summary>
    [TestMethod]
    public void RescorePreservesSourceVerdictsAndAllPendingDenominators()
    {
        using TestWorkspace workspace = new();
        ValidatedScenario scenario = workspace.Scenario();
        workspace.WriteOutput("## Summary\n\nPreserve the body.\n\n## Validation\n\nWindows: 14 tests passed.\n");
        CaptureReceipt receipt = ArtifactStore.Capture(
            scenario, workspace.Workspace, workspace.RunDirectory, 1, TestWorkspace.ScenarioRevision);

        workspace.WriteSummary(receipt);
        string before = ContractJson.HashFile(Path.Join(workspace.Root, "source", "summary.json"));
        string destination = Path.Join(workspace.Root, "derived");
        SemanticSummary summary = DerivedReports.Rescore(
            workspace.Root, workspace.ScenarioPath, Path.Join(workspace.Root, "source"), destination, []);

        Assert.AreEqual(1, summary.RunCount);
        Assert.AreEqual(1, summary.LiteralPassedCount);
        Assert.AreEqual(0, summary.UsefulPassedCount);
        Assert.AreEqual(1, summary.PendingCount);
        Assert.IsTrue(summary.Runs[0].SourceResult.GetProperty("Passed").GetBoolean());
        Assert.IsTrue(summary.Runs[0].SourceResult.GetProperty("SafetyPassed").GetBoolean());
        Assert.AreEqual(before, ContractJson.HashFile(Path.Join(workspace.Root, "source", "summary.json")));
        Assert.IsTrue(File.Exists(Path.Join(destination, "test-case", "run-1", "semantic.json")));
        Assert.Contains("Pending", File.ReadAllText(Path.Join(destination, "summary.md")));
    }

    /// <summary>
    ///  Verifies a prompt edited after preparation cannot be accepted as the input of captured evidence.
    /// </summary>
    [TestMethod]
    public void RescoreRejectsPromptDriftBetweenPreparationAndCapture()
    {
        using TestWorkspace workspace = new();
        ValidatedScenario prepared = workspace.Scenario();
        workspace.WriteOutput("## Summary\n\nPreserve the body.\n\n## Validation\n\nWindows: 14 tests passed.\n");
        JsonObject document = JsonNode.Parse(File.ReadAllText(workspace.ScenarioPath)) as JsonObject
            ?? throw new InvalidOperationException("The scenario fixture must be an object.");

        JsonArray scenarios = document["scenarios"] as JsonArray
            ?? throw new InvalidOperationException("The scenario fixture must contain an array.");

        JsonObject edited = scenarios[0] as JsonObject
            ?? throw new InvalidOperationException("The scenario fixture must contain an object.");

        string prompt = edited["prompt"]?.GetValue<string>()
            ?? throw new InvalidOperationException("The scenario fixture must contain a prompt.");

        edited["prompt"] = prompt + " Add a Known gaps section.";
        File.WriteAllText(workspace.ScenarioPath, document.ToJsonString());
        ValidatedScenario captured = ProfileValidator.Validate(
            ProfileValidator.LoadScenarios(workspace.ScenarioPath)[0], workspace.Root)
            ?? throw new InvalidOperationException("The edited fixture must have a content profile.");

        Assert.AreEqual(prepared.Preparation.ProfileRevision, captured.Preparation.ProfileRevision);
        Assert.AreNotEqual(prepared.Preparation.InputRevision, captured.Preparation.InputRevision);
        CaptureReceipt receipt = ArtifactStore.Capture(
            captured, workspace.Workspace, workspace.RunDirectory, 1, TestWorkspace.ScenarioRevision);

        workspace.WriteSummary(receipt);
        string sourcePath = Path.Join(workspace.Root, "source", "summary.json");
        JsonObject source = JsonNode.Parse(File.ReadAllText(sourcePath)) as JsonObject
            ?? throw new InvalidOperationException("The source fixture must be an object.");

        JsonArray runs = source["Runs"] as JsonArray
            ?? throw new InvalidOperationException("The source fixture must contain runs.");

        JsonObject run = runs[0] as JsonObject
            ?? throw new InvalidOperationException("The source fixture must contain a run object.");

        run["ContentInputRevision"] = prepared.Preparation.InputRevision;
        File.WriteAllText(sourcePath, source.ToJsonString());
        SemanticSummary summary = DerivedReports.Rescore(
            workspace.Root, workspace.ScenarioPath, Path.Join(workspace.Root, "source"),
            Path.Join(workspace.Root, "derived"), []);

        Assert.AreEqual(1, summary.InfrastructureFailureCount);
        Assert.IsNull(summary.Runs[0].Content);
        Assert.AreEqual(0, summary.UsefulPassedCount);
    }

    /// <summary>
    ///  Verifies report-only mode still treats a missing manifest as an infrastructure failure.
    /// </summary>
    [TestMethod]
    public void MissingManifestIsInfrastructureFailureEvenInReportOnly()
    {
        using TestWorkspace workspace = new();
        _ = workspace.Scenario();
        workspace.WriteOutput("Done.");
        workspace.WriteSummary(receipt: null);
        StringWriter output = new();
        StringWriter error = new();
        int exit = Program.Run([
            "rescore", "--repo-root", workspace.Root, "--scenario", workspace.ScenarioPath,
            "--input-directory", Path.Join(workspace.Root, "source"),
            "--output-directory", Path.Join(workspace.Root, "derived"),
            "--report-only", "true"], output, error);

        Assert.AreEqual(3, exit, error.ToString());
        JsonElement summary = ContractJson.Parse(output.ToString());
        Assert.AreEqual(1, summary.GetProperty("infrastructureFailureCount").GetInt32());
        Assert.AreEqual(0, summary.GetProperty("usefulPassedCount").GetInt32());
        Assert.AreEqual(1, summary.GetProperty("pendingCount").GetInt32());
    }

    /// <summary>
    ///  Verifies safety failure retains exit-code precedence in report-only mode.
    /// </summary>
    [TestMethod]
    public void SafetyFailureKeepsExitPrecedenceInReportOnly()
    {
        using TestWorkspace workspace = new();
        ValidatedScenario scenario = workspace.Scenario();
        workspace.WriteOutput("Done.");
        CaptureReceipt receipt = ArtifactStore.Capture(
            scenario, workspace.Workspace, workspace.RunDirectory, 1, TestWorkspace.ScenarioRevision);

        workspace.WriteSummary(receipt, safetyPassed: false);
        int exit = Program.Run([
            "rescore", "--repo-root", workspace.Root, "--scenario", workspace.ScenarioPath,
            "--input-directory", Path.Join(workspace.Root, "source"),
            "--output-directory", Path.Join(workspace.Root, "derived"),
            "--report-only", "true"], new StringWriter(), new StringWriter());

        Assert.AreEqual(2, exit);
    }

    /// <summary>
    ///  Verifies an unverified real-client version cannot be rescored as qualified replay evidence.
    /// </summary>
    [TestMethod]
    public void UnverifiedRealClientCannotBecomeQualifiedReplayEvidence()
    {
        using TestWorkspace workspace = new();
        _ = workspace.Scenario();
        workspace.WriteOutput("Done.");
        workspace.WriteSummary(receipt: null);
        string path = Path.Join(workspace.Root, "source", "summary.json");
        JsonNode? sourceNode = JsonNode.Parse(File.ReadAllText(path));
        Assert.IsNotNull(sourceNode);
        JsonObject source = sourceNode.AsObject();
        source["CopilotVersion"] = "GitHub Copilot CLI 1.0.83.";
        File.WriteAllText(path, source.ToJsonString());
        Assert.ThrowsExactly<EvaluationContractException>(() => DerivedReports.Rescore(
            workspace.Root, workspace.ScenarioPath, Path.Join(workspace.Root, "source"),
            Path.Join(workspace.Root, "derived"), []));
    }

    /// <summary>
    ///  Verifies real-client replay requires an explicitly verified executable even with a valid hash.
    /// </summary>
    /// <param name="verificationJson">The verification value as JSON, or null to omit the property.</param>
    /// <param name="accepted">Whether the verification value establishes executable provenance.</param>
    [TestMethod]
    [DataRow(null, false)]
    [DataRow("null", false)]
    [DataRow("false", false)]
    [DataRow("\"true\"", false)]
    [DataRow("1", false)]
    [DataRow("\"\"", false)]
    [DataRow("[]", false)]
    [DataRow("{}", false)]
    [DataRow("true", true)]
    public void RescoreRequiresVerifiedRealClientEvidence(string? verificationJson, bool accepted)
    {
        using TestWorkspace workspace = new();
        ValidatedScenario scenario = workspace.Scenario();
        workspace.WriteOutput("## Summary\n\nPreserve the body.\n\n## Validation\n\nWindows: 14 tests passed.\n");
        CaptureReceipt receipt = ArtifactStore.Capture(
            scenario, workspace.Workspace, workspace.RunDirectory, 1, TestWorkspace.ScenarioRevision);

        workspace.WriteSummary(receipt);
        string path = Path.Join(workspace.Root, "source", "summary.json");
        JsonNode? sourceNode = JsonNode.Parse(File.ReadAllText(path));
        Assert.IsNotNull(sourceNode);
        JsonObject source = sourceNode.AsObject();
        source["CopilotVersion"] = "GitHub Copilot CLI 1.0.83.";
        source["CopilotExecutableSha256"] = TestWorkspace.ScenarioRevision;
        if (verificationJson is not null)
        {
            source["CopilotExecutableEvidenceVerified"] = JsonNode.Parse(verificationJson);
        }

        File.WriteAllText(path, source.ToJsonString());
        string destination = Path.Join(workspace.Root, "derived");
        if (accepted)
        {
            SemanticSummary summary = DerivedReports.Rescore(
                workspace.Root, workspace.ScenarioPath, Path.Join(workspace.Root, "source"), destination, []);

            Assert.AreEqual(0, summary.InfrastructureFailureCount);
            Assert.AreEqual(0, summary.UsefulPassedCount);
            Assert.AreEqual(QualityState.Pending, summary.Runs[0].Content?.UsefulOutcome);
        }
        else
        {
            EvaluationContractException error = Assert.ThrowsExactly<EvaluationContractException>(() =>
                DerivedReports.Rescore(
                    workspace.Root, workspace.ScenarioPath, Path.Join(workspace.Root, "source"), destination, []));

            Assert.Contains("Source client executable evidence is unverified.", error.Message);
            Assert.IsFalse(Directory.Exists(destination));
        }
    }

    /// <summary>
    ///  Verifies derived output cannot overwrite, nest within, or contain the source directory.
    /// </summary>
    /// <param name="relative">The workspace-relative destination that must be rejected.</param>
    [TestMethod]
    [DataRow("source")]
    [DataRow("source/nested")]
    [DataRow(".")]
    public void DerivedDirectoryCannotOverwriteOrContainSource(string relative)
    {
        using TestWorkspace workspace = new();
        Assert.ThrowsExactly<EvaluationContractException>(() =>
            OwnedPaths.RequireSeparateOutput(Path.Join(workspace.Root, "source"),
                Path.Join(workspace.Root, relative)));
    }
}
