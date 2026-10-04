// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  A structurally validated development bank with resolved source-pinned scenario inputs.
/// </summary>
/// <param name="Bank">The assistant-proposed development controls.</param>
/// <param name="Scenarios">The validated prompts, facts, and rubric closures.</param>
/// <param name="Summary">The preparation receipt, not human or model accuracy evidence.</param>
public sealed record ValidatedReviewPackets(
    ReviewPacketBank Bank,
    ValidatedScenario[] Scenarios,
    ReviewPacketSummary Summary);
