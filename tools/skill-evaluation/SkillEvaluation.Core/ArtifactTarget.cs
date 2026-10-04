// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Serialization;

namespace SkillEvaluation;

/// <summary>
///  An artifact source selected for capture and evaluation.
/// </summary>
/// <param name="Id">The artifact identifier used by profile checks.</param>
/// <param name="Source">Whether to capture the last assistant message or a workspace file.</param>
/// <param name="Path">The workspace-relative file path, if any. Defaults to <see langword="null"/>.</param>
public sealed record ArtifactTarget(
    string Id,
    ArtifactSource Source,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? Path = null);
