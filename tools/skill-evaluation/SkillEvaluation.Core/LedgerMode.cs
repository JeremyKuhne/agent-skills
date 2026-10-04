// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  Whether grounding-ledger consistency is checked and enforced.
/// </summary>
public enum LedgerMode
{
    /// <summary>
    ///  No grounding ledger is checked.
    /// </summary>
    Off,

    /// <summary>
    ///  Ledger consistency is checked without making it a hard gate.
    /// </summary>
    Diagnostic,

    /// <summary>
    ///  Ledger consistency is a hard gate for a useful outcome.
    /// </summary>
    Required
}
