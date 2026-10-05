// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  Explicit-probe diagnostic evidence, separate from capture verdicts and learned qualification.
/// </summary>
/// <param name="SchemaVersion">The diagnostic record version.</param>
/// <param name="EvidenceMode">The manual diagnostic evidence identifier.</param>
/// <param name="Coverage">The explicit-probe-only scope, not whole-prose coverage.</param>
/// <param name="BankId">The source development-bank identifier.</param>
/// <param name="BankRevision">The LF-normalized immutable bank revision.</param>
/// <param name="AssetRevision">The verified model/tokenizer closure revision.</param>
/// <param name="GroundingRevision">The revision binding all material semantic/preprocessing inputs.</param>
/// <param name="ModelId">The pinned model identifier.</param>
/// <param name="ModelRevision">The pinned upstream model revision.</param>
/// <param name="Backend">The actual computation owner, including synthetic evidence status.</param>
/// <param name="ReviewEvidence">The separate source-bound declared human development judgments.</param>
/// <param name="ProbeCount">The number of explicitly selected probes.</param>
/// <param name="UsefulPassedCount">The useful-pass count, always zero for uncalibrated diagnostics.</param>
/// <param name="UsefulOutcome">The pending useful-outcome state.</param>
/// <param name="CalibrationStatus">The pending calibration state.</param>
/// <param name="Probes">The complete source-bound probe results.</param>
public sealed record GroundingDiagnosticSummary(
    int SchemaVersion,
    string EvidenceMode,
    string Coverage,
    string BankId,
    string BankRevision,
    string AssetRevision,
    string GroundingRevision,
    string ModelId,
    string ModelRevision,
    GroundingBackendIdentity Backend,
    GroundingReviewEvidence ReviewEvidence,
    int ProbeCount,
    int UsefulPassedCount,
    QualityState UsefulOutcome,
    QualityState CalibrationStatus,
    GroundingProbeResult[] Probes);
