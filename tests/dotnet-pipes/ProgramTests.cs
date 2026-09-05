using System.Diagnostics;
using DotNetPipes.Sample;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace DotNetPipes.Tests;

[TestClass]
public sealed class ProgramTests
{
    [TestMethod]
    [Timeout(10_000)]
    [DataRow(false)]
    [DataRow(true)]
    public async Task Main_InvalidArguments_PrintsPublicCommandForms(bool requestTestHelper)
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