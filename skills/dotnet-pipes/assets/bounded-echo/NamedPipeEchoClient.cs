using System.IO.Pipes;

namespace DotNetPipes.Sample;

public static class NamedPipeEchoClient
{
    public static Task<byte[]> EchoAsync(
        string pipeName,
        ReadOnlyMemory<byte> payload,
        TimeSpan connectTimeout,
        CancellationToken cancellationToken)
    {
        return EchoAsync(pipeName, payload, connectTimeout, TimeSpan.FromSeconds(5), cancellationToken);
    }

    public static async Task<byte[]> EchoAsync(
        string pipeName,
        ReadOnlyMemory<byte> payload,
        TimeSpan connectTimeout,
        TimeSpan requestTimeout,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(pipeName);
        ArgumentOutOfRangeException.ThrowIfLessThanOrEqual(connectTimeout, TimeSpan.Zero);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(connectTimeout, TimeSpan.FromMilliseconds(uint.MaxValue - 1));
        ArgumentOutOfRangeException.ThrowIfLessThanOrEqual(requestTimeout, TimeSpan.Zero);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(requestTimeout, TimeSpan.FromMilliseconds(uint.MaxValue - 1));

        await using NamedPipeClientStream client = new(
            ".",
            pipeName,
            PipeDirection.InOut,
            PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);

        using (CancellationTokenSource connectDeadline =
            CancellationTokenSource.CreateLinkedTokenSource(cancellationToken))
        {
            connectDeadline.CancelAfter(connectTimeout);
            try
            {
                await client.ConnectAsync(connectDeadline.Token).ConfigureAwait(false);
            }
            catch (OperationCanceledException exception)
                when (!cancellationToken.IsCancellationRequested && connectDeadline.IsCancellationRequested)
            {
                throw new TimeoutException($"The pipe connection exceeded {connectTimeout}.", exception);
            }
        }

        using CancellationTokenSource requestDeadline =
            CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        requestDeadline.CancelAfter(requestTimeout);
        try
        {
            await PipeFrames.WriteAsync(client, payload, requestDeadline.Token).ConfigureAwait(false);
            byte[]? response = await PipeFrames.ReadAsync(client, requestDeadline.Token).ConfigureAwait(false);
            return response ?? throw new EndOfStreamException("The server closed before returning a response.");
        }
        catch (OperationCanceledException exception)
            when (!cancellationToken.IsCancellationRequested && requestDeadline.IsCancellationRequested)
        {
            throw new TimeoutException($"The pipe request exceeded {requestTimeout}.", exception);
        }
    }
}