// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Serialization;

namespace SkillEvaluation;

/// <summary>
///  The grounding-ledger mode, artifact, and format declared by a profile.
/// </summary>
/// <param name="Mode">Whether ledger consistency is ignored, diagnostic, or required.</param>
/// <param name="TargetId">The target containing the ledger. Defaults to <see langword="null"/>.</param>
/// <param name="Format">The ledger format identifier. Defaults to <see langword="null"/>.</param>
public sealed record LedgerConfiguration(
    LedgerMode Mode,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? TargetId = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? Format = null);
