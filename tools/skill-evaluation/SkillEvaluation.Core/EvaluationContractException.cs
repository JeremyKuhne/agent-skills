// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  Signals an invalid evaluation contract or inconsistent captured evidence.
/// </summary>
/// <param name="message">The explanation of the contract or evidence failure.</param>
public sealed class EvaluationContractException(string message) : Exception(message);
