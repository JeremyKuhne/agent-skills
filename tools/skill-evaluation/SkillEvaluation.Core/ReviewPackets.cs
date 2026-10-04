// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Runtime.InteropServices;
using System.Text.Json;

namespace SkillEvaluation;

/// <summary>
///  Validates development controls without asserting human labels, classifier accuracy, or useful success.
/// </summary>
public static class ReviewPackets
{
    /// <summary>
    ///  Loads a strict owned packet bank and verifies profiles, evidence, literal results, and paired edits.
    /// </summary>
    /// <param name="repoRoot">The directory owning the bank and its rubric closure.</param>
    /// <param name="packetPath">The root-relative or owned absolute packet-bank path.</param>
    /// <returns>The validated development controls and pending preparation receipt.</returns>
    public static ValidatedReviewPackets Load(string repoRoot, string packetPath)
    {
        string path = ResolveBankPath(repoRoot, packetPath);
        string text = ArtifactStore.Decode(File.ReadAllBytes(path));
        JsonElement document = ContractJson.Parse(text);
        ReviewPacketBank bank = ContractJson.Read<ReviewPacketBank>(document, "review-packets.v1");

        ProfileValidator.UniqueIds(bank.Scenarios.Select(value => value.Id), "review scenario");
        ProfileValidator.UniqueIds(bank.Packets.Select(value => value.Id), "review packet");
        ProfileValidator.UniqueIds(bank.Pairs.Select(value => value.Id), "case cluster");

        ValidatedScenario[] scenarios = document.GetProperty("scenarios").EnumerateArray()
            .Select(value => ProfileValidator.Validate(value, repoRoot)
                ?? throw new EvaluationContractException("Review scenarios require declared content profiles.")).ToArray();

        Dictionary<string, ValidatedScenario> byScenario = scenarios.ToDictionary(value => value.Id, StringComparer.Ordinal);
        Dictionary<string, ReviewPacket> packets = bank.Packets.ToDictionary(value => value.Id, StringComparer.Ordinal);
        foreach (ReviewPacket packet in bank.Packets)
        {
            if (!byScenario.TryGetValue(packet.ScenarioId, out ValidatedScenario? scenario))
            {
                throw new EvaluationContractException($"Unknown review scenario '{packet.ScenarioId}'.");
            }

            ValidatePacket(packet, scenario);
        }

        HashSet<string> pairedPackets = new(StringComparer.Ordinal);
        HashSet<string> pairedScenarios = new(StringComparer.Ordinal);
        foreach (ReviewPacketPair pair in bank.Pairs)
        {
            if (!packets.TryGetValue(pair.BasePacketId, out ReviewPacket? original)
                || !packets.TryGetValue(pair.TwinPacketId, out ReviewPacket? twin)
                || !pairedPackets.Add(original.Id)
                || !pairedPackets.Add(twin.Id))
            {
                throw new EvaluationContractException("Every case pair requires two known, exclusively paired packets.");
            }

            if (original.ScenarioId != twin.ScenarioId
                || original.TargetId != twin.TargetId
                || !pairedScenarios.Add(original.ScenarioId))
            {
                throw new EvaluationContractException("Each cluster requires unchanged inputs and its own distinct scenario.");
            }

            ValidatePair(pair, original, twin, byScenario[original.ScenarioId]);
        }

        if (pairedPackets.Count != packets.Count || pairedScenarios.Count != scenarios.Length)
        {
            throw new EvaluationContractException("Unpaired packets or unused review scenarios are not permitted.");
        }

        string location = typeof(ReviewPackets).Assembly.Location;
        if (string.IsNullOrWhiteSpace(location))
        {
            throw new EvaluationContractException("The preparation engine requires a hashable assembly identity.");
        }

        string engineRevision = ContractJson.HashFile(location);
        string runtime = RuntimeInformation.FrameworkDescription;
        ReviewPacketSummary summary = new(
            bank.Id, ContractJson.HashText(text), engineRevision, runtime,
            ContractJson.Revision(new
            {
                engine = engineRevision,
                runtime,
                bank,
                profiles = scenarios.Select(value => value.Preparation).ToArray()
            }),
            bank.Packets.Length, bank.Pairs.Length, scenarios.Length,
            bank.Packets.Count(value => byScenario[value.ScenarioId].Profile.ArtifactKind == ArtifactKind.PrDescription),
            bank.Packets.Count(value => byScenario[value.ScenarioId].Profile.ArtifactKind == ArtifactKind.ReviewComment),
            bank.Packets.Sum(value => value.ProposedLabels.Length),
            bank.Packets.Sum(value => value.GroundingProbes.Length),
            bank.Packets.Count(value => value.ExpectedLiteralStatus == QualityState.Passed),
            bank.Packets.Count(value => value.ExpectedLiteralStatus == QualityState.Failed),
            0, QualityState.Pending, QualityState.Pending);

        return new(bank, scenarios, summary);
    }

    /// <summary>
    ///  Resolves one exact evidence witness and rejects ambiguous quotations or mismatched supplied spans.
    /// </summary>
    /// <param name="text">The artifact's decoded source text.</param>
    /// <param name="evidence">The declared quotation or whole-artifact witness.</param>
    /// <returns>The exact quote and independently computed UTF-16 location.</returns>
    public static PacketEvidence ResolveEvidence(string text, ReviewEvidence evidence)
    {
        PacketEvidence resolved = evidence.Scope switch
        {
            "whole-artifact" when evidence.Quote is null && text.Length > 0 =>
                new(new(0, text.Length, 1), text),
            "quote" when !string.IsNullOrWhiteSpace(evidence.Quote) => LocateQuote(text, evidence.Quote),
            _ => throw new EvaluationContractException("A nonempty whole artifact or exact quoted witness is required.")
        };

        if (evidence.Span is not null && evidence.Span != resolved.Span)
        {
            throw new EvaluationContractException("Evidence span does not match the exact source quotation.");
        }

        return resolved;
    }

    /// <summary>
    ///  Resolves a bank path within its owner without following links.
    /// </summary>
    /// <param name="repoRoot">The owner of the packet bank.</param>
    /// <param name="packetPath">The relative or owned absolute bank path.</param>
    /// <returns>The absolute ordinary-file path.</returns>
    internal static string ResolveBankPath(string repoRoot, string packetPath)
    {
        string root = Path.GetFullPath(repoRoot);
        string absolute = Path.GetFullPath(packetPath, root);
        return OwnedPaths.Resolve(root, Path.GetRelativePath(root, absolute));
    }

    /// <summary>
    ///  Verifies one packet's declared target, artifact revision, complete proposals, and explicit probes.
    /// </summary>
    /// <param name="packet">The synthetic packet to check.</param>
    /// <param name="scenario">The source-verified profile governing it.</param>
    private static void ValidatePacket(ReviewPacket packet, ValidatedScenario scenario)
    {
        if (scenario.Profile.ArtifactKind is not (ArtifactKind.PrDescription or ArtifactKind.ReviewComment)
            || scenario.Profile.Ledger.Mode != LedgerMode.Off
            || scenario.Profile.ArtifactTargets.Length != 1
            || scenario.Profile.ArtifactTargets[0].Id != packet.TargetId
            || scenario.RubricItems.Length == 0)
        {
            throw new EvaluationContractException("Review controls require one natural writing target and an applicable rubric.");
        }

        if (ContractJson.HashText(packet.ArtifactText) != packet.ArtifactRevision)
        {
            throw new EvaluationContractException($"Review artifact revision changed: '{packet.Id}'.");
        }

        CheckResult[] checks = LiteralEvaluator.Evaluate(packet.ArtifactText, packet.TargetId, scenario.Profile);
        QualityState literal = checks.Any(value => value.State == QualityState.Failed)
            ? QualityState.Failed : QualityState.Passed;

        if (checks.Length == 0 || literal != packet.ExpectedLiteralStatus)
        {
            throw new EvaluationContractException($"Declared literal result is incorrect: '{packet.Id}'.");
        }

        ProfileValidator.UniqueIds(packet.ProposedLabels.Select(value => value.ItemId), "proposed rubric item");
        HashSet<string> rubricIds = scenario.RubricItems.Select(value => value.Id).ToHashSet(StringComparer.Ordinal);
        if (!rubricIds.SetEquals(packet.ProposedLabels.Select(value => value.ItemId)))
        {
            throw new EvaluationContractException("Proposed labels must cover every applicable item exactly once.");
        }

        HashSet<string> facts = scenario.Profile.SuppliedFacts.Select(value => value.Id).ToHashSet(StringComparer.Ordinal);
        foreach (ProposedRubricLabel label in packet.ProposedLabels)
        {
            if (string.IsNullOrWhiteSpace(label.Rationale))
            {
                throw new EvaluationContractException("A proposed label requires a reviewable rationale.");
            }

            ValidateFacts(facts, label.FactRefs);
            foreach (ReviewEvidence evidence in label.Evidence)
            {
                _ = ResolveEvidence(packet.ArtifactText, evidence);
            }
        }

        ProfileValidator.UniqueIds(packet.GroundingProbes.Select(value => value.Id), "grounding probe");
        foreach (GroundingProbe probe in packet.GroundingProbes)
        {
            ValidateFacts(facts, probe.FactRefs);
            _ = ResolveEvidence(packet.ArtifactText, new("quote", probe.ClaimQuote));
        }
    }

    /// <summary>
    ///  Requires unique, known fact identifiers rather than silently omitting unresolved premises.
    /// </summary>
    /// <param name="facts">The authoritative supplied-fact identifiers.</param>
    /// <param name="references">The requested fact identifiers.</param>
    private static void ValidateFacts(HashSet<string> facts, string[] references)
    {
        ProfileValidator.UniqueIds(references, "review fact reference");
        if (references.Any(value => !facts.Contains(value)))
        {
            throw new EvaluationContractException("A review label or probe references an unknown supplied fact.");
        }
    }

    /// <summary>
    ///  Requires a literal single edit and exactly the declared hard-item verdict flips.
    /// </summary>
    /// <param name="pair">The case-cluster edit and defect declaration.</param>
    /// <param name="original">The proposed valid base packet.</param>
    /// <param name="twin">The declared defect twin.</param>
    /// <param name="scenario">The unchanged source profile for both artifacts.</param>
    private static void ValidatePair(
        ReviewPacketPair pair, ReviewPacket original, ReviewPacket twin, ValidatedScenario scenario)
    {
        string edited;
        if (pair.Edit.Kind == PacketEditKind.Append)
        {
            edited = original.ArtifactText + pair.Edit.AfterText;
        }
        else
        {
            string quote = pair.Edit.BeforeQuote
                ?? throw new EvaluationContractException("A replacement edit requires its exact source quotation.");

            PacketEvidence location = LocateQuote(original.ArtifactText, quote);
            edited = original.ArtifactText.Remove(location.Span.Start, location.Span.Length)
                .Insert(location.Span.Start, pair.Edit.AfterText);
        }

        if (edited != twin.ArtifactText || original.ArtifactText == twin.ArtifactText)
        {
            throw new EvaluationContractException("The declared single edit must reproduce a distinct twin exactly.");
        }

        Dictionary<string, ProposedRubricLabel> before = original.ProposedLabels.ToDictionary(
            value => value.ItemId, StringComparer.Ordinal);

        Dictionary<string, ProposedRubricLabel> after = twin.ProposedLabels.ToDictionary(
            value => value.ItemId, StringComparer.Ordinal);

        HashSet<string> hard = scenario.RubricItems.Where(value => value.HardGate)
            .Select(value => value.Id).ToHashSet(StringComparer.Ordinal);

        if (original.ExpectedLiteralStatus != QualityState.Passed
            || hard.Count == 0
            || hard.Any(value => before[value].State != QualityState.Passed))
        {
            throw new EvaluationContractException("A base control must propose every hard item passing and pass its literal checks.");
        }

        ProfileValidator.UniqueIds(pair.ChangedItemIds, "changed rubric item");
        if (pair.ChangedItemIds.Any(value => !hard.Contains(value)
            || before[value].State != QualityState.Passed
            || after[value].State != QualityState.Failed))
        {
            throw new EvaluationContractException("Declared defect items must be applicable hard pass-to-fail flips.");
        }

        HashSet<string> changed = before.Keys.Where(value => before[value].State != after[value].State)
            .ToHashSet(StringComparer.Ordinal);

        if (!changed.SetEquals(pair.ChangedItemIds))
        {
            throw new EvaluationContractException("Unrelated item verdicts changed or declared flips are missing.");
        }
    }

    /// <summary>
    ///  Finds a unique exact quotation and computes its source line using UTF-16 offsets.
    /// </summary>
    /// <param name="text">The source artifact text.</param>
    /// <param name="quote">The nonempty quotation to locate.</param>
    /// <returns>The exact quotation and source location.</returns>
    private static PacketEvidence LocateQuote(string text, string quote)
    {
        if (string.IsNullOrWhiteSpace(quote))
        {
            throw new EvaluationContractException("An exact nonempty quotation is required.");
        }

        int start = text.IndexOf(quote, StringComparison.Ordinal);
        if (start < 0 || text.IndexOf(quote, start + 1, StringComparison.Ordinal) >= 0)
        {
            throw new EvaluationContractException("Evidence quotation is missing or ambiguous in the artifact.");
        }

        return new(new(start, quote.Length, 1 + text.AsSpan(0, start).Count('\n')), quote);
    }
}
