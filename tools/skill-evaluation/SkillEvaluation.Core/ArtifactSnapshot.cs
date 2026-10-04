// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  The source, stored location, and byte identity of a captured artifact.
/// </summary>
/// <param name="TargetId">The artifact identifier declared by the profile.</param>
/// <param name="Source">Whether the bytes came from an assistant message or a workspace file.</param>
/// <param name="SourcePath">The workspace-relative source file path, or null for a message artifact.</param>
/// <param name="StoredPath">The run-relative path of the captured bytes.</param>
/// <param name="Encoding">The detected UTF-8 encoding, including whether a byte-order mark is present.</param>
/// <param name="Sha256">The uppercase hexadecimal SHA-256 hash of the captured bytes.</param>
/// <param name="AssistantEventLine">
///  The one-based source event line for a message artifact.
///  Defaults to <see langword="null"/> for file artifacts.
/// </param>
public sealed record ArtifactSnapshot(
    string TargetId,
    ArtifactSource Source,
    string? SourcePath,
    string StoredPath,
    string Encoding,
    string Sha256,
    int? AssistantEventLine = null);
