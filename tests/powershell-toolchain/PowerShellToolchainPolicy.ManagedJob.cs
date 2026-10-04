// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using YamlDotNet.Serialization;

namespace PowerShellToolchain.Tests;

internal static partial class PowerShellToolchainPolicy
{
    /// <summary>
    ///  Deserializes a managed test job's host, matrix strategy, and steps.
    /// </summary>
    private sealed class ManagedJob
    {
        /// <summary>
        ///  Gets the job's runner label or expression.
        /// </summary>
        /// <value>The runs-on scalar, or null when no host is declared.</value>
        [YamlMember(Alias = "runs-on")]
        public string? RunsOn { get; init; }

        /// <summary>
        ///  Gets the job's matrix strategy.
        /// </summary>
        /// <value>The deserialized strategy, or null when absent or explicitly null.</value>
        [YamlMember(Alias = "strategy")]
        public ManagedStrategy? Strategy { get; init; }

        /// <summary>
        ///  Gets the job's ordered steps.
        /// </summary>
        /// <value>The deserialized step sequence, or null when absent or explicitly null.</value>
        [YamlMember(Alias = "steps")]
        public List<ManagedStep?>? Steps { get; init; }
    }
}
