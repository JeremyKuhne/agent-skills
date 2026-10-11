// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  Valid model identifiers used in blind skill-quality grading.
/// </summary>
public enum SkillQualityModelId
{
    /// <summary>
    ///  The GPT-6.1 Sol judge model.
    /// </summary>
    [System.Text.Json.Serialization.JsonStringEnumMemberName("gpt-6.1-sol")]
    Gpt61Sol,

    /// <summary>
    ///  The GPT-6.0 Luna judge model.
    /// </summary>
    [System.Text.Json.Serialization.JsonStringEnumMemberName("gpt-6-luna")]
    Gpt6Luna
}
