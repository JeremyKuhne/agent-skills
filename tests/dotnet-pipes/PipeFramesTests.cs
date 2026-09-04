using System.Buffers.Binary;
using DotNetPipes.Sample;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace DotNetPipes.Tests;

[TestClass]
public sealed class PipeFramesTests
{
    [TestMethod]
    public async Task WriteAsync_Payload_WritesBigEndianLengthAndPayload()
    {
        byte[] payload = [0x10, 0x20, 0x30];
        await using MemoryStream stream = new();

        await PipeFrames.WriteAsync(stream, payload, CancellationToken.None);

        CollectionAssert.AreEqual(
            new byte[] { 0x00, 0x00, 0x00, 0x03, 0x10, 0x20, 0x30 },
            stream.ToArray());
    }

    [TestMethod]
    public async Task ReadAsync_OneByteReads_ReturnsCompletePayload()
    {
        byte[] expected = [0x10, 0x20, 0x30, 0x40];
        await using FragmentingReadStream stream = new(CreateFrame(expected.Length, expected));

        byte[]? actual = await PipeFrames.ReadAsync(stream, CancellationToken.None);

        CollectionAssert.AreEqual(expected, actual);
    }

    [TestMethod]
    public async Task ReadAsync_CleanEndOfStreamBetweenFrames_ReturnsNull()
    {
        await using MemoryStream stream = new();

        byte[]? payload = await PipeFrames.ReadAsync(stream, CancellationToken.None);

        Assert.IsNull(payload);
    }

    [TestMethod]
    public async Task ReadAsync_TruncatedHeader_ThrowsEndOfStreamException()
    {
        await using MemoryStream stream = new([0x00, 0x00]);

        await Assert.ThrowsExactlyAsync<EndOfStreamException>(
            () => PipeFrames.ReadAsync(stream, CancellationToken.None).AsTask());
    }

    [TestMethod]
    public async Task ReadAsync_TruncatedPayload_ThrowsEndOfStreamException()
    {
        await using MemoryStream stream = new(CreateFrame(4, [0x10, 0x20]));

        await Assert.ThrowsExactlyAsync<EndOfStreamException>(
            () => PipeFrames.ReadAsync(stream, CancellationToken.None).AsTask());
    }

    [TestMethod]
    [DataRow(-1)]
    [DataRow(PipeFrames.MaxPayloadLength + 1)]
    public async Task ReadAsync_InvalidLength_ThrowsInvalidDataException(int length)
    {
        await using MemoryStream stream = new(CreateFrame(length, []));

        await Assert.ThrowsExactlyAsync<InvalidDataException>(
            () => PipeFrames.ReadAsync(stream, CancellationToken.None).AsTask());
    }

    [TestMethod]
    public async Task ReadAsync_MaximumPayload_ReturnsCompletePayload()
    {
        byte[] expected = new byte[PipeFrames.MaxPayloadLength];
        Random.Shared.NextBytes(expected);
        await using MemoryStream stream = new(CreateFrame(expected.Length, expected));

        byte[]? actual = await PipeFrames.ReadAsync(stream, CancellationToken.None);

        CollectionAssert.AreEqual(expected, actual);
    }

    [TestMethod]
    public async Task WriteAsync_OversizedPayload_ThrowsArgumentOutOfRangeException()
    {
        byte[] payload = new byte[PipeFrames.MaxPayloadLength + 1];
        await using MemoryStream stream = new();

        await Assert.ThrowsExactlyAsync<ArgumentOutOfRangeException>(
            () => PipeFrames.WriteAsync(stream, payload, CancellationToken.None).AsTask());
    }

    private static byte[] CreateFrame(int length, byte[] payload)
    {
        byte[] frame = new byte[sizeof(int) + payload.Length];
        BinaryPrimitives.WriteInt32BigEndian(frame, length);
        payload.CopyTo(frame, sizeof(int));
        return frame;
    }

    private sealed class FragmentingReadStream : Stream
    {
        private readonly MemoryStream _inner;

        public FragmentingReadStream(byte[] data)
        {
            _inner = new MemoryStream(data);
        }

        public override bool CanRead => true;

        public override bool CanSeek => false;

        public override bool CanWrite => false;

        public override long Length => _inner.Length;

        public override long Position
        {
            get => _inner.Position;
            set => throw new NotSupportedException();
        }

        public override void Flush()
        {
        }

        public override int Read(byte[] buffer, int offset, int count)
        {
            return _inner.Read(buffer, offset, Math.Min(count, 1));
        }

        public override ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
        {
            return _inner.ReadAsync(buffer[..Math.Min(buffer.Length, 1)], cancellationToken);
        }

        public override long Seek(long offset, SeekOrigin origin)
        {
            throw new NotSupportedException();
        }

        public override void SetLength(long value)
        {
            throw new NotSupportedException();
        }

        public override void Write(byte[] buffer, int offset, int count)
        {
            throw new NotSupportedException();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _inner.Dispose();
            }

            base.Dispose(disposing);
        }

        public override async ValueTask DisposeAsync()
        {
            await _inner.DisposeAsync();
            await base.DisposeAsync();
        }
    }
}