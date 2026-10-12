// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  Token and cost usage captured for a run or judge; missing receipts remain null.
/// </summary>
/// <param name="InputTokens">The input-token count.</param>
/// <param name="OutputTokens">The output-token count.</param>
/// <param name="CachedInputTokens">The cached input-token count.</param>
/// <param name="CachedOutputTokens">The cached output-token count.</param>
/// <param name="CostDollars">The cost in US dollars.</param>
/// <param name="ElapsedMs">The recorded elapsed time in milliseconds.</param>
public sealed record SkillQualityUsage(
    int? InputTokens,
    int? OutputTokens,
    int? CachedInputTokens,
    int? CachedOutputTokens,
    decimal? CostDollars,
    int? ElapsedMs);
