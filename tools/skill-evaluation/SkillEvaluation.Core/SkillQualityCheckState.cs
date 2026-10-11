// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  Execution-state result for a safety or infrastructure gate.
/// </summary>
public enum SkillQualityCheckState
{
    /// <summary>
    ///  The check passed.
    /// </summary>
    [System.Text.Json.Serialization.JsonStringEnumMemberName("passed")]
    Passed,

    /// <summary>
    ///  The check failed.
    /// </summary>
    [System.Text.Json.Serialization.JsonStringEnumMemberName("failed")]
    Failed,

    /// <summary>
    ///  The check is pending.
    /// </summary>
    [System.Text.Json.Serialization.JsonStringEnumMemberName("pending")]
    Pending,

    /// <summary>
    ///  The check is not applicable.
    /// </summary>
    [System.Text.Json.Serialization.JsonStringEnumMemberName("not-applicable")]
    NotApplicable
}
