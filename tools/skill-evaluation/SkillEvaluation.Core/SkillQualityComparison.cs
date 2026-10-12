// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  Records a matched task comparison without counting absent or disputed outcomes as wins.
/// </summary>
/// <param name="SkillId">The pilot skill.</param>
/// <param name="CaseId">The matched task case.</param>
/// <param name="ModelId">The same candidate model in both conditions.</param>
/// <param name="Repetition">The matched repetition.</param>
/// <param name="Comparison">The current/baseline or revised/current comparison.</param>
/// <param name="Baseline">The observed reference task outcome.</param>
/// <param name="Candidate">The observed candidate task outcome.</param>
/// <param name="Outcome">The descriptive win, loss, tie, or pending state.</param>
public sealed record SkillQualityComparison(
    string SkillId, string CaseId, string ModelId, int Repetition, string Comparison,
    string Baseline, string Candidate, string Outcome);
