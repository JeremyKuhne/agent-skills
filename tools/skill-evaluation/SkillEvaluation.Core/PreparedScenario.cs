// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  A rendered scenario prompt and the revisions binding its evaluation inputs.
/// </summary>
/// <param name="ScenarioId">The scenario identifier.</param>
/// <param name="Prompt">The prompt with supplied facts substituted.</param>
/// <param name="ProfileRevision">The revision of the profile and resolved rubric items.</param>
/// <param name="InputRevision">The revision of the prompt and model-visible profile inputs.</param>
public sealed record PreparedScenario(
    string ScenarioId,
    string Prompt,
    string ProfileRevision,
    string InputRevision);
