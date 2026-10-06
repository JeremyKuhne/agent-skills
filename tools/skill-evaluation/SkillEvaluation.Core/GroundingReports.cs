// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Diagnostics;
using System.Text;
using Touki.Text;

namespace SkillEvaluation;

/// <summary>
///  Manually evaluates only declared development probes and writes immutable report-only evidence.
/// </summary>
public static class GroundingReports
{
    /// <summary>
    ///  Preflights all inputs before any dispatch and writes an explicitly uncalibrated diagnostic tree.
    /// </summary>
    /// <param name="repoRoot">The owner of the development bank and rubric closure.</param>
    /// <param name="packetPath">The owned relative or absolute bank path.</param>
    /// <param name="assetRoot">The ordinary directory owning locally provisioned assets.</param>
    /// <param name="manifestPath">The owned asset-manifest path.</param>
    /// <param name="reviewOwner">The owner of the completed local human review.</param>
    /// <param name="reviewPath">The owned human review document path.</param>
    /// <param name="outputDirectory">The absent or empty, nonoverlapping derived directory.</param>
    /// <param name="backendFactory">
    ///  The actual runtime owner; synthetic fixtures must identify themselves explicitly.
    /// </param>
    /// <returns>Complete probe diagnostics with useful quality and calibration pending.</returns>
    public static GroundingDiagnosticSummary Evaluate(
        string repoRoot, string packetPath, string assetRoot, string manifestPath,
        string reviewOwner, string reviewPath,
        string outputDirectory, Func<VerifiedGroundingAssets, IGroundingBackend> backendFactory)
    {
        ArgumentNullException.ThrowIfNull(backendFactory);
        string bankPath = GroundingAssets.ResolveOwned(repoRoot, packetPath);
        string bankDirectory = Path.GetDirectoryName(bankPath)
            ?? throw new EvaluationContractException("Grounding bank requires an owning directory.");

        OwnedPaths.RequireSeparateOutput(bankDirectory, outputDirectory);
        OwnedPaths.RequireSeparateOutput(assetRoot, outputDirectory);
        OwnedPaths.RequireSeparateOutput(reviewOwner, outputDirectory);
        VerifiedGroundingAssets assets = GroundingAssets.Load(assetRoot, manifestPath);
        ValidatedReviewPackets bank = ReviewPackets.Load(repoRoot, bankPath);
        PreparedGroundingProbe[] inputs = GroundingInference.Prepare(bank);
        GroundingReviewEvidence review = GroundingHumanLabels.Load(reviewOwner, reviewPath, bank, inputs);
        Dictionary<string, ReviewedGroundingLabel> labels = review.Labels.ToDictionary(
            value => value.PacketId + ":" + value.ProbeId, StringComparer.Ordinal);

        using IGroundingBackend backend = backendFactory(assets)
            ?? throw new EvaluationContractException("A grounding computation owner is required.");

        GroundingBackendIdentity identity = backend.Identity
            ?? throw new EvaluationContractException("An explicit grounding backend identity is required.");

        if (string.IsNullOrWhiteSpace(identity.Id)
            || string.IsNullOrWhiteSpace(identity.Runtime)
            || string.IsNullOrWhiteSpace(identity.Tokenizer))
        {
            throw new EvaluationContractException("Grounding backend identity is incomplete.");
        }

        ArtifactStore.RequireRevision(identity.Revision);
        if (!identity.Synthetic && review.AuthorityScope != "declared-human-reviewed-development")
        {
            throw new EvaluationContractException(
                "A non-synthetic grounding backend requires completed declared human review, not synthetic fixture evidence.");
        }

        GroundingTokens[] tokens = inputs.Select(value =>
        {
            GroundingTokens pair = backend.Encode(value.Premise, value.Claim.Quote);
            GroundingInference.ValidateTokens(pair, assets.Manifest.MaximumTokens);
            return new GroundingTokens([.. pair.InputIds], [.. pair.AttentionMask], [.. pair.TokenTypeIds]);
        }).ToArray();

        foreach (GroundingTokens pair in tokens)
        {
            GroundingInference.ValidateTokens(pair, assets.Manifest.MaximumTokens);
        }

        GroundingAssets.RequireUnchanged(assets);
        RequireBankUnchanged(repoRoot, bankPath, bank);
        RequireReviewUnchanged(reviewOwner, reviewPath, bank, inputs, review);
        string tokenRevision = ContractJson.Revision(tokens);
        List<GroundingProbeResult> results = [];
        for (int index = 0; index < inputs.Length; index++)
        {
            Stopwatch watch = Stopwatch.StartNew();
            GroundingScores scores = GroundingInference.Score(backend.Predict(tokens[index]));
            watch.Stop();
            GroundingRelation human = labels[inputs[index].PacketId + ":" + inputs[index].ProbeId].Relation;
            results.Add(new(inputs[index], tokens[index].InputIds.Length, scores,
                QualityState.Pending, human,
                scores.RawRelation is null ? null : scores.RawRelation == human,
                watch.Elapsed.TotalMilliseconds));
        }

        GroundingAssets.RequireUnchanged(assets);
        RequireBankUnchanged(repoRoot, bankPath, bank);
        RequireReviewUnchanged(reviewOwner, reviewPath, bank, inputs, review);
        if (ContractJson.Revision(tokens) != tokenRevision)
        {
            throw new EvaluationContractException("Grounding backend mutated the preflight-verified input tensors.");
        }

        string revision = ContractJson.Revision(new
        {
            engine = "manual-probe-grounding/v1",
            core = ContentEvaluator.EngineRevision,
            assets.AssetRevision,
            backend = identity,
            preprocessing = "complete-pair/no-truncation/one-thread/one-batch",
            inputs,
            tokenRevision,
            review.SourceRevision,
            calibration = "pending"
        });

        GroundingDiagnosticSummary summary = new(
            1, "grounding-diagnostic", "explicit-development-probes-only",
            bank.Bank.Id, bank.Summary.SourceRevision, assets.AssetRevision, revision,
            assets.Manifest.ModelId, assets.Manifest.ModelRevision, identity, review,
            results.Count, 0, QualityState.Pending, QualityState.Pending, results.ToArray());

        _ = ContractJson.Read<GroundingDiagnosticSummary>(
            ContractJson.Parse(ContractJson.Serialize(summary)), "grounding-diagnostic.v1");

        Directory.CreateDirectory(outputDirectory);
        ContractJson.WriteNew(Path.Join(outputDirectory, "grounding.json"), summary);
        WriteMarkdown(summary, Path.Join(outputDirectory, "grounding.md"));
        return summary;
    }

    /// <summary>
    ///  Rejects review-record changes rather than borrowing a later judgment for earlier model output.
    /// </summary>
    /// <param name="owner">The ordinary review owner.</param>
    /// <param name="path">The source review path.</param>
    /// <param name="bank">The source bank.</param>
    /// <param name="inputs">The source-bound explicit probes.</param>
    /// <param name="original">The originally loaded review evidence.</param>
    private static void RequireReviewUnchanged(
        string owner, string path, ValidatedReviewPackets bank,
        PreparedGroundingProbe[] inputs, GroundingReviewEvidence original)
    {
        if (GroundingHumanLabels.Load(owner, path, bank, inputs).SourceRevision != original.SourceRevision)
        {
            throw new EvaluationContractException("Human review changed during grounding diagnostics.");
        }
    }

    /// <summary>
    ///  Requires unchanged source bytes and resolved profile/rubric revisions.
    /// </summary>
    /// <param name="root">The bank owner.</param>
    /// <param name="path">The original bank path.</param>
    /// <param name="original">The prepared bank snapshot.</param>
    private static void RequireBankUnchanged(string root, string path, ValidatedReviewPackets original)
    {
        ValidatedReviewPackets current = ReviewPackets.Load(root, path);
        if (current.Summary.SourceRevision != original.Summary.SourceRevision
            || current.Summary.Revision != original.Summary.Revision)
        {
            throw new EvaluationContractException("Grounding source bank or profile closure changed during evaluation.");
        }
    }

    /// <summary>
    ///  Writes a human-readable diagnostic report without implying useful success or complete prose coverage.
    /// </summary>
    /// <param name="summary">The complete uncalibrated probe results.</param>
    /// <param name="path">The new Markdown report path.</param>
    private static void WriteMarkdown(GroundingDiagnosticSummary summary, string path)
    {
        using ValueStringBuilder text = new(stackalloc char[256]);
        text.AppendLine("# Manual grounding diagnostics");
        text.AppendLine();
        text.AppendLine("Only explicit development claim/fact probes were assessed. Full prose, omissions, and required-claim coverage remain unassessed.");
        text.AppendLine("Raw model relations and softmax scores are uncalibrated. Useful outcome and calibration remain pending.");
        text.AppendLine();
        text.AppendLine($"- Backend: `{summary.Backend.Id}`; synthetic: `{summary.Backend.Synthetic}`.");
        text.AppendLine($"- Bank: `{summary.BankId}`; source revision: `{summary.BankRevision}`.");
        text.AppendLine($"- Model: `{summary.ModelId}` at `{summary.ModelRevision}`.");
        text.AppendLine($"- Grounding revision: `{summary.GroundingRevision}`.");
        text.AppendLine($"- Human development review: `{summary.ReviewEvidence.SourceRevision}`; not held-out calibration.");
        text.AppendLine($"- Probes: {summary.ProbeCount}; useful passes: 0.");
        text.AppendLine();
        text.AppendLine("| Packet | Probe | Raw relation | Reviewed relation | Tokens | Quality |");
        text.AppendLine("| --- | --- | --- | --- | ---: | --- |");
        foreach (GroundingProbeResult probe in summary.Probes)
        {
            string relation = probe.Scores.RawRelation?.ToString() ?? "Exact tie";
            text.AppendLine($"| `{probe.Input.PacketId}` | `{probe.Input.ProbeId}` | {relation} | {probe.ReviewedRelation} | {probe.TokenCount} | Pending |");
        }

        using FileStream stream = new(path, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        stream.Write(Encoding.UTF8.GetBytes(text.ToString().Replace("\r\n", "\n", StringComparison.Ordinal)));
    }
}
