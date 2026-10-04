// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  The literal operations admitted for a single-defect twin.
/// </summary>
public enum PacketEditKind
{
    /// <summary>
    ///  Replace one uniquely identified source quotation.
    /// </summary>
    Replace,

    /// <summary>
    ///  Append text without changing the existing artifact.
    /// </summary>
    Append
}
