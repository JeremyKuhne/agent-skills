// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  Pinned maintained library versions for the CPU runtime and tokenizer.
/// </summary>
/// <param name="OnnxRuntime">The exact ONNX Runtime package version.</param>
/// <param name="Tokenizers">The exact managed tokenizer package version.</param>
public sealed record GroundingRuntimeVersions(string OnnxRuntime, string Tokenizers);
