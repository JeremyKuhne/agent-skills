// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  A separately collected item-level model judgment, provisional even when two judges agree.
/// </summary>
/// <param name="JudgeId">The judge model identifier.</param>
/// <param name="SkillId">The skill identifier.</param>
/// <param name="CaseId">The case identifier.</param>
/// <param name="ModelId">The model identifier being judged.</param>
/// <param name="Condition">The run condition.</param>
/// <param name="Repetition">The repetition number.</param>
/// <param name="InputRevision">The input revision used for the judged run.</param>
/// <param name="ArtifactRevision">The exact captured artifact graded in this fresh session.</param>
/// <param name="Judgments">The item-level judgments.</param>
/// <param name="Usage">The judge usage metadata.</param>
/// <param name="ElapsedMs">The judge elapsed time in milliseconds.</param>
public sealed record SkillQualityJudgeRecord(
    SkillQualityModelId JudgeId,
    string SkillId,
    string CaseId,
    string ModelId,
    SkillQualityCondition Condition,
    int Repetition,
    string InputRevision,
    string ArtifactRevision,
    SkillQualityJudgment[] Judgments,
    SkillQualityUsage? Usage,
    int? ElapsedMs);
