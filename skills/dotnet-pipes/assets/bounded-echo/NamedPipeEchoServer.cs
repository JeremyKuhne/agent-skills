using System.IO.Pipes;

namespace DotNetPipes.Sample;

public static class NamedPipeEchoServer
{
    public static Task RunAsync(
        string pipeName,
        int maxConcurrentClients,
        CancellationToken stoppingToken)
    {
        return RunAsync(
            pipeName,
            maxConcurrentClients,
            TimeSpan.FromSeconds(5),
            TimeSpan.FromSeconds(30),
            stoppingToken);
    }

    public static async Task RunAsync(
        string pipeName,
        int maxConcurrentClients,
        TimeSpan requestTimeout,
        TimeSpan idleTimeout,
        CancellationToken stoppingToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(pipeName);
        ArgumentOutOfRangeException.ThrowIfLessThan(maxConcurrentClients, 1);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(maxConcurrentClients, 254);
        ArgumentOutOfRangeException.ThrowIfLessThanOrEqual(requestTimeout, TimeSpan.Zero);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(requestTimeout, TimeSpan.FromMilliseconds(uint.MaxValue - 1));
        ArgumentOutOfRangeException.ThrowIfLessThanOrEqual(idleTimeout, TimeSpan.Zero);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(idleTimeout, TimeSpan.FromMilliseconds(uint.MaxValue - 1));

        using CancellationTokenSource serverLifetime = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken);
        Task[] workers = new Task[maxConcurrentClients];
        for (int index = 0; index < workers.Length; index++)
        {
            workers[index] = RunSupervisedWorkerAsync(
                pipeName,
                maxConcurrentClients,
                requestTimeout,
                idleTimeout,
                serverLifetime);
        }

        await Task.WhenAll(workers).ConfigureAwait(false);
    }

    private static async Task RunSupervisedWorkerAsync(
        string pipeName,
        int maxConcurrentClients,
        TimeSpan requestTimeout,
        TimeSpan idleTimeout,
        CancellationTokenSource serverLifetime)
    {
        try
        {
            await RunWorkerAsync(
                pipeName,
                maxConcurrentClients,
                requestTimeout,
                idleTimeout,
                serverLifetime.Token).ConfigureAwait(false);
        }
        catch
        {
            serverLifetime.Cancel();
            throw;
        }
    }

    private static async Task RunWorkerAsync(
        string pipeName,
        int maxConcurrentClients,
        TimeSpan requestTimeout,
        TimeSpan idleTimeout,
        CancellationToken stoppingToken)
    {
        try
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                await using NamedPipeServerStream server = new(
                    pipeName,
                    PipeDirection.InOut,
                    maxConcurrentClients,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);

                while (!stoppingToken.IsCancellationRequested
                    && await TryAcceptClientAsync(server.WaitForConnectionAsync(stoppingToken)).ConfigureAwait(false))
                {
                    try
                    {
                        await HandleClientAsync(server, requestTimeout, idleTimeout, stoppingToken).ConfigureAwait(false);
                    }
                    finally
                    {
                        server.Disconnect();
                    }
                }
            }
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
        {
        }
    }

    internal static async Task<bool> TryAcceptClientAsync(Task acceptTask)
    {
        try
        {
            await acceptTask.ConfigureAwait(false);
            return true;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
    }

    private static async Task HandleClientAsync(
        NamedPipeServerStream server,
        TimeSpan requestTimeout,
        TimeSpan idleTimeout,
        CancellationToken stoppingToken)
    {
        byte[] header = new byte[sizeof(int)];
        try
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                using (CancellationTokenSource idleDeadline =
                    CancellationTokenSource.CreateLinkedTokenSource(stoppingToken))
                {
                    idleDeadline.CancelAfter(idleTimeout);
                    int firstRead = await server.ReadAsync(header.AsMemory(0, 1), idleDeadline.Token)
                        .ConfigureAwait(false);
                    if (firstRead == 0)
                    {
                        return;
                    }
                }

                using CancellationTokenSource requestDeadline =
                    CancellationTokenSource.CreateLinkedTokenSource(stoppingToken);
                requestDeadline.CancelAfter(requestTimeout);

                byte[] payload = await PipeFrames.ReadRemainderAsync(server, header, 1, requestDeadline.Token)
                    .ConfigureAwait(false);
                await PipeFrames.WriteAsync(server, payload, requestDeadline.Token).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) when (!stoppingToken.IsCancellationRequested)
        {
        }
        catch (InvalidDataException)
        {
        }
        catch (IOException)
        {
        }
    }
}