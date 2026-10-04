// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  A quotation from revision-pinned source text supporting a rubric item.
/// </summary>
/// <param name="Path">The repository-relative source path.</param>
/// <param name="Revision">The expected revision of the source text.</param>
/// <param name="Quote">The source quotation supporting the criterion.</param>
public sealed record RubricSource(string Path, string Revision, string Quote);
