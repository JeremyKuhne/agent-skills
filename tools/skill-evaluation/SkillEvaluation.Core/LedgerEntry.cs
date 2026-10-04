// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  A supplied fact's identity, evidence status, and authority in a grounding ledger.
/// </summary>
/// <param name="FactId">The referenced supplied-fact identifier.</param>
/// <param name="State">The evidence status declared for the fact.</param>
/// <param name="Kind">The factual or authority-bearing role declared for the fact.</param>
public sealed record LedgerEntry(string FactId, EvidenceState State, FactKind Kind);
