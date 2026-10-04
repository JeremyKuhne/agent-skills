// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json;
using Markdig;
using Markdig.Syntax;

namespace SkillEvaluation;

/// <summary>
///  Checks literal artifact requirements and grounding-ledger consistency without judging prose support.
/// </summary>
public static class LiteralEvaluator
{
    private static readonly MarkdownPipeline Pipeline =
        new MarkdownPipelineBuilder().UsePreciseSourceLocation().Build();

    /// <summary>
    ///  Evaluates a target's literal checks and required verbatim tokens with source spans where available.
    /// </summary>
    /// <param name="text">The artifact text to inspect.</param>
    /// <param name="targetId">The artifact target identifier.</param>
    /// <param name="profile">The profile declaring literal checks and required claims.</param>
    /// <returns>The target's deterministic literal-check results.</returns>
    public static CheckResult[] Evaluate(string text, string targetId, ContentProfile profile)
    {
        MarkdownDocument document = Markdown.Parse(text, Pipeline);
        List<CheckResult> results = [];
        foreach (LiteralCheck check in profile.LiteralChecks.Where(value => value.TargetId == targetId))
        {
            bool passed;
            EvidenceSpan? span = null;
            switch (check.Kind)
            {
                case LiteralKind.Nonempty:
                    passed = !string.IsNullOrWhiteSpace(text);
                    break;
                case LiteralKind.Heading:
                    HeadingBlock? heading = document.OfType<HeadingBlock>().FirstOrDefault(value =>
                        value.Level == check.Level
                            && PlainBlock(text, value) == check.Text);

                    passed = heading is not null;
                    if (heading is not null) span = Span(text, heading.Span.Start, heading.Span.Length);
                    break;
                case LiteralKind.StartsWith:
                    string prefix = check.Text
                        ?? throw new EvaluationContractException($"Literal check '{check.Id}' requires text.");

                    ParagraphBlock? opening = document.FirstOrDefault() as ParagraphBlock;
                    passed = opening is not null
                        && PlainBlock(text, opening).StartsWith(prefix, StringComparison.Ordinal);

                    if (passed && opening is not null) span = Span(text, opening.Span.Start, opening.Span.Length);
                    break;
                case LiteralKind.ContainsLiteral:
                case LiteralKind.ForbidsLiteral:
                    string literal = check.Text
                        ?? throw new EvaluationContractException($"Literal check '{check.Id}' requires text.");

                    int index = text.IndexOf(literal, StringComparison.Ordinal);
                    passed = check.Kind == LiteralKind.ContainsLiteral ? index >= 0 : index < 0;
                    if (index >= 0) span = Span(text, index, literal.Length);
                    break;
                case LiteralKind.SingleLineParagraphs:
                    ParagraphBlock? wrapped = document.Descendants<ParagraphBlock>().FirstOrDefault(value =>
                        text.AsSpan(value.Span.Start, value.Span.Length).IndexOfAny('\r', '\n') >= 0);

                    passed = wrapped is null;
                    if (wrapped is not null) span = Span(text, wrapped.Span.Start, wrapped.Span.Length);
                    break;
                default:
                    throw new EvaluationContractException($"Unsupported literal check '{check.Kind}'.");
            }

            results.Add(new(check.Id, targetId, CheckDimension.Literal,
                passed ? QualityState.Passed : QualityState.Failed, HardGate: true,
                $"{check.Kind}: {(passed ? "satisfied" : "not satisfied")}.", span));
        }

        foreach (RequiredClaim claim in profile.RequiredClaims.Where(value => value.TargetId == targetId))
        {
            for (int index = 0; index < claim.VerbatimTokens.Length; index++)
            {
                string token = claim.VerbatimTokens[index];
                int start = text.IndexOf(token, StringComparison.Ordinal);
                results.Add(new($"required:{claim.Id}:literal:{index + 1}", targetId,
                    CheckDimension.Literal, start >= 0 ? QualityState.Passed : QualityState.Failed,
                    HardGate: true, $"Required literal '{token}'; its presence does not establish claim support.",
                    start >= 0 ? Span(text, start, token.Length) : null, claim.FactRefs));
            }
        }

        return results.ToArray();
    }

    /// <summary>
    ///  Converts a Markdown block's source slice to trimmed plain text.
    /// </summary>
    /// <param name="text">The complete Markdown source.</param>
    /// <param name="block">The parsed block whose source span is used.</param>
    /// <returns>The block's trimmed plain text.</returns>
    private static string PlainBlock(string text, Block block) =>
        Markdown.ToPlainText(text.Substring(block.Span.Start, block.Span.Length), Pipeline).Trim();

    /// <summary>
    ///  Creates an evidence span with a one-based source line number.
    /// </summary>
    /// <param name="text">The complete artifact text.</param>
    /// <param name="start">The zero-based character offset.</param>
    /// <param name="length">The number of characters in the span.</param>
    /// <returns>The character range and its starting line.</returns>
    private static EvidenceSpan Span(string text, int start, int length) =>
        new(start, length, 1 + text.AsSpan(0, start).Count('\n'));

    /// <summary>
    ///  Checks a JSON ledger against supplied fact identities, evidence states, and authority kinds.
    /// </summary>
    /// <param name="text">A JSON ledger or Markdown ending with a single JSON fenced ledger.</param>
    /// <param name="targetId">The artifact target containing the ledger.</param>
    /// <param name="profile">The supplied facts and ledger enforcement mode.</param>
    /// <returns>A passed or failed consistency check, without establishing prose support.</returns>
    public static CheckResult CheckLedger(string text, string targetId, ContentProfile profile)
    {
        try
        {
            string json = text;
            if (!text.TrimStart().StartsWith('{'))
            {
                MarkdownDocument document = Markdown.Parse(text, Pipeline);
                FencedCodeBlock[] blocks = document.Descendants<FencedCodeBlock>()
                    .Where(value => value.Info == "json").ToArray();

                if (blocks.Length != 1 || !ReferenceEquals(document.LastOrDefault(), blocks[0]))
                {
                    throw new EvaluationContractException("A single JSON ledger must follow the prose as the final block.");
                }

                json = blocks[0].Lines.ToString();
            }

            GroundingLedger ledger = ContractJson.Read<GroundingLedger>(
                ContractJson.Parse(json), "grounding-ledger.v1");

            ProfileValidator.UniqueIds(ledger.Entries.Select(value => value.FactId), "ledger fact");
            Dictionary<string, SuppliedFact> facts = profile.SuppliedFacts.ToDictionary(
                value => value.Id, StringComparer.Ordinal);

            foreach (LedgerEntry entry in ledger.Entries)
            {
                if (!facts.TryGetValue(entry.FactId, out SuppliedFact? fact)
                    || entry.State != fact.State
                    || entry.Kind != fact.Kind)
                {
                    throw new EvaluationContractException($"Ledger fact '{entry.FactId}' has unknown identity or changed evidence/authority.");
                }
            }

            foreach (SuppliedFact fact in profile.SuppliedFacts.Where(value => value.State == EvidenceState.Unknown))
            {
                if (!ledger.Entries.Any(value => value.FactId == fact.Id))
                {
                    throw new EvaluationContractException($"Ledger omits unknown fact '{fact.Id}'.");
                }
            }

            return new("ledger-consistency", targetId, CheckDimension.Ledger, QualityState.Passed,
                profile.Ledger.Mode == LedgerMode.Required,
                "Ledger identity and states are consistent; prose support has not been established.");
        }
        catch (Exception error) when (error is JsonException or EvaluationContractException)
        {
            return new("ledger-consistency", targetId, CheckDimension.Ledger, QualityState.Failed,
                profile.Ledger.Mode == LedgerMode.Required, error.Message);
        }
    }
}
