// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Serialization;

namespace SkillEvaluation;

/// <summary>
///  A deterministic text or Markdown check for one artifact.
/// </summary>
/// <param name="Id">The literal check identifier.</param>
/// <param name="TargetId">The artifact to check.</param>
/// <param name="Kind">The text or Markdown requirement to apply.</param>
/// <param name="Text">The expected or forbidden text. Defaults to <see langword="null"/>.</param>
/// <param name="Level">The required heading level. Defaults to <see langword="null"/>.</param>
public sealed record LiteralCheck(
    string Id,
    string TargetId,
    LiteralKind Kind,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? Text = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] int? Level = null);
