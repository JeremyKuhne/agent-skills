// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Diagnostics;
using DotNetPipes.Sample;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace DotNetPipes.Tests;

/// <summary>
///  Verifies that the standalone sample reports only its public command forms.
/// </summary>
[TestClass]
public sealed class ProgramTests
{
    /// <summary>
    ///  Verifies that invalid arguments print the public usage text without exposing the test child.
    /// </summary>
    /// <param name="requestTestHelper">Whether to pass the test-only child command to the sample.</param>
    /// <returns>A task representing the test.</returns>
    [TestMethod]
    [Timeout(10_000)]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public async Task MainInvalidArgumentsPrintsPublicCommandForms(bool requestTestHelper)
    {
        string dotnetHost = Environment.GetEnvironmentVariable("DOTNET_HOST_PATH") ?? "dotnet";
        ProcessStartInfo startInfo = new(dotnetHost)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false
        };

        startInfo.ArgumentList.Add(typeof(PipeFrames).Assembly.Location);
        if (requestTestHelper)
        {
            startInfo.ArgumentList.Add("anonymous-child");
            startInfo.ArgumentList.Add("invalid-handle");
        }

        using Process sample = Process.Start(startInfo)
            ?? throw new InvalidOperationException("The bounded-pipe sample did not start.");

        using CancellationTokenSource testDeadline = new(TimeSpan.FromSeconds(8));

        Task<string> outputTask = sample.StandardOutput.ReadToEndAsync(testDeadline.Token);
        Task<string> errorTask = sample.StandardError.ReadToEndAsync(testDeadline.Token);
        await sample.WaitForExitAsync(testDeadline.Token);

        string output = await outputTask;
        string error = await errorTask;

        Assert.AreEqual(1, sample.ExitCode);
        Assert.AreEqual(string.Empty, output);
        StringAssert.Contains(error, "BoundedPipeEcho server <pipe-name> [max-clients]");
        StringAssert.Contains(error, "BoundedPipeEcho client <pipe-name> <message>");
        Assert.IsFalse(error.Contains("anonymous-child", StringComparison.Ordinal));
        StringAssert.Contains(error, "max-clients defaults to 4 and must be between 1 and 254.");
    }
}