// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  The content requirement assessed by an evaluation check.
/// </summary>
public enum CheckDimension
{
    /// <summary>
    ///  Exact text or Markdown structure.
    /// </summary>
    Literal,

    /// <summary>
    ///  Grounding-ledger identity and evidence-state consistency.
    /// </summary>
    Ledger,

    /// <summary>
    ///  Support for a required claim.
    /// </summary>
    RequiredClaim,

    /// <summary>
    ///  Absence of a forbidden claim.
    /// </summary>
    ForbiddenClaim,

    /// <summary>
    ///  A referenced rubric criterion.
    /// </summary>
    Rubric
}
