# Test .NET pipe behavior

Use real endpoints for lifecycle, security, concurrency, cancellation, and
platform behavior. Use in-memory or deliberately fragmenting streams only for
the framing codec's pure stream contract.

The buildable [bounded echo sample](assets/bounded-echo/README.md) provides a
canonical endpoint and frame codec for these checks. Compile and exercise that
source instead of copying prose snippets into a separate test implementation.

## Deterministic test shape

- Generate a unique, non-secret pipe name per test process.
- Give every wait a bounded test deadline and include captured server/client
  state in timeout failures.
- Coordinate phases with tasks, barriers, or explicit protocol messages, not
  arbitrary sleeps.
- Start and observe every server, client, and handler task. Await shutdown before
  disposing shared test state.
- Use `await using` or `using` for every endpoint and close unintended inherited
  or duplicated handles.
- Do not preflight with file-existence APIs. Attempt the real connection.
- Separate protocol tests from Windows ACL/identity and remote SMB tests so a
  failure identifies its layer.
- Gate Windows-only assertions with the repository's normal platform mechanism;
  never turn unsupported behavior into a silent pass.

## Minimum matrix

### Framing

- zero-length, ordinary, exact-maximum, and just-over-maximum payloads;
- negative encoded length and largest representable header value;
- header and payload delivered one byte at a time;
- clean end-of-stream between frames and truncation in both header and payload;
- two concurrent producers cannot interleave complete frames; and
- repeated maximum-size frames remain within the aggregate connection budget.

### Connection lifecycle

- server starts first and client starts first;
- two clients race for one listener;
- configured peak clients connect while excess clients receive bounded overload
  behavior;
- clients remain open until all replies arrive, so a single-worker negative
  control cannot pass the concurrency test by serving clients serially;
- listener capacity is replenished while an earlier client is busy;
- a partial-startup or unexpected worker failure cancels and drains its siblings
  and reports the original failure without requiring external shutdown;
- peer closes before handshake, mid-frame, after request, and during response;
- server restart requires a fresh client object and a new handshake; and
- every background operation finishes before its stream is disposed.

### Cancellation and deadlines

- cancel pending connect, accept, read, and write;
- normal completion wins a cancellation race without duplicate completion;
- one frame deadline covers all partial reads rather than resetting per byte;
- idle and shutdown deadlines stop a non-progressing peer; and
- caller cancellation is distinguishable from application timeout where the
  public contract promises that distinction.

### Security

- intended identity can connect with the required direction;
- unintended identity, elevation level, or remote origin is denied according to
  the design;
- first-instance ownership behaves as intended without blocking legitimate
  additional instances;
- required impersonation authorizes the intended resource and fails closed; and
- names, logs, and exception output do not disclose secrets or payloads.

### Platform and transport

- byte-framed local protocol runs on every supported operating system;
- Windows message-mode tests force a message larger than the read buffer;
- anonymous-pipe tests close all parent and child copies and observe EOF;
- any test-only capture helper enforces an aggregate byte limit and is reaped by
  its parent within a bounded lifetime;
- packaged/session scenarios run in representative deployment contexts; and
- remote Windows tests separately cover SMB authentication/policy, destination
  authorization, transport interruption, and ambiguous request completion.

## Validation order

1. Compile the touched project for its narrowest target.
2. Run the single regression or endpoint test for the changed behavior.
3. Run the containing test project.
4. Run supported target-framework and operating-system legs affected by the
   design.
5. Run measured load or fault-injection tests when the claim concerns capacity,
   backpressure, scheduler behavior, or recovery.

Do not claim cancellation, security, remote compatibility, or load behavior from
a mock-only test. Record skipped environmental tests as residual risk with the
identity, platform, or infrastructure needed to run them.
