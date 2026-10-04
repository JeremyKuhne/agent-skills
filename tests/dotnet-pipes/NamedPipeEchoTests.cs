// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers.Binary;
using System.IO.Pipes;
using DotNetPipes.Sample;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace DotNetPipes.Tests;

/// <summary>
///  Verifies bounded same-user pipe exchanges, worker recovery, and cancellation.
/// </summary>
[TestClass]
public sealed class NamedPipeEchoTests
{
    /// <summary>
    ///  Verifies that rejecting an unauthorized peer does not reject the next accepted peer.
    /// </summary>
    /// <returns>A task representing the test.</returns>
    [TestMethod]
    public async Task TryAcceptClientAsyncRejectedPeerAllowsNextAcceptedPeer()
    {
        bool rejected = await NamedPipeEchoServer.TryAcceptClientAsync(
            Task.FromException(new UnauthorizedAccessException()));

        bool accepted = await NamedPipeEchoServer.TryAcceptClientAsync(Task.CompletedTask);

        Assert.IsFalse(rejected);
        Assert.IsTrue(accepted);
    }

    /// <summary>
    ///  Verifies that an unexpected accept failure propagates unchanged.
    /// </summary>
    /// <returns>A task representing the test.</returns>
    [TestMethod]
    public async Task TryAcceptClientAsyncUnexpectedFailurePropagates()
    {
        IOException failure = new("The accept operation failed.");

        IOException actual = await Assert.ThrowsExactlyAsync<IOException>(
            () => NamedPipeEchoServer.TryAcceptClientAsync(Task.FromException(failure)));

        Assert.AreSame(failure, actual);
    }

    /// <summary>
    ///  Verifies that a canceled accept propagates as cancellation.
    /// </summary>
    /// <returns>A task representing the test.</returns>
    [TestMethod]
    public async Task TryAcceptClientAsyncCanceledAcceptPropagates()
    {
        using CancellationTokenSource cancellation = new();
        cancellation.Cancel();

        await Assert.ThrowsAsync<OperationCanceledException>(
            () => NamedPipeEchoServer.TryAcceptClientAsync(Task.FromCanceled(cancellation.Token)));
    }

    /// <summary>
    ///  Verifies that a running server returns the request payload.
    /// </summary>
    /// <returns>A task representing the test.</returns>
    [TestMethod]
    [Timeout(10_000)]
    public async Task EchoAsyncServerRunningRoundTripsPayload()
    {
        string pipeName = CreatePipeName();
        using CancellationTokenSource serverShutdown = new();
        Task serverTask = NamedPipeEchoServer.RunAsync(pipeName, 2, serverShutdown.Token);

        try
        {
            byte[] expected = [0x10, 0x20, 0x30, 0x40];
            byte[] actual = await NamedPipeEchoClient.EchoAsync(
                pipeName,
                expected,
                TimeSpan.FromSeconds(5),
                CancellationToken.None);

            CollectionAssert.AreEqual(expected, actual);
        }
        finally
        {
            await StopServerAsync(serverShutdown, serverTask);
        }
    }

    /// <summary>
    ///  Verifies that clients held open require enough concurrent server workers for every reply.
    /// </summary>
    /// <param name="workerCount">The number of server workers.</param>
    /// <param name="expectAllReplies">Whether every client should receive a reply before the deadline.</param>
    /// <returns>A task representing the test.</returns>
    [TestMethod]
    [Timeout(10_000)]
    [DataRow(4, true)]
    [DataRow(1, false)]
    public async Task RunAsyncClientsHeldOpenRequiresConcurrentWorkers(int workerCount, bool expectAllReplies)
    {
        const int clientCount = 4;
        string pipeName = CreatePipeName();
        using CancellationTokenSource serverShutdown = new();
        using CancellationTokenSource testDeadline = new(
            expectAllReplies ? TimeSpan.FromSeconds(5) : TimeSpan.FromMilliseconds(500));

        Task serverTask = NamedPipeEchoServer.RunAsync(pipeName, workerCount, serverShutdown.Token);
        List<NamedPipeClientStream> clients = [];

        try
        {
            for (int index = 0; index < clientCount; index++)
            {
                clients.Add(new NamedPipeClientStream(
                    ".",
                    pipeName,
                    PipeDirection.InOut,
                    PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly));
            }

            Task<byte[]>[] clientTasks = new Task<byte[]>[clientCount];
            for (int index = 0; index < clientTasks.Length; index++)
            {
                clientTasks[index] = ExchangeFrameAsync(clients[index], index, testDeadline.Token);
            }

            Task<byte[][]> allReplies = Task.WhenAll(clientTasks);
            if (!expectAllReplies)
            {
                await Assert.ThrowsAsync<OperationCanceledException>(() => allReplies);
                return;
            }

            byte[][] responses = await allReplies;
            for (int index = 0; index < responses.Length; index++)
            {
                CollectionAssert.AreEqual(BitConverter.GetBytes(index), responses[index]);
            }
        }
        finally
        {
            foreach (NamedPipeClientStream client in clients)
            {
                await client.DisposeAsync();
            }

            await StopServerAsync(serverShutdown, serverTask);
        }
    }

    /// <summary>
    ///  Verifies that canceling pending accepts completes server shutdown normally.
    /// </summary>
    /// <returns>A task representing the test.</returns>
    [TestMethod]
    [Timeout(10_000)]
    public async Task RunAsyncPendingAcceptsAreCanceledCompletesNormally()
    {
        using CancellationTokenSource serverShutdown = new();
        Task serverTask = NamedPipeEchoServer.RunAsync(CreatePipeName(), 4, serverShutdown.Token);

        serverShutdown.Cancel();

        await serverTask;
        Assert.AreEqual(TaskStatus.RanToCompletion, serverTask.Status);
    }

    /// <summary>
    ///  Verifies that a startup failure cancels sibling workers and releases their pipe instances.
    /// </summary>
    /// <returns>A task representing the test.</returns>
    [TestMethod]
    [Timeout(10_000)]
    public async Task RunAsyncPartialStartupFailureCancelsWorkersAndReportsFailure()
    {
        string pipeName = CreatePipeName();
        using NamedPipeServerStream existingInstance = new(
            pipeName,
            PipeDirection.InOut,
            2,
            PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);

        using CancellationTokenSource serverShutdown = new();
        Task serverTask = NamedPipeEchoServer.RunAsync(pipeName, 2, serverShutdown.Token);

        try
        {
            await Assert.ThrowsExactlyAsync<IOException>(
                () => serverTask.WaitAsync(TimeSpan.FromSeconds(2)));

            Assert.IsFalse(serverShutdown.IsCancellationRequested);

            using NamedPipeServerStream replacementInstance = new(
                pipeName,
                PipeDirection.InOut,
                2,
                PipeTransmissionMode.Byte,
                PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
        }
        finally
        {
            serverShutdown.Cancel();
            try
            {
                await serverTask.WaitAsync(TimeSpan.FromSeconds(2));
            }
            catch (IOException)
            {
            }
        }
    }

    /// <summary>
    ///  Verifies that rejecting a negative frame length does not stop later clients.
    /// </summary>
    /// <returns>A task representing the test.</returns>
    [TestMethod]
    [Timeout(10_000)]
    public async Task RunAsyncNegativeLengthDisconnectsNextClientStillSucceeds()
    {
        byte[] invalidHeader = new byte[sizeof(int)];
        BinaryPrimitives.WriteInt32BigEndian(invalidHeader, -1);

        await AssertMalformedClientDoesNotStopServerAsync(invalidHeader);
    }

    /// <summary>
    ///  Verifies that a truncated header does not stop later clients.
    /// </summary>
    /// <returns>A task representing the test.</returns>
    [TestMethod]
    [Timeout(10_000)]
    public async Task RunAsyncTruncatedHeaderDisconnectsNextClientStillSucceeds()
    {
        await AssertMalformedClientDoesNotStopServerAsync([0x00, 0x00]);
    }

    /// <summary>
    ///  Verifies that a truncated payload does not stop later clients.
    /// </summary>
    /// <returns>A task representing the test.</returns>
    [TestMethod]
    [Timeout(10_000)]
    public async Task RunAsyncTruncatedPayloadDisconnectsNextClientStillSucceeds()
    {
        byte[] truncatedFrame = new byte[sizeof(int) + 2];
        BinaryPrimitives.WriteInt32BigEndian(truncatedFrame, 4);
        truncatedFrame[^2] = 0x10;
        truncatedFrame[^1] = 0x20;

        await AssertMalformedClientDoesNotStopServerAsync(truncatedFrame);
    }

    /// <summary>
    ///  Verifies that connecting to an absent server reports a timeout.
    /// </summary>
    /// <returns>A task representing the test.</returns>
    [TestMethod]
    [Timeout(10_000)]
    public async Task EchoAsyncServerAbsentThrowsTimeoutException()
    {
        await Assert.ThrowsExactlyAsync<TimeoutException>(
            () => NamedPipeEchoClient.EchoAsync(
                CreatePipeName(),
                ReadOnlyMemory<byte>.Empty,
                TimeSpan.FromMilliseconds(250),
                CancellationToken.None));
    }

    /// <summary>
    ///  Verifies that an already canceled caller token remains cancellation rather than a timeout.
    /// </summary>
    /// <returns>A task representing the test.</returns>
    [TestMethod]
    [Timeout(10_000)]
    public async Task EchoAsyncCallerCanceledThrowsOperationCanceledException()
    {
        using CancellationTokenSource callerCancellation = new();
        callerCancellation.Cancel();

        await Assert.ThrowsAsync<OperationCanceledException>(
            () => NamedPipeEchoClient.EchoAsync(
                CreatePipeName(),
                ReadOnlyMemory<byte>.Empty,
                TimeSpan.FromSeconds(5),
                callerCancellation.Token));
    }

    /// <summary>
    ///  Verifies that an idle client releases its server worker when the idle deadline expires.
    /// </summary>
    /// <returns>A task representing the test.</returns>
    [TestMethod]
    [Timeout(10_000)]
    public async Task RunAsyncIdleClientReleasesWorker()
    {
        await AssertStalledClientDoesNotStopServerAsync([], TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(250));
    }

    /// <summary>
    ///  Verifies that a stalled frame releases its server worker when the request deadline expires.
    /// </summary>
    /// <param name="bytesSent">The number of header and payload bytes sent before stalling.</param>
    /// <returns>A task representing the test.</returns>
    [TestMethod]
    [Timeout(10_000)]
    [DataRow(2)]
    [DataRow(4)]
    [DataRow(6)]
    public async Task RunAsyncStalledFrameReleasesWorker(int bytesSent)
    {
        byte[] frame = new byte[sizeof(int) + 4];
        BinaryPrimitives.WriteInt32BigEndian(frame, 4);

        await AssertStalledClientDoesNotStopServerAsync(
            frame[..bytesSent],
            TimeSpan.FromMilliseconds(250),
            TimeSpan.FromSeconds(5));
    }

    /// <summary>
    ///  Verifies that a connected peer that never replies causes a request timeout.
    /// </summary>
    /// <returns>A task representing the test.</returns>
    [TestMethod]
    [Timeout(10_000)]
    public async Task EchoAsyncConnectedPeerStallsThrowsRequestTimeout()
    {
        string pipeName = CreatePipeName();
        using CancellationTokenSource testDeadline = new(TimeSpan.FromSeconds(8));
        await using NamedPipeServerStream silentServer = new(
            pipeName,
            PipeDirection.InOut,
            1,
            PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);

        Task acceptTask = silentServer.WaitForConnectionAsync(testDeadline.Token);
        Task<byte[]> clientTask = NamedPipeEchoClient.EchoAsync(
            pipeName,
            new byte[] { 0x10 },
            TimeSpan.FromSeconds(5),
            TimeSpan.FromMilliseconds(250),
            testDeadline.Token);

        await acceptTask;
        Assert.IsNotNull(await PipeFrames.ReadAsync(silentServer, testDeadline.Token));

        TimeoutException exception = await Assert.ThrowsExactlyAsync<TimeoutException>(
            () => clientTask.WaitAsync(TimeSpan.FromSeconds(2)));

        StringAssert.Contains(exception.Message, "pipe request");
    }

    /// <summary>
    ///  Verifies that canceling a pending reply preserves caller cancellation.
    /// </summary>
    /// <returns>A task representing the test.</returns>
    [TestMethod]
    [Timeout(10_000)]
    public async Task EchoAsyncCallerCancelsPendingReplyPreservesCancellation()
    {
        string pipeName = CreatePipeName();
        using CancellationTokenSource testDeadline = new(TimeSpan.FromSeconds(8));
        using CancellationTokenSource callerCancellation =
            CancellationTokenSource.CreateLinkedTokenSource(testDeadline.Token);

        await using NamedPipeServerStream silentServer = new(
            pipeName,
            PipeDirection.InOut,
            1,
            PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);

        Task acceptTask = silentServer.WaitForConnectionAsync(testDeadline.Token);
        Task<byte[]> clientTask = NamedPipeEchoClient.EchoAsync(
            pipeName,
            new byte[] { 0x10 },
            TimeSpan.FromSeconds(5),
            TimeSpan.FromSeconds(5),
            callerCancellation.Token);

        await acceptTask;
        Assert.IsNotNull(await PipeFrames.ReadAsync(silentServer, testDeadline.Token));
        callerCancellation.Cancel();

        await Assert.ThrowsAsync<OperationCanceledException>(
            () => clientTask.WaitAsync(TimeSpan.FromSeconds(2)));
    }

    /// <summary>
    ///  Verifies that a queued client can exchange frames after the previous client disconnects.
    /// </summary>
    /// <returns>A task representing the test.</returns>
    [TestMethod]
    [Timeout(10_000)]
    public async Task RunAsyncQueuedClientSurvivesPreviousDisconnect()
    {
        string pipeName = CreatePipeName();
        using CancellationTokenSource testDeadline = new(TimeSpan.FromSeconds(8));
        using CancellationTokenSource serverShutdown = new();
        Task serverTask = NamedPipeEchoServer.RunAsync(pipeName, 1, serverShutdown.Token);

        try
        {
            await using NamedPipeClientStream firstClient = new(
                ".",
                pipeName,
                PipeDirection.InOut,
                PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);

            byte[] firstResponse = await ExchangeFrameAsync(firstClient, 1, testDeadline.Token);
            CollectionAssert.AreEqual(BitConverter.GetBytes(1), firstResponse);

            await using NamedPipeClientStream queuedClient = new(
                ".",
                pipeName,
                PipeDirection.InOut,
                PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);

            Task connectTask = queuedClient.ConnectAsync(testDeadline.Token);
            if (!OperatingSystem.IsWindows())
            {
                await connectTask;
            }

            await firstClient.DisposeAsync();
            await connectTask;

            byte[] expected = [0x10, 0x20];
            await PipeFrames.WriteAsync(queuedClient, expected, testDeadline.Token);
            byte[]? actual = await PipeFrames.ReadAsync(queuedClient, testDeadline.Token);
            Assert.IsNotNull(actual);
            CollectionAssert.AreEqual(expected, actual);
        }
        finally
        {
            await StopServerAsync(serverShutdown, serverTask);
        }
    }

    private static async Task AssertStalledClientDoesNotStopServerAsync(
        byte[] partialFrame,
        TimeSpan requestTimeout,
        TimeSpan idleTimeout)
    {
        string pipeName = CreatePipeName();
        using CancellationTokenSource testDeadline = new(TimeSpan.FromSeconds(8));
        using CancellationTokenSource serverShutdown = new();
        Task serverTask = NamedPipeEchoServer.RunAsync(pipeName, 1, requestTimeout, idleTimeout, serverShutdown.Token);

        try
        {
            await using NamedPipeClientStream stalledClient = new(
                ".",
                pipeName,
                PipeDirection.InOut,
                PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);

            await stalledClient.ConnectAsync(testDeadline.Token);
            if (partialFrame.Length != 0)
            {
                await stalledClient.WriteAsync(partialFrame, testDeadline.Token);
            }

            int bytesRead = await stalledClient.ReadAsync(new byte[1], testDeadline.Token).AsTask()
                .WaitAsync(TimeSpan.FromSeconds(2));

            Assert.AreEqual(0, bytesRead);

            byte[] expected = [0x10, 0x20];
            byte[] actual = await NamedPipeEchoClient.EchoAsync(
                pipeName,
                expected,
                TimeSpan.FromSeconds(2),
                testDeadline.Token);

            CollectionAssert.AreEqual(expected, actual);
        }
        finally
        {
            await StopServerAsync(serverShutdown, serverTask);
        }
    }

    private static async Task AssertMalformedClientDoesNotStopServerAsync(byte[] malformedFrame)
    {
        string pipeName = CreatePipeName();
        using CancellationTokenSource testDeadline = new(TimeSpan.FromSeconds(8));
        using CancellationTokenSource serverShutdown = new();
        Task serverTask = NamedPipeEchoServer.RunAsync(pipeName, 1, serverShutdown.Token);

        try
        {
            await using (NamedPipeClientStream malformedClient = new(
                ".",
                pipeName,
                PipeDirection.InOut,
                PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly))
            {
                await malformedClient.ConnectAsync(testDeadline.Token);
                await malformedClient.WriteAsync(malformedFrame, testDeadline.Token);
            }

            byte[] expected = [0x10, 0x20];
            byte[] actual = await NamedPipeEchoClient.EchoAsync(
                pipeName,
                expected,
                TimeSpan.FromSeconds(5),
                testDeadline.Token);

            CollectionAssert.AreEqual(expected, actual);
        }
        finally
        {
            await StopServerAsync(serverShutdown, serverTask);
        }
    }

    private static async Task<byte[]> ExchangeFrameAsync(
        NamedPipeClientStream client,
        int clientId,
        CancellationToken cancellationToken)
    {
        await client.ConnectAsync(cancellationToken);
        await PipeFrames.WriteAsync(client, BitConverter.GetBytes(clientId), cancellationToken);
        return await PipeFrames.ReadAsync(client, cancellationToken)
            ?? throw new EndOfStreamException("The server closed before replying.");
    }

    private static string CreatePipeName()
    {
        return $"agent-skills-dotnet-pipes-{Guid.NewGuid():N}";
    }

    private static async Task StopServerAsync(CancellationTokenSource serverShutdown, Task serverTask)
    {
        serverShutdown.Cancel();
        await serverTask.WaitAsync(TimeSpan.FromSeconds(5));
    }
}