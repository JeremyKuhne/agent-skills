// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  The kind of written artifact evaluated by a content profile.
/// </summary>
public enum ArtifactKind
{
    /// <summary>
    ///  A pull request description.
    /// </summary>
    PrDescription,

    /// <summary>
    ///  A pull request review comment.
    /// </summary>
    ReviewComment,

    /// <summary>
    ///  A decision note.
    /// </summary>
    Decision
}
