// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  The grounding-specific projection of a completed local human review, kept separate from proposals.
/// </summary>
/// <param name="SessionId">The source review-session identifier.</param>
/// <param name="SourceRevision">The LF-normalized entire review-document revision.</param>
/// <param name="BankRevision">The bank revision reviewed by that session.</param>
/// <param name="AuthorityScope">The declared human development-label scope, not authenticated qualification.</param>
/// <param name="Labels">The complete explicit probe labels.</param>
public sealed record GroundingReviewEvidence(
    string SessionId,
    string SourceRevision,
    string BankRevision,
    string AuthorityScope,
    ReviewedGroundingLabel[] Labels);
