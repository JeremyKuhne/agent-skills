// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Diagnostics;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace PowerShellToolchain.Tests;

public sealed partial class RepositoryPolicyTests
{
    private static string RunRepositoryProcess(ProcessStartInfo startInfo, string subject)
    {
        using Process process = Process.Start(startInfo)
            ?? throw new InvalidOperationException($"{subject} process did not start.");

        using CancellationTokenSource deadline = new(TimeSpan.FromMinutes(2));
        Task<string> outputTask = process.StandardOutput.ReadToEndAsync(deadline.Token);
        Task<string> errorTask = process.StandardError.ReadToEndAsync(deadline.Token);
        try
        {
            process.WaitForExitAsync(deadline.Token).GetAwaiter().GetResult();
        }
        finally
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
                process.WaitForExit();
            }
        }

        string output = outputTask.GetAwaiter().GetResult();
        string error = errorTask.GetAwaiter().GetResult();
        Assert.AreEqual(
            0,
            process.ExitCode,
            $"{subject} output:{Environment.NewLine}{output}{Environment.NewLine}{error}");

        return output;
    }
}
