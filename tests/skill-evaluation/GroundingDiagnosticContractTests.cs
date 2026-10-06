// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace SkillEvaluation.Tests;

/// <summary>
///  Verifies original diagnostic JSON cannot replace required provenance with empty or defaulted records.
/// </summary>
[TestClass]
public sealed class GroundingDiagnosticContractTests
{
    /// <summary>
    ///  Gets independently missing, unknown, malformed, and out-of-range diagnostic evidence.
    /// </summary>
    public static IEnumerable<object[]> InvalidDiagnostics
    {
        get
        {
            (string Name, Func<JsonObject, JsonObject> Select, string[] Fields)[] objects =
            [
                ("label", Label,
                    ["packetId", "probeId", "artifactRevision", "relation", "reviewerResponse", "decisionScope", "recordedAt"]),
                ("input", Input,
                    ["packetId", "probeId", "artifactRevision", "profileRevision", "inputRevision", "claim", "factRefs", "facts", "premise"]),
                ("claim", document => RequiredObject(Input(document)["claim"]), ["span", "quote"]),
                ("span", Span, ["start", "length", "line"]),
                ("fact", Fact, ["id", "text", "state", "kind", "provenance"])
            ];

            foreach ((string name, Func<JsonObject, JsonObject> select, string[] fields) in objects)
            {
                foreach (string property in fields)
                {
                    yield return [$"{name}-missing-{property}", (Action<JsonObject>)(document => select(document).Remove(property))];
                }

                yield return [$"{name}-empty", (Action<JsonObject>)(document => select(document).Clear())];
                yield return [$"{name}-unknown-field", (Action<JsonObject>)(document => select(document)["extra"] = true)];
            }

            yield return ["label-invalid-revision", (Action<JsonObject>)(document => Label(document)["artifactRevision"] = "stale")];
            yield return ["label-invalid-relation", (Action<JsonObject>)(document => Label(document)["relation"] = "passed")];
            yield return ["label-numeric-relation", (Action<JsonObject>)(document => Label(document)["relation"] = 0)];
            yield return ["label-empty-response", (Action<JsonObject>)(document => Label(document)["reviewerResponse"] = "")];
            yield return ["input-invalid-revision", (Action<JsonObject>)(document => Input(document)["inputRevision"] = "stale")];
            yield return ["input-empty-fact-refs", (Action<JsonObject>)(document => Input(document)["factRefs"] = new JsonArray())];
            yield return ["input-duplicate-fact-refs", (Action<JsonObject>)(document => Input(document)["factRefs"] = new JsonArray("fact", "fact"))];
            yield return ["input-empty-facts", (Action<JsonObject>)(document => Input(document)["facts"] = new JsonArray())];
            yield return ["span-negative-start", (Action<JsonObject>)(document => Span(document)["start"] = -1)];
            yield return ["span-zero-length", (Action<JsonObject>)(document => Span(document)["length"] = 0)];
            yield return ["span-zero-line", (Action<JsonObject>)(document => Span(document)["line"] = 0)];
            yield return ["span-overflow", (Action<JsonObject>)(document => Span(document)["start"] = 2147483648L)];
            yield return ["fact-invalid-state", (Action<JsonObject>)(document => Fact(document)["state"] = "accepted")];
            yield return ["fact-invalid-kind", (Action<JsonObject>)(document => Fact(document)["kind"] = "authority")];
            yield return ["fact-borrowed-provenance", (Action<JsonObject>)(document => Fact(document)["provenance"] = "model-output")];
            yield return ["empty-scores", (Action<JsonObject>)(document => Probe(document)["scores"] = new JsonObject())];
            yield return ["missing-raw-relation", (Action<JsonObject>)(document => Scores(document).Remove("rawRelation"))];
            yield return ["out-of-range-score", (Action<JsonObject>)(document => Scores(document)["neutral"] = 1.1)];
        }
    }

    /// <summary>
    ///  Verifies malformed source JSON fails before typed constructors can fill missing fields with defaults.
    /// </summary>
    /// <param name="name">The independent source mutation.</param>
    /// <param name="mutate">The mutation applied to the original JSON.</param>
    [TestMethod]
    [DynamicData(nameof(InvalidDiagnostics))]
    public void DiagnosticReadRejectsMalformedOriginalEvidence(string name, Action<JsonObject> mutate)
    {
        JsonObject document = Diagnostic();
        mutate(document);
        JsonElement original = ContractJson.Parse(document.ToJsonString(ContractJson.Options));
        Assert.ThrowsExactly<EvaluationContractException>(() =>
            ContractJson.Read<JsonElement>(original, "grounding-diagnostic.v1"), name);

        Assert.ThrowsExactly<EvaluationContractException>(() =>
            ContractJson.Read<GroundingDiagnosticSummary>(original, "grounding-diagnostic.v1"), name);
    }

    /// <summary>
    ///  Verifies valid evidence states and authority kinds remain valid, with tie abstention and no promotion.
    /// </summary>
    /// <param name="state">The source evidence state.</param>
    /// <param name="kind">The source fact or authority kind.</param>
    [TestMethod]
    [DataRow("verified", "fact")]
    [DataRow("inference", "ownership")]
    [DataRow("hypothesis", "commitment")]
    [DataRow("unknown", "permission")]
    public void DiagnosticReadPreservesValidEvidenceAndAbstention(string state, string kind)
    {
        JsonObject document = Diagnostic();
        Fact(document)["state"] = state;
        Fact(document)["kind"] = kind;
        GroundingDiagnosticSummary report = ContractJson.Read<GroundingDiagnosticSummary>(
            ContractJson.Parse(document.ToJsonString(ContractJson.Options)), "grounding-diagnostic.v1");

        Assert.AreEqual(QualityState.Pending, report.UsefulOutcome);
        Assert.AreEqual(QualityState.Pending, report.CalibrationStatus);
        Assert.AreEqual(0, report.UsefulPassedCount);
        Assert.IsNull(report.Probes[0].Scores.RawRelation);
        Assert.IsNull(report.Probes[0].MatchesReviewedRelation);
    }

    /// <summary>
    ///  Verifies diagnostic token bounds agree with the nonempty complete-pair runtime contract.
    /// </summary>
    /// <param name="count">The source token count.</param>
    /// <param name="valid">Whether the complete-pair boundary permits the count.</param>
    [TestMethod]
    [DataRow(4, false)]
    [DataRow(5, true)]
    [DataRow(512, true)]
    [DataRow(513, false)]
    public void DiagnosticReadEnforcesCompletePairTokenBounds(int count, bool valid)
    {
        JsonObject document = Diagnostic();
        Probe(document)["tokenCount"] = count;
        JsonElement original = ContractJson.Parse(document.ToJsonString(ContractJson.Options));
        if (valid)
        {
            Assert.AreEqual(count, ContractJson.Read<GroundingDiagnosticSummary>(
                original, "grounding-diagnostic.v1").Probes[0].TokenCount);
        }
        else
        {
            Assert.ThrowsExactly<EvaluationContractException>(() =>
                ContractJson.Read<JsonElement>(original, "grounding-diagnostic.v1"));
        }
    }

    /// <summary>
    ///  Creates a complete synthetic record without assets, private evidence, or a prediction backend.
    /// </summary>
    /// <returns>The original valid diagnostic JSON.</returns>
    private static JsonObject Diagnostic()
    {
        string revision = new('A', 64);
        PreparedGroundingProbe input = new("packet", "probe", revision, revision, revision,
            new(new(0, 6, 1), "Claim."), ["fact"],
            [new("fact", "Fact.", EvidenceState.Verified, FactKind.Fact, "scenario-input")], "Fact.");

        ReviewedGroundingLabel label = new("packet", "probe", revision, GroundingRelation.Neutral,
            "Synthetic approval.", "Synthetic evidence only.", "2026-10-05T00:00:00Z");

        GroundingDiagnosticSummary report = new(1, "grounding-diagnostic", "explicit-development-probes-only",
            "synthetic-bank", revision, revision, revision, "synthetic-model", new('a', 40),
            new("synthetic-backend", Synthetic: true, revision, "synthetic-runtime", "synthetic-tokenizer"),
            new("synthetic-session", revision, revision, "synthetic-review-fixture", [label]),
            1, 0, QualityState.Pending, QualityState.Pending,
            [new(input, 5, GroundingInference.Score(new(0, 0, 0)),
                QualityState.Pending, GroundingRelation.Neutral, MatchesReviewedRelation: null, 0)]);

        return JsonNode.Parse(ContractJson.Serialize(report)) as JsonObject
            ?? throw new InvalidOperationException("The synthetic diagnostic must be an object.");
    }

    private static JsonObject Label(JsonObject document) => RequiredObject(
        RequiredObject(document["reviewEvidence"])["labels"]?[0]);

    private static JsonObject Probe(JsonObject document) => RequiredObject(document["probes"]?[0]);

    private static JsonObject Input(JsonObject document) => RequiredObject(Probe(document)["input"]);

    private static JsonObject Span(JsonObject document) => RequiredObject(
        RequiredObject(Input(document)["claim"])["span"]);

    private static JsonObject Fact(JsonObject document) => RequiredObject(Input(document)["facts"]?[0]);

    private static JsonObject Scores(JsonObject document) => RequiredObject(Probe(document)["scores"]);

    private static JsonObject RequiredObject(JsonNode? node) => node as JsonObject
        ?? throw new InvalidOperationException("The synthetic evidence node must be an object.");
}
