// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  An exact quotation and its verified location in a review packet's artifact.
/// </summary>
/// <param name="Span">The UTF-16 source location with a one-based line.</param>
/// <param name="Quote">The text at that location.</param>
public sealed record PacketEvidence(EvidenceSpan Span, string Quote);
