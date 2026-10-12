// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  Oracle outcome captured for a case or run.
/// </summary>
public enum SkillQualityOracleOutcome
{
    /// <summary>
    ///  The oracle passes the run.
    /// </summary>
    [System.Text.Json.Serialization.JsonStringEnumMemberName("passed")]
    Passed,

    /// <summary>
    ///  The oracle fails the run.
    /// </summary>
    [System.Text.Json.Serialization.JsonStringEnumMemberName("failed")]
    Failed,

    /// <summary>
    ///  The oracle result is pending.
    /// </summary>
    [System.Text.Json.Serialization.JsonStringEnumMemberName("pending")]
    Pending,

    /// <summary>
    ///  The oracle is explicitly not applicable for this case.
    /// </summary>
    [System.Text.Json.Serialization.JsonStringEnumMemberName("none")]
    None
}
