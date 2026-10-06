// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using SkillEvaluation.Cli;
using SkillEvaluation.Onnx;

namespace SkillEvaluation.Tests;

/// <summary>
///  Verifies pinned report-only contract behavior using only synthetic assets and deterministic scores.
/// </summary>
[TestClass]
public sealed class GroundingTests
{
    /// <summary>
    ///  Verifies the public validation command checks local byte pins without invoking a classifier.
    /// </summary>
    /// <param name="maximumTokens">The complete-pair token limit in the original manifest.</param>
    /// <param name="expectedExit">The expected public validation outcome.</param>
    [TestMethod]
    [DataRow(4, 3)]
    [DataRow(5, 0)]
    [DataRow(512, 0)]
    [DataRow(513, 3)]
    public void ValidateGroundingAssetsCliChecksPinsWithoutInference(int maximumTokens, int expectedExit)
    {
        using TestWorkspace workspace = new();
        string manifest = WriteSyntheticAssets(workspace);
        JsonObject document = JsonNode.Parse(File.ReadAllText(manifest)) as JsonObject
            ?? throw new InvalidOperationException("The synthetic manifest must be an object.");

        document["maximumTokens"] = maximumTokens;
        File.WriteAllText(manifest, document.ToJsonString(ContractJson.Options));
        using StringWriter output = new();
        using StringWriter error = new();
        int exit = Program.Run([
            "validate-grounding-assets", "--asset-root", Path.Join(workspace.Root, "assets"),
            "--manifest", manifest
        ], output, error);

        Assert.AreEqual(expectedExit, exit, error.ToString());
        if (expectedExit == 0)
        {
            Assert.AreEqual("", error.ToString());
            Assert.AreEqual("report-only", ContractJson.Parse(output.ToString())
                .GetProperty("manifest").GetProperty("mode").GetString());
        }
        else
        {
            Assert.AreEqual("", output.ToString());
            Assert.Contains("Skill evaluation failed:", error.ToString());
        }
    }

    /// <summary>
    ///  Verifies completed review projection can be checked through the public CLI without any runtime backend.
    /// </summary>
    /// <param name="role">The explicitly supported reviewer declaration.</param>
    /// <param name="authority">The corresponding evidence classification.</param>
    [TestMethod]
    [DataRow("synthetic-fixture-reviewer", "synthetic-review-fixture")]
    [DataRow("repository-maintainer", "declared-human-reviewed-development")]
    public void ValidateGroundingReviewCliKeepsDeclaredRolesExplicit(string role, string authority)
    {
        using TestWorkspace workspace = new();
        string bank = workspace.WriteReviewBank();
        string review = GroundingFixture.WriteReview(workspace, bank, document => document["reviewerRole"] = role);
        using StringWriter output = new();
        using StringWriter error = new();
        int exit = Program.Run([
            "validate-grounding-review", "--repo-root", workspace.Root, "--packets", bank,
            "--review-owner", Path.Join(workspace.Root, "reviews"), "--review", review
        ], output, error);

        Assert.AreEqual(0, exit, error.ToString());
        System.Text.Json.JsonElement result = ContractJson.Parse(output.ToString());
        Assert.AreEqual(authority, result.GetProperty("authorityScope").GetString());
        Assert.AreEqual(14, result.GetProperty("labels").GetArrayLength());
        Assert.AreEqual("", error.ToString());
    }

    /// <summary>
    ///  Verifies even extreme finite scores cannot establish calibrated or useful quality.
    /// </summary>
    [TestMethod]
    public void ScoreUsesFiniteStableSoftmaxAndPreservesTies()
    {
        GroundingScores result = GroundingInference.Score(new(-10000, 10000, 0));
        Assert.AreEqual(GroundingRelation.Entailed, result.RawRelation);
        Assert.AreEqual(1.0, result.Entailment);
        Assert.AreEqual(0.0, result.Contradiction);
        Assert.IsNull(GroundingInference.Score(new(1, 1, 0)).RawRelation);
        Assert.ThrowsExactly<EvaluationContractException>(() =>
            GroundingInference.Score(new(double.NaN, 1, 0)));

        Assert.ThrowsExactly<EvaluationContractException>(() =>
            GroundingInference.Score(new(1, double.PositiveInfinity, 0)));
    }

    /// <summary>
    ///  Verifies the canonical pair markers and 512-token boundary without a learned tokenizer or model.
    /// </summary>
    [TestMethod]
    public void PairCompositionPreservesCanonicalIdsAndRejectsTruncation()
    {
        int[] sentence = [5768, 10872, 303, 298, 684, 260];
        GroundingTokens pair = DebertaPairEncoding.Compose(sentence, sentence, maximumTokens: 512);
        CollectionAssert.AreEqual(new[] { 1, 5768, 10872, 303, 298, 684, 260, 2, 5768, 10872, 303, 298, 684, 260, 2 },
            pair.InputIds);

        CollectionAssert.AreEqual(Enumerable.Repeat(1, 15).ToArray(), pair.AttentionMask);
        CollectionAssert.AreEqual(new[] { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1 }, pair.TokenTypeIds);
        Assert.AreEqual(512, DebertaPairEncoding.Compose(
            Enumerable.Repeat(10, 508).ToArray(), [11], maximumTokens: 512).InputIds.Length);

        Assert.ThrowsExactly<EvaluationContractException>(() => DebertaPairEncoding.Compose(
            Enumerable.Repeat(10, 509).ToArray(), [11], maximumTokens: 512));

        Assert.ThrowsExactly<EvaluationContractException>(() =>
            DebertaPairEncoding.Compose([], [11], maximumTokens: 512));

        Assert.ThrowsExactly<EvaluationContractException>(() =>
            DebertaPairEncoding.Compose([10], [], maximumTokens: 512));

        GroundingInference.ValidateTokens(
            DebertaPairEncoding.Compose([10], [11], maximumTokens: 5), maximumTokens: 5);
    }

    /// <summary>
    ///  Gets malformed tensors that must fail before a classifier can dispatch.
    /// </summary>
    public static IEnumerable<object[]> InvalidTensors
    {
        get
        {
            yield return ["empty", new GroundingTokens([], [], [])];
            yield return ["empty-premise", new GroundingTokens([1, 2, 11, 2], [1, 1, 1, 1], [0, 0, 1, 1])];
            yield return ["empty-claim", new GroundingTokens([1, 10, 2, 2], [1, 1, 1, 1], [0, 0, 0, 1])];
            yield return ["empty-longer-premise", new GroundingTokens([1, 2, 10, 11, 2], [1, 1, 1, 1, 1], [0, 0, 1, 1, 1])];
            yield return ["empty-longer-claim", new GroundingTokens([1, 10, 11, 2, 2], [1, 1, 1, 1, 1], [0, 0, 0, 0, 1])];
            yield return ["wrong-cls", new GroundingTokens([3, 10, 2, 11, 2], [1, 1, 1, 1, 1], [0, 0, 0, 1, 1])];
            yield return ["wrong-final-sep", new GroundingTokens([1, 10, 2, 11, 3], [1, 1, 1, 1, 1], [0, 0, 0, 1, 1])];
            yield return ["missing-first-sep", new GroundingTokens([1, 10, 10, 11, 2], [1, 1, 1, 1, 1], [0, 0, 0, 1, 1])];
            yield return ["padded-mask", new GroundingTokens([1, 10, 2, 11, 2], [1, 1, 1, 0, 1], [0, 0, 0, 1, 1])];
            yield return ["short-mask", new GroundingTokens([1, 10, 2, 11, 2], [1, 1], [0, 0, 0, 1, 1])];
            yield return ["wrong-types", new GroundingTokens([1, 10, 2, 11, 2], [1, 1, 1, 1, 1], [0, 1, 0, 1, 1])];
            yield return ["out-of-vocabulary", new GroundingTokens([1, 128001, 2, 11, 2], [1, 1, 1, 1, 1], [0, 0, 0, 1, 1])];
            foreach (int control in new[] { 0, 1, 2, 128000 })
            {
                yield return [$"premise-control-{control}",
                    new GroundingTokens([1, control, 2, 11, 2], [1, 1, 1, 1, 1], [0, 0, 0, 1, 1])];

                yield return [$"claim-control-{control}",
                    new GroundingTokens([1, 10, 2, control, 2], [1, 1, 1, 1, 1], [0, 0, 0, 1, 1])];
            }
        }
    }

    /// <summary>
    ///  Verifies tensor rejection is explicit and not a coercive empty/default result.
    /// </summary>
    /// <param name="name">The invalid control name.</param>
    /// <param name="tokens">The invalid complete-pair tensors.</param>
    [TestMethod]
    [DynamicData(nameof(InvalidTensors))]
    public void ValidateTokensRejectsMalformedInputs(string name, GroundingTokens tokens)
    {
        Assert.ThrowsExactly<EvaluationContractException>(() =>
            GroundingInference.ValidateTokens(tokens, maximumTokens: 512), name);
    }

    /// <summary>
    ///  Verifies composition cannot hide a reserved model control inside either text segment.
    /// </summary>
    /// <param name="control">The independently injected model control ID.</param>
    /// <param name="inPremise">Whether the injection is in the premise rather than the claim.</param>
    [TestMethod]
    [DataRow(0, true)]
    [DataRow(1, true)]
    [DataRow(2, true)]
    [DataRow(128000, true)]
    [DataRow(0, false)]
    [DataRow(1, false)]
    [DataRow(2, false)]
    [DataRow(128000, false)]
    public void PairCompositionRejectsInteriorControls(int control, bool inPremise)
    {
        Assert.ThrowsExactly<EvaluationContractException>(() => DebertaPairEncoding.Compose(
            inPremise ? [control] : [10], inPremise ? [11] : [control], maximumTokens: 512));
    }

    /// <summary>
    ///  Verifies legitimate unknown-token IDs remain ordinary text evidence, not structural controls.
    /// </summary>
    [TestMethod]
    public void PairCompositionPreservesUnknownTokens()
    {
        GroundingTokens tokens = DebertaPairEncoding.Compose([3], [3], maximumTokens: 512);
        CollectionAssert.AreEqual(new[] { 1, 3, 2, 3, 2 }, tokens.InputIds);
        GroundingInference.ValidateTokens(tokens, maximumTokens: 512);
    }

    /// <summary>
    ///  Verifies only explicit human-review authority can accompany a non-synthetic computation marker.
    /// </summary>
    /// <param name="role">The supported review declaration.</param>
    /// <param name="syntheticBackend">The controlled backend identity marker, not learned inference.</param>
    /// <param name="accepted">Whether the authority/computation combination is permitted.</param>
    [TestMethod]
    [DataRow("synthetic-fixture-reviewer", true, true)]
    [DataRow("synthetic-fixture-reviewer", false, false)]
    [DataRow("repository-maintainer", true, true)]
    [DataRow("repository-maintainer", false, true)]
    public void GroundCliRequiresHumanEvidenceForNonSyntheticIdentity(
        string role, bool syntheticBackend, bool accepted)
    {
        using TestWorkspace workspace = new();
        string bank = workspace.WriteReviewBank();
        string manifest = WriteSyntheticAssets(workspace);
        string review = GroundingFixture.WriteReview(workspace, bank, document => document["reviewerRole"] = role);
        using FixtureGroundingBackend backend = new()
        {
            Identity = new("controlled-fixture-identity", syntheticBackend,
                ContractJson.HashText($"fixture-identity/{syntheticBackend}"),
                "deterministic-fixture-runtime", "deterministic-fixture-tokenizer")
        };

        using StringWriter output = new();
        using StringWriter error = new();
        string destination = Path.Join(workspace.Root, "diagnostics");
        int exit = Program.Run(Arguments(workspace, bank, manifest, review, destination),
            output, error, _ => backend);

        Assert.AreEqual(accepted ? 0 : 3, exit, error.ToString());
        Assert.IsTrue(backend.WasDisposed);
        if (accepted)
        {
            Assert.AreEqual(14, backend.PredictedCount);
            System.Text.Json.JsonElement result = ContractJson.Parse(output.ToString());
            Assert.AreEqual("pending", result.GetProperty("usefulOutcome").GetString());
            Assert.AreEqual(0, result.GetProperty("usefulPassedCount").GetInt32());
        }
        else
        {
            Assert.AreEqual(0, backend.EncodedCount);
            Assert.AreEqual(0, backend.PredictedCount);
            Assert.AreEqual("", output.ToString());
            Assert.Contains("Skill evaluation failed:", error.ToString());
            Assert.IsFalse(Directory.Exists(destination));
        }
    }

    /// <summary>
    ///  Verifies explicitly synthetic high-support output remains pending and immutable source bytes stay unchanged.
    /// </summary>
    [TestMethod]
    public void GroundCliReportsSyntheticEvidenceWithoutPromotingQuality()
    {
        using TestWorkspace workspace = new();
        string bank = workspace.WriteReviewBank();
        string manifest = WriteSyntheticAssets(workspace);
        string review = GroundingFixture.WriteReview(workspace, bank);
        string bankBefore = ContractJson.HashFile(bank);
        string reviewBefore = ContractJson.HashFile(review);
        FixtureGroundingBackend backend = new();
        using StringWriter output = new();
        using StringWriter error = new();
        string destination = Path.Join(workspace.Root, "diagnostics");
        int exit = Program.Run(Arguments(workspace, bank, manifest, review, destination),
            output, error, _ => backend);

        Assert.AreEqual(0, exit, error.ToString());
        Assert.AreEqual(14, backend.EncodedCount);
        Assert.AreEqual(14, backend.PredictedCount);
        Assert.IsTrue(backend.WasDisposed);
        Assert.AreEqual(bankBefore, ContractJson.HashFile(bank));
        Assert.AreEqual(reviewBefore, ContractJson.HashFile(review));
        AssertDiagnosticContract(output.ToString());
        Assert.Contains("uncalibrated", File.ReadAllText(Path.Join(destination, "grounding.md")));
        Assert.Contains("Full prose", File.ReadAllText(Path.Join(destination, "grounding.md")));
        Assert.IsTrue(File.Exists(Path.Join(destination, "grounding.json")));
        Assert.ThrowsExactly<EvaluationContractException>(() =>
            GroundingReports.Evaluate(workspace.Root, bank, Path.Join(workspace.Root, "assets"), manifest,
                Path.Join(workspace.Root, "reviews"), review, destination, _ => new FixtureGroundingBackend()));
    }

    /// <summary>
    ///  Verifies a missing, unsupported, or non-report-only CLI input cannot launch native inference.
    /// </summary>
    /// <param name="mode">The intentionally invalid boundary mode.</param>
    [TestMethod]
    [DataRow("non-report-only")]
    [DataRow("native-synthetic-profile")]
    [DataRow("missing-review")]
    public void GroundCliRejectsInvalidBoundaryBeforeNativeDispatch(string mode)
    {
        using TestWorkspace workspace = new();
        string bank = workspace.WriteReviewBank();
        string manifest = WriteSyntheticAssets(workspace);
        string review = GroundingFixture.WriteReview(workspace, bank);
        string destination = Path.Join(workspace.Root, "diagnostics");
        string[] arguments = Arguments(workspace, bank, manifest, review, destination);
        if (mode == "non-report-only")
        {
            arguments[^1] = "false";
        }
        else if (mode == "missing-review")
        {
            File.Delete(review);
        }

        using StringWriter output = new();
        using StringWriter error = new();
        int exit = Program.Run(arguments, output, error);
        Assert.AreEqual(3, exit, mode);
        Assert.AreEqual("", output.ToString(), mode);
        Assert.Contains("Skill evaluation failed:", error.ToString(), mode);
        Assert.IsFalse(Directory.Exists(destination));
    }

    /// <summary>
    ///  Verifies direct and wrapped native-loader failures retain the public infrastructure exit and cause.
    /// </summary>
    /// <param name="kind">The known native-loader exception.</param>
    /// <param name="wrappers">The number of CLR type-initialization wrappers.</param>
    [TestMethod]
    [DataRow("missing", 0)]
    [DataRow("missing", 1)]
    [DataRow("missing", 2)]
    [DataRow("bad-image", 0)]
    [DataRow("bad-image", 1)]
    [DataRow("bad-image", 2)]
    [DataRow("entry-point", 0)]
    [DataRow("entry-point", 1)]
    [DataRow("entry-point", 2)]
    public void GroundCliKnownNativeLoadingErrorsReturnInfrastructureExit(string kind, int wrappers)
    {
        using TestWorkspace workspace = new();
        string bank = workspace.WriteReviewBank();
        string manifest = WriteSyntheticAssets(workspace);
        string review = GroundingFixture.WriteReview(workspace, bank);
        string destination = Path.Join(workspace.Root, "diagnostics");
        Exception cause = kind switch
        {
            "missing" => new DllNotFoundException("The controlled native library is missing."),
            "bad-image" => new BadImageFormatException("The controlled native library has the wrong architecture."),
            "entry-point" => new EntryPointNotFoundException("The controlled native entry point is missing."),
            _ => throw new ArgumentOutOfRangeException(nameof(kind))
        };

        Exception failure = cause;
        for (int index = 0; index < wrappers; index++)
        {
            failure = new TypeInitializationException("ControlledNativeMethods", failure);
        }

        using StringWriter output = new();
        using StringWriter error = new();
        int exit = Program.Run(Arguments(workspace, bank, manifest, review, destination),
            output, error, _ => throw failure);

        Assert.AreEqual(3, exit);
        Assert.AreEqual("", output.ToString());
        Assert.Contains("Skill evaluation failed:", error.ToString());
        Assert.Contains(cause.Message, error.ToString());
        Assert.IsFalse(Directory.Exists(destination));
    }

    /// <summary>
    ///  Verifies unrelated initialization defects are not hidden by the native-loader classifier.
    /// </summary>
    [TestMethod]
    public void GroundCliDoesNotHideUnrelatedInitializationFailure()
    {
        using TestWorkspace workspace = new();
        string bank = workspace.WriteReviewBank();
        string manifest = WriteSyntheticAssets(workspace);
        string review = GroundingFixture.WriteReview(workspace, bank);
        string destination = Path.Join(workspace.Root, "diagnostics");
        TypeInitializationException failure = new("ControlledUnrelatedType",
            new InvalidOperationException("An unrelated programming defect."));

        using StringWriter output = new();
        using StringWriter error = new();
        Assert.ThrowsExactly<TypeInitializationException>(() =>
            Program.Run(Arguments(workspace, bank, manifest, review, destination),
                output, error, _ => throw failure));

        Assert.AreEqual("", output.ToString());
        Assert.AreEqual("", error.ToString());
        Assert.IsFalse(Directory.Exists(destination));
    }

    /// <summary>
    ///  Verifies native failure classification rejects a missing observed exception explicitly.
    /// </summary>
    [TestMethod]
    public void NativeLibraryFailuresRejectsNull()
    {
        Assert.ThrowsExactly<ArgumentNullException>(() => NativeLibraryFailures.FindCause(error: null));
    }

    /// <summary>
    ///  Verifies malformed final-pair tensors reject the complete cohort before any prediction.
    /// </summary>
    /// <param name="name">The independently malformed pair.</param>
    /// <param name="tokens">The invalid final pair.</param>
    [TestMethod]
    [DynamicData(nameof(InvalidTensors))]
    public void GroundCliRejectsMalformedFinalPairBeforeAnyDispatch(string name, GroundingTokens tokens)
    {
        using TestWorkspace workspace = new();
        string bank = workspace.WriteReviewBank();
        string manifest = WriteSyntheticAssets(workspace);
        string review = GroundingFixture.WriteReview(workspace, bank);
        using FixtureGroundingBackend backend = new()
        {
            TokenFactory = count => count == 14
                ? tokens
                : new([1, 10, 2, 11, 2], [1, 1, 1, 1, 1], [0, 0, 0, 1, 1])
        };

        using StringWriter output = new();
        using StringWriter error = new();
        string destination = Path.Join(workspace.Root, "diagnostics");
        int exit = Program.Run(Arguments(workspace, bank, manifest, review, destination),
            output, error, _ => backend);

        Assert.AreEqual(3, exit, name);
        Assert.AreEqual(14, backend.EncodedCount, name);
        Assert.AreEqual(0, backend.PredictedCount, name);
        Assert.IsTrue(backend.WasDisposed, name);
        Assert.AreEqual("", output.ToString(), name);
        Assert.Contains("Skill evaluation failed:", error.ToString(), name);
        Assert.IsFalse(Directory.Exists(destination), name);
    }

    /// <summary>
    ///  Gets unsupported review-counter representations through both public grounding entry points.
    /// </summary>
    public static IEnumerable<object[]> InvalidReviewCountCommands
    {
        get
        {
            foreach (string command in new[] { "validate-grounding-review", "ground" })
            {
                foreach ((string Field, string Value) control in new[]
                {
                    ("humanReviewedArtifactCount", "2147483648"),
                    ("rubricDecisionCount", "2147483648"),
                    ("groundingDecisionCount", "2147483648"),
                    ("humanReviewedArtifactCount", "16.0"),
                    ("rubricDecisionCount", "6.4e1"),
                    ("groundingDecisionCount", "1.4e1")
                })
                {
                    yield return [command, control.Field, control.Value];
                }
            }
        }
    }

    /// <summary>
    ///  Verifies out-of-range or non-Int32 counters produce explicit infrastructure errors before backend creation.
    /// </summary>
    /// <param name="command">The public review or grounding entry point.</param>
    /// <param name="field">The independently invalid completeness counter.</param>
    /// <param name="value">The original JSON number representation.</param>
    [TestMethod]
    [DynamicData(nameof(InvalidReviewCountCommands))]
    public void GroundingCliRejectsUnsupportedReviewCounters(string command, string field, string value)
    {
        using TestWorkspace workspace = new();
        string bank = workspace.WriteReviewBank();
        string manifest = WriteSyntheticAssets(workspace);
        string review = GroundingFixture.WriteReview(workspace, bank);
        JsonObject document = JsonNode.Parse(File.ReadAllText(review)) as JsonObject
            ?? throw new InvalidOperationException("The synthetic review must be an object.");

        document[field] = JsonNode.Parse(value);
        File.WriteAllText(review, document.ToJsonString(ContractJson.Options));
        string destination = Path.Join(workspace.Root, "diagnostics");
        string[] arguments = command == "ground"
            ? Arguments(workspace, bank, manifest, review, destination)
            : ["validate-grounding-review", "--repo-root", workspace.Root, "--packets", bank,
                "--review-owner", Path.Join(workspace.Root, "reviews"), "--review", review];

        using StringWriter output = new();
        using StringWriter error = new();
        bool constructed = false;
        int exit = Program.Run(arguments, output, error, _ =>
        {
            constructed = true;
            return new FixtureGroundingBackend();
        });

        Assert.AreEqual(3, exit);
        Assert.AreEqual("", output.ToString());
        Assert.Contains("Skill evaluation failed:", error.ToString());
        Assert.IsFalse(constructed);
        Assert.IsFalse(Directory.Exists(destination));
    }

    /// <summary>
    ///  Gets unknown or mistyped reviewer roles through both public preflight entry points.
    /// </summary>
    public static IEnumerable<object[]> UnsupportedReviewerRoles
    {
        get
        {
            foreach (string command in new[] { "validate-grounding-review", "ground" })
            {
                foreach (string role in new[]
                {
                    "assistant",
                    "judge",
                    "unknown-reviewer",
                    "synthetic-fixture-reviwer",
                    "SYNTHETIC-FIXTURE-REVIEWER",
                    "repository-maintainer "
                })
                {
                    yield return [command, role];
                }
            }
        }
    }

    /// <summary>
    ///  Verifies an unsupported role cannot become human evidence or reach backend construction.
    /// </summary>
    /// <param name="command">The public review or grounding command.</param>
    /// <param name="role">The unsupported original role declaration.</param>
    [TestMethod]
    [DynamicData(nameof(UnsupportedReviewerRoles))]
    public void GroundingCliRejectsUnsupportedReviewerRolesBeforeBackendCreation(string command, string role)
    {
        using TestWorkspace workspace = new();
        string bank = workspace.WriteReviewBank();
        string manifest = WriteSyntheticAssets(workspace);
        string review = GroundingFixture.WriteReview(workspace, bank, document => document["reviewerRole"] = role);
        string destination = Path.Join(workspace.Root, "diagnostics");
        string[] arguments = command == "ground"
            ? Arguments(workspace, bank, manifest, review, destination)
            : ["validate-grounding-review", "--repo-root", workspace.Root, "--packets", bank,
                "--review-owner", Path.Join(workspace.Root, "reviews"), "--review", review];

        using StringWriter output = new();
        using StringWriter error = new();
        bool constructed = false;
        int exit = Program.Run(arguments, output, error, _ =>
        {
            constructed = true;
            return new FixtureGroundingBackend();
        });

        Assert.AreEqual(3, exit);
        Assert.AreEqual("", output.ToString());
        Assert.Contains("Skill evaluation failed:", error.ToString());
        Assert.IsFalse(constructed);
        Assert.IsFalse(Directory.Exists(destination));
    }

    /// <summary>
    ///  Verifies every pair is preflighted before any prediction, including a bad late pair.
    /// </summary>
    [TestMethod]
    public void GroundingPreflightsAllPairsAndDisposesOnFailure()
    {
        using TestWorkspace workspace = new();
        string bank = workspace.WriteReviewBank();
        string manifest = WriteSyntheticAssets(workspace);
        string review = GroundingFixture.WriteReview(workspace, bank);
        FixtureGroundingBackend backend = new()
        {
            TokenFactory = count => count == 14
                ? new([1, .. Enumerable.Repeat(10, 510), 2, 11, 2],
                    Enumerable.Repeat(1, 514).ToArray(),
                    [.. Enumerable.Repeat(0, 512), 1, 1])
                : new([1, 10, 2, 11, 2], [1, 1, 1, 1, 1], [0, 0, 0, 1, 1])
        };

        string destination = Path.Join(workspace.Root, "diagnostics");
        Assert.ThrowsExactly<EvaluationContractException>(() =>
            GroundingReports.Evaluate(workspace.Root, bank, Path.Join(workspace.Root, "assets"), manifest,
                Path.Join(workspace.Root, "reviews"), review, destination, _ => backend));

        Assert.AreEqual(14, backend.EncodedCount);
        Assert.AreEqual(0, backend.PredictedCount);
        Assert.IsTrue(backend.WasDisposed);
        Assert.IsFalse(Directory.Exists(destination));
    }

    /// <summary>
    ///  Verifies invalid scores, input mutation, and source tamper never produce a diagnostic success tree.
    /// </summary>
    /// <param name="mode">The independent failure control.</param>
    [TestMethod]
    [DataRow("invalid-scores")]
    [DataRow("mutated-tensors")]
    [DataRow("changed-assets")]
    [DataRow("changed-review")]
    [DataRow("changed-bank")]
    public void GroundingRejectsMutationAndInvalidScores(string mode)
    {
        using TestWorkspace workspace = new();
        string bank = workspace.WriteReviewBank();
        string manifest = WriteSyntheticAssets(workspace);
        string review = GroundingFixture.WriteReview(workspace, bank);
        FixtureGroundingBackend backend = new();
        if (mode == "invalid-scores")
        {
            backend.Logits = new(double.NaN, 1, 0);
        }
        else
        {
            backend.OnPredict = tokens =>
            {
                if (backend.PredictedCount != 1)
                {
                    return;
                }

                switch (mode)
                {
                    case "mutated-tensors":
                        tokens.InputIds[1] = 12;
                        break;
                    case "changed-assets":
                        File.AppendAllText(Path.Join(workspace.Root, "assets", "model.bin"), "tampered");
                        break;
                    case "changed-review":
                        File.AppendAllText(review, " ");
                        break;
                    case "changed-bank":
                        File.AppendAllText(bank, " ");
                        break;
                }
            };
        }

        string destination = Path.Join(workspace.Root, "diagnostics");
        Assert.ThrowsExactly<EvaluationContractException>(() =>
            GroundingReports.Evaluate(workspace.Root, bank, Path.Join(workspace.Root, "assets"), manifest,
                Path.Join(workspace.Root, "reviews"), review, destination, _ => backend), mode);

        Assert.IsTrue(backend.WasDisposed);
        Assert.IsFalse(Directory.Exists(destination));
    }

    /// <summary>
    ///  Asserts the public output keeps scores and reviewed diagnostic comparison distinct from qualification.
    /// </summary>
    /// <param name="json">The actual CLI result.</param>
    private static void AssertDiagnosticContract(string json)
    {
        System.Text.Json.JsonElement result = ContractJson.Parse(json);
        Assert.AreEqual("grounding-diagnostic", result.GetProperty("evidenceMode").GetString());
        Assert.AreEqual("explicit-development-probes-only", result.GetProperty("coverage").GetString());
        Assert.AreEqual(14, result.GetProperty("probeCount").GetInt32());
        Assert.AreEqual(0, result.GetProperty("usefulPassedCount").GetInt32());
        Assert.AreEqual("pending", result.GetProperty("usefulOutcome").GetString());
        Assert.AreEqual("pending", result.GetProperty("calibrationStatus").GetString());
        Assert.IsTrue(result.GetProperty("backend").GetProperty("synthetic").GetBoolean());
        Assert.AreEqual("synthetic-review-fixture", result.GetProperty("reviewEvidence")
            .GetProperty("authorityScope").GetString());

        Assert.IsTrue(result.GetProperty("probes").EnumerateArray().All(value =>
            value.GetProperty("qualityStatus").GetString() == "pending"));
    }

    /// <summary>
    ///  Gets independently invalid asset-manifest mutations, including raw-field presence and mapping states.
    /// </summary>
    public static IEnumerable<object[]> InvalidManifests
    {
        get
        {
            yield return ["missing-mode", (Action<JsonObject>)(node => node.Remove("mode"))];
            yield return ["unsupported-version", (Action<JsonObject>)(node => node["schemaVersion"] = 2)];
            yield return ["unknown-field", (Action<JsonObject>)(node => node["qualified"] = true)];
            yield return ["non-report-mode", (Action<JsonObject>)(node => node["mode"] = "blocking")];
            yield return ["overlong-limit", (Action<JsonObject>)(node => node["maximumTokens"] = 513)];
            yield return ["wrong-label-order", (Action<JsonObject>)(node =>
                node["labelOrder"] = new JsonArray("entailed", "contradicted", "neutral"))];

            yield return ["wrong-inputs", (Action<JsonObject>)(node =>
                node["inputNames"] = new JsonArray("input_ids", "attention_mask", "token_type_ids"))];

            yield return ["unpinned-runtime", (Action<JsonObject>)(node =>
                Object(node, "runtimeVersions")["onnxRuntime"] = "latest")];

            yield return ["duplicate-role", (Action<JsonObject>)(node =>
                Item(node, "files", 1)["role"] = "model")];

            yield return ["duplicate-path", (Action<JsonObject>)(node =>
                Item(node, "files", 1)["path"] = "model.bin")];

            yield return ["wrong-sha", (Action<JsonObject>)(node =>
                Item(node, "files", 0)["sha256"] = TestWorkspace.ScenarioRevision)];

            yield return ["wrong-size", (Action<JsonObject>)(node =>
                Item(node, "files", 0)["bytes"] = 1)];

            yield return ["escaped-path", (Action<JsonObject>)(node =>
                Item(node, "files", 0)["path"] = "../escaped.bin")];

            yield return ["moving-source", (Action<JsonObject>)(node =>
                Item(node, "files", 0)["source"] = "https://example.invalid/resolve/main/model.bin")];

            yield return ["missing-file-role", (Action<JsonObject>)(node =>
                Item(node, "files", 0)["role"] = "other")];
        }
    }

    /// <summary>
    ///  Verifies strict original manifest input and byte/source pins reject malformed declarations.
    /// </summary>
    /// <param name="name">The independent invalid control.</param>
    /// <param name="mutate">The mutation applied before schema validation.</param>
    [TestMethod]
    [DynamicData(nameof(InvalidManifests))]
    public void GroundingAssetsRejectsInvalidOriginalManifest(string name, Action<JsonObject> mutate)
    {
        using TestWorkspace workspace = new();
        string path = WriteSyntheticAssets(workspace);
        JsonObject document = JsonNode.Parse(File.ReadAllText(path)) as JsonObject
            ?? throw new InvalidOperationException("The synthetic manifest must be an object.");

        mutate(document);
        File.WriteAllText(path, document.ToJsonString(ContractJson.Options));
        Assert.ThrowsExactly<EvaluationContractException>(() =>
            GroundingAssets.Load(Path.Join(workspace.Root, "assets"), path), name);
    }

    /// <summary>
    ///  Gets incomplete, stale, borrowed, duplicate, and misquoted review judgments.
    /// </summary>
    public static IEnumerable<object[]> InvalidReviews
    {
        get
        {
            yield return ["incomplete-session", (Action<JsonObject>)(node => node["status"] = "in-progress")];
            yield return ["qualified-calibration", (Action<JsonObject>)(node => node["calibrationStatus"] = "passed")];
            yield return ["wrong-bank", (Action<JsonObject>)(node => node["bankId"] = "missing")];
            yield return ["stale-bank-revision", (Action<JsonObject>)(node =>
                node["bankRevision"] = TestWorkspace.ScenarioRevision)];

            yield return ["wrong-count", (Action<JsonObject>)(node => node["groundingDecisionCount"] = 13)];
            yield return ["unresolved", (Action<JsonObject>)(node => node["unresolved"] = new JsonArray("unresolved"))];
            yield return ["unknown-decision", (Action<JsonObject>)(node =>
                Item(node, "decisions", 0)["decisionKind"] = "judge")];

            yield return ["empty-response", (Action<JsonObject>)(node =>
                Item(node, "decisions", 0)["reviewerResponse"] = " ")];

            yield return ["invalid-time", (Action<JsonObject>)(node =>
                Item(node, "decisions", 0)["recordedAt"] = "not-a-time")];

            yield return ["wrong-case", (Action<JsonObject>)(node =>
                Item(node, "decisions", 0)["pairId"] = "pr-number")];

            yield return ["missing-label", (Action<JsonObject>)(node =>
                Array(Item(node, "decisions", 0), "labels").RemoveAt(0))];

            yield return ["duplicate-label", (Action<JsonObject>)(node =>
                Array(Item(node, "decisions", 0), "labels").Add(Label(node).DeepClone()))];

            yield return ["stale-artifact", (Action<JsonObject>)(node =>
                Label(node)["artifactRevision"] = TestWorkspace.ScenarioRevision)];

            yield return ["unknown-probe", (Action<JsonObject>)(node => Label(node)["probeId"] = "missing")];
            yield return ["invented-quote", (Action<JsonObject>)(node => Label(node)["claim"] = "This was never written.")];
            yield return ["borrowed-premise", (Action<JsonObject>)(node =>
                Label(node)["premise"] = "Linux validation passed.")];

            yield return ["borrowed-facts", (Action<JsonObject>)(node =>
                Label(node)["premiseFactRefs"] = new JsonArray("windows-tests"))];

            yield return ["implicit-relation", (Action<JsonObject>)(node => Label(node).Remove("verdict"))];
            yield return ["coerced-relation", (Action<JsonObject>)(node => Label(node)["verdict"] = "ENTAILED")];
        }
    }

    /// <summary>
    ///  Verifies a bad review stops before constructing or dispatching any classifier.
    /// </summary>
    /// <param name="name">The independent invalid review state.</param>
    /// <param name="mutate">The raw review mutation.</param>
    [TestMethod]
    [DynamicData(nameof(InvalidReviews))]
    public void GroundingRejectsInvalidReviewBeforeCreatingBackend(string name, Action<JsonObject> mutate)
    {
        using TestWorkspace workspace = new();
        string bank = workspace.WriteReviewBank();
        string manifest = WriteSyntheticAssets(workspace);
        string review = GroundingFixture.WriteReview(workspace, bank, mutate);
        bool constructed = false;
        string destination = Path.Join(workspace.Root, "diagnostics");
        Assert.ThrowsExactly<EvaluationContractException>(() =>
            GroundingReports.Evaluate(workspace.Root, bank, Path.Join(workspace.Root, "assets"), manifest,
                Path.Join(workspace.Root, "reviews"), review, destination, _ =>
                {
                    constructed = true;
                    return new FixtureGroundingBackend();
                }), name);

        Assert.IsFalse(constructed, name);
        Assert.IsFalse(Directory.Exists(destination), name);
    }

    /// <summary>
    ///  Verifies file hashes preserve the original raw-byte algorithm while streaming large inputs.
    /// </summary>
    [TestMethod]
    public void StreamingFileRevisionPreservesOriginalBytes()
    {
        using TestWorkspace workspace = new();
        byte[] bytes = new byte[1024 * 1024 + 7];
        new Random(17).NextBytes(bytes);
        string path = Path.Join(workspace.Root, "raw.bin");
        File.WriteAllBytes(path, bytes);
        Assert.AreEqual(ContractJson.HashBytes(bytes), ContractJson.HashFile(path));
    }

    /// <summary>
    ///  Verifies public pins are bundled but synthetic dummy assets are rejected before native loading.
    /// </summary>
    [TestMethod]
    public void PinnedCpuProfileDoesNotAcceptSyntheticRuntimeAssets()
    {
        GroundingAssetManifest profile = PinnedNliProfile.Read();
        Assert.AreEqual("cross-encoder/nli-deberta-v3-base", profile.ModelId);
        Assert.AreEqual("6c749ce3425cd33b46d187e45b92bbf96ee12ec7", profile.ModelRevision);
        Assert.AreEqual("apache-2.0", profile.License);
        Assert.AreEqual(8, profile.Files.Length);
        using TestWorkspace workspace = new();
        string manifest = WriteSyntheticAssets(workspace);
        VerifiedGroundingAssets assets = GroundingAssets.Load(Path.Join(workspace.Root, "assets"), manifest);
        Assert.ThrowsExactly<EvaluationContractException>(() => new CpuNliBackend(assets));
    }

    /// <summary>
    ///  Verifies package identity tolerates a commit suffix but never substitutes the assembly binding version.
    /// </summary>
    [TestMethod]
    public void TokenizerPinChecksPackageRatherThanAssemblyVersion()
    {
        PinnedNliProfile.RequireTokenizerPackageVersion("2.0.0", "2.0.0");
        PinnedNliProfile.RequireTokenizerPackageVersion(
            "2.0.0+efefa92f4486a43047c5b47618885a71bf7f0967", "2.0.0");

        Assert.ThrowsExactly<EvaluationContractException>(() =>
            PinnedNliProfile.RequireTokenizerPackageVersion("1.0.0.0", "2.0.0"));

        Assert.ThrowsExactly<EvaluationContractException>(() =>
            PinnedNliProfile.RequireTokenizerPackageVersion("2.0.1+different", "2.0.0"));

        Assert.ThrowsExactly<EvaluationContractException>(() =>
            PinnedNliProfile.RequireTokenizerPackageVersion(informationalVersion: null, expected: "2.0.0"));
    }

    /// <summary>
    ///  Verifies a checked receipt cannot borrow its revision while replacing manifest or path identities.
    /// </summary>
    /// <param name="mode">The independently forged receipt field.</param>
    [TestMethod]
    [DataRow("manifest")]
    [DataRow("paths")]
    public void VerifiedAssetsCannotBorrowIdentityForAlteredReceipt(string mode)
    {
        using TestWorkspace workspace = new();
        string manifest = WriteSyntheticAssets(workspace);
        VerifiedGroundingAssets original = GroundingAssets.Load(Path.Join(workspace.Root, "assets"), manifest);
        Dictionary<string, string> paths = new(StringComparer.Ordinal)
        {
            ["model"] = manifest,
            ["sentencepiece"] = original.Paths["sentencepiece"]
        };

        VerifiedGroundingAssets altered = mode == "manifest"
            ? original with { Manifest = original.Manifest with { ModelId = "borrowed-model" } }
            : original with { Paths = paths };

        Assert.ThrowsExactly<EvaluationContractException>(() => GroundingAssets.RequireUnchanged(altered));
    }

    /// <summary>
    ///  Gets an object property in a synthetic control.
    /// </summary>
    /// <param name="node">The owning object.</param>
    /// <param name="name">The required property.</param>
    /// <returns>The object.</returns>
    private static JsonObject Object(JsonObject node, string name) =>
        node[name] as JsonObject ?? throw new InvalidOperationException($"Fixture '{name}' must be an object.");

    /// <summary>
    ///  Gets an array property in a synthetic control.
    /// </summary>
    /// <param name="node">The owning object.</param>
    /// <param name="name">The required property.</param>
    /// <returns>The array.</returns>
    private static JsonArray Array(JsonObject node, string name) =>
        node[name] as JsonArray ?? throw new InvalidOperationException($"Fixture '{name}' must be an array.");

    /// <summary>
    ///  Gets an object-valued control array item.
    /// </summary>
    /// <param name="node">The owning object.</param>
    /// <param name="name">The array property.</param>
    /// <param name="index">The item index.</param>
    /// <returns>The object item.</returns>
    private static JsonObject Item(JsonObject node, string name, int index) =>
        Array(node, name)[index] as JsonObject ?? throw new InvalidOperationException("Fixture item must be an object.");

    /// <summary>
    ///  Gets the first explicitly declared synthetic grounding judgment.
    /// </summary>
    /// <param name="node">The review document.</param>
    /// <returns>The first label object.</returns>
    private static JsonObject Label(JsonObject node) => Item(Item(node, "decisions", 0), "labels", 0);

    /// <summary>
    ///  Creates the exact public manual CLI invocation, including completed review and report-only opt-in.
    /// </summary>
    /// <param name="workspace">The fixture owner.</param>
    /// <param name="bank">The owned bank path.</param>
    /// <param name="manifest">The owned manifest path.</param>
    /// <param name="review">The owned synthetic review path.</param>
    /// <param name="destination">The disjoint derived path.</param>
    /// <returns>The named command arguments.</returns>
    private static string[] Arguments(
        TestWorkspace workspace, string bank, string manifest, string review, string destination) =>
        [
            "ground", "--repo-root", workspace.Root, "--packets", bank,
            "--asset-root", Path.Join(workspace.Root, "assets"), "--manifest", manifest,
            "--review-owner", Path.Join(workspace.Root, "reviews"), "--review", review,
            "--output-directory", destination, "--report-only", "true"
        ];

    /// <summary>
    ///  Writes a synthetic two-file manifest; these dummy bytes are never accepted by the production NLI profile.
    /// </summary>
    /// <param name="workspace">The temporary fixture owner.</param>
    /// <returns>The owned manifest path.</returns>
    internal static string WriteSyntheticAssets(TestWorkspace workspace)
    {
        string root = Path.Join(workspace.Root, "assets");
        Directory.CreateDirectory(root);
        File.WriteAllText(Path.Join(root, "model.bin"), "Synthetic model bytes; not an ONNX graph.");
        File.WriteAllText(Path.Join(root, "tokens.bin"), "Synthetic tokenizer bytes; not a SentencePiece model.");
        GroundingAssetFile FilePin(string role, string path) => new(
            role, path, ContractJson.HashFile(Path.Join(root, path)),
            new FileInfo(Path.Join(root, path)).Length, "fixture:" + role);

        GroundingAssetManifest manifest = new(
            1, "synthetic-test-v1", "synthetic-fixture", new string('a', 40), "mit", "report-only",
            512, [GroundingRelation.Contradicted, GroundingRelation.Entailed, GroundingRelation.Neutral],
            ["input_ids", "attention_mask"], new("1.30.0", "2.0.0"),
            [FilePin("model", "model.bin"), FilePin("sentencepiece", "tokens.bin")]);

        string path = Path.Join(root, "manifest.json");
        ContractJson.WriteNew(path, manifest);
        return path;
    }
}
