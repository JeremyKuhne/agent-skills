// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  Revision-bound content results derived from one captured scenario attempt.
/// </summary>
/// <param name="SchemaVersion">The semantic-record schema version.</param>
/// <param name="EvidenceMode">The semantic evidence-mode identifier.</param>
/// <param name="ScenarioId">The evaluated scenario identifier.</param>
/// <param name="RunNumber">The one-based attempt number for the scenario.</param>
/// <param name="ProfileRevision">The revision of the profile and rubric used for this evaluation.</param>
/// <param name="SourceProfileRevision">The profile revision recorded by the original capture.</param>
/// <param name="InputRevision">The revision of the model-visible scenario inputs.</param>
/// <param name="SemanticRevision">The revision binding the content engine and evaluation profile.</param>
/// <param name="ModelOutputRevision">The revision of the captured model-output files.</param>
/// <param name="ArtifactManifestRevision">The revision of the verified artifact manifest.</param>
/// <param name="LiteralStatus">The aggregate state of deterministic literal checks.</param>
/// <param name="SemanticStatus">The state of semantic judgment.</param>
/// <param name="UsefulOutcome">The aggregate outcome accounting for hard gates and pending judgment.</param>
/// <param name="Checks">The individual content-check results.</param>
public sealed record SemanticRecord(
    int SchemaVersion,
    string EvidenceMode,
    string ScenarioId,
    int RunNumber,
    string ProfileRevision,
    string SourceProfileRevision,
    string InputRevision,
    string SemanticRevision,
    string ModelOutputRevision,
    string ArtifactManifestRevision,
    QualityState LiteralStatus,
    QualityState SemanticStatus,
    QualityState UsefulOutcome,
    CheckResult[] Checks);
