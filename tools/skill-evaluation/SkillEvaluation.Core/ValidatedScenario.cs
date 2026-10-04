// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  A validated content profile with its resolved rubric and prepared prompt.
/// </summary>
/// <param name="Id">The scenario identifier.</param>
/// <param name="Profile">The validated content requirements and supplied evidence.</param>
/// <param name="RubricItems">The selected and source-verified rubric criteria.</param>
/// <param name="Preparation">The rendered prompt and input revisions prepared for capture.</param>
public sealed record ValidatedScenario(
    string Id,
    ContentProfile Profile,
    RubricItem[] RubricItems,
    PreparedScenario Preparation);
