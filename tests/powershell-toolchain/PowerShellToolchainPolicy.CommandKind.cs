// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace PowerShellToolchain.Tests;

internal static partial class PowerShellToolchainPolicy
{
    /// <summary>
    ///  Classifies commands relevant to Pester bootstrap and execution policy.
    /// </summary>
    private enum CommandKind
    {
        /// <summary>
        ///  A command that is not a recognized Pester bootstrap or execution command.
        /// </summary>
        Other,

        /// <summary>
        ///  An Install-Module command targeting Pester.
        /// </summary>
        Install,

        /// <summary>
        ///  A command whose final path segment is Invoke-PesterShards.ps1.
        /// </summary>
        Runner,

        /// <summary>
        ///  An Invoke-Pester invocation, including qualified command names.
        /// </summary>
        DirectPester
    }
}
