// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using YamlDotNet.Serialization;

namespace PowerShellToolchain.Tests;

internal static partial class PowerShellToolchainPolicy
{
    /// <summary>
    ///  Deserializes workflow triggers and jobs for Pester execution-policy checks.
    /// </summary>
    private sealed class WorkflowFile
    {
        /// <summary>
        ///  Gets the workflow's trigger mapping.
        /// </summary>
        /// <value>Trigger names mapped to their YAML configuration values.</value>
        [YamlMember(Alias = "on")]
        public Dictionary<string, object?> On { get; init; } = new(StringComparer.Ordinal);

        /// <summary>
        ///  Gets the workflow's job mapping.
        /// </summary>
        /// <value>Job identifiers mapped to their deserialized job definitions.</value>
        [YamlMember(Alias = "jobs")]
        public Dictionary<string, WorkflowJob> Jobs { get; init; } = new(StringComparer.Ordinal);
    }
}
