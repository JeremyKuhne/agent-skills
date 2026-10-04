// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  One content check's outcome, explanation, and supporting evidence.
/// </summary>
/// <param name="Id">The check identifier.</param>
/// <param name="TargetId">The evaluated artifact identifier or aggregate target identifier.</param>
/// <param name="Dimension">The content requirement assessed by the check.</param>
/// <param name="State">The check's evaluation state.</param>
/// <param name="HardGate">Whether failure blocks a useful outcome.</param>
/// <param name="Detail">The result explanation.</param>
/// <param name="Span">The matching or failing text location. Defaults to <see langword="null"/>.</param>
/// <param name="FactRefs">The referenced supplied-fact identifiers. Defaults to <see langword="null"/>.</param>
public sealed record CheckResult(
    string Id,
    string TargetId,
    CheckDimension Dimension,
    QualityState State,
    bool HardGate,
    string Detail,
    EvidenceSpan? Span = null,
    string[]? FactRefs = null);
