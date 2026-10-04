// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  Content-check results and their aggregate literal and useful-outcome states.
/// </summary>
/// <param name="LiteralStatus">The aggregate state of deterministic literal checks.</param>
/// <param name="UsefulOutcome">The aggregate outcome accounting for hard gates and unassessed claims.</param>
/// <param name="Checks">The individual literal, ledger, claim, and rubric results.</param>
public sealed record ArtifactEvaluation(
    QualityState LiteralStatus,
    QualityState UsefulOutcome,
    CheckResult[] Checks);
