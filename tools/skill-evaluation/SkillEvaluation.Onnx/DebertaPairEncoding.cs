// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation.Onnx;

/// <summary>
///  Composes the pinned DeBERTa pair structure from complete maintained-tokenizer output.
/// </summary>
public static class DebertaPairEncoding
{
    /// <summary>
    ///  Adds exact CLS/SEP markers, attention, and segment IDs without dropping input tokens.
    /// </summary>
    /// <param name="premise">Every premise token produced by the maintained tokenizer.</param>
    /// <param name="claim">Every claim token produced by the maintained tokenizer.</param>
    /// <param name="maximumTokens">The explicit complete-pair limit.</param>
    /// <returns>The canonical complete pair, or an explicit overlength error before allocation/dispatch.</returns>
    public static GroundingTokens Compose(int[] premise, int[] claim, int maximumTokens)
    {
        ArgumentNullException.ThrowIfNull(premise);
        ArgumentNullException.ThrowIfNull(claim);
        if (premise.Length == 0 || claim.Length == 0)
        {
            throw new EvaluationContractException("Complete grounding pairs require nonempty premise and claim tokens.");
        }

        int count = checked(premise.Length + claim.Length + 3);
        if (count > maximumTokens)
        {
            throw new EvaluationContractException(
                $"Pair contains {count} tokens; the complete-pair limit forbids silent truncation.");
        }

        GroundingTokens tokens = new(
            [1, .. premise, 2, .. claim, 2],
            Enumerable.Repeat(1, count).ToArray(),
            [.. Enumerable.Repeat(0, premise.Length + 2), .. Enumerable.Repeat(1, claim.Length + 1)]);

        GroundingInference.ValidateTokens(tokens, maximumTokens);
        return tokens;
    }
}
