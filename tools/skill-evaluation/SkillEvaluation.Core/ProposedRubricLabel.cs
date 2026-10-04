// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  An assistant-authored item expectation awaiting independent human review.
/// </summary>
/// <param name="ItemId">The referenced rubric item identifier.</param>
/// <param name="State">The proposed pass, failure, or pending label.</param>
/// <param name="Rationale">The source-backed explanation proposed for review.</param>
/// <param name="FactRefs">The supplied facts relevant to the proposed label.</param>
/// <param name="Evidence">Exact artifact quotations or whole-artifact omission evidence.</param>
public sealed record ProposedRubricLabel(
    string ItemId,
    QualityState State,
    string Rationale,
    string[] FactRefs,
    ReviewEvidence[] Evidence);
