// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers.Binary;
using DotNetPipes.Sample;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace DotNetPipes.Tests;

/// <summary>
///  Verifies frame encoding, fragmented reads, payload bounds, and end-of-stream handling.
/// </summary>
[TestClass]
public sealed partial class PipeFramesTests
{
    /// <summary>
    ///  Verifies that writing a payload emits its big-endian length followed by the payload.
    /// </summary>
    /// <returns>A task representing the test.</returns>
    [TestMethod]
    public async Task WriteAsyncPayloadWritesBigEndianLengthAndPayload()
    {
        byte[] payload = [0x10, 0x20, 0x30];
        await using MemoryStream stream = new();

        await PipeFrames.WriteAsync(stream, payload, CancellationToken.None);

        CollectionAssert.AreEqual(
            new byte[] { 0x00, 0x00, 0x00, 0x03, 0x10, 0x20, 0x30 },
            stream.ToArray());
    }

    /// <summary>
    ///  Verifies that one-byte reads reconstruct a complete payload.
    /// </summary>
    /// <returns>A task representing the test.</returns>
    [TestMethod]
    public async Task ReadAsyncOneByteReadsReturnsCompletePayload()
    {
        byte[] expected = [0x10, 0x20, 0x30, 0x40];
        await using FragmentingReadStream stream = new(CreateFrame(expected.Length, expected));

        byte[]? actual = await PipeFrames.ReadAsync(stream, CancellationToken.None);

        CollectionAssert.AreEqual(expected, actual);
    }

    /// <summary>
    ///  Verifies that clean end-of-stream between frames returns no payload.
    /// </summary>
    /// <returns>A task representing the test.</returns>
    [TestMethod]
    public async Task ReadAsyncCleanEndOfStreamBetweenFramesReturnsNull()
    {
        await using MemoryStream stream = new();

        byte[]? payload = await PipeFrames.ReadAsync(stream, CancellationToken.None);

        Assert.IsNull(payload);
    }

    /// <summary>
    ///  Verifies that a truncated frame header reports end-of-stream.
    /// </summary>
    /// <returns>A task representing the test.</returns>
    [TestMethod]
    public async Task ReadAsyncTruncatedHeaderThrowsEndOfStreamException()
    {
        await using MemoryStream stream = new([0x00, 0x00]);

        await Assert.ThrowsExactlyAsync<EndOfStreamException>(
            () => PipeFrames.ReadAsync(stream, CancellationToken.None).AsTask());
    }

    /// <summary>
    ///  Verifies that a truncated payload reports end-of-stream.
    /// </summary>
    /// <returns>A task representing the test.</returns>
    [TestMethod]
    public async Task ReadAsyncTruncatedPayloadThrowsEndOfStreamException()
    {
        await using MemoryStream stream = new(CreateFrame(4, [0x10, 0x20]));

        await Assert.ThrowsExactlyAsync<EndOfStreamException>(
            () => PipeFrames.ReadAsync(stream, CancellationToken.None).AsTask());
    }

    /// <summary>
    ///  Verifies that negative and oversized frame lengths are rejected.
    /// </summary>
    /// <param name="length">An invalid encoded payload length.</param>
    /// <returns>A task representing the test.</returns>
    [TestMethod]
    [DataRow(-1)]
    [DataRow(PipeFrames.MaxPayloadLength + 1)]
    public async Task ReadAsyncInvalidLengthThrowsInvalidDataException(int length)
    {
        await using MemoryStream stream = new(CreateFrame(length, []));

        await Assert.ThrowsExactlyAsync<InvalidDataException>(
            () => PipeFrames.ReadAsync(stream, CancellationToken.None).AsTask());
    }

    /// <summary>
    ///  Verifies that a payload exactly at the size limit is returned intact.
    /// </summary>
    /// <returns>A task representing the test.</returns>
    [TestMethod]
    public async Task ReadAsyncMaximumPayloadReturnsCompletePayload()
    {
        byte[] expected = new byte[PipeFrames.MaxPayloadLength];
        Random.Shared.NextBytes(expected);
        await using MemoryStream stream = new(CreateFrame(expected.Length, expected));

        byte[]? actual = await PipeFrames.ReadAsync(stream, CancellationToken.None);

        CollectionAssert.AreEqual(expected, actual);
    }

    /// <summary>
    ///  Verifies that writing an oversized payload is rejected.
    /// </summary>
    /// <returns>A task representing the test.</returns>
    [TestMethod]
    public async Task WriteAsyncOversizedPayloadThrowsArgumentOutOfRangeException()
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

}