// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  A versioned collection of source-grounded content criteria.
/// </summary>
/// <param name="SchemaVersion">The rubric schema version.</param>
/// <param name="Id">The rubric document identifier.</param>
/// <param name="Items">The criteria defined by the rubric.</param>
public sealed record RubricDocument(int SchemaVersion, string Id, RubricItem[] Items);
