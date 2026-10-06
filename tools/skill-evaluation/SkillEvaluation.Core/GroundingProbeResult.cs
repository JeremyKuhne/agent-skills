// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  A diagnostic result whose source, preprocessing, and unresolved quality are explicit.
/// </summary>
/// <param name="Input">The source-bound claim and authoritative premise.</param>
/// <param name="TokenCount">The complete pair token count.</param>
/// <param name="Scores">The raw logits and uncalibrated display scores.</param>
/// <param name="QualityStatus">The pending quality status, never inferred from model confidence.</param>
/// <param name="ReviewedRelation">The source-bound declared human development relation.</param>
/// <param name="MatchesReviewedRelation">Whether the raw model relation agrees, or null for an exact score tie.</param>
/// <param name="ElapsedMilliseconds">
///  The model-dispatch duration, excluding tokenization and score post-processing.
/// </param>
public sealed record GroundingProbeResult(
    PreparedGroundingProbe Input,
    int TokenCount,
    GroundingScores Scores,
    QualityState QualityStatus,
    GroundingRelation ReviewedRelation,
    bool? MatchesReviewedRelation,
    double ElapsedMilliseconds);
