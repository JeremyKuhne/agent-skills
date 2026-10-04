// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  A claim whose meaning must not appear in an artifact.
/// </summary>
/// <param name="Id">The claim check identifier.</param>
/// <param name="TargetId">The artifact in which the claim is forbidden.</param>
/// <param name="Text">The forbidden claim's meaning.</param>
/// <param name="Kind">The category of unsupported or unauthorized claim.</param>
/// <param name="FactRefs">The supplied-fact identifiers establishing the prohibition.</param>
public sealed record ForbiddenClaim(
    string Id,
    string TargetId,
    string Text,
    string Kind,
    string[] FactRefs);
