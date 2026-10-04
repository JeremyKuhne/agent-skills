// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;
using Touki.Text;

namespace SkillEvaluation;

/// <summary>
///  Exports proposed development controls for a bounded human review without modifying their source.
/// </summary>
public static class ReviewPacketReports
{
    /// <summary>
    ///  Writes a revision-bound JSON packet and readable Markdown to a separate, empty output directory.
    /// </summary>
    /// <param name="repoRoot">The directory owning the source bank and rubric closure.</param>
    /// <param name="packetPath">The root-relative or owned absolute development-bank path.</param>
    /// <param name="outputDirectory">The absent or empty directory receiving the review packet.</param>
    /// <returns>The pending preparation receipt, with no model invocation or human-label promotion.</returns>
    public static ReviewPacketSummary Export(string repoRoot, string packetPath, string outputDirectory)
    {
        string source = ReviewPackets.ResolveBankPath(repoRoot, packetPath);
        string parent = Path.GetDirectoryName(source)
            ?? throw new EvaluationContractException("The packet bank requires an owning directory.");

        OwnedPaths.RequireSeparateOutput(parent, outputDirectory);
        ValidatedReviewPackets validated = ReviewPackets.Load(repoRoot, source);
        Dictionary<string, ValidatedScenario> scenarios = validated.Scenarios.ToDictionary(
            value => value.Id, StringComparer.Ordinal);

        object[] packets = validated.Bank.Packets.Select(value => new
        {
            value.Id,
            value.ScenarioId,
            value.TargetId,
            value.ArtifactText,
            value.ArtifactRevision,
            value.ExpectedLiteralStatus,
            proposedLabels = value.ProposedLabels.Select(label => new
            {
                label.ItemId,
                label.State,
                label.Rationale,
                label.FactRefs,
                evidence = label.Evidence.Select(evidence =>
                    ReviewPackets.ResolveEvidence(value.ArtifactText, evidence)).ToArray()
            }).ToArray(),
            groundingProbes = value.GroundingProbes.Select(probe => new
            {
                probe.Id,
                probe.FactRefs,
                probe.ProposedRelation,
                claim = ReviewPackets.ResolveEvidence(value.ArtifactText, new("quote", probe.ClaimQuote))
            }).ToArray()
        }).ToArray();

        string markdown = RenderMarkdown(validated, scenarios);
        ValidatedReviewPackets current = ReviewPackets.Load(repoRoot, source);
        if (current.Summary.Revision != validated.Summary.Revision
            || current.Summary.SourceRevision != validated.Summary.SourceRevision)
        {
            throw new EvaluationContractException("Review inputs changed during export.");
        }

        Directory.CreateDirectory(outputDirectory);
        ContractJson.WriteNew(Path.Join(outputDirectory, "review.json"), new
        {
            validated.Summary,
            validated.Bank.DatasetRole,
            validated.Bank.LabelAuthority,
            scenarios = validated.Scenarios.Select(value => new
            {
                value.Id,
                value.Preparation.Prompt,
                value.Preparation.InputRevision,
                value.Preparation.ProfileRevision,
                facts = value.Profile.SuppliedFacts,
                rubricItems = value.RubricItems
            }).ToArray(),
            packets,
            validated.Bank.Pairs
        });

        using FileStream stream = new(Path.Join(outputDirectory, "review.md"),
            FileMode.CreateNew, FileAccess.Write, FileShare.None);

        stream.Write(Encoding.UTF8.GetBytes(markdown));
        return validated.Summary;
    }

    /// <summary>
    ///  Renders the reviewer's task, source inputs, criteria, artifacts, and explicitly proposed labels.
    /// </summary>
    /// <param name="validated">The source-verified development bank.</param>
    /// <param name="scenarios">The resolved scenario inputs indexed by identifier.</param>
    /// <returns>LF-normalized Markdown that does not claim completed human review.</returns>
    private static string RenderMarkdown(
        ValidatedReviewPackets validated, Dictionary<string, ValidatedScenario> scenarios)
    {
        ValueStringBuilder text = new(stackalloc char[512]);
        try
        {
            text.AppendLine("# Proposed output-quality review packets");
            text.AppendLine();
            text.AppendLine("Development controls only. Labels below are assistant-proposed, not independent human ground truth.");
            text.AppendLine("No classifier or judge inference was performed. Human review and calibration remain pending.");
            text.AppendLine("This export contains expected labels; do not use it as a blinded judge prompt or sealed acceptance set.");
            text.AppendLine();
            text.AppendLine($"- Bank: `{validated.Bank.Id}`");
            text.AppendLine($"- Source revision: `{validated.Summary.SourceRevision}`");
            text.AppendLine($"- Engine revision: `{validated.Summary.EngineRevision}`");
            text.AppendLine($"- Runtime: `{validated.Summary.Runtime}`");
            text.AppendLine($"- Preparation revision: `{validated.Summary.Revision}`");
            text.AppendLine($"- Artifacts: {validated.Summary.PacketCount}; base-case clusters: {validated.Summary.ClusterCount}.");
            text.AppendLine("- Planned initial review window: 30-60 minutes; no minutes have been recorded by this export.");
            text.AppendLine("- Review each proposed verdict and relation. Record corrections, source-backed reasons, unresolved labels, and actual minutes separately.");
            text.AppendLine();

            Dictionary<string, ReviewPacket> packets = validated.Bank.Packets.ToDictionary(
                value => value.Id, StringComparer.Ordinal);

            foreach (ReviewPacketPair pair in validated.Bank.Pairs)
            {
                ReviewPacket original = packets[pair.BasePacketId];
                ReviewPacket twin = packets[pair.TwinPacketId];
                ValidatedScenario scenario = scenarios[original.ScenarioId];
                text.AppendLine($"## {pair.Id}");
                text.AppendLine();
                text.AppendLine($"Family: `{scenario.Profile.ArtifactKind}`. Proposed defect: `{pair.DefectKind}`.");
                text.AppendLine($"Proposed hard-item flips: {string.Join(", ", pair.ChangedItemIds)}.");
                text.AppendLine();
                text.AppendLine("### Task and supplied evidence");
                text.AppendLine();
                text.Append(RenderLiteral(scenario.Preparation.Prompt));
                text.AppendLine("### Applicable criteria");
                text.AppendLine();
                foreach (RubricItem item in scenario.RubricItems)
                {
                    text.AppendLine($"- `{item.Id}` ({(item.HardGate ? "hard" : "advisory")}): {item.PassCondition}");
                    text.AppendLine($"  Failure: {item.FailCondition}");
                }

                text.AppendLine();
                text.Append(RenderPacket(original));
                text.Append(RenderPacket(twin));
            }

            return text.ToString().Replace("\r\n", "\n", StringComparison.Ordinal).TrimEnd('\n') + "\n";
        }
        finally
        {
            text.Dispose();
        }
    }

    /// <summary>
    ///  Renders one artifact with literal status and proposed item/probe evidence for review.
    /// </summary>
    /// <param name="packet">The synthetic artifact and assistant-proposed labels.</param>
    /// <returns>The artifact and its explicitly proposed review evidence as Markdown.</returns>
    private static string RenderPacket(ReviewPacket packet)
    {
        using ValueStringBuilder text = new(stackalloc char[256]);
        text.AppendLine($"### {packet.Id}");
        text.AppendLine();
        text.AppendLine($"Artifact revision: `{packet.ArtifactRevision}`. Literal checks only: `{packet.ExpectedLiteralStatus}`.");
        text.AppendLine();
        text.Append(RenderLiteral(packet.ArtifactText));
        foreach (ProposedRubricLabel label in packet.ProposedLabels)
        {
            text.AppendLine($"- Proposed `{label.ItemId}`: `{label.State}`.");
            text.AppendLine($"  Reason: {label.Rationale}");
            text.AppendLine($"  Supplied facts: {(label.FactRefs.Length == 0 ? "none needed for this advisory proposal" : string.Join(", ", label.FactRefs))}.");
            foreach (ReviewEvidence witness in label.Evidence)
            {
                PacketEvidence evidence = ReviewPackets.ResolveEvidence(packet.ArtifactText, witness);
                text.AppendLine($"  Evidence: `{witness.Scope}`, UTF-16 offset {evidence.Span.Start}, length {evidence.Span.Length}, line {evidence.Span.Line}.");
            }
        }

        text.AppendLine();
        foreach (GroundingProbe probe in packet.GroundingProbes)
        {
            text.AppendLine($"Proposed probe `{probe.Id}`: `{probe.ProposedRelation}`; premise facts: {string.Join(", ", probe.FactRefs)}.");
            text.AppendLine();
            text.Append(RenderLiteral(probe.ClaimQuote));
        }

        if (packet.GroundingProbes.Length == 0)
        {
            text.AppendLine("No claim/fact probe is declared for this omission. Whole-artifact review is still required.");
            text.AppendLine();
        }

        return text.ToString();
    }

    /// <summary>
    ///  Uses a fence longer than every source backtick run so literal artifacts cannot close their display block.
    /// </summary>
    /// <param name="value">The literal source text to display.</param>
    /// <returns>The source text in a complete fenced literal block.</returns>
    private static string RenderLiteral(string value)
    {
        int longest = 0;
        int current = 0;
        foreach (char character in value)
        {
            current = character == '`' ? current + 1 : 0;
            longest = Math.Max(longest, current);
        }

        using ValueStringBuilder text = new(stackalloc char[256]);
        string fence = new('`', Math.Max(3, longest + 1));
        text.AppendLine(fence + "text");
        text.Append(value);
        if (!value.EndsWith('\n'))
        {
            text.AppendLine();
        }

        text.AppendLine(fence);
        text.AppendLine();
        return text.ToString();
    }
}
