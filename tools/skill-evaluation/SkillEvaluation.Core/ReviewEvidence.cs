// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  A review witness that resolves to exact source text rather than an invented quotation.
/// </summary>
/// <param name="Scope">Whether the witness quotes text or identifies the whole artifact.</param>
/// <param name="Quote">The exact unique quotation, absent for whole-artifact evidence.</param>
/// <param name="Span">An optional supplied span that must equal the independently resolved location.</param>
public sealed record ReviewEvidence(string Scope, string? Quote = null, EvidenceSpan? Span = null);
