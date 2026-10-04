// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json;
using System.Text.Json.Nodes;
using Markdig;
using Markdig.Syntax;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using SkillEvaluation.Cli;

namespace SkillEvaluation.Tests;

/// <summary>
///  Verifies review preparation never turns synthetic proposals into human or model qualification.
/// </summary>
[TestClass]
public sealed class ReviewPacketTests
{
    private const string BankRelativePath = "evals/fixtures/output-quality/review-packets.v1.json";

    /// <summary>
    ///  Verifies the public CLI counts paired cases separately and leaves review and calibration pending.
    /// </summary>
    [TestMethod]
    public void ValidateReviewPacketsReportsProposalsWithoutPromotingGroundTruth()
    {
        string root = TestWorkspace.FindRepositoryRoot();
        using StringWriter output = new();
        using StringWriter error = new();
        int exit = Program.Run([
            "validate-review-packets", "--repo-root", root,
            "--packets", BankRelativePath
        ], output, error);

        Assert.AreEqual(0, exit, error.ToString());
        JsonElement summary = ContractJson.Parse(output.ToString());
        Assert.AreEqual(ContractJson.HashFile(typeof(ReviewPackets).Assembly.Location),
            summary.GetProperty("engineRevision").GetString());

        Assert.IsFalse(string.IsNullOrWhiteSpace(summary.GetProperty("runtime").GetString()));
        Assert.AreEqual(16, summary.GetProperty("packetCount").GetInt32());
        Assert.AreEqual(8, summary.GetProperty("clusterCount").GetInt32());
        Assert.AreEqual(8, summary.GetProperty("scenarioCount").GetInt32());
        Assert.AreEqual(8, summary.GetProperty("prDescriptionCount").GetInt32());
        Assert.AreEqual(8, summary.GetProperty("reviewCommentCount").GetInt32());
        Assert.AreEqual(64, summary.GetProperty("proposedLabelCount").GetInt32());
        Assert.AreEqual(14, summary.GetProperty("groundingProbeCount").GetInt32());
        Assert.AreEqual(15, summary.GetProperty("literalPassedCount").GetInt32());
        Assert.AreEqual(1, summary.GetProperty("literalFailedCount").GetInt32());
        Assert.AreEqual(0, summary.GetProperty("humanReviewedCount").GetInt32());
        Assert.AreEqual("pending", summary.GetProperty("humanReviewStatus").GetString());
        Assert.AreEqual("pending", summary.GetProperty("calibrationStatus").GetString());
        Assert.AreEqual("", error.ToString());
    }

    /// <summary>
    ///  Gets independently invalid structural, evidence, and pairing mutations of the valid development bank.
    /// </summary>
    public static IEnumerable<object[]> InvalidBanks
    {
        get
        {
            yield return ["unsupported-version", (Action<JsonObject>)(node => node["schemaVersion"] = 2)];
            yield return ["sealed-role", (Action<JsonObject>)(node => node["datasetRole"] = "acceptance")];
            yield return ["human-authority", (Action<JsonObject>)(node => node["labelAuthority"] = "human-reviewed")];
            yield return ["invented-human-count", (Action<JsonObject>)(node => node["humanReviewedCount"] = 16)];
            yield return ["empty-packets", (Action<JsonObject>)(node => node["packets"] = new JsonArray())];
            yield return ["null-proposals", (Action<JsonObject>)(node =>
                Item(node, "packets", 0)["proposedLabels"] = null)];

            yield return ["duplicate-scenario", (Action<JsonObject>)(node =>
                Item(node, "scenarios", 1)["id"] = "pr-validation")];

            yield return ["duplicate-packet", (Action<JsonObject>)(node =>
                Item(node, "packets", 1)["id"] = "pr-validation-base")];

            yield return ["unknown-scenario", (Action<JsonObject>)(node =>
                Item(node, "packets", 0)["scenarioId"] = "missing")];

            yield return ["unknown-target", (Action<JsonObject>)(node =>
                Item(node, "packets", 0)["targetId"] = "missing")];

            yield return ["changed-artifact-pin", (Action<JsonObject>)(node =>
                Item(node, "packets", 0)["artifactRevision"] = TestWorkspace.ScenarioRevision)];

            yield return ["incorrect-literal-result", (Action<JsonObject>)(node =>
                Item(node, "packets", 0)["expectedLiteralStatus"] = "failed")];

            yield return ["missing-label", (Action<JsonObject>)(node =>
                Array(Item(node, "packets", 0), "proposedLabels").RemoveAt(0))];

            yield return ["duplicate-label", (Action<JsonObject>)(node =>
                Array(Item(node, "packets", 0), "proposedLabels").Add(Label(node, 0).DeepClone()))];

            yield return ["unknown-label", (Action<JsonObject>)(node => Label(node, 0)["itemId"] = "missing")];
            yield return ["unknown-fact", (Action<JsonObject>)(node =>
                Label(node, 0)["factRefs"] = new JsonArray("missing"))];

            yield return ["blank-rationale", (Action<JsonObject>)(node => Label(node, 0)["rationale"] = " ")];
            yield return ["empty-evidence", (Action<JsonObject>)(node =>
                Label(node, 0)["evidence"] = new JsonArray())];

            yield return ["invented-quote", (Action<JsonObject>)(node =>
                Label(node, 0)["evidence"] = JsonNode.Parse("""[{"scope":"quote","quote":"This never appeared."}]"""))];

            yield return ["ambiguous-quote", (Action<JsonObject>)(node =>
                Label(node, 10)["evidence"] = JsonNode.Parse("""[{"scope":"quote","quote":"Close"}]"""))];

            yield return ["bad-span", (Action<JsonObject>)(node =>
                Label(node, 0)["evidence"] = JsonNode.Parse("""[{"scope":"quote","quote":"Windows: 14 tests passed.","span":{"start":1,"length":24,"line":1}}]"""))];

            yield return ["unknown-probe-fact", (Action<JsonObject>)(node =>
                Item(Item(node, "packets", 0), "groundingProbes", 0)["factRefs"] = new JsonArray("missing"))];

            yield return ["empty-probe-premise", (Action<JsonObject>)(node =>
                Item(Item(node, "packets", 0), "groundingProbes", 0)["factRefs"] = new JsonArray())];

            yield return ["invalid-relation", (Action<JsonObject>)(node =>
                Item(Item(node, "packets", 0), "groundingProbes", 0)["proposedRelation"] = "not-support-as-contradiction")];

            yield return ["wrong-edit", (Action<JsonObject>)(node =>
                Object(Item(node, "pairs", 0), "edit")["afterText"] = "Linux validation is still pending.")];

            yield return ["missing-edit-quote", (Action<JsonObject>)(node =>
                Object(Item(node, "pairs", 0), "edit")["beforeQuote"] = "This never appeared.")];

            yield return ["unrelated-verdict-flip", (Action<JsonObject>)(node =>
                Label(node, 1, 3)["state"] = "failed")];

            yield return ["missing-hard-flip", (Action<JsonObject>)(node => Label(node, 1)["state"] = "passed")];
            yield return ["partial-flip-declaration", (Action<JsonObject>)(node =>
                Item(node, "pairs", 0)["changedItemIds"] = new JsonArray("grounded-authority"))];

            yield return ["reused-packet", (Action<JsonObject>)(node =>
                Item(node, "pairs", 1)["basePacketId"] = "pr-validation-base")];

            yield return ["unpaired-packet", (Action<JsonObject>)(node =>
            {
                JsonObject packet = Item(node, "packets", 0).DeepClone() as JsonObject
                    ?? throw new InvalidOperationException("The cloned packet must be an object.");

                packet["id"] = "unpaired";
                Array(node, "packets").Add(packet);
            })];

            yield return ["extra-twin-edit", (Action<JsonObject>)(node =>
            {
                JsonObject packet = Item(node, "packets", 1);
                string text = RequiredText(packet, "artifactText") + "An unrelated change.\n";
                packet["artifactText"] = text;
                packet["artifactRevision"] = ContractJson.HashText(text);
            })];

            yield return ["stale-rubric-pin", (Action<JsonObject>)(node =>
                Item(Object(Item(node, "scenarios", 0), "contentEvaluation"), "rubricRefs", 0)["revision"] =
                    TestWorkspace.ScenarioRevision)];

            yield return ["missing-artifact-kind", (Action<JsonObject>)(node =>
                Profile(node).Remove("artifactKind"))];

            yield return ["missing-fact-state", (Action<JsonObject>)(node =>
                Item(Profile(node), "suppliedFacts", 3).Remove("state"))];

            yield return ["missing-fact-kind", (Action<JsonObject>)(node =>
                Item(Profile(node), "suppliedFacts", 0).Remove("kind"))];

            yield return ["missing-ledger-mode", (Action<JsonObject>)(node =>
                Object(Profile(node), "ledger").Remove("mode"))];

            yield return ["missing-target-source", (Action<JsonObject>)(node =>
                Item(Profile(node), "artifactTargets", 0).Remove("source"))];

            yield return ["mistyped-fact-state-case", (Action<JsonObject>)(node =>
                Item(Profile(node), "suppliedFacts", 0)["state"] = "VERIFIED")];

            yield return ["forbidden-null-target-path", (Action<JsonObject>)(node =>
                Item(Profile(node), "artifactTargets", 0)["path"] = null)];
        }
    }

    /// <summary>
    ///  Gets both public commands for every invalid bank so validation and export fail independently.
    /// </summary>
    public static IEnumerable<object[]> InvalidBankCommands
    {
        get
        {
            foreach (object[] data in InvalidBanks)
            {
                foreach (string command in new[] { "validate-review-packets", "export-review-packets" })
                {
                    yield return [data[0], command, data[1]];
                }
            }
        }
    }

    /// <summary>
    ///  Verifies the public CLI rejects invalid control data rather than emitting a pending-shaped success.
    /// </summary>
    /// <param name="name">The independently invalid mutation identifier.</param>
    /// <param name="command">The public validation or export command.</param>
    /// <param name="mutate">The mutation applied to the otherwise valid bank.</param>
    [TestMethod]
    [DynamicData(nameof(InvalidBankCommands))]
    public void ReviewPacketCommandsRejectInvalidControls(string name, string command, Action<JsonObject> mutate)
    {
        using TestWorkspace workspace = new();
        string path = WriteFixture(workspace, mutate);
        string destination = Path.Join(workspace.Root, "derived");
        string[] arguments = [command, "--repo-root", workspace.Root, "--packets", path];
        if (command == "export-review-packets")
        {
            arguments = [.. arguments, "--output-directory", destination];
        }

        using StringWriter output = new();
        using StringWriter error = new();
        int exit = Program.Run(arguments, output, error);

        Assert.AreEqual(3, exit, name);
        Assert.AreEqual("", output.ToString(), name);
        Assert.Contains("Skill evaluation failed:", error.ToString(), name);
        Assert.IsFalse(error.ToString().Contains("Unsupported command", StringComparison.Ordinal), name);
        Assert.IsFalse(Directory.Exists(destination), name);
    }

    /// <summary>
    ///  Verifies duplicate JSON properties cannot bypass packet validation.
    /// </summary>
    [TestMethod]
    public void LoadRejectsDuplicateJsonProperties()
    {
        using TestWorkspace workspace = new();
        string path = WriteFixture(workspace);
        string text = File.ReadAllText(path).Replace(
            "\"schemaVersion\": 1,", "\"schemaVersion\": 1, \"schemaVersion\": 1,", StringComparison.Ordinal);

        File.WriteAllText(path, text);
        EvaluationContractException error = Assert.ThrowsExactly<EvaluationContractException>(() =>
            ReviewPackets.Load(workspace.Root, path));

        Assert.Contains("Duplicate JSON property", error.Message);
    }

    /// <summary>
    ///  Verifies evidence indexes UTF-16 source text, rejects a wrong line, and represents omissions honestly.
    /// </summary>
    [TestMethod]
    public void ResolveEvidenceUsesExactUtf16OffsetsAndWholeArtifactOmissions()
    {
        const string Text = "\U0001F642\nSupported claim.\n";
        PacketEvidence quote = ReviewPackets.ResolveEvidence(Text, new("quote", "Supported claim."));
        Assert.AreEqual(new EvidenceSpan(3, 16, 2), quote.Span);
        Assert.AreEqual("Supported claim.", quote.Quote);
        Assert.AreEqual(quote, ReviewPackets.ResolveEvidence(Text,
            new("quote", "Supported claim.", new(3, 16, 2))));

        Assert.ThrowsExactly<EvaluationContractException>(() => ReviewPackets.ResolveEvidence(
            Text, new("quote", "Supported claim.", new(3, 16, 1))));

        PacketEvidence omission = ReviewPackets.ResolveEvidence(Text, new("whole-artifact"));
        Assert.AreEqual(new EvidenceSpan(0, Text.Length, 1), omission.Span);
        Assert.AreEqual(Text, omission.Quote);
    }

    /// <summary>
    ///  Verifies export preserves source bytes and carries pending labels, facts, criteria, and resolved spans.
    /// </summary>
    [TestMethod]
    public void ExportReviewPacketsPreservesSourceAndPendingAuthority()
    {
        using TestWorkspace workspace = new();
        string path = WriteFixture(workspace);
        string before = ContractJson.HashFile(path);
        string destination = Path.Join(workspace.Root, "derived");
        using StringWriter output = new();
        using StringWriter error = new();
        int exit = Program.Run([
            "export-review-packets", "--repo-root", workspace.Root, "--packets", path,
            "--output-directory", destination
        ], output, error);

        Assert.AreEqual(0, exit, error.ToString());
        Assert.AreEqual(before, ContractJson.HashFile(path));
        JsonElement export = ContractJson.Parse(File.ReadAllText(Path.Join(destination, "review.json")));
        Assert.AreEqual("development", export.GetProperty("datasetRole").GetString());
        Assert.AreEqual("assistant-proposed", export.GetProperty("labelAuthority").GetString());
        Assert.AreEqual(0, export.GetProperty("summary").GetProperty("humanReviewedCount").GetInt32());
        Assert.AreEqual("pending", export.GetProperty("summary").GetProperty("calibrationStatus").GetString());
        Assert.AreEqual(16, export.GetProperty("packets").GetArrayLength());
        Assert.AreEqual(8, export.GetProperty("scenarios").GetArrayLength());
        JsonElement evidence = export.GetProperty("packets")[0].GetProperty("proposedLabels")[0]
            .GetProperty("evidence")[0];

        Assert.AreEqual(0, evidence.GetProperty("span").GetProperty("start").GetInt32());
        Assert.AreEqual(export.GetProperty("packets")[0].GetProperty("artifactText").GetString(),
            evidence.GetProperty("quote").GetString());

        string markdown = File.ReadAllText(Path.Join(destination, "review.md"));
        Assert.Contains("not independent human ground truth", markdown);
        Assert.Contains("base-case clusters: 8", markdown);
        FencedCodeBlock[] blocks = Markdown.Parse(markdown).Descendants().OfType<FencedCodeBlock>().ToArray();
        Assert.HasCount(38, blocks);
        string[] lines = markdown.Split('\n');
        Assert.IsTrue(blocks.All(value => value.Line > 0 && lines[value.Line - 1].Length == 0));
        Assert.IsFalse(markdown.EndsWith("\n\n", StringComparison.Ordinal));
        Assert.ThrowsExactly<EvaluationContractException>(() =>
            ReviewPacketReports.Export(workspace.Root, path, destination));
    }

    /// <summary>
    ///  Verifies literal displays cannot be terminated by a code fence contained in the source artifact.
    /// </summary>
    [TestMethod]
    public void ExportReviewPacketsPreservesQuotedCodeFences()
    {
        using TestWorkspace workspace = new();
        const string Extra = "\n````text\nQuoted code is not a new execution claim.\n````\n";
        string path = WriteFixture(workspace, node =>
        {
            foreach (int index in new[] { 0, 1 })
            {
                JsonObject packet = Item(node, "packets", index);
                string text = RequiredText(packet, "artifactText") + Extra;
                packet["artifactText"] = text;
                packet["artifactRevision"] = ContractJson.HashText(text);
            }
        });

        string destination = Path.Join(workspace.Root, "derived");
        _ = ReviewPacketReports.Export(workspace.Root, path, destination);
        MarkdownDocument markdown = Markdown.Parse(File.ReadAllText(Path.Join(destination, "review.md")));
        FencedCodeBlock[] blocks = markdown.Descendants().OfType<FencedCodeBlock>()
            .Where(value => value.Lines.ToString().Contains("Quoted code is not a new execution claim.", StringComparison.Ordinal))
            .ToArray();

        Assert.HasCount(2, blocks);
        Assert.IsTrue(blocks.All(value => value.OpeningFencedCharCount == 5 && value.ClosingFencedCharCount == 5));
    }

    /// <summary>
    ///  Verifies export refuses source overlap before creating any derived file.
    /// </summary>
    [TestMethod]
    public void ExportReviewPacketsRejectsSourceOverlap()
    {
        using TestWorkspace workspace = new();
        string path = WriteFixture(workspace);
        Assert.ThrowsExactly<EvaluationContractException>(() =>
            ReviewPacketReports.Export(workspace.Root, path, Path.Join(workspace.Root, "inputs", "derived")));

        Assert.IsFalse(Directory.Exists(Path.Join(workspace.Root, "inputs", "derived")));
    }

    /// <summary>
    ///  Copies the source-pinned public rubric closure and writes an isolated, optionally mutated bank.
    /// </summary>
    /// <param name="workspace">The temporary owner receiving the control data.</param>
    /// <param name="mutate">An optional independently defined invalid-input mutation.</param>
    /// <returns>The owned input-bank path.</returns>
    private static string WriteFixture(TestWorkspace workspace, Action<JsonObject>? mutate = null)
    {
        string root = TestWorkspace.FindRepositoryRoot();
        foreach (string relative in new[]
        {
            "evals/rubrics/technical-writing.v2.json",
            "skills/technical-writing/SKILL.md",
            "skills/technical-writing/artifact-patterns.md"
        })
        {
            string destination = OwnedPaths.Resolve(workspace.Root, relative, requireFile: false);
            string parent = Path.GetDirectoryName(destination)
                ?? throw new InvalidOperationException("Fixture files require a parent directory.");

            Directory.CreateDirectory(parent);
            File.Copy(OwnedPaths.Resolve(root, relative), destination);
        }

        JsonObject bank = JsonNode.Parse(File.ReadAllText(OwnedPaths.Resolve(root, BankRelativePath))) as JsonObject
            ?? throw new InvalidOperationException("The public packet fixture must be an object.");

        mutate?.Invoke(bank);
        string input = Path.Join(workspace.Root, "inputs");
        Directory.CreateDirectory(input);
        string path = Path.Join(input, "bank.json");
        File.WriteAllText(path, bank.ToJsonString(ContractJson.Options));
        return path;
    }

    /// <summary>
    ///  Gets an object-valued fixture property without unchecked casts.
    /// </summary>
    /// <param name="node">The owning fixture object.</param>
    /// <param name="name">The required property name.</param>
    /// <returns>The required object.</returns>
    private static JsonObject Object(JsonObject node, string name) =>
        node[name] as JsonObject ?? throw new InvalidOperationException($"Fixture '{name}' must be an object.");

    /// <summary>
    ///  Gets the first fixture scenario's original JSON profile for malformed-input controls.
    /// </summary>
    /// <param name="bank">The development bank to mutate.</param>
    /// <returns>The original profile object, before typed deserialization.</returns>
    private static JsonObject Profile(JsonObject bank) =>
        Object(Item(bank, "scenarios", 0), "contentEvaluation");

    /// <summary>
    ///  Gets an array-valued fixture property.
    /// </summary>
    /// <param name="node">The owning fixture object.</param>
    /// <param name="name">The required property name.</param>
    /// <returns>The required array.</returns>
    private static JsonArray Array(JsonObject node, string name) =>
        node[name] as JsonArray ?? throw new InvalidOperationException($"Fixture '{name}' must be an array.");

    /// <summary>
    ///  Gets an object from a fixture array.
    /// </summary>
    /// <param name="node">The owning fixture object.</param>
    /// <param name="name">The array property name.</param>
    /// <param name="index">The object index.</param>
    /// <returns>The required object.</returns>
    private static JsonObject Item(JsonObject node, string name, int index) =>
        Array(node, name)[index] as JsonObject ?? throw new InvalidOperationException("A fixture array item must be an object.");

    /// <summary>
    ///  Gets one proposed rubric-label object.
    /// </summary>
    /// <param name="bank">The packet bank.</param>
    /// <param name="packetIndex">The packet index.</param>
    /// <param name="labelIndex">The label index within the packet.</param>
    /// <returns>The proposed-label object.</returns>
    private static JsonObject Label(JsonObject bank, int packetIndex, int labelIndex = 0) =>
        Item(Item(bank, "packets", packetIndex), "proposedLabels", labelIndex);

    /// <summary>
    ///  Reads a required fixture string.
    /// </summary>
    /// <param name="node">The owning object.</param>
    /// <param name="name">The string property name.</param>
    /// <returns>The non-null string.</returns>
    private static string RequiredText(JsonObject node, string name) =>
        node[name]?.GetValue<string>() ?? throw new InvalidOperationException($"Fixture '{name}' must contain text.");
}
