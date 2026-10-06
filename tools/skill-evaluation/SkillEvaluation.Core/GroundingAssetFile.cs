// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  A locally provisioned model/tokenizer asset with explicit identity and source provenance.
/// </summary>
/// <param name="Role">The unique runtime or supporting-file role.</param>
/// <param name="Path">The owned relative file path.</param>
/// <param name="Sha256">The uppercase SHA-256 pin for raw bytes.</param>
/// <param name="Bytes">The exact pinned byte length.</param>
/// <param name="Source">The immutable HTTPS source URI or synthetic fixture provenance.</param>
public sealed record GroundingAssetFile(string Role, string Path, string Sha256, long Bytes, string Source);
