// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  Models a single skill-quality campaign with expected run inventory, observed runs, and blinded judge records.
/// </summary>
/// <param name="SchemaVersion">The campaign schema version.</param>
/// <param name="CampaignId">The frozen campaign identifier.</param>
/// <param name="CriteriaRevision">The criteria revision controlling the campaign.</param>
/// <param name="ExpectedSkillIds">The expected skill identifiers in this campaign.</param>
/// <param name="Criteria">The frozen per-skill item identifiers and their hard/advisory strength.</param>
/// <param name="ExpectedRunInventory">The explicit scheduled or attempted inventory expected to exist.</param>
/// <param name="ActualRunRecords">The observed actual-run records.</param>
/// <param name="JudgeRecords">The blinded judge records from the allowed model pool.</param>
public sealed record SkillQualityCampaign(
    int SchemaVersion,
    string CampaignId,
    string CriteriaRevision,
    string[] ExpectedSkillIds,
    SkillQualityCriterion[] Criteria,
    SkillQualityRunRecord[] ExpectedRunInventory,
    SkillQualityRunRecord[] ActualRunRecords,
    SkillQualityJudgeRecord[] JudgeRecords);
