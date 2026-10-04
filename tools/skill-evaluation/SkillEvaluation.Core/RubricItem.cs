// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  A source-grounded content criterion requiring qualified judgment.
/// </summary>
/// <param name="Id">The rubric criterion identifier.</param>
/// <param name="PassCondition">The condition establishing that the criterion is satisfied.</param>
/// <param name="FailCondition">The condition establishing that the criterion is violated.</param>
/// <param name="HardGate">Whether failure blocks a useful outcome.</param>
/// <param name="ArtifactKinds">The artifact kinds to which the criterion applies.</param>
/// <param name="Sources">The revision-pinned source quotations supporting the criterion.</param>
public sealed record RubricItem(
    string Id,
    string PassCondition,
    string FailCondition,
    bool HardGate,
    ArtifactKind[] ArtifactKinds,
    RubricSource[] Sources);
