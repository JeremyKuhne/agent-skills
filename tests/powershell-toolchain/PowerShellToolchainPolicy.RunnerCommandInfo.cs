// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Management.Automation.Language;

namespace PowerShellToolchain.Tests;

internal static partial class PowerShellToolchainPolicy
{
    /// <summary>
    ///  Associates a classified PowerShell command with its workflow job and step.
    /// </summary>
    /// <param name="WorkflowPath">The workflow path containing the command.</param>
    /// <param name="JobId">The containing job's identifier.</param>
    /// <param name="StepIndex">The step's zero-based position in the job.</param>
    /// <param name="Step">The containing step's deserialized metadata.</param>
    /// <param name="Script">The parsed PowerShell script for the step.</param>
    /// <param name="Command">The command's syntax node within the script.</param>
    /// <param name="Kind">The command's Pester execution-policy classification.</param>
    private sealed record RunnerCommandInfo(
        string WorkflowPath,
        string JobId,
        int StepIndex,
        WorkflowStep Step,
        ScriptBlockAst Script,
        CommandAst Command,
        CommandKind Kind);
}
