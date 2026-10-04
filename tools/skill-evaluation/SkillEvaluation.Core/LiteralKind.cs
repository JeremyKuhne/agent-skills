// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  A deterministic text or Markdown requirement.
/// </summary>
public enum LiteralKind
{
    /// <summary>
    ///  The artifact contains non-whitespace text.
    /// </summary>
    Nonempty,

    /// <summary>
    ///  An exact heading text appears at the specified Markdown level.
    /// </summary>
    Heading,

    /// <summary>
    ///  The opening paragraph starts with the specified text.
    /// </summary>
    StartsWith,

    /// <summary>
    ///  The specified text occurs verbatim.
    /// </summary>
    ContainsLiteral,

    /// <summary>
    ///  The specified text does not occur.
    /// </summary>
    ForbidsLiteral,

    /// <summary>
    ///  No Markdown paragraph spans multiple source lines.
    /// </summary>
    SingleLineParagraphs
}
