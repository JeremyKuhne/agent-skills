// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  The actual computation owner and implementation identity for diagnostic grounding.
/// </summary>
/// <param name="Id">The backend implementation identifier.</param>
/// <param name="Synthetic">Whether the output comes from a deterministic fixture rather than a learned model.</param>
/// <param name="Revision">The implementation/dependency revision.</param>
/// <param name="Runtime">The actual runtime identity.</param>
/// <param name="Tokenizer">The actual tokenizer identity.</param>
public sealed record GroundingBackendIdentity(
    string Id, bool Synthetic, string Revision, string Runtime, string Tokenizer);
