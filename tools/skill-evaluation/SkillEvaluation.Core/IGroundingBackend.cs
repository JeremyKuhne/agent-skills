// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  Owns exact pair tokenization and explicit manual CPU dispatch without defining useful-output authority.
/// </summary>
public interface IGroundingBackend : IDisposable
{
    /// <summary>
    ///  Gets the actual implementation/dependency identity, including synthetic evidence status.
    /// </summary>
    GroundingBackendIdentity Identity { get; }

    /// <summary>
    ///  Encodes complete premise and claim text without inference or silent truncation.
    /// </summary>
    /// <param name="premise">The supplied authoritative fact text.</param>
    /// <param name="claim">The exact artifact claim quotation.</param>
    /// <returns>The complete pair tensors.</returns>
    GroundingTokens Encode(string premise, string claim);

    /// <summary>
    ///  Dispatches one already validated pair and returns explicit raw three-way scores.
    /// </summary>
    /// <param name="tokens">The complete preflight-validated tensors.</param>
    /// <returns>The raw finite logits in contradiction/entailment/neutral order.</returns>
    GroundingLogits Predict(GroundingTokens tokens);
}
