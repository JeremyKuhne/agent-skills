// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  A source-text location supporting an evaluation result.
/// </summary>
/// <param name="Start">The zero-based UTF-16 offset of the evidence.</param>
/// <param name="Length">The evidence length in UTF-16 code units.</param>
/// <param name="Line">The one-based source line containing the start of the evidence.</param>
public sealed record EvidenceSpan(int Start, int Length, int Line);
