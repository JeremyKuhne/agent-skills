// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using YamlDotNet.Serialization;

namespace PowerShellToolchain.Tests;

internal static partial class PowerShellToolchainPolicy
{
    /// <summary>
    ///  Deserializes a workflow job's host, condition, and ordered steps.
    /// </summary>
    private sealed class WorkflowJob
    {
        /// <summary>
        ///  Gets the job's runner label or expression.
        /// </summary>
        /// <value>The runs-on scalar, or null when no host is declared.</value>
        [YamlMember(Alias = "runs-on")]
        public string? RunsOn { get; init; }

        /// <summary>
        ///  Gets the optional job-level condition.
        /// </summary>
        /// <value>The if expression, or null when the job has no condition.</value>
        [YamlMember(Alias = "if")]
        public string? Condition { get; init; }

        /// <summary>
        ///  Gets the job's ordered steps.
        /// </summary>
        /// <value>The deserialized step sequence in declaration order.</value>
        [YamlMember(Alias = "steps")]
        public List<WorkflowStep> Steps { get; init; } = [];
    }
}
