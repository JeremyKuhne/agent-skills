// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  Development-only review controls whose proposed labels are not independent human ground truth.
/// </summary>
/// <param name="SchemaVersion">The review-packet contract version.</param>
/// <param name="Id">The packet-bank identifier.</param>
/// <param name="DatasetRole">The development-only role of this public packet bank.</param>
/// <param name="LabelAuthority">The assistant-proposed status of the labels.</param>
/// <param name="Scenarios">The single-source prompts, facts, profiles, and pinned rubrics.</param>
/// <param name="Packets">The base and defect-twin artifact packets.</param>
/// <param name="Pairs">The paired case clusters and their declared single edits.</param>
public sealed record ReviewPacketBank(
    int SchemaVersion,
    string Id,
    string DatasetRole,
    string LabelAuthority,
    ReviewScenario[] Scenarios,
    ReviewPacket[] Packets,
    ReviewPacketPair[] Pairs);
