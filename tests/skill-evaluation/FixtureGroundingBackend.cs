// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Touki;

namespace SkillEvaluation.Tests;

/// <summary>
///  Explicit deterministic score/token fixture, never a learned-model readiness or accuracy result.
/// </summary>
internal sealed class FixtureGroundingBackend : DisposableBase, IGroundingBackend
{
    /// <summary>
    ///  Gets or sets the controlled identity, synthetic by default; identity-pairing tests may vary its marker.
    /// </summary>
    public GroundingBackendIdentity Identity { get; init; } = new(
        "synthetic-grounding-fixture", Synthetic: true, ContractJson.HashText("synthetic-backend/v1"),
        "synthetic-cpu", "synthetic-tokenizer");

    /// <summary>
    ///  Gets the number of tokenization calls.
    /// </summary>
    public int EncodedCount { get; private set; }

    /// <summary>
    ///  Gets the number of explicit deterministic prediction calls.
    /// </summary>
    public int PredictedCount { get; private set; }

    /// <summary>
    ///  Gets whether deterministic disposal completed.
    /// </summary>
    public bool WasDisposed { get; private set; }

    /// <summary>
    ///  Gets or sets an optional independently specified token mutation.
    /// </summary>
    public Func<int, GroundingTokens>? TokenFactory { get; set; }

    /// <summary>
    ///  Gets or sets the controlled finite or intentionally invalid logits.
    /// </summary>
    public GroundingLogits Logits { get; set; } = new(0, 10, 0);

    /// <summary>
    ///  Gets or sets an explicit test side effect at dispatch.
    /// </summary>
    public Action<GroundingTokens>? OnPredict { get; set; }

    /// <summary>
    ///  Returns controlled complete pair tokens without a tokenizer asset or native model.
    /// </summary>
    /// <param name="premise">The source premise.</param>
    /// <param name="claim">The source quote.</param>
    /// <returns>The deterministic fixture tensors.</returns>
    public GroundingTokens Encode(string premise, string claim)
    {
        EncodedCount++;
        return TokenFactory?.Invoke(EncodedCount)
            ?? new([1, 10, 2, 11, 2], [1, 1, 1, 1, 1], [0, 0, 0, 1, 1]);
    }

    /// <summary>
    ///  Returns only explicitly synthetic scores after counting the fixture dispatch.
    /// </summary>
    /// <param name="tokens">The full validated fixture tensors.</param>
    /// <returns>The controlled logits.</returns>
    public GroundingLogits Predict(GroundingTokens tokens)
    {
        PredictedCount++;
        OnPredict?.Invoke(tokens);
        return Logits;
    }

    /// <summary>
    ///  Records explicit disposal for failure-path assertions.
    /// </summary>
    /// <param name="disposing">Whether deterministic disposal was requested.</param>
    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            WasDisposed = true;
        }
    }
}
