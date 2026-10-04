// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  A base-case cluster containing one valid control and one declared single-defect twin.
/// </summary>
/// <param name="Id">The case-cluster identifier.</param>
/// <param name="BasePacketId">The base packet identifier.</param>
/// <param name="TwinPacketId">The defective twin identifier.</param>
/// <param name="DefectKind">The proposed material-defect category.</param>
/// <param name="ChangedItemIds">Exactly the hard rubric items whose proposed verdicts flip.</param>
/// <param name="Edit">The one literal edit reproducing the twin without changing scenario inputs.</param>
public sealed record ReviewPacketPair(
    string Id,
    string BasePacketId,
    string TwinPacketId,
    string DefectKind,
    string[] ChangedItemIds,
    PacketEdit Edit);
