// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  Records an evidence-citing model judgment without granting useful-output qualification.
/// </summary>
/// <param name="ItemId">The frozen rubric item.</param>
/// <param name="HardGate">The declared item strength, checked against the frozen criteria.</param>
/// <param name="State">The proposed pass, fail, or pending result.</param>
/// <param name="Evidence">The cited artifact or executable receipt evidence.</param>
/// <param name="Why">The bounded reason for the judgment.</param>
public sealed record SkillQualityJudgment(
    string ItemId, bool HardGate, SkillQualityJudgeState State, string Evidence, string Why);
