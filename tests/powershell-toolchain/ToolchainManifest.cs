// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace PowerShellToolchain.Tests;

/// <summary>
///  Carries the retained-test host requirement, Pester compatibility floor, and Pester execution lock.
/// </summary>
/// <param name="SchemaVersion">The toolchain manifest's schema version.</param>
/// <param name="TestMinimumVersion">The PowerShell version required by retained tests and the canonical runner.</param>
/// <param name="PesterCompatibilityMinimumVersion">The minimum Pester version declared by retained tests.</param>
/// <param name="PesterExecutionVersion">The exact Pester version used by the canonical runner and CI bootstrap.</param>
internal sealed record ToolchainManifest(
    int SchemaVersion,
    string TestMinimumVersion,
    string PesterCompatibilityMinimumVersion,
    string PesterExecutionVersion);
