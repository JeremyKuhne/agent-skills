// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  A review control's prompt and authoritative content inputs, separate from scheduled capture scenarios.
/// </summary>
/// <param name="Id">The review scenario identifier.</param>
/// <param name="Prompt">The prompt containing one supplied-facts placeholder.</param>
/// <param name="ContentEvaluation">The versioned content profile and rubric references.</param>
public sealed record ReviewScenario(string Id, string Prompt, ContentProfile ContentEvaluation);
