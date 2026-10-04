// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  A claim that an artifact must support, with optional verbatim text requirements.
/// </summary>
/// <param name="Id">The claim check identifier.</param>
/// <param name="TargetId">The artifact that must contain the claim.</param>
/// <param name="Text">The required claim's meaning.</param>
/// <param name="FactRefs">The supplied-fact identifiers supporting the claim.</param>
/// <param name="VerbatimTokens">The exact text tokens also required in the artifact.</param>
public sealed record RequiredClaim(
    string Id,
    string TargetId,
    string Text,
    string[] FactRefs,
    string[] VerbatimTokens);
