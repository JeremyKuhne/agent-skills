// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using YamlDotNet.Serialization;

namespace PowerShellToolchain.Tests;

internal static partial class PowerShellToolchainPolicy
{
    /// <summary>
    ///  Deserializes workflow jobs for the managed file-creation CI policy.
    /// </summary>
    private sealed class ManagedWorkflow
    {
        /// <summary>
        ///  Gets the deserialized jobs mapping.
        /// </summary>
        /// <value>Jobs keyed by identifier, or null for an explicit YAML null.</value>
        [YamlMember(Alias = "jobs")]
        public Dictionary<string, ManagedJob?>? Jobs { get; init; } = new(StringComparer.Ordinal);
    }
}
