// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Text.Json;

namespace SkillEvaluation;

/// <summary>
///  Reads only the explicit grounding projection of a completed human development-review document.
/// </summary>
public static class GroundingHumanLabels
{
    /// <summary>
    ///  Rejects incomplete, stale, duplicate, misquoted, or borrowed judgments before any inference.
    /// </summary>
    /// <param name="owner">The ordinary directory owning the local review document.</param>
    /// <param name="path">The owned relative or absolute review path.</param>
    /// <param name="bank">The independently source-verified bank.</param>
    /// <param name="probes">Every explicitly declared source probe.</param>
    /// <returns>Complete declared human development judgments and the source document revision.</returns>
    public static GroundingReviewEvidence Load(
        string owner, string path, ValidatedReviewPackets bank, PreparedGroundingProbe[] probes)
    {
        string text = ArtifactStore.Decode(File.ReadAllBytes(GroundingAssets.ResolveOwned(owner, path)));
        JsonElement document = ContractJson.Read<JsonElement>(
            ContractJson.Parse(text), "grounding-review-projection.v1");

        if (ProfileValidator.RequiredString(document, "bankId") != bank.Bank.Id
            || ProfileValidator.RequiredString(document, "bankRevision") != bank.Summary.SourceRevision
            || !document.GetProperty("humanReviewedArtifactCount").TryGetInt32(out int artifactCount)
            || artifactCount != bank.Bank.Packets.Length
            || !document.GetProperty("rubricDecisionCount").TryGetInt32(out int rubricCount)
            || rubricCount != bank.Summary.ProposedLabelCount
            || !document.GetProperty("groundingDecisionCount").TryGetInt32(out int probeCount)
            || probeCount != probes.Length)
        {
            throw new EvaluationContractException("Human review identity or declared completeness differs from the source bank.");
        }

        Dictionary<string, PreparedGroundingProbe> expected = probes.ToDictionary(
            value => value.PacketId + ":" + value.ProbeId, StringComparer.Ordinal);

        Dictionary<string, ReviewPacketPair> pairs = bank.Bank.Pairs.ToDictionary(
            value => value.Id, StringComparer.Ordinal);

        HashSet<string> keys = new(StringComparer.Ordinal);
        List<ReviewedGroundingLabel> labels = [];
        foreach (JsonElement decision in document.GetProperty("decisions").EnumerateArray())
        {
            if (decision.GetProperty("decisionKind").GetString() == "rubric")
            {
                continue;
            }

            string pairId = ProfileValidator.RequiredString(decision, "pairId");
            if (!pairs.TryGetValue(pairId, out ReviewPacketPair? pair))
            {
                throw new EvaluationContractException("Human grounding decision references an unknown case pair.");
            }

            string response = ProfileValidator.RequiredString(decision, "reviewerResponse");
            string scope = ProfileValidator.RequiredString(decision, "decisionScope");
            string recorded = ProfileValidator.RequiredString(decision, "recordedAt");
            if (!DateTimeOffset.TryParse(recorded, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out _))
            {
                throw new EvaluationContractException("Human grounding decision requires an explicit valid timestamp.");
            }

            foreach (JsonElement label in decision.GetProperty("labels").EnumerateArray())
            {
                string packetId = ProfileValidator.RequiredString(label, "packetId");
                string probeId = ProfileValidator.RequiredString(label, "probeId");
                string key = packetId + ":" + probeId;
                if (!keys.Add(key)
                    || !expected.TryGetValue(key, out PreparedGroundingProbe? input)
                    || (packetId != pair.BasePacketId && packetId != pair.TwinPacketId))
                {
                    throw new EvaluationContractException("Human grounding labels are duplicate, unknown, or attached to the wrong case.");
                }

                JsonElement facts = label.TryGetProperty("premiseFactRefs", out JsonElement localFacts)
                    ? localFacts
                    : decision.TryGetProperty("premiseFactRefs", out JsonElement inheritedFacts)
                        ? inheritedFacts
                        : throw new EvaluationContractException("Human grounding judgment lacks its premise fact references.");

                string[] references = facts.EnumerateArray().Select(value =>
                    value.GetString() ?? throw new EvaluationContractException("Human fact references must be strings.")).ToArray();

                string premise = label.TryGetProperty("premise", out JsonElement localPremise)
                    ? localPremise.GetString() ?? throw new EvaluationContractException("A human premise must be text.")
                    : ProfileValidator.RequiredString(decision, "premise");

                if (ProfileValidator.RequiredString(label, "artifactRevision") != input.ArtifactRevision
                    || ProfileValidator.RequiredString(label, "claim") != input.Claim.Quote
                    || !references.SequenceEqual(input.FactRefs)
                    || premise != input.Premise)
                {
                    throw new EvaluationContractException("Human grounding judgment does not bind the exact artifact, quote, and facts.");
                }

                GroundingRelation relation = label.GetProperty("verdict").GetString() switch
                {
                    "entailed" => GroundingRelation.Entailed,
                    "contradicted" => GroundingRelation.Contradicted,
                    "neutral" => GroundingRelation.Neutral,
                    _ => throw new EvaluationContractException("An explicit three-way human relation is required.")
                };

                labels.Add(new(packetId, probeId, input.ArtifactRevision, relation, response, scope, recorded));
            }
        }

        if (labels.Count != probes.Length || !keys.SetEquals(expected.Keys))
        {
            throw new EvaluationContractException("The completed human grounding record is incomplete for the selected bank.");
        }

        string authority = ProfileValidator.RequiredString(document, "reviewerRole") == "synthetic-fixture-reviewer"
            ? "synthetic-review-fixture" : "declared-human-reviewed-development";

        return new(ProfileValidator.RequiredString(document, "sessionId"), ContractJson.HashText(text),
            bank.Summary.SourceRevision, authority, labels.ToArray());
    }
}
