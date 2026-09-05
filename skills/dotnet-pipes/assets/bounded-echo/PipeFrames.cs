using System.Buffers.Binary;

namespace DotNetPipes.Sample;

public static class PipeFrames
{
    public const int MaxPayloadLength = 64 * 1024;

    public static async ValueTask WriteAsync(
        Stream stream,
        ReadOnlyMemory<byte> payload,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(stream);

        if (payload.Length > MaxPayloadLength)
        {
            throw new ArgumentOutOfRangeException(nameof(payload));
        }

        byte[] header = new byte[sizeof(int)];
        BinaryPrimitives.WriteInt32BigEndian(header, payload.Length);

        await stream.WriteAsync(header, cancellationToken).ConfigureAwait(false);
        await stream.WriteAsync(payload, cancellationToken).ConfigureAwait(false);
    }

    public static async ValueTask<byte[]?> ReadAsync(Stream stream, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(stream);

        byte[] header = new byte[sizeof(int)];
        int firstRead = await stream.ReadAsync(header, cancellationToken).ConfigureAwait(false);

        if (firstRead == 0)
        {
            return null;
        }

        return await ReadRemainderAsync(stream, header, firstRead, cancellationToken).ConfigureAwait(false);
    }

    internal static async ValueTask<byte[]> ReadRemainderAsync(
        Stream stream,
        Memory<byte> header,
        int headerBytesRead,
        CancellationToken cancellationToken)
    {
        await stream.ReadExactlyAsync(header[headerBytesRead..], cancellationToken).ConfigureAwait(false);

        int length = BinaryPrimitives.ReadInt32BigEndian(header.Span);
        if ((uint)length > MaxPayloadLength)
        {
            throw new InvalidDataException($"Invalid frame length: {length}.");
        }

        byte[] payload = new byte[length];
        await stream.ReadExactlyAsync(payload, cancellationToken).ConfigureAwait(false);
        return payload;
    }
}