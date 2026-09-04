---
name: dotnet-pipes
description: Design, implement, review, and troubleshoot secure, reliable .NET interprocess communication with System.IO.Pipes. Use when choosing named versus anonymous pipes or another IPC transport; writing NamedPipeServerStream, NamedPipeClientStream, AnonymousPipeServerStream, or AnonymousPipeClientStream code; designing framing, timeouts, cancellation, concurrency, reconnect, Windows ACL, impersonation, local or remote behavior; auditing pipe safety; or diagnosing pipe connection, hang, access, message, disposal, or SMB failures. Do not use for System.IO.Pipelines buffering unless an operating-system pipe is also involved.
license: MIT
compatibility: Requires a .NET project. Message mode, Windows access control, impersonation, remote named pipes, and peer-consumption drain are Windows-specific; verify the target framework's public API before using them.
metadata:
  portability: portable
  applicability: dotnet
  binding: optional-overlay
  risk: local-write
  maturity: canary
  requires: technical-writing
  related: security-review, performance-testing, cswin32-interop
---

# .NET pipes

If `overlay.md` exists beside this file, read it before acting; it contains
repository-specific bindings. This core remains usable without it.

Design and implement operating-system pipes through the public
`System.IO.Pipes` surface, or review and diagnose an existing implementation.
Keep transport choice, protocol design, security, resource limits, and
lifecycle behavior explicit. A connected byte stream is not yet a safe
application protocol.

## Route the request

| Request | Read and execute |
| --- | --- |
| Choose a transport or architecture | [design.md](design.md) |
| Write or change pipe code | [design.md](design.md), then [implementation.md](implementation.md) and [testing.md](testing.md) |
| Audit pipe code for correctness and safety | [audit.md](audit.md) |
| Diagnose a failure, hang, or intermittent result | [troubleshooting.md](troubleshooting.md), then add a regression case from [testing.md](testing.md) |
| Explain an API or platform difference | [references/research.md](references/research.md), then verify time-sensitive API details against current public documentation |

For mixed requests, choose the controlling workflow first. Troubleshoot an
unexplained failure before redesigning it; audit a proposed patch after its
behavior is stable.

## Resolve material unknowns

Inspect the project before asking. Determine its target frameworks, supported
operating systems, process topology, existing protocol, hosting model, package
references, tests, and local conventions. Ask focused questions only when the
answer changes the design or security boundary:

- Must both endpoints run on one machine, and on which operating systems?
- Does a parent launch the child, or must unrelated clients discover a service?
- Which identities may connect, and does a privileged server cross a trust
  boundary?
- Is traffic one-way or duplex, and how many clients and outstanding requests
  must be supported?
- What are the maximum frame size, deadlines, shutdown rules, and replay
  semantics?

Do not guess an identity boundary, remote requirement, or replay guarantee. If
the user cannot answer, state the conservative assumption in the design and
make it configurable where practical.

## Non-negotiable rules

- Do not confuse `System.IO.Pipes` with `System.IO.Pipelines`. The latter is a
  buffering and parsing library, not an IPC transport.
- Prefer byte mode with explicit bounded framing. Treat Windows message mode as
  a platform-specific protocol choice, and never assume one read returns one
  message or one write maps to one read.
- Open endpoints for asynchronous I/O when operations must scale or cancel.
  Pass cancellation to the actual I/O call; do not wrap blocking pipe I/O in
  `Task.Run()` and call it cancelable.
- Use one logical reader and serialize each complete application frame across
  concurrent writers.
- Treat `IsConnected` as a snapshot. Read completion, end-of-stream, and I/O
  failure determine connection health.
- Bound connection count, queued work, frame size, total work, and every wait
  phase. Preserve one deadline across all partial reads of a frame.
- One `NamedPipeServerStream` instance serves one client at a time. Replenish a
  bounded listener pool before doing long-running client work.
- Treat the pipe name as discoverable routing data, never as authentication.
  Use `CurrentUserOnly` only for its documented identity boundary; use an
  explicit Windows ACL for services or intentional cross-user access.
- Never continue privileged work as the server after required impersonation
  fails. Keep impersonation synchronous, narrow, and auditable.
- Treat a broken connection as terminal. Reconnect with a new client object and
  replay only requests whose identifiers and idempotency rules make that safe.
- Avoid `WaitForPipeDrain()` on responsive paths. Prefer a bounded
  application-level acknowledgment when proof of processing matters.
- Use only documented public .NET APIs. If a requirement is absent from the
  managed surface, report the gap. Hand public Win32 interop to a suitable
  interop workflow only when the requirement justifies it; never use runtime
  internals, undocumented controls, or private structures.

## Completion contract

After implementation, run the narrowest build and real endpoint test that can
falsify the design, then the affected test suite. Report the selected transport,
security boundary, framing and limits, cancellation and shutdown behavior,
validation run, and any platform-specific or unverified behavior.

For an audit, lead with findings ordered by severity and file/line evidence. For
troubleshooting, separate observed facts, supported inference, hypotheses, and
unknowns. Use `technical-writing` after the domain facts stabilize so the final
human-facing explanation remains grounded and concise.
