// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  Stable softmax display scores with an uncalibrated raw relation, never a qualified verdict.
/// </summary>
/// <param name="Logits">The untouched classifier logits.</param>
/// <param name="Contradiction">The uncalibrated contradiction display score.</param>
/// <param name="Entailment">The uncalibrated entailment display score.</param>
/// <param name="Neutral">The uncalibrated neutral display score.</param>
/// <param name="RawRelation">The highest-scoring relation, or null for an exact tie.</param>
public sealed record GroundingScores(
    GroundingLogits Logits,
    double Contradiction,
    double Entailment,
    double Neutral,
    GroundingRelation? RawRelation);
