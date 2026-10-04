// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  The factual or authority-bearing role of a supplied statement.
/// </summary>
public enum FactKind
{
    /// <summary>
    ///  A statement about the observed or supplied state.
    /// </summary>
    Fact,

    /// <summary>
    ///  An assignment of responsibility.
    /// </summary>
    Ownership,

    /// <summary>
    ///  A promise of future action.
    /// </summary>
    Commitment,

    /// <summary>
    ///  Authority to perform an action.
    /// </summary>
    Permission
}
