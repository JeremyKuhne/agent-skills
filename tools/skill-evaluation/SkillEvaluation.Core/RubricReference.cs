// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  Selected items from a revision-pinned rubric document.
/// </summary>
/// <param name="Path">The repository-relative rubric path.</param>
/// <param name="Revision">The expected revision of the rubric text.</param>
/// <param name="ItemIds">The rubric item identifiers selected for evaluation.</param>
public sealed record RubricReference(string Path, string Revision, string[] ItemIds);
