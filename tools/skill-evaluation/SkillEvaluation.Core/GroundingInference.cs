// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  Enforces complete pair tensors and displays finite three-way scores without calibrated quality promotion.
/// </summary>
public static class GroundingInference
{
    /// <summary>
    ///  Rejects malformed, padded, noncanonical, or overlength pair tensors before dispatch.
    /// </summary>
    /// <param name="tokens">The full pair tensors.</param>
    /// <param name="maximumTokens">The manifest's explicit complete-pair limit.</param>
    public static void ValidateTokens(GroundingTokens tokens, int maximumTokens)
    {
        ArgumentNullException.ThrowIfNull(tokens);
        ArgumentNullException.ThrowIfNull(tokens.InputIds);
        ArgumentNullException.ThrowIfNull(tokens.AttentionMask);
        ArgumentNullException.ThrowIfNull(tokens.TokenTypeIds);
        int count = tokens.InputIds.Length;
        if (maximumTokens is < 5 or > 512
            || count < 5
            || count > maximumTokens
            || tokens.AttentionMask.Length != count
            || tokens.TokenTypeIds.Length != count
            || tokens.InputIds.Any(value => value is < 0 or > 128000)
            || tokens.AttentionMask.Any(value => value != 1)
            || tokens.InputIds[0] != 1
            || tokens.InputIds[^1] != 2)
        {
            throw new EvaluationContractException(
                "Grounding tensors are malformed or exceed the complete-pair token limit; truncation is forbidden.");
        }

        int second = Array.IndexOf(tokens.TokenTypeIds, 1);
        if (second < 3
            || second >= count - 1
            || tokens.InputIds[second - 1] != 2
            || tokens.TokenTypeIds[..second].Any(value => value != 0)
            || tokens.TokenTypeIds[second..].Any(value => value != 1))
        {
            throw new EvaluationContractException("Grounding pair special-token or segment-ID structure is invalid.");
        }
    }

    /// <summary>
    ///  Computes stable display softmax scores and preserves an exact tie as an unassessed raw relation.
    /// </summary>
    /// <param name="logits">The three raw classifier logits.</param>
    /// <returns>Finite uncalibrated display scores and the raw relation, never a quality verdict.</returns>
    public static GroundingScores Score(GroundingLogits logits)
    {
        ArgumentNullException.ThrowIfNull(logits);
        double[] values = [logits.Contradiction, logits.Entailment, logits.Neutral];
        if (values.Any(value => !double.IsFinite(value)))
        {
            throw new EvaluationContractException("Grounding classifier logits must be finite.");
        }

        double maximum = values.Max();
        double[] exponentials = values.Select(value => Math.Exp(value - maximum)).ToArray();
        double total = exponentials.Sum();
        double[] scores = exponentials.Select(value => value / total).ToArray();
        GroundingRelation? relation = values.Count(value => value == maximum) != 1
            ? null
            : Array.IndexOf(values, maximum) switch
            {
                0 => GroundingRelation.Contradicted,
                1 => GroundingRelation.Entailed,
                2 => GroundingRelation.Neutral,
                _ => throw new EvaluationContractException("A three-way grounding relation is required.")
            };

        return new(logits, scores[0], scores[1], scores[2], relation);
    }

    /// <summary>
    ///  Resolves explicit probe claims and authoritative fact premises from a validated development bank.
    /// </summary>
    /// <param name="bank">The immutable source-verified bank.</param>
    /// <returns>Every declared probe, with no sentence extraction, omission invention, or silent skip.</returns>
    public static PreparedGroundingProbe[] Prepare(ValidatedReviewPackets bank)
    {
        Dictionary<string, ValidatedScenario> scenarios = bank.Scenarios.ToDictionary(
            value => value.Id, StringComparer.Ordinal);

        List<PreparedGroundingProbe> result = [];
        foreach (ReviewPacket packet in bank.Bank.Packets)
        {
            ValidatedScenario scenario = scenarios[packet.ScenarioId];
            Dictionary<string, SuppliedFact> facts = scenario.Profile.SuppliedFacts.ToDictionary(
                value => value.Id, StringComparer.Ordinal);

            foreach (GroundingProbe probe in packet.GroundingProbes)
            {
                SuppliedFact[] selected = probe.FactRefs.Select(value => facts[value]).ToArray();
                result.Add(new(
                    packet.Id, probe.Id, packet.ArtifactRevision,
                    scenario.Preparation.ProfileRevision, scenario.Preparation.InputRevision,
                    ReviewPackets.ResolveEvidence(packet.ArtifactText, new("quote", probe.ClaimQuote)),
                    probe.FactRefs, selected, string.Join("\n", selected.Select(value => value.Text))));
            }
        }

        if (result.Count == 0)
        {
            throw new EvaluationContractException("No explicit grounding probes are declared; empty output is not a successful assessment.");
        }

        return result.ToArray();
    }
}
