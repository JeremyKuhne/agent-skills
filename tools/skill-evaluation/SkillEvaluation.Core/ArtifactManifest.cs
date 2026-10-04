// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  The revision-bound inventory of artifacts captured for one scenario attempt.
/// </summary>
/// <param name="SchemaVersion">The artifact-manifest schema version.</param>
/// <param name="ScenarioId">The captured scenario identifier.</param>
/// <param name="RunNumber">The one-based attempt number for the scenario.</param>
/// <param name="ScenarioRevision">The revision of the scenario used for capture.</param>
/// <param name="ProfileRevision">The revision of the capture profile and resolved rubric.</param>
/// <param name="InputRevision">The revision of the model-visible scenario inputs.</param>
/// <param name="ModelOutputRevision">The revision of the captured model-output files.</param>
/// <param name="Artifacts">The captured artifact locations and byte hashes.</param>
public sealed record ArtifactManifest(
    int SchemaVersion,
    string ScenarioId,
    int RunNumber,
    string ScenarioRevision,
    string ProfileRevision,
    string InputRevision,
    string ModelOutputRevision,
    ArtifactSnapshot[] Artifacts);
