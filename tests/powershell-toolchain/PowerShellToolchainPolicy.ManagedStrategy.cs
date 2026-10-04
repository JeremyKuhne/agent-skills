// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using YamlDotNet.Serialization;

namespace PowerShellToolchain.Tests;

internal static partial class PowerShellToolchainPolicy
{
    /// <summary>
    ///  Deserializes the managed test job's matrix strategy.
    /// </summary>
    private sealed class ManagedStrategy
    {
        /// <summary>
        ///  Gets the strategy's explicit host and coverage matrix.
        /// </summary>
        /// <value>The deserialized matrix, or null when absent or explicitly null.</value>
        [YamlMember(Alias = "matrix")]
        public ManagedMatrix? Matrix { get; init; }
    }
}
