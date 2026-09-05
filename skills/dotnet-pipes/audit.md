# Audit .NET pipe usage

This is the audit subskill. Review an existing `System.IO.Pipes`
implementation for architecture, security, protocol, concurrency, lifetime,
resource, platform, and recovery defects. For a review-only request, do not edit
production code unless the user separately asks for fixes.

## 1. Establish scope and intended contract

Inventory the relevant projects and every use of:

- `NamedPipeServerStream`, `NamedPipeClientStream`,
  `AnonymousPipeServerStream`, and `AnonymousPipeClientStream`;
- `PipeOptions`, `PipeTransmissionMode`, `PipeDirection`, and
  `TokenImpersonationLevel`;
- `PipeSecurity`, `PipeAccessRule`, and `NamedPipeServerStreamAcl`;
- `WaitForConnection*`, `Connect*`, `Read*`, `Write*`, `Disconnect`,
  `WaitForPipeDrain`, `RunAsClient`, `IsConnected`, and `IsMessageComplete`;
- raw safe-handle access, handle inheritance, stream wrappers, serializers, and
  reconnect loops; and
- tests, deployment identities, remote server names, and platform guards.

Trace constructors to their configuration and each accepted connection through
its owner, reader, writer, handlers, cancellation, and disposal. Do not judge a
single call without the surrounding lifecycle.

Write down the intended platforms, process relationship, allowed identities,
local or remote boundary, direction, concurrent clients, protocol framing,
size limits, deadlines, and replay guarantee. Mark missing requirements as
unknown; do not infer them from convenient code.

## 2. Run the audit gates

### Architecture and platform

- Does the process topology justify named or anonymous pipes rather than a
  socket, HTTP/RPC, or in-process primitive?
- Are Windows-only message, ACL, impersonation, remote, and drain behaviors
  guarded and tested rather than assumed portable?
- Is `System.IO.Pipelines` correctly treated as optional buffering over a
  transport, not as the transport itself?

### Security

- Is the pipe name stable and non-secret, with untrusted text excluded?
- Does a same-user endpoint deliberately use `CurrentUserOnly`, or does a
  service/cross-user endpoint create atomically with an explicit least-privilege
  `PipeSecurity` allow-list?
- Is an explicit `PipeSecurity` kept separate from `CurrentUserOnly`, which
  would cause the ACL factory to ignore the supplied descriptor?
- Is remote access explicitly allowed or denied as a separate decision from
  user identity?
- Is first-instance exclusivity used when name squatting matters, without
  breaking subsequent legitimate instances?
- Are package, session, elevation, service-account, and remote-authentication
  boundaries represented in tests?
- Does required impersonation fail closed, stay synchronous and narrow, and
  avoid using unvalidated client input for privileged resource selection?
- Are peer-supplied lengths, paths, commands, and serialized values validated
  before allocation or privileged use?

### Protocol and resource bounds

- Does byte mode have explicit framing, versioning, request IDs, maximum frame
  and aggregate sizes, and defined error responses?
- Does message mode loop until completion and cap aggregate size?
- Can concurrent writers interleave a header and payload? Can multiple readers
  steal bytes from one another?
- Are client count, listener count, queued bytes, outstanding requests, handler
  work, and idle connections bounded?
- Can a peer keep a frame alive forever by sending one byte before each renewed
  timeout?

### Async, cancellation, and lifetime

- Were both endpoint handles created for asynchronous operation when async APIs
  are expected to cancel or scale?
- Does each pending operation retain its stream, buffer, and state until final
  completion?
- Does cancellation reach the actual pipe call, and are completion-versus-
  cancellation races accepted?
- Is there one connection owner, with every spawned task observed before
  disposal?
- Can a wrapper, callback, host shutdown path, or child process retain or close
  the handle unexpectedly?

### Connection and server capacity

- Does one `NamedPipeServerStream` serve only one active client, with listening
  capacity replenished under load?
- Are accept exceptions contained so one client cannot permanently stop the
  listener?
- Does the client use a bounded connect policy without existence probes or a
  tight retry loop?
- Is `IsConnected` absent from correctness decisions?

### Failure, shutdown, and replay

- Are zero-byte reads, broken connections, I/O exceptions, and disposal treated
  as terminal for that connection?
- Does reconnect create a new client object and repeat authentication?
- Are retries restricted to requests proven safe through idempotency or
  deduplication IDs?
- Does shutdown avoid indefinite drain or mutual read/write waits?
- Are slow or malicious peers removed within explicit resource and time limits?

### Observability and tests

- Do logs carry operation, endpoint role, local/remote target, connection and
  request IDs, elapsed deadline, byte counts, exception type, full `HResult`,
  cancellation source, and relevant identity context without payload leakage?
- Do real endpoint tests cover startup order, fragmentation, malformed lengths,
  maximum boundaries, concurrent clients, cancellation, peer exit, identity,
  and supported platforms?
- Are remote SMB and privileged identity tests separated from local protocol
  tests so a failed layer is identifiable?

## 3. Classify findings

| Severity | Use when |
| --- | --- |
| High | An unintended identity can connect; privileged work can run under the wrong identity; peer input can cause unbounded allocation/work; handle lifetime can corrupt data; replay can duplicate consequential actions |
| Medium | A realistic peer, load, cancellation, or shutdown path can hang, permanently stop accepts, corrupt framing, leak connections, or fail on a supported platform |
| Low | Diagnostics, tests, clarity, or defense in depth are incomplete without a demonstrated current correctness or security failure |

Do not inflate severity from a suspicious API name alone. Show the reachable
path, precondition, and consequence. If deployment identity, platform, or remote
policy is unavailable, state that the finding is conditional and name the
evidence needed to resolve it.

## 4. Report findings first

For each finding provide:

1. Severity and concise title.
2. File and line evidence, including the controlling constructor or owner.
3. Observable failure or security consequence.
4. Required preconditions and confidence.
5. Smallest adequate remediation.
6. Regression or integration test that would fail before the fix.

Then list open questions, audit coverage, commands or tests run, and residual
risk. If no findings remain, say so explicitly and identify untested identity,
platform, load, or remote scenarios. Use `technical-writing` in review mode on
the exact report after the technical conclusions stabilize.

For broader hostile-input review beyond pipe-specific boundaries, invoke a
security review workflow. Use performance testing when a queue, buffer, or load
claim requires measurement rather than inspection.
