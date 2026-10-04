// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  Distinguishes three-way entailment proposals without treating lack of support as contradiction.
/// </summary>
public enum GroundingRelation
{
    /// <summary>
    ///  The premise is proposed to support the claim.
    /// </summary>
    Entailed,

    /// <summary>
    ///  The premise is proposed to contradict the claim.
    /// </summary>
    Contradicted,

    /// <summary>
    ///  The premise is proposed to establish neither the claim nor its negation.
    /// </summary>
    Neutral
}
