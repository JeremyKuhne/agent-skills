// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  The artifacts, supplied evidence, and content requirements for a scenario.
/// </summary>
/// <param name="SchemaVersion">The content-profile schema version.</param>
/// <param name="ArtifactKind">The kind of written artifact being evaluated.</param>
/// <param name="ArtifactTargets">The outputs to capture and evaluate.</param>
/// <param name="SuppliedFacts">The evidence and authority supplied to the model.</param>
/// <param name="RequiredClaims">The claims that the artifacts must support.</param>
/// <param name="ForbiddenClaims">The claims that the artifacts must not make.</param>
/// <param name="LiteralChecks">The deterministic text and Markdown requirements.</param>
/// <param name="RubricRefs">The revision-pinned rubric items to assess.</param>
/// <param name="Ledger">The grounding-ledger requirements.</param>
public sealed record ContentProfile(
    int SchemaVersion,
    ArtifactKind ArtifactKind,
    ArtifactTarget[] ArtifactTargets,
    SuppliedFact[] SuppliedFacts,
    RequiredClaim[] RequiredClaims,
    ForbiddenClaim[] ForbiddenClaims,
    LiteralCheck[] LiteralChecks,
    RubricReference[] RubricRefs,
    LedgerConfiguration Ledger);
