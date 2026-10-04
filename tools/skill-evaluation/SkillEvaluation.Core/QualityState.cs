// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  The evaluation state of a check or aggregate outcome.
/// </summary>
public enum QualityState
{
    /// <summary>
    ///  The evaluated requirements are satisfied.
    /// </summary>
    Passed,

    /// <summary>
    ///  An evaluated requirement is not satisfied.
    /// </summary>
    Failed,

    /// <summary>
    ///  Required judgment has not been completed.
    /// </summary>
    Pending,

    /// <summary>
    ///  Available evidence does not resolve the outcome.
    /// </summary>
    Inconclusive,

    /// <summary>
    ///  The check or outcome does not apply.
    /// </summary>
    NotApplicable
}
