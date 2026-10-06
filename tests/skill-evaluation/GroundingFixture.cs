// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace SkillEvaluation.Tests;

/// <summary>
///  Creates complete synthetic review evidence without reading private maintainer decisions.
/// </summary>
internal static class GroundingFixture
{
    /// <summary>
    ///  Creates a projection-compatible synthetic approval record bound to every declared source probe.
    /// </summary>
    /// <param name="workspace">The temporary owner.</param>
    /// <param name="bankPath">The isolated source bank path.</param>
    /// <param name="mutate">An optional explicitly invalid record mutation.</param>
    /// <returns>The owned synthetic review path.</returns>
    public static string WriteReview(TestWorkspace workspace, string bankPath, Action<JsonObject>? mutate = null)
    {
        ValidatedReviewPackets bank = ReviewPackets.Load(workspace.Root, bankPath);
        PreparedGroundingProbe[] probes = GroundingInference.Prepare(bank);
        object[] decisions = bank.Bank.Pairs.Select(pair => new
        {
            pairId = pair.Id,
            decisionKind = "grounding",
            reviewerResponse = "Synthetic fixture approval; not an actual human judgment.",
            recordedAt = "2026-01-01T00:00:00Z",
            decisionScope = "Synthetic contract fixture only.",
            labels = probes.Where(value => value.PacketId == pair.BasePacketId || value.PacketId == pair.TwinPacketId)
                .Select(value => new
                {
                    packetId = value.PacketId,
                    artifactRevision = value.ArtifactRevision,
                    probeId = value.ProbeId,
                    premiseFactRefs = value.FactRefs,
                    premise = value.Premise,
                    claim = value.Claim.Quote,
                    verdict = bank.Bank.Packets.Single(packet => packet.Id == value.PacketId)
                        .GroundingProbes.Single(probe => probe.Id == value.ProbeId).ProposedRelation
                }).ToArray()
        }).ToArray();

        string text = ContractJson.Serialize(new
        {
            schemaVersion = 1,
            sessionId = "synthetic-review",
            bankId = bank.Bank.Id,
            bankRevision = bank.Summary.SourceRevision,
            datasetRole = "development",
            reviewerRole = "synthetic-fixture-reviewer",
            status = "completed",
            humanReviewedArtifactCount = bank.Bank.Packets.Length,
            rubricDecisionCount = bank.Summary.ProposedLabelCount,
            groundingDecisionCount = probes.Length,
            calibrationStatus = "pending",
            decisions,
            unresolved = Array.Empty<object>()
        });

        JsonObject document = JsonNode.Parse(text) as JsonObject
            ?? throw new InvalidOperationException("Synthetic review must be an object.");

        mutate?.Invoke(document);
        string owner = Path.Join(workspace.Root, "reviews");
        Directory.CreateDirectory(owner);
        string path = Path.Join(owner, "review.json");
        File.WriteAllText(path, document.ToJsonString(ContractJson.Options));
        return path;
    }
}
