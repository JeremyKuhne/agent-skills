// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  The baseline/differential condition applied to a skill run.
/// </summary>
public enum SkillQualityCondition
{
    /// <summary>
    ///  The no-skill baseline run.
    /// </summary>
    [System.Text.Json.Serialization.JsonStringEnumMemberName("no-skill")]
    NoSkill,

    /// <summary>
    ///  The current production or reference run.
    /// </summary>
    [System.Text.Json.Serialization.JsonStringEnumMemberName("current")]
    Current,

    /// <summary>
    ///  The revised candidate run under evaluation.
    /// </summary>
    [System.Text.Json.Serialization.JsonStringEnumMemberName("revised")]
    Revised
}
