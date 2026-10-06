// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  A source-bound declared human development judgment, not a calibration or useful-output certificate.
/// </summary>
/// <param name="PacketId">The reviewed packet identifier.</param>
/// <param name="ProbeId">The explicitly declared probe identifier.</param>
/// <param name="ArtifactRevision">The artifact revision checked by the human session.</param>
/// <param name="Relation">The explicitly recorded relation.</param>
/// <param name="ReviewerResponse">The captured reviewer response, not inferred agreement.</param>
/// <param name="DecisionScope">The scope of the recorded approval.</param>
/// <param name="RecordedAt">The source record timestamp.</param>
public sealed record ReviewedGroundingLabel(
    string PacketId,
    string ProbeId,
    string ArtifactRevision,
    GroundingRelation Relation,
    string ReviewerResponse,
    string DecisionScope,
    string RecordedAt);
