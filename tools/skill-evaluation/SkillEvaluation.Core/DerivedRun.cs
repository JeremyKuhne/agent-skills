// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json;

namespace SkillEvaluation;

/// <summary>
///  A source attempt that may carry derived content results or an infrastructure error.
/// </summary>
/// <param name="ScenarioId">The source scenario identifier.</param>
/// <param name="RunNumber">The one-based source attempt number.</param>
/// <param name="SourceResult">The original run result retained from the capture summary.</param>
/// <param name="Content">The derived content evaluation, if available.</param>
/// <param name="InfrastructureError">The execution or evidence-verification failure message, if any.</param>
public sealed record DerivedRun(
    string ScenarioId,
    int RunNumber,
    JsonElement SourceResult,
    SemanticRecord? Content,
    string? InfrastructureError);
