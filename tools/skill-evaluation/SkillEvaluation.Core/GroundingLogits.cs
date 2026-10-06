// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  Raw three-way classifier logits, not calibrated probabilities or quality authority.
/// </summary>
/// <param name="Contradiction">The contradiction logit.</param>
/// <param name="Entailment">The entailment logit.</param>
/// <param name="Neutral">The neither-established-nor-refuted logit.</param>
public sealed record GroundingLogits(double Contradiction, double Entailment, double Neutral);
