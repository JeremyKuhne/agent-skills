// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  A judge's item-level state for a run.
/// </summary>
public enum SkillQualityJudgeState
{
    /// <summary>
    ///  The judged item passed.
    /// </summary>
    [System.Text.Json.Serialization.JsonStringEnumMemberName("passed")]
    Passed,

    /// <summary>
    ///  The judged item failed.
    /// </summary>
    [System.Text.Json.Serialization.JsonStringEnumMemberName("failed")]
    Failed,

    /// <summary>
    ///  The judged item is pending.
    /// </summary>
    [System.Text.Json.Serialization.JsonStringEnumMemberName("pending")]
    Pending
}
