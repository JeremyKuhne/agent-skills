// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  Aggregate content outcomes derived from a revision-pinned capture summary.
/// </summary>
/// <param name="SchemaVersion">The semantic-summary schema version.</param>
/// <param name="EvidenceMode">The semantic evidence-mode identifier.</param>
/// <param name="Model">The model identifier recorded by the source capture.</param>
/// <param name="SemanticRevision">The revision of the engine and profiles used for rescoring.</param>
/// <param name="SourceSummaryRevision">The byte revision of the original capture summary.</param>
/// <param name="SourceScorerRevision">The scorer revision recorded by the source capture.</param>
/// <param name="RunCount">The number of selected source attempts.</param>
/// <param name="LiteralPassedCount">The number of runs with passed literal checks.</param>
/// <param name="UsefulPassedCount">The number of runs with a passed useful outcome.</param>
/// <param name="UsefulFailedCount">The number of runs with a failed useful outcome.</param>
/// <param name="PendingCount">The number of runs with missing content or pending outcomes.</param>
/// <param name="SafetyFailureCount">The number of selected runs that failed source safety checks.</param>
/// <param name="InfrastructureFailureCount">The number of runs with execution or evidence-verification errors.</param>
/// <param name="Runs">The selected attempts and their derived results.</param>
public sealed record SemanticSummary(
    int SchemaVersion,
    string EvidenceMode,
    string Model,
    string SemanticRevision,
    string SourceSummaryRevision,
    string SourceScorerRevision,
    int RunCount,
    int LiteralPassedCount,
    int UsefulPassedCount,
    int UsefulFailedCount,
    int PendingCount,
    int SafetyFailureCount,
    int InfrastructureFailureCount,
    DerivedRun[] Runs);
