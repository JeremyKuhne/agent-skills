// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  A versioned local CPU-grounding asset contract, never permission to download or dispatch inference.
/// </summary>
/// <param name="SchemaVersion">The manifest contract version.</param>
/// <param name="ProfileId">The preprocessing/runtime profile identifier.</param>
/// <param name="ModelId">The upstream model identifier.</param>
/// <param name="ModelRevision">The immutable model-source revision.</param>
/// <param name="License">The declared license of the pinned source/export.</param>
/// <param name="Mode">The required report-only mode.</param>
/// <param name="MaximumTokens">The complete pair limit, with truncation forbidden.</param>
/// <param name="LabelOrder">The exact three-way output mapping.</param>
/// <param name="InputNames">The required model input tensor names.</param>
/// <param name="RuntimeVersions">The pinned runtime/tokenizer package identities.</param>
/// <param name="Files">The uniquely owned file closure and raw-byte pins.</param>
public sealed record GroundingAssetManifest(
    int SchemaVersion,
    string ProfileId,
    string ModelId,
    string ModelRevision,
    string License,
    string Mode,
    int MaximumTokens,
    GroundingRelation[] LabelOrder,
    string[] InputNames,
    GroundingRuntimeVersions RuntimeVersions,
    GroundingAssetFile[] Files);
