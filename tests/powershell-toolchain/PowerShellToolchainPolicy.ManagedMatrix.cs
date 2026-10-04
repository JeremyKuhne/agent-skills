// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using YamlDotNet.Serialization;

namespace PowerShellToolchain.Tests;

internal static partial class PowerShellToolchainPolicy
{
    /// <summary>
    ///  Deserializes the managed test matrix's explicit include rows.
    /// </summary>
    private sealed class ManagedMatrix
    {
        /// <summary>
        ///  Gets the matrix's explicit include rows.
        /// </summary>
        /// <value>The host and coverage rows, or null when absent or explicitly null.</value>
        [YamlMember(Alias = "include")]
        public List<ManagedMatrixRow?>? Include { get; init; }
    }
}
