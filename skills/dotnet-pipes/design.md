# Choose a .NET pipe design

Choose the transport before writing constructors. The controlling questions are
process relationship, machine boundary, platform support, identity boundary,
concurrency, and protocol guarantees.

## 1. Establish the constraints

Inspect the target project and answer:

| Constraint | Evidence to collect | Why it changes the design |
| --- | --- | --- |
| Platforms and target frameworks | Project files, runtime identifiers, deployment docs | Windows-only features cannot be hidden behind a portable type name |
| Process relationship | Who launches whom; how endpoints discover each other | Parent-child can use inherited anonymous handles; unrelated processes need discovery |
| Machine boundary | Local only, remote Windows, or general network | Remote Windows named pipes add SMB; cross-platform networking usually favors sockets or HTTP/RPC |
| Direction | One-way or duplex | Anonymous pipes are one-way; duplex needs two or a named pipe |
| Client population | Peak connected, waiting, and idle clients | Determines listener count, admission limits, and memory budget |
| Identity boundary | Same user/elevation, service-to-user, cross-user, packaged, remote | Selects `CurrentUserOnly`, an explicit ACL, package rules, or another authenticated transport |
| Protocol | Payload shape, maximum size, ordering, request IDs, replay | A stream requires framing and failure semantics |
| Operations | Deadlines, cancellation, shutdown, peer failure | Determines asynchronous handles and connection ownership |

Ask only about constraints that cannot be recovered from the repository or
deployment model. Do not begin with constructor parameters.

## 2. Select the transport

| Situation | Default choice | Do not choose it when |
| --- | --- | --- |
| Parent launches child; one-way standard-stream-like flow | `AnonymousPipeServerStream` plus `AnonymousPipeClientStream` | Unrelated clients need discovery, several clients connect independently, or one object must be duplex |
| Unrelated local processes; service name; Windows identity or ACL matters | `NamedPipeServerStream` plus `NamedPipeClientStream` | The protocol must be network-portable or standard network tooling is required |
| Cross-platform local IPC through `System.IO.Pipes` | Named pipes in byte mode, after testing every target OS | Windows message mode, remote server names, ACLs, impersonation, or drain semantics are part of the contract |
| Remote Windows client through an established SMB environment | Windows named pipe only when SMB identity, policy, operations, and diagnostics are intentional | Internet routing, TLS, proxies, broad interoperability, or independent service evolution matter |
| General cross-platform or remote service | Unix-domain socket, TCP, HTTP, gRPC, or another established transport | Windows pipe security or compatibility is the controlling requirement |
| In-process producer/consumer buffering | `System.IO.Pipelines`, channels, or streams | Separate processes need an operating-system endpoint |

Do not choose a named pipe merely because the application is written in .NET.
Record why its discovery, security, deployment, or compatibility properties beat
the alternatives.

## 3. Fix the platform contract

The `System.IO.Pipes` type names are cross-platform, but the behavior is not
uniform.

| Capability | Windows | Unix-like systems |
| --- | --- | --- |
| Local named endpoint | Supported | Supported through the platform's local socket implementation |
| Byte-stream protocol | Supported | Supported |
| Message transmission/read mode | Supported | Do not depend on it |
| Remote computer name | Available through Windows remote named pipes and SMB | Do not depend on it |
| `PipeSecurity`, ACL factory, Windows identity impersonation | Supported with Windows-specific APIs | Not a portable contract |
| Peer-consumption drain | Windows-specific | Not a portable contract |

If any Windows-only row is required, make Windows support explicit in project
configuration, platform guards, tests, and documentation. Do not catch
`PlatformNotSupportedException` and silently weaken security or protocol
semantics.

## 4. Choose the security boundary

### Same-user IPC

Use `PipeOptions.CurrentUserOnly` when each endpoint must have the same user as
its peer. Apply it to the server and client where their constructors support it.
On Windows, the check includes both user account and elevation level. On Unix,
verify the target runtime's peer-credential and socket-file permission behavior.
It does not mean "same machine only," and it is too narrow for a service
intentionally accepting another account.

### Service or cross-user IPC on Windows

Create the first server instance atomically with an explicit `PipeSecurity`
through `NamedPipeServerStreamAcl.Create()`. Build an allow-list from stable
SIDs for the server and intended clients. Grant only the data and instance
creation rights each identity needs. Do not create permissively and tighten the
descriptor later. Do not combine an explicit descriptor with
`PipeOptions.CurrentUserOnly`; the ACL factory ignores the supplied
`PipeSecurity` when that option is present.

Decide separately whether remote clients are allowed. An ACL and transport
locality answer different questions. If transport-enforced local-only behavior
is required and the target framework has no public managed option, record the
managed gap. Use a reviewed ACL that excludes network identities, and escalate
to documented public Win32 interop only when the stronger guarantee is required.

### Name ownership and peer identity

- Use a stable, product-specific, versioned name without secrets or raw
  user-controlled text.
- Consider `PipeOptions.FirstPipeInstance` for the legitimate first server when
  name squatting is in scope. Do not apply it blindly to subsequent instances.
- Treat process IDs, session IDs, computer names, and the pipe name as
  diagnostics, not authentication.
- Add protocol authentication when Windows handle access alone does not prove
  the peer expected by the application.

### Impersonation

Use `RunAsClient()` only when resource authorization should occur as the client.
Request the least client impersonation level that meets the protocol. Validate
the request before entering the impersonated scope, perform only the intended
synchronous resource operation inside it, and fail the request if impersonation
cannot be established.

## 5. Define the protocol and resource model

Default to byte mode with a fixed-size length header and a configured maximum.
Also define:

- protocol version and message kind;
- request or correlation ID;
- maximum frame and aggregate request sizes;
- legal ordering and whether requests may overlap;
- response and error envelope;
- authentication or authorization step;
- connection, handshake, request, idle, and shutdown deadlines;
- admission, queued-byte, and per-client work limits;
- cancellation ownership; and
- idempotency and replay rules after ambiguous failure.

Use message mode only for a Windows-specific protocol that benefits from write
boundaries. Continue reads until the message is complete and enforce an
aggregate maximum.

## 6. Produce the design record

Before implementation, state:

1. Transport and why alternatives were rejected.
2. Supported platforms and target frameworks.
3. Name or inherited-handle discovery.
4. Direction, instance count, and admission limit.
5. Allowed identities, locality, name-ownership, and impersonation policy.
6. Framing, versioning, size limits, ordering, and replay behavior.
7. Deadlines, cancellation, shutdown, and reconnect behavior.
8. Required logs and integration tests.

An unknown that affects identity, locality, or replay blocks implementation. A
tunable capacity value may proceed with a conservative documented default and a
testable configuration point.
