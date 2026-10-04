// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  The captured output from which an artifact is obtained.
/// </summary>
public enum ArtifactSource
{
    /// <summary>
    ///  The terminal assistant message in captured JSONL output.
    /// </summary>
    LastMessage,

    /// <summary>
    ///  A file produced in the scenario workspace.
    /// </summary>
    File
}
