// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using YamlDotNet.RepresentationModel;

namespace PowerShellToolchain.Tests;

internal static partial class PowerShellToolchainPolicy
{
    /// <summary>
    ///  Retains a workflow's path, deserialized values, and YAML tree for policy validation.
    /// </summary>
    /// <param name="Path">The workflow path used in policy diagnostics.</param>
    /// <param name="Value">The workflow's deserialized trigger and job values.</param>
    /// <param name="Root">The YAML document's root mapping for structural checks.</param>
    private sealed record ParsedWorkflow(string Path, WorkflowFile Value, YamlMappingNode Root);
}
