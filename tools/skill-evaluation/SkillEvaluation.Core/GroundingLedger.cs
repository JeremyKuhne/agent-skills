// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  The structured grounding ledger supplied with an evaluated artifact.
/// </summary>
/// <param name="SchemaVersion">The grounding-ledger schema version.</param>
/// <param name="Entries">The supplied-fact identities and classifications declared by the artifact.</param>
public sealed record GroundingLedger(int SchemaVersion, LedgerEntry[] Entries);
