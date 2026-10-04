// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  A single exact replacement or append operation constructing a defect twin.
/// </summary>
/// <param name="Kind">The edit operation.</param>
/// <param name="BeforeQuote">The unique replaced text, absent for an append.</param>
/// <param name="AfterText">The replacement or appended text.</param>
public sealed record PacketEdit(PacketEditKind Kind, string? BeforeQuote, string AfterText);
