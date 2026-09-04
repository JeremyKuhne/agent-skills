using System.Buffers.Binary;
using System.IO.Pipes;
using DotNetPipes.Sample;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace DotNetPipes.Tests;

[TestClass]
public sealed class NamedPipeEchoTests
{
    [TestMethod]
    public async Task TryAcceptClientAsync_RejectedPeer_AllowsNextAcceptedPeer()
    {
        bool rejected = await NamedPipeEchoServer.TryAcceptClientAsync(
            Task.FromException(new UnauthorizedAccessException()));
        bool accepted = await NamedPipeEchoServer.TryAcceptClientAsync(Task.CompletedTask);

        Assert.IsFalse(rejected);
        Assert.IsTrue(accepted);
    }

    [TestMethod]
    public async Task TryAcceptClientAsync_UnexpectedFailure_Propagates()
    {
        IOException failure = new("The accept operation failed.");

        IOException actual = await Assert.ThrowsExactlyAsync<IOException>(
            () => NamedPipeEchoServer.TryAcceptClientAsync(Task.FromException(failure)));

        Assert.AreSame(failure, actual);
    }

    [TestMethod]
    public async Task TryAcceptClientAsync_CanceledAccept_Propagates()
    {
        using CancellationTokenSource cancellation = new();
        cancellation.Cancel();

        await Assert.ThrowsAsync<OperationCanceledException>(
            () => NamedPipeEchoServer.TryAcceptClientAsync(Task.FromCanceled(cancellation.Token)));
    }

    [TestMethod]
    [Timeout(10_000)]
    public async Task EchoAsync_ServerRunning_RoundTripsPayload()
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

    [TestMethod]
    [Timeout(10_000)]
    [DataRow(4, true)]
    [DataRow(1, false)]
    public async Task RunAsync_ClientsHeldOpen_RequiresConcurrentWorkers(int workerCount, bool expectAllReplies)
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

    [TestMethod]
    [Timeout(10_000)]
    public async Task RunAsync_PendingAcceptsAreCanceled_CompletesNormally()
    {
        using CancellationTokenSource serverShutdown = new();
        Task serverTask = NamedPipeEchoServer.RunAsync(CreatePipeName(), 4, serverShutdown.Token);

        serverShutdown.Cancel();

        await serverTask;
        Assert.AreEqual(TaskStatus.RanToCompletion, serverTask.Status);
    }

    [TestMethod]
    [Timeout(10_000)]
    public async Task RunAsync_PartialStartupFailure_CancelsWorkersAndReportsFailure()
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

    [TestMethod]
    [Timeout(10_000)]
    public async Task RunAsync_NegativeLengthDisconnects_NextClientStillSucceeds()
    {
        byte[] invalidHeader = new byte[sizeof(int)];
        BinaryPrimitives.WriteInt32BigEndian(invalidHeader, -1);

        await AssertMalformedClientDoesNotStopServerAsync(invalidHeader);
    }

    [TestMethod]
    [Timeout(10_000)]
    public async Task RunAsync_TruncatedHeaderDisconnects_NextClientStillSucceeds()
    {
        await AssertMalformedClientDoesNotStopServerAsync([0x00, 0x00]);
    }

    [TestMethod]
    [Timeout(10_000)]
    public async Task RunAsync_TruncatedPayloadDisconnects_NextClientStillSucceeds()
    {
        byte[] truncatedFrame = new byte[sizeof(int) + 2];
        BinaryPrimitives.WriteInt32BigEndian(truncatedFrame, 4);
        truncatedFrame[^2] = 0x10;
        truncatedFrame[^1] = 0x20;

        await AssertMalformedClientDoesNotStopServerAsync(truncatedFrame);
    }

    [TestMethod]
    [Timeout(10_000)]
    public async Task EchoAsync_ServerAbsent_ThrowsTimeoutException()
    {
        await Assert.ThrowsExactlyAsync<TimeoutException>(
            () => NamedPipeEchoClient.EchoAsync(
                CreatePipeName(),
                ReadOnlyMemory<byte>.Empty,
                TimeSpan.FromMilliseconds(250),
                CancellationToken.None));
    }

    [TestMethod]
    [Timeout(10_000)]
    public async Task EchoAsync_CallerCanceled_ThrowsOperationCanceledException()
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

    [TestMethod]
    [Timeout(10_000)]
    public async Task RunAsync_IdleClient_ReleasesWorker()
    {
        await AssertStalledClientDoesNotStopServerAsync([], TimeSpan.FromSeconds(5), TimeSpan.FromMilliseconds(250));
    }

    [TestMethod]
    [Timeout(10_000)]
    [DataRow(2)]
    [DataRow(4)]
    [DataRow(6)]
    public async Task RunAsync_StalledFrame_ReleasesWorker(int bytesSent)
    {
        byte[] frame = new byte[sizeof(int) + 4];
        BinaryPrimitives.WriteInt32BigEndian(frame, 4);

        await AssertStalledClientDoesNotStopServerAsync(
            frame[..bytesSent],
            TimeSpan.FromMilliseconds(250),
            TimeSpan.FromSeconds(5));
    }

    [TestMethod]
    [Timeout(10_000)]
    public async Task EchoAsync_ConnectedPeerStalls_ThrowsRequestTimeout()
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

    [TestMethod]
    [Timeout(10_000)]
    public async Task EchoAsync_CallerCancelsPendingReply_PreservesCancellation()
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
                await malformedClient.ConnectAsync(serverShutdown.Token);
                await malformedClient.WriteAsync(malformedFrame, serverShutdown.Token);
            }

            byte[] expected = [0x10, 0x20];
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