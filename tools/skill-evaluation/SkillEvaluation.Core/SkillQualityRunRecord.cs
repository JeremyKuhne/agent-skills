// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  A single run record for a skill, case, model, and condition.
/// </summary>
/// <param name="SkillId">The skill identifier.</param>
/// <param name="CaseId">The case identifier.</param>
/// <param name="ModelId">The model identifier.</param>
/// <param name="Condition">The skill condition.</param>
/// <param name="Repetition">The repetition number.</param>
/// <param name="InputRevision">The frozen input revision.</param>
/// <param name="ArtifactRevision">The captured artifact revision, when present.</param>
/// <param name="Status">The scheduled state of the run.</param>
/// <param name="Safety">The safety check outcome.</param>
/// <param name="Infrastructure">The infrastructure check outcome.</param>
/// <param name="OracleOutcome">The oracle outcome, if present.</param>
/// <param name="HardChecks">The named executable hard checks.</param>
/// <param name="Usage">The observed token and cost usage.</param>
/// <param name="ElapsedMs">The elapsed time in milliseconds, if recorded.</param>
public sealed record SkillQualityRunRecord(
    string SkillId,
    string CaseId,
    string ModelId,
    SkillQualityCondition Condition,
    int Repetition,
    string InputRevision,
    string? ArtifactRevision,
    SkillQualityRunStatus Status,
    SkillQualityCheckState Safety,
    SkillQualityCheckState Infrastructure,
    SkillQualityOracleOutcome? OracleOutcome,
    SkillQualityHardCheck[] HardChecks,
    SkillQualityUsage? Usage,
    int? ElapsedMs);
