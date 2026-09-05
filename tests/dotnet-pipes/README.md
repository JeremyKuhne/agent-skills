# .NET pipes fact tests

This `net10.0` MSTest project references the bundled `net10.0` sample directly.
Building the test graph therefore compiles and exercises the same source that
the skill publishes.

Run the suite:

```pwsh
dotnet test --project DotNetPipes.Tests.csproj --configuration Release
```

The suite verifies:

- four-byte big-endian framing, exact-maximum payloads, and oversized or
  negative length rejection;
- one-byte reads, clean end-of-stream between frames, and truncated header or
  payload failure;
- same-user round trips with every client held open until all replies arrive,
  plus a one-worker negative control that cannot satisfy the same workload;
- clients queued in the Unix backlog survive the preceding client's disconnect;
- normal server completion when pending accepts are canceled;
- accept-completion classification using synthetic failures: an unauthorized
  peer is rejected while cancellation and unexpected I/O failures propagate;
- propagation of partial-startup failures after sibling workers release their
  pipe instances, without requiring external shutdown;
- containment of invalid and truncated client frames so a later client can
  connect;
- recovery of listener capacity after idle, partial-header, and partial-payload
  deadlines expire;
- connection and request timeout reporting, with caller cancellation during a
  pending reply preserved as cancellation;
- complementary anonymous-pipe directions; and
- anonymous-pipe EOF for empty, ordinary, and exact-limit input, and rejection of
  input just over the capture limit.

The [anonymous child](anonymous-child/Program.cs) is a test-only executable with
a 64 KiB capture limit, not a command in the published echo sample. The parent
test bounds its lifetime and kills and reaps it on timeout or failure. This does
not claim native cancellation support for anonymous pipes.

These tests do not establish cross-user denial, explicit Windows ACL behavior,
impersonation, remote SMB behavior, Windows message mode, or the .NET 11 Unix
socket-permission ratchet. Those require the identity, platform, runtime, or
network matrices described in the skill.
