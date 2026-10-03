// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace PowerShellToolchain.Tests;

/// <summary>
///  Reports rejected toolchain metadata, source syntax, or workflow execution policy.
/// </summary>
/// <param name="message">The policy violation's description.</param>
/// <param name="innerException">The originating parser failure, when one caused the policy violation.</param>
internal sealed class ToolchainPolicyException(string message, Exception? innerException = null)
    : Exception(message, innerException);
