// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  A scenario-supplied statement with its evidence status and authority.
/// </summary>
/// <param name="Id">The fact identifier referenced by claims and ledger entries.</param>
/// <param name="Text">The statement supplied to the model.</param>
/// <param name="State">The statement's evidence status.</param>
/// <param name="Kind">The statement's factual or authority-bearing role.</param>
/// <param name="Provenance">The source of the statement in the scenario input.</param>
public sealed record SuppliedFact(
    string Id,
    string Text,
    EvidenceState State,
    FactKind Kind,
    string Provenance);
