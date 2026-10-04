// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  The evidence status assigned to a supplied fact.
/// </summary>
public enum EvidenceState
{
    /// <summary>
    ///  A statement supported directly by the supplied evidence.
    /// </summary>
    Verified,

    /// <summary>
    ///  A conclusion inferred from the supplied evidence.
    /// </summary>
    Inference,

    /// <summary>
    ///  An unverified explanation or prediction.
    /// </summary>
    Hypothesis,

    /// <summary>
    ///  Information not established by the supplied evidence.
    /// </summary>
    Unknown
}
