// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  A checked local asset closure whose files must be reverified before and after manual dispatch.
/// </summary>
/// <param name="Root">The ordinary directory owning all assets.</param>
/// <param name="ManifestPath">The owned manifest file.</param>
/// <param name="ManifestRevision">The LF-normalized source manifest revision.</param>
/// <param name="AssetRevision">The revision binding the complete manifest and file inventory.</param>
/// <param name="Manifest">The strict declared manifest.</param>
/// <param name="Paths">The verified absolute file paths indexed by role.</param>
public sealed record VerifiedGroundingAssets(
    string Root,
    string ManifestPath,
    string ManifestRevision,
    string AssetRevision,
    GroundingAssetManifest Manifest,
    IReadOnlyDictionary<string, string> Paths);
