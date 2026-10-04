// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using YamlDotNet.Serialization;

namespace PowerShellToolchain.Tests;

internal static partial class PowerShellToolchainPolicy
{
    /// <summary>
    ///  Retains a managed matrix row's host and raw coverage value for strict policy validation.
    /// </summary>
    private sealed class ManagedMatrixRow
    {
        /// <summary>
        ///  Gets the row's operating-system runner label.
        /// </summary>
        /// <value>The os scalar, or null when absent or explicitly null.</value>
        [YamlMember(Alias = "os")]
        public string? OperatingSystem { get; init; }

        /// <summary>
        ///  Gets the parsed coverage value before Boolean policy validation.
        /// </summary>
        /// <value>The YAML coverage scalar, which policy requires to be a Boolean.</value>
        [YamlMember(Alias = "coverage")]
        public object? Coverage { get; init; }
    }
}
