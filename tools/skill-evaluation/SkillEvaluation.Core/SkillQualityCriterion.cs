// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  Freezes required item identity and strength before candidate outputs or model grades exist.
/// </summary>
/// <param name="SkillId">The owning pilot skill.</param>
/// <param name="ItemId">The exact expected grading item.</param>
/// <param name="HardGate">Whether a failed item cannot be offset by advisory style.</param>
public sealed record SkillQualityCriterion(string SkillId, string ItemId, bool HardGate);
