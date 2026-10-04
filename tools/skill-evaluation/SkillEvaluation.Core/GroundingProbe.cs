// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  An explicitly selected claim/fact control, not a classifier result or complete prose-grounding pass.
/// </summary>
/// <param name="Id">The probe identifier within its packet.</param>
/// <param name="ClaimQuote">The exact unique claim in the artifact.</param>
/// <param name="FactRefs">The authoritative scenario facts supplied as the premise.</param>
/// <param name="ProposedRelation">The assistant-proposed three-way relation awaiting human review.</param>
public sealed record GroundingProbe(
    string Id,
    string ClaimQuote,
    string[] FactRefs,
    GroundingRelation ProposedRelation);
