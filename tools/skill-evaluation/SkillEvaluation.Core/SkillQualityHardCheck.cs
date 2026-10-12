// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  A single named executable hard check that must pass before a task can be treated as complete.
/// </summary>
/// <param name="Id">The check identifier.</param>
/// <param name="Name">The check name.</param>
/// <param name="Status">The result state of the check.</param>
/// <param name="Evidence">The evidence observing the check.</param>
/// <param name="Why">The rationale for the result.</param>
public sealed record SkillQualityHardCheck(
    string Id,
    string Name,
    SkillQualityCheckState Status,
    string Evidence,
    string Why);
