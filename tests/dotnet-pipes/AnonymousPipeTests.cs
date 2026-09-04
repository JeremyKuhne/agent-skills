using System.Diagnostics;
using System.IO.Pipes;
using DotNetPipes.TestSupport;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace DotNetPipes.Tests;

[TestClass]
public sealed class AnonymousPipeTests
{
    [TestMethod]
    public void Constructor_OutDirection_ExposesWriteOnlyServer()
    {
        using AnonymousPipeServerStream server = new(PipeDirection.Out, HandleInheritability.None);

        Assert.IsTrue(server.CanWrite);
        Assert.IsFalse(server.CanRead);
    }

    [TestMethod]
    [Timeout(10_000)]
    [DataRow(0)]
    [DataRow(4)]
    [DataRow(AnonymousPipeChild.MaxCaptureLength)]
    public async Task DisposeLocalCopyAndServer_Close_AllowsClientToObserveEndOfStream(int payloadLength)
    {
        await using AnonymousPipeServerStream server = new(
            PipeDirection.Out,
            HandleInheritability.Inheritable);
        using CancellationTokenSource testDeadline = new(TimeSpan.FromSeconds(8));
        using Process child = StartAnonymousChild(server.GetClientHandleAsString());

        try
        {
            server.DisposeLocalCopyOfClientHandle();

            byte[] expected = new byte[payloadLength];
            Random.Shared.NextBytes(expected);
            await server.WriteAsync(expected, testDeadline.Token);
            await server.DisposeAsync();

            string output = await child.StandardOutput.ReadToEndAsync(testDeadline.Token);
            string error = await child.StandardError.ReadToEndAsync(testDeadline.Token);
            await child.WaitForExitAsync(testDeadline.Token);

            Assert.AreEqual(0, child.ExitCode, error);
            CollectionAssert.AreEqual(expected, Convert.FromBase64String(output));
        }
        finally
        {
            if (!child.HasExited)
            {
                child.Kill(entireProcessTree: true);
            }

            await child.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(2));
        }
    }

    [TestMethod]
    [Timeout(10_000)]
    public async Task AnonymousChild_OversizedInput_IsRejected()
    {
        await using AnonymousPipeServerStream server = new(PipeDirection.Out, HandleInheritability.Inheritable);
        using CancellationTokenSource testDeadline = new(TimeSpan.FromSeconds(8));
        using Process child = StartAnonymousChild(server.GetClientHandleAsString());

        try
        {
            server.DisposeLocalCopyOfClientHandle();
            try
            {
                await server.WriteAsync(new byte[AnonymousPipeChild.MaxCaptureLength + 1], testDeadline.Token);
            }
            catch (IOException)
            {
            }

            await server.DisposeAsync();
            string output = await child.StandardOutput.ReadToEndAsync(testDeadline.Token);
            string error = await child.StandardError.ReadToEndAsync(testDeadline.Token);
            await child.WaitForExitAsync(testDeadline.Token);

            Assert.AreEqual(2, child.ExitCode, error);
            Assert.AreEqual(string.Empty, output);
            StringAssert.Contains(error, "capture limit");
        }
        finally
        {
            if (!child.HasExited)
            {
                child.Kill(entireProcessTree: true);
            }

            await child.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(2));
        }
    }

    private static Process StartAnonymousChild(string clientHandle)
    {
        string dotnetHost = Environment.GetEnvironmentVariable("DOTNET_HOST_PATH") ?? "dotnet";
        ProcessStartInfo startInfo = new(dotnetHost)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false
        };
        startInfo.ArgumentList.Add(typeof(AnonymousPipeChild).Assembly.Location);
        startInfo.ArgumentList.Add(clientHandle);

        return Process.Start(startInfo) ?? throw new InvalidOperationException("The anonymous-pipe child did not start.");
    }
}