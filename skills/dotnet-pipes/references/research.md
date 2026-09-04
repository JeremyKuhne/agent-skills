# .NET pipes research ledger

This reference records the public-contract findings used by the skill. It is a
decision aid, not a substitute for checking the target framework's current
reference assemblies and Microsoft documentation when an API detail may have
changed.

## Scope and authority

The source set combined:

- a Windows named-pipe architecture and API survey;
- symptom-first Win32 and .NET troubleshooting guides;
- a production-oriented modern .NET implementation guide;
- an assessment of gaps and possible additions to `System.IO.Pipes`; and
- public Microsoft documentation linked below.

The supplied source survey included operating-system implementation detail that
helped corroborate lifecycle, queueing, security, and remote-transport behavior.
This portable skill intentionally excludes runtime-internal entry points,
structures, file-system controls, source paths, and undocumented extensions. It
uses only public .NET APIs and public platform behavior. When a managed gap
matters, the workflow records it and permits escalation only to documented
public Win32 interop.

Use this evidence order:

1. Current public API documentation and target reference assemblies.
2. Observable integration tests on every supported platform and identity.
3. Public implementation documentation and issue investigations as supporting
   evidence, not application contract.
4. Hypotheses that remain explicitly labeled until reproduced.

## Stable findings

### Model and transport

- A named pipe has a discoverable name and one server instance per simultaneously
  connected client. Several instances can share one name.
- Anonymous pipes suit inherited parent-child channels and are one-way. Duplex
  communication requires two pipes.
- `System.IO.Pipes` is an operating-system IPC API. `System.IO.Pipelines` is an
  in-process buffering/parsing library that can wrap a stream but does not create
  an IPC endpoint.
- Remote Windows named pipes travel over SMB. Local success does not validate
  remote naming, network reachability, authentication, SMB policy, or destination
  authorization.
- The managed type names are cross-platform, but Windows message mode, remote
  names, ACLs, impersonation, and drain semantics are not portable promises.

### Streams and framing

- A stream read can return fewer bytes than requested. One write is not one read
  in byte mode.
- Windows message mode preserves write boundaries, but a read buffer can hold
  only a prefix. Callers must preserve that prefix, continue until complete, and
  enforce an aggregate maximum.
- The client side of a Windows message pipe does not imply message-read behavior
  merely because the server selected message transmission; code must establish
  the intended read mode through the public managed contract.
- Pipe buffer sizes provide buffering and backpressure, not a trustworthy maximum
  application message size. The protocol must validate its own lengths before
  allocating.
- `Flush()` or `FlushAsync()` is not proof that the peer processed data.
  `WaitForPipeDrain()` has stronger peer-consumption behavior on Windows but is
  synchronous, platform-specific, and capable of waiting indefinitely.

### Async, cancellation, and lifetime

- Asynchronous methods need endpoints created with `PipeOptions.Asynchronous`
  when true cancelable/scalable operating-system I/O is required. Wrapping a
  synchronous call in `Task.Run()` does not provide equivalent cancellation.
- Immediate completion and pending completion are both valid. Cancellation races
  normal completion, so operation state must remain alive until final completion.
- One reader and one writer can operate concurrently on a connection. Multiple
  readers compete for the stream; writers must serialize whole application
  frames when a frame spans more than one write.
- `IsConnected` is a snapshot, not a liveness guarantee. Zero-byte read,
  end-of-stream, and I/O completion are authoritative for protocol flow.
- A broken connection is terminal for that client object. Reconnect with a new
  object and replay only when the protocol makes duplicate processing safe.

### Connection and capacity

- One `NamedPipeServerStream` represents one server instance and one active
  client. Multi-client servers need several instances or prompt replenishment.
- Availability checks do not reserve an instance. Connect directly under one
  bounded policy rather than using file-existence probes.
- Client-first startup, busy instances, and server restart require a bounded
  retry/deadline design. A tight absence loop can consume CPU and delay startup.
- Backpressure can leave writes pending when the peer does not read. Protocols in
  which both sides write large payloads before reading can deadlock.

### Security

- A pipe name is discoverable and is not authentication.
- `PipeOptions.CurrentUserOnly` requires a named-pipe server and client to have
  the same user as their peer. On Windows, it also checks elevation level. On
  Unix, runtime behavior includes peer-credential validation; starting in .NET
  11, server creation also tightens the backing socket file to owner-only mode
  at bind time. Within one process, that permission ratchets for a shared pipe
  name: after any `CurrentUserOnly` instance selects owner-only mode, later
  instances retain it until the shared server entry is released, even when they
  omit the option. Verify the deployed runtime when socket-file visibility
  matters. The option does not express every cross-user, service, or locality
  policy.
- Windows services and intentional cross-user endpoints should create atomically
  with an explicit least-privilege `PipeSecurity`, commonly through
  `NamedPipeServerStreamAcl.Create()`. Tightening security after creation opens a
  race. The ACL factory ignores a supplied `PipeSecurity` when
  `CurrentUserOnly` is also present, so these are alternative creation policies.
- Remote-client policy and identity authorization are separate controls. Verify
  the current managed surface when transport-enforced local-only behavior is a
  requirement; do not invent a `PipeOptions` value. An ACL that excludes network
  identities is useful but answers the authorization layer.
- `PipeOptions.FirstPipeInstance` can protect ownership of the first well-known
  server name. Additional legitimate instances need a compatible creation path.
- Impersonation must fail closed, remain narrow, and never substitute for
  application message validation and authorization.
- Peer process IDs, session IDs, and computer names are diagnostic attributes,
  not credentials.

## Public managed surface used by this skill

| Area | Public types or members |
| --- | --- |
| Named server/client | `NamedPipeServerStream`, `NamedPipeClientStream` |
| Anonymous parent/child | `AnonymousPipeServerStream`, `AnonymousPipeClientStream` |
| Common stream contract | `PipeStream`, `ReadAsync`, `WriteAsync`, `IsConnected`, `IsMessageComplete` |
| Design options | `PipeDirection`, `PipeTransmissionMode`, `PipeOptions`, `HandleInheritability` |
| Windows ACL creation | `PipeSecurity`, `PipeAccessRule`, `PipeAccessRights`, `NamedPipeServerStreamAcl.Create()` |
| Windows impersonation | `TokenImpersonationLevel`, `RunAsClient()`, `GetImpersonationUserName()` |
| Ownership/interoperation | `SafePipeHandle` only when the design explicitly owns raw-handle lifetime |

Raw-handle interoperation is not the default. If selected, audit duplicate
handles, ownership transfer, asynchronous operation lifetime, and stream
disposal as one system.

## API drift gates

Before generating code, verify against the target framework:

- available `ConnectAsync()` timeout overloads and their timeout-versus-
  cancellation exception behavior;
- available `WaitForConnectionAsync()` overloads;
- whether Windows access-control types require a package reference;
- platform annotations on message mode, ACLs, impersonation, instance queries,
  and drain;
- whether the current managed surface exposes a required locality or transaction
  capability; and
- behavior of any constructor combining `CurrentUserOnly`, explicit ACLs,
  inheritance, or existing safe handles.

When the API differs, preserve the design invariant rather than copying a newer
overload. Use a linked cancellation source for a missing timeout overload, a
tested read-exactly loop for an older stream API, or report that public interop
is required for a Windows-only capability.

## Public references

- [System.IO.Pipes namespace](https://learn.microsoft.com/dotnet/api/system.io.pipes)
- [NamedPipeServerStream](https://learn.microsoft.com/dotnet/api/system.io.pipes.namedpipeserverstream)
- [NamedPipeClientStream](https://learn.microsoft.com/dotnet/api/system.io.pipes.namedpipeclientstream)
- [AnonymousPipeServerStream](https://learn.microsoft.com/dotnet/api/system.io.pipes.anonymouspipeserverstream)
- [PipeStream](https://learn.microsoft.com/dotnet/api/system.io.pipes.pipestream)
- [PipeOptions](https://learn.microsoft.com/dotnet/api/system.io.pipes.pipeoptions)
- [CurrentUserOnly Unix permission change](https://learn.microsoft.com/dotnet/core/compatibility/core-libraries/11/namedpipeserverstream-unix-permissions)
- [NamedPipeServerStreamAcl.Create](https://learn.microsoft.com/dotnet/api/system.io.pipes.namedpipeserverstreamacl.create)
- [PipeSecurity](https://learn.microsoft.com/dotnet/api/system.io.pipes.pipesecurity)
- [Pipe operations in .NET](https://learn.microsoft.com/dotnet/standard/io/pipe-operations)
- [Use named pipes for network IPC](https://learn.microsoft.com/dotnet/standard/io/how-to-use-named-pipes-for-network-interprocess-communication)
- [Unsupported APIs by platform](https://learn.microsoft.com/dotnet/core/compatibility/unsupported-apis#systemiopipes)
- [Windows named pipes](https://learn.microsoft.com/windows/win32/ipc/named-pipes)
- [Named-pipe security and access rights](https://learn.microsoft.com/windows/win32/ipc/named-pipe-security-and-access-rights)
- [Interprocess communication for Windows apps](https://learn.microsoft.com/windows/apps/develop/communication/interprocess-communication#pipes)
- [Troubleshooting SMB](https://learn.microsoft.com/windows-server/storage/file-server/troubleshoot/troubleshooting-smb)
