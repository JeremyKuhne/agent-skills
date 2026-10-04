// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  The revisions and artifact count returned by a completed capture.
/// </summary>
/// <param name="ProfileRevision">The revision of the capture profile and resolved rubric.</param>
/// <param name="InputRevision">The revision of the prompt, facts, and target contract used by capture.</param>
/// <param name="ArtifactManifestRevision">The revision of the stored artifact manifest.</param>
/// <param name="ModelOutputRevision">The revision of the captured model-output files.</param>
/// <param name="ArtifactCount">The number of artifacts stored in the capture.</param>
public sealed record CaptureReceipt(
    string ProfileRevision,
    string InputRevision,
    string ArtifactManifestRevision,
    string ModelOutputRevision,
    int ArtifactCount);
