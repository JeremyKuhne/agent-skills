// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  A source-bound explicit development probe, not automatic or exhaustive sentence extraction.
/// </summary>
/// <param name="PacketId">The artifact packet identifier.</param>
/// <param name="ProbeId">The explicit probe identifier.</param>
/// <param name="ArtifactRevision">The frozen artifact-text revision.</param>
/// <param name="ProfileRevision">The source-verified input/rubric profile revision.</param>
/// <param name="InputRevision">The model-visible input revision.</param>
/// <param name="Claim">The exact quoted claim and UTF-16 source location.</param>
/// <param name="FactRefs">The authoritative premise fact identifiers.</param>
/// <param name="Facts">The full evidence/authority states supplying the premise.</param>
/// <param name="Premise">The joined fact texts supplied to the classifier.</param>
public sealed record PreparedGroundingProbe(
    string PacketId,
    string ProbeId,
    string ArtifactRevision,
    string ProfileRevision,
    string InputRevision,
    PacketEvidence Claim,
    string[] FactRefs,
    SuppliedFact[] Facts,
    string Premise);
