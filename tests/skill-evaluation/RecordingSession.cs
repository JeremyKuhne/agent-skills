// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Touki;

namespace SkillEvaluation.Tests;

/// <summary>
///  Records deterministic disposal at the session ownership boundary without native allocation.
/// </summary>
internal sealed class RecordingSession : DisposableBase
{
    /// <summary>
    ///  Gets the number of deterministic disposal operations.
    /// </summary>
    internal int DisposedCount { get; private set; }

    /// <summary>
    ///  Records release of the controlled owned session.
    /// </summary>
    /// <param name="disposing">Whether deterministic disposal was requested.</param>
    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            DisposedCount++;
        }
    }
}
