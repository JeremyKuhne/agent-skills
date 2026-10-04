// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace SkillEvaluation.Tests;

/// <summary>
///  Verifies immutable artifact capture and owned-path validation.
/// </summary>
[TestClass]
public sealed class ArtifactTests
{
    private const string Body = "## Summary\n\nPreserve the body.\n\n## Validation\n\nWindows: 14 tests passed.\n";

    /// <summary>
    ///  Verifies captured file snapshots stay immutable and cannot be recaptured.
    /// </summary>
    [TestMethod]
    public void FileSnapshotIsImmutableWhenLiveWorkspaceChanges()
    {
        using TestWorkspace workspace = new();
        ValidatedScenario scenario = workspace.Scenario(TestWorkspace.Profile(ArtifactSource.File));
        workspace.WriteOutput("Done.");
        File.WriteAllText(Path.Join(workspace.Workspace, "body draft.md"), Body);
        CaptureReceipt receipt = ArtifactStore.Capture(
            scenario, workspace.Workspace, workspace.RunDirectory, 1, TestWorkspace.ScenarioRevision);

        File.WriteAllText(Path.Join(workspace.Workspace, "body draft.md"), "Changed after capture.");
        SemanticRecord record = ContentEvaluator.EvaluateCaptured(scenario,
            workspace.RunDirectory, 1, TestWorkspace.ScenarioRevision,
            receipt.ModelOutputRevision, receipt.ArtifactManifestRevision);

        Assert.AreEqual(QualityState.Passed, record.LiteralStatus);
        Assert.AreEqual(QualityState.Pending, record.UsefulOutcome);
        Assert.ThrowsExactly<EvaluationContractException>(() => ArtifactStore.Capture(
            scenario, workspace.Workspace, workspace.RunDirectory, 1, TestWorkspace.ScenarioRevision));
    }

    /// <summary>
    ///  Verifies capture uses the terminal acknowledgment rather than an earlier artifact.
    /// </summary>
    [TestMethod]
    public void TerminalAcknowledgmentIsNotReplacedByAnEarlierArtifact()
    {
        using TestWorkspace workspace = new();
        ValidatedScenario scenario = workspace.Scenario();
        workspace.WriteOutput(Body, "Done.");
        CaptureReceipt receipt = ArtifactStore.Capture(
            scenario, workspace.Workspace, workspace.RunDirectory, 1, TestWorkspace.ScenarioRevision);

        SemanticRecord record = ContentEvaluator.EvaluateCaptured(scenario,
            workspace.RunDirectory, 1, TestWorkspace.ScenarioRevision,
            receipt.ModelOutputRevision, receipt.ArtifactManifestRevision);

        Assert.AreEqual(QualityState.Failed, record.LiteralStatus);
        Assert.AreEqual("Done.", File.ReadAllText(Path.Join(workspace.RunDirectory, "artifacts", "body.utf8")));
    }

    /// <summary>
    ///  Verifies revised checks can regrade captured evidence but changed facts cannot.
    /// </summary>
    [TestMethod]
    public void NewCheckRevisionCanRegradeWithoutChangingCapturedFacts()
    {
        using TestWorkspace workspace = new();
        ValidatedScenario original = workspace.Scenario();
        workspace.WriteOutput(Body);
        CaptureReceipt receipt = ArtifactStore.Capture(
            original, workspace.Workspace, workspace.RunDirectory, 1, TestWorkspace.ScenarioRevision);

        ValidatedScenario revised = workspace.Scenario(original.Profile with
        {
            LiteralChecks = [
                .. original.Profile.LiteralChecks,
                new("additional-heading", "body", LiteralKind.Heading, "Known gaps", 2)
            ]
        });

        Assert.AreEqual(original.Preparation.InputRevision, revised.Preparation.InputRevision);
        SemanticRecord record = ContentEvaluator.EvaluateCaptured(revised,
            workspace.RunDirectory, 1, TestWorkspace.ScenarioRevision,
            receipt.ModelOutputRevision, receipt.ArtifactManifestRevision, receipt.ProfileRevision);

        Assert.AreEqual(QualityState.Failed, record.LiteralStatus);
        Assert.AreEqual(receipt.ProfileRevision, record.SourceProfileRevision);
        Assert.AreEqual(revised.Preparation.ProfileRevision, record.ProfileRevision);

        ValidatedScenario changedFacts = workspace.Scenario(revised.Profile with
        {
            SuppliedFacts = [
                revised.Profile.SuppliedFacts[0],
                revised.Profile.SuppliedFacts[1] with { Text = "Compatibility is verified." }
            ]
        });

        Assert.ThrowsExactly<EvaluationContractException>(() => ContentEvaluator.EvaluateCaptured(
            changedFacts, workspace.RunDirectory, 1, TestWorkspace.ScenarioRevision,
            receipt.ModelOutputRevision, receipt.ArtifactManifestRevision, receipt.ProfileRevision));
    }

    /// <summary>
    ///  Verifies changes to captured evidence are rejected during evaluation.
    /// </summary>
    /// <param name="relative">The run-relative evidence path to tamper with.</param>
    [TestMethod]
    [DataRow("artifacts/body.utf8")]
    [DataRow("artifacts.json")]
    [DataRow("stdout.jsonl")]
    public void ChangedCapturedEvidenceIsRejected(string relative)
    {
        using TestWorkspace workspace = new();
        ValidatedScenario scenario = workspace.Scenario();
        workspace.WriteOutput(Body);
        CaptureReceipt receipt = ArtifactStore.Capture(
            scenario, workspace.Workspace, workspace.RunDirectory, 1, TestWorkspace.ScenarioRevision);

        File.AppendAllText(Path.Join(workspace.RunDirectory, relative), "tampered");
        Assert.ThrowsExactly<EvaluationContractException>(() =>
            ContentEvaluator.EvaluateCaptured(scenario, workspace.RunDirectory, 1,
                TestWorkspace.ScenarioRevision, receipt.ModelOutputRevision, receipt.ArtifactManifestRevision));
    }

    /// <summary>
    ///  Verifies missing files and invalid UTF-8 cannot produce a capture manifest.
    /// </summary>
    [TestMethod]
    public void MissingOrInvalidUtf8FileCannotBecomeCapturedEvidence()
    {
        using TestWorkspace workspace = new();
        ValidatedScenario scenario = workspace.Scenario(TestWorkspace.Profile(ArtifactSource.File));
        workspace.WriteOutput("Done.");
        Assert.ThrowsExactly<EvaluationContractException>(() => ArtifactStore.Capture(
            scenario, workspace.Workspace, workspace.RunDirectory, 1, TestWorkspace.ScenarioRevision));

        File.WriteAllBytes(Path.Join(workspace.Workspace, "body draft.md"), [0xFF, 0xFE]);
        Assert.ThrowsExactly<DecoderFallbackException>(() => ArtifactStore.Capture(
            scenario, workspace.Workspace, workspace.RunDirectory, 1, TestWorkspace.ScenarioRevision));

        Assert.IsFalse(File.Exists(Path.Join(workspace.RunDirectory, "artifacts.json")));
    }

    /// <summary>
    ///  Verifies rooted, escaping, and malformed relative paths are rejected on every host.
    /// </summary>
    /// <param name="relative">The path that must not resolve within the workspace.</param>
    [TestMethod]
    [DataRow("../escape")]
    [DataRow("nested/../../escape")]
    [DataRow("C:\\escape")]
    [DataRow("\\\\server\\share")]
    [DataRow("/escape")]
    [DataRow("nested//file")]
    public void EscapingPathsAreRejectedOnEveryHost(string relative)
    {
        using TestWorkspace workspace = new();
        Assert.ThrowsExactly<EvaluationContractException>(() =>
            OwnedPaths.Resolve(workspace.Workspace, relative, requireFile: false));
    }

    /// <summary>
    ///  Verifies symbolic-link sources are rejected when the host can create the control.
    /// </summary>
    [TestMethod]
    public void SymlinkSourceIsRejected()
    {
        using TestWorkspace workspace = new();
        File.WriteAllText(Path.Join(workspace.Root, "outside.md"), Body);
        string link = Path.Join(workspace.Workspace, "body draft.md");
        Exception? symlinkError = null;
        try
        {
            File.CreateSymbolicLink(link, Path.Join(workspace.Root, "outside.md"));
        }
        catch (Exception error) when (error is UnauthorizedAccessException or IOException or PlatformNotSupportedException)
        {
            symlinkError = error;
        }

        if (symlinkError is not null)
        {
            Assert.Inconclusive($"This host cannot create the symlink control: {symlinkError.Message}");
            return;
        }

        Assert.ThrowsExactly<EvaluationContractException>(() =>
            OwnedPaths.Resolve(workspace.Workspace, "body draft.md"));
    }

    /// <summary>
    ///  Verifies an ordinary root beneath a symbolic-link ancestor cannot resolve outside its owner.
    /// </summary>
    [TestMethod]
    public void ResolveRejectsSymlinkedRootAncestors()
    {
        using TestWorkspace workspace = new();
        string owner = Path.Join(workspace.Root, "owner");
        string outside = Path.Join(workspace.Root, "outside");
        Directory.CreateDirectory(owner);
        Directory.CreateDirectory(Path.Join(outside, "subdir"));
        File.WriteAllText(Path.Join(outside, "subdir", "payload.md"), Body);
        string link = Path.Join(owner, "linked");
        Exception? symlinkError = null;
        try
        {
            Directory.CreateSymbolicLink(link, outside);
        }
        catch (Exception error) when (error is UnauthorizedAccessException or IOException or PlatformNotSupportedException)
        {
            symlinkError = error;
        }

        if (symlinkError is not null)
        {
            Assert.Inconclusive($"This host cannot create the symlink ancestor control: {symlinkError.Message}");
            return;
        }

        string root = Path.Join(link, "subdir");
        Assert.IsFalse((File.GetAttributes(root) & FileAttributes.ReparsePoint) != 0);
        Assert.IsTrue(File.Exists(Path.Join(root, "payload.md")));
        EvaluationContractException rejected = Assert.ThrowsExactly<EvaluationContractException>(() =>
            OwnedPaths.Resolve(root, "payload.md"));

        Assert.Contains("Links and reparse points", rejected.Message);
    }
}
