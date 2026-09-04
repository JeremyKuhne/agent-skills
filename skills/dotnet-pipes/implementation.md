# Implement .NET pipes

Use this workflow after [design.md](design.md) fixes the transport, platform,
security boundary, protocol, and capacity model.

## Apply this page

Use the completed design record to follow this sequence:

1. Fit the implementation to the target repository.
2. Add bounded framing only when the protocol treats the byte stream as
   discrete messages. Skip framing for a deliberately unframed one-way stream.
3. Implement the selected transport branch. Use named pipes for discoverable
   endpoints or anonymous pipes for an inherited parent-child channel; do not
   implement both branches unless the design explicitly requires both.
4. Complete lifecycle and shutdown behavior for the selected branch.
5. Run the focused build and real-endpoint tests.
6. Return to the optional throughput section only when measurements identify
   framing as a bottleneck.

For a change to one existing endpoint, implement only that endpoint and verify
that its behavior remains compatible with the peer.

The [bounded echo sample](assets/bounded-echo/README.md) is executable source for
the framing and named-pipe patterns below. Prefer adapting that project over
reconstructing a complete implementation from isolated snippets.

## 1. Fit the repository

Read the target project, nullable and language settings, package management,
hosting lifecycle, logging conventions, and nearest integration test. Reuse the
repository's established cancellation, options, and test patterns. Verify every
member and overload against the target framework's current public reference
assemblies instead of assuming that a newer SDK surface is available.

For Windows ACL creation, determine whether the project already references
`System.IO.Pipes.AccessControl`. Add a package only when the target framework
requires it and the security design calls for `PipeSecurity`.

## 2. Add framing when the protocol has messages

When the design defines discrete messages on a byte stream, use a fixed-width
header and validate the advertised size before allocating. This .NET 10 pattern
treats clean end-of-stream between frames differently from truncation inside a
frame:

```csharp
using System.Buffers.Binary;

static class PipeFrames
{
    public const int MaxPayloadLength = 64 * 1024;

    public static async ValueTask WriteAsync(
        Stream stream,
        ReadOnlyMemory<byte> payload,
        CancellationToken cancellationToken)
    {
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
        byte[] header = new byte[sizeof(int)];
        int firstRead = await stream.ReadAsync(header, cancellationToken).ConfigureAwait(false);

        if (firstRead == 0)
        {
            return null;
        }

        await stream.ReadExactlyAsync(header.AsMemory(firstRead), cancellationToken).ConfigureAwait(false);

        int length = BinaryPrimitives.ReadInt32BigEndian(header);
        if ((uint)length > MaxPayloadLength)
        {
            throw new InvalidDataException($"Invalid frame length: {length}.");
        }

        byte[] payload = new byte[length];
        await stream.ReadExactlyAsync(payload, cancellationToken).ConfigureAwait(false);
        return payload;
    }
}
```

Adapt the maximum to the protocol and budget. For older target frameworks, use
a tested read-exactly loop. Serialize the header and payload as one logical
write operation; a lock around only each individual `WriteAsync()` still allows
frames to interleave.

Do not create a fresh full timeout for every partial read. Give the whole frame
one deadline, pass its remaining cancellation budget to header and payload
reads, and close the connection after malformed or truncated framing.

### Preserve stream ordering

Do not parallelize header and payload reads on one connection. The payload
length is unknown until the header completes, and simultaneous reads compete for
the same ordered byte stream. Use one read loop per connection. A duplex pipe
can still overlap that read loop with one writer, and independent connections
should run concurrently.

Parallelize CPU-bound request handling only after a complete frame has been
validated. Bound the number of in-flight handlers, include request IDs when
responses can complete out of order, and funnel every response through the
single writer.

## 3. Implement the selected transport

Choose the branch fixed by [design.md](design.md). Within the named-pipe branch,
implement the server, client, or both according to which endpoints the target
repository owns.

### Named-pipe branch

#### Create a bounded server

Default local same-user servers to a fixed set of supervised asynchronous
workers. The bundled
[NamedPipeEchoServer](assets/bounded-echo/NamedPipeEchoServer.cs) helper supplies
the complete lifecycle; it is sample code, not a framework API:

```csharp
await NamedPipeEchoServer.RunAsync(
    pipeName,
    maxConcurrentClients: 4,
    requestTimeout: TimeSpan.FromSeconds(5),
    idleTimeout: TimeSpan.FromSeconds(30),
    stoppingToken: stoppingToken).ConfigureAwait(false);
```

Preserve these properties when adapting it:

1. A linked lifetime source belongs to the whole worker set. An unexpected
   worker failure cancels its siblings, then `Task.WhenAll()` drains the set
   before propagating the fault. `Task.WhenAll()` alone is not fail-fast.
2. Host cancellation completes normally; rejected peers do not stop other workers.
3. An idle deadline covers the wait for the first byte of each frame. After
   that byte arrives, one request deadline covers the remaining header,
   payload, and response write. Partial reads never renew the request budget.
4. An idle or request timeout closes the affected connection and releases its
   worker. It does not shut down the other clients.

Host shutdown cancels pending accepts and connected I/O. Access-denied accepts
and connection-level I/O failures close only the affected client. Its worker
disposes the instance and resumes listening.

The worker count bounds active handlers, and the constructor uses the same
value for its server-instance limit. Every server instance sharing a pipe name
must use a compatible ceiling. Treat an incompatible creation attempt as a
startup or configuration conflict. At capacity, Windows clients wait for an
available pipe instance. On Unix, a connection can enter the socket backlog
before a worker accepts it: connect can succeed while the request waits and may
time out. Bound both phases. If the design needs spare listeners during
long-running work, maintain that capacity separately without exceeding the
overall admission budget.

Give each connection one owner. That owner coordinates its reader, serialized
writer, per-request deadlines, handler tasks, cancellation, and disposal. Do
not let a handler outlive the `await using` scope that owns the stream.

For a Windows service or cross-user endpoint, replace `CurrentUserOnly` with the
approved `NamedPipeServerStreamAcl.Create()` design. Construct a protected
allow-list from stable SIDs and create the descriptor atomically. Compile and
run an authorized and unauthorized connection test under representative tokens.
Never pass `CurrentUserOnly` with an explicit `PipeSecurity`; the factory ignores
the supplied descriptor in that combination.

#### Create a bounded client

Use a new client object per connection attempt and a real asynchronous handle:

```csharp
await using NamedPipeClientStream client = new(
    ".",
    pipeName,
    PipeDirection.InOut,
    PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);

await client.ConnectAsync(timeout, cancellationToken).ConfigureAwait(false);
```

Use the timeout overload available to the target framework, or one linked
`CancellationTokenSource` with `CancelAfter()`. Distinguish caller cancellation
from an elapsed application deadline in logs and public behavior. The connection
timeout does not bound subsequent I/O. Start a separate request deadline and
pass its token through both the write and the complete response read.

The bundled [NamedPipeEchoClient](assets/bounded-echo/NamedPipeEchoClient.cs)
helper applies a five-second request budget by default. Its overload accepts
separate connection and request timeouts. Expiration of either phase throws
`TimeoutException`; caller cancellation remains `OperationCanceledException`.
Both failure paths finish the owned I/O and dispose the connection.

After connect, perform a bounded version/authentication handshake before normal
requests. After end-of-stream, `IOException`, or disposal, stop all new work and
create a new `NamedPipeClientStream`. Do not use `IsConnected` as a preflight or
automatically replay an ambiguous request.

### Anonymous-pipe branch

Use this branch only for inherited one-way channels.

The parent creates `AnonymousPipeServerStream`, launches the child with the
client handle string, then calls `DisposeLocalCopyOfClientHandle()` after the
child has inherited or opened its end. The child constructs
`AnonymousPipeClientStream` from that handle string. Close every duplicate so
end-of-stream is observable.

An anonymous pipe is one-way. Use two independent pipes for duplex parent-child
traffic and define ownership and shutdown for each direction. Do not use handle
inheritance as a discovery mechanism for unrelated clients.

Do not copy an arbitrary anonymous stream into an ever-growing `MemoryStream`.
Process it incrementally or enforce a total capture limit before accumulation.
Give the parent a bounded child-process lifetime and a cleanup path when a child
does not finish. An async method name alone does not establish that a pending
anonymous-pipe operation supports cancellation on the target runtime.

## 4. Complete lifecycle and shutdown

- Pass host shutdown to pending accept and connection operations.
- Use separate bounded deadlines for connect, handshake, each request, idle
  time, and shutdown where their policies differ.
- Stop admitting requests, finish or cancel owned work, await all I/O tasks,
  send a final protocol response or acknowledgment when required, then dispose.
- Do not rely on `FlushAsync()` as proof that the peer processed bytes.
- Avoid `WaitForPipeDrain()` unless its Windows-only, synchronous, potentially
  unbounded peer-consumption semantics are explicitly required and isolated.
- For reusable named-pipe server objects, finish all client I/O before
  `Disconnect()` and the next accept. Creating a fresh server instance per
  connection is often easier to own correctly.

## 5. Validate immediately

After the smallest implementation edit, compile the touched project and run one
real endpoint integration test that exercises the changed path. Then run
the applicable matrix in [testing.md](testing.md). When framing applies, a mock
stream can validate only the frame codec. It cannot establish pipe connection,
identity, cancellation, or disposal behavior.

## 6. Optimize only after measurement

The baseline framing helper favors clear ownership. It allocates one payload
array per frame and performs separate header and payload writes. When
measurement shows that framing is a bottleneck:

- pass caller-owned `Memory<byte>` into the reader, or return an explicit
  `IMemoryOwner<byte>` backed by `MemoryPool<byte>`; never return a pooled array
  without making disposal and ownership unambiguous;
- reuse the four-byte header buffer inside the single-reader connection object;
- use one `PipeReader` and one `PipeWriter` over the `PipeStream` to amortize
  reads, parse several complete frames from a `ReadOnlySequence<byte>`, and
  batch serialized writes before `FlushAsync()`;
- never mix direct stream reads with a `PipeReader`, because either reader can
  consume bytes expected by the other;
- copy or finish processing sequence-backed payload data before advancing the
  `PipeReader`; and
- put outbound frames in a bounded channel drained by one writer loop. This
  permits concurrent request processing while preserving frame order and
  applying backpressure.

A faster codec does not remove the connection, byte, or work limits from
[design.md](design.md). Rerun the framing tests, real-endpoint regression test,
and relevant load measurement after each optimization.
