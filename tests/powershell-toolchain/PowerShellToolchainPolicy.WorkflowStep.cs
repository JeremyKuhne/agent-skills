// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using YamlDotNet.Serialization;

namespace PowerShellToolchain.Tests;

internal static partial class PowerShellToolchainPolicy
{
    /// <summary>
    ///  Deserializes a workflow step's condition, shell, and run script.
    /// </summary>
    private sealed class WorkflowStep
    {
        /// <summary>
        ///  Gets the optional step-level condition.
        /// </summary>
        /// <value>The if expression, or null when the step has no condition.</value>
        [YamlMember(Alias = "if")]
        public string? Condition { get; init; }

        /// <summary>
        ///  Gets the explicitly specified step shell.
        /// </summary>
        /// <value>The shell name, or null when no shell is declared.</value>
        [YamlMember(Alias = "shell")]
        public string? Shell { get; init; }

        /// <summary>
        ///  Gets the step's script source.
        /// </summary>
        /// <value>The run scalar's text, or null for a step without a run script.</value>
        [YamlMember(Alias = "run")]
        public string? Run { get; init; }
    }
}
