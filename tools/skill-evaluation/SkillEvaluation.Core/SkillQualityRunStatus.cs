// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  The run scheduling state captured in a campaign.
/// </summary>
public enum SkillQualityRunStatus
{
    /// <summary>
    ///  The run is scheduled but not started.
    /// </summary>
    [System.Text.Json.Serialization.JsonStringEnumMemberName("scheduled")]
    Scheduled,

    /// <summary>
    ///  The run was attempted.
    /// </summary>
    [System.Text.Json.Serialization.JsonStringEnumMemberName("attempted")]
    Attempted,

    /// <summary>
    ///  The run completed.
    /// </summary>
    [System.Text.Json.Serialization.JsonStringEnumMemberName("completed")]
    Completed
}
