// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  A structural preparation receipt that explicitly leaves human review and calibration pending.
/// </summary>
/// <param name="BankId">The validated bank identifier.</param>
/// <param name="SourceRevision">The LF-normalized source-document revision.</param>
/// <param name="EngineRevision">The SHA-256 identity of the preparation engine assembly.</param>
/// <param name="Runtime">The managed runtime identity used for preparation.</param>
/// <param name="Revision">The revision binding the bank, resolved profiles, and preparation engine.</param>
/// <param name="PacketCount">The artifact count, including twins.</param>
/// <param name="ClusterCount">The distinct base-case cluster count, not independent artifact observations.</param>
/// <param name="ScenarioCount">The distinct scenario-input count.</param>
/// <param name="PrDescriptionCount">The number of PR-description packets.</param>
/// <param name="ReviewCommentCount">The number of review-comment packets.</param>
/// <param name="ProposedLabelCount">The assistant-proposed rubric-label count.</param>
/// <param name="GroundingProbeCount">The explicit claim/fact probe count.</param>
/// <param name="LiteralPassedCount">The number of artifacts passing only their literal checks.</param>
/// <param name="LiteralFailedCount">The number of artifacts failing literal checks.</param>
/// <param name="HumanReviewedCount">The independently human-reviewed count, always zero for this contract.</param>
/// <param name="HumanReviewStatus">The pending independent human-review state.</param>
/// <param name="CalibrationStatus">The pending classifier/judge calibration state.</param>
public sealed record ReviewPacketSummary(
    string BankId,
    string SourceRevision,
    string EngineRevision,
    string Runtime,
    string Revision,
    int PacketCount,
    int ClusterCount,
    int ScenarioCount,
    int PrDescriptionCount,
    int ReviewCommentCount,
    int ProposedLabelCount,
    int GroundingProbeCount,
    int LiteralPassedCount,
    int LiteralFailedCount,
    int HumanReviewedCount,
    QualityState HumanReviewStatus,
    QualityState CalibrationStatus);
