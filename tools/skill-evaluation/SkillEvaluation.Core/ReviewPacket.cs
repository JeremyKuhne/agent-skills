// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  A pinned synthetic artifact with proposed rubric and grounding labels.
/// </summary>
/// <param name="Id">The packet identifier.</param>
/// <param name="ScenarioId">The scenario supplying its prompt, facts, and criteria.</param>
/// <param name="TargetId">The declared artifact target represented by the text.</param>
/// <param name="ArtifactText">The natural artifact text, without an added evidence ledger.</param>
/// <param name="ArtifactRevision">The LF-normalized UTF-8 text revision of the artifact.</param>
/// <param name="ExpectedLiteralStatus">The independently declared literal-check result.</param>
/// <param name="ProposedLabels">The complete assistant-proposed rubric labels.</param>
/// <param name="GroundingProbes">Explicit claim/fact pairs for a later approved classifier spike.</param>
public sealed record ReviewPacket(
    string Id,
    string ScenarioId,
    string TargetId,
    string ArtifactText,
    string ArtifactRevision,
    QualityState ExpectedLiteralStatus,
    ProposedRubricLabel[] ProposedLabels,
    GroundingProbe[] GroundingProbes);
