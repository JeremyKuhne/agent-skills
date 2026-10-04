// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace PowerShellToolchain.Tests;

internal static partial class PowerShellToolchainPolicy
{
    /// <summary>
    ///  Retains a workflow's path and deserialized values for policy validation.
    /// </summary>
    /// <param name="Path">The workflow path used in policy diagnostics.</param>
    /// <param name="Value">The workflow's deserialized trigger and job values.</param>
    private sealed record ParsedWorkflow(string Path, WorkflowFile Value);
}
