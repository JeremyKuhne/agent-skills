// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  Complete, untruncated tensors for one premise/claim pair.
/// </summary>
/// <param name="InputIds">The complete pair token sequence.</param>
/// <param name="AttentionMask">The non-padding attention mask.</param>
/// <param name="TokenTypeIds">The canonical premise/claim segment identifiers.</param>
public sealed record GroundingTokens(int[] InputIds, int[] AttentionMask, int[] TokenTypeIds);
