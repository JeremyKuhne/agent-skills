# Troubleshoot .NET pipes

This is the troubleshooting subskill. Diagnose from the failed operation and
final completion, not from a cached connection property or localized exception
message. Change one variable at a time and preserve the original failure before
adding retries, buffers, or timeouts.

## 1. Capture the failure

Collect:

- exception type, `Message`, full `HResult`, inner exception, and stack trace;
- endpoint role and operation: create, connect, accept, read, write, handshake,
  disconnect, drain, or dispose;
- pipe and server name with sensitive values removed, plus local or remote;
- target framework, operating system, architecture, and deployment model;
- direction, transmission/read mode, options, ACL strategy, and impersonation
  level;
- immediate result versus final asynchronous completion;
- requested and transferred bytes, frame state, and operation/request ID;
- elapsed time, configured deadline, and which cancellation source fired;
- server instance/listener counts and active/queued work; and
- peer startup, exit, restart, close, cancellation, identity, session, and
  elevation events immediately around the failure.

On Windows, the low 16 bits of an `IOException.HResult` often contain a wrapped
Win32 error. Use that only as diagnostic evidence when the HRESULT is in that
form; preserve the complete value and do not make portable control flow depend
on it.

## 2. Split the problem at the highest-value boundary

1. Reproduce with one server and one client on the same machine.
2. Use byte mode, asynchronous endpoints, bounded length framing, and direct
   `PipeStream` reads/writes without serializers or buffered text wrappers.
3. If local succeeds and a remote Windows name fails, diagnose DNS, TCP/SMB,
   authentication, sharing and firewall policy, then the destination pipe ACL
   and server state. Do not change framing first.
4. If the minimal local case fails, classify create/connect, protocol,
   cancellation/lifetime, security, or resource pressure before widening scope.

A local path and a name that resolves through SMB are different transports even
when they target the same computer.

## 3. Use the symptom map

| Symptom | Most likely areas | Cheapest discriminating check |
| --- | --- | --- |
| Connect times out | Server absent, wrong name/context, every instance busy, listener not replenished, deadline too short | Log server instance creation and count waiting listeners during the same interval |
| `UnauthorizedAccessException` | ACL, `CurrentUserOnly`, elevation/user mismatch, direction/access, package boundary, remote identity | Run authorized and denied probes under the exact production tokens and inspect the creation policy |
| Server handles one client only | One server object reused incorrectly or next listener created after handler completion | Trace when the next instance begins waiting relative to client handling |
| Read returns zero | Peer closed and buffered data is exhausted | Correlate peer close and frame position; zero inside a frame is truncation |
| Read or write throws `IOException` | Peer close, disconnect, cancellation race, transport loss | Record the operation, final completion, byte count, peer event, and full HRESULT |
| Write stalls | Peer not reading, queue pressure, both sides write first, wrapper buffering | Capture both endpoint stacks/protocol states and queued outbound work |
| Protocol hangs after connect | Framing disagreement, both sides read first, missing writer flush, multiple readers | Replace protocol with one bounded request/response and trace every partial read/write |
| Messages merge or split | Byte-stream assumptions or concurrent frame writes | Force tiny reads and delayed header/payload writes under one serialized writer |
| Message is incomplete | Buffer smaller than message or aggregate loop missing | Continue until `IsMessageComplete` while enforcing one maximum |
| Cancellation appears ignored | Synchronous handle, token not passed to native async call, blocked wrapper, completion won race | Confirm `PipeOptions.Asynchronous`, call-site token, and final completion |
| `ObjectDisposedException` | Competing owner, scope ended before background task, wrapper closed stream | Trace stream construction, every task using it, wrapper `leaveOpen`, and disposal |
| End-of-stream never arrives | Duplicated or inherited handle remains open | Inventory parent, child, and wrapper ownership; close every unintended duplicate |
| Works until load rises | Listener starvation, unbounded handlers/queues/frames, thread-pool or memory pressure | Plot active listeners, clients, tasks, queued bytes, handles, and completion latency |
| Local works, remote fails | SMB reachability/authentication/policy before destination ACL | Prove the same identity can establish the intended SMB session, then test the pipe |
| `WaitForPipeDrain()` hangs | Peer stopped consuming prior outbound bytes | Remove drain from the reproduction or add a protocol acknowledgment |

Common Windows codes found inside a wrapped `IOException` include 2 (not
found), 5 (access denied), 109 (broken pipe), 121 (wait timeout), 231 (busy),
232 (no data/closing), 233 (not connected), 234 (more message data), 995
(operation aborted), and 997 (I/O pending at native submission). Managed APIs
may consume or translate native control-flow results, so do not duplicate their
internal handling from this table.

## 4. Test one hypothesis at a time

Pair every hypothesis with a result that can disprove it:

- "The server is absent" is disproved by a logged live listening instance with
  the same normalized name and namespace at failure time.
- "All instances are busy" is disproved by a waiting instance that remains
  available throughout the failed attempt.
- "The ACL denies the client" is weakened when the exact client token opens a
  minimal endpoint created with the same descriptor and access direction.
- "The pipe lost bytes" is weakened when raw byte logs show mismatched framing
  or concurrent writers before the transport boundary.
- "Cancellation is broken" is disproved when the operation completes normally
  before cancellation wins; final completion is authoritative.
- "The network is slow" is weakened when remote transport completes promptly
  but the application callback waits in a saturated scheduler.

Do not add broad retries until the retryable states and one overall deadline are
known. An existence probe does not reserve an instance and can perturb the
system; connect directly.

## 5. Isolate common defect classes

### Connection and startup

Start client-first and server-first. Ensure server creation succeeds before it
advertises readiness, listener capacity exists while handlers run, and clients
use a bounded connect operation. Avoid tight loops when the server name does not
yet exist; backoff must preserve one monotonic deadline.

### Framing and wrappers

Force one-byte and short reads. Verify both sides use the same endianness,
encoding, header width, message mode, and maximum. Never mix direct reads with a
`StreamReader` or serializer that can read ahead. Flush a buffering wrapper when
needed, but do not interpret that as peer processing.

### Lifetime and concurrency

Confirm one logical reader, one serialized complete-frame writer, one stream
owner, and observed handler tasks. Delay disposal until outstanding operations
reach final completion. For anonymous pipes, close the parent's local copy of
the client handle after child startup.

### Security and identity

Log actual user, groups relevant to the ACL, elevation, session, service or
package identity, and local/remote origin. Test under those tokens. Do not grant
broad access or run elevated merely to make the symptom disappear; that proves
only that identity affects the result.

### External interference and resource pressure

When failure is environment-specific, compare a policy-approved controlled
baseline and collect application timelines, process/thread stacks, operating-
system I/O traces, security-product logs, and SMB logs for remote endpoints.
Endpoint security can alter timing without changing the eventual status. Do not
disable production controls as a first fix.

## 6. Fix and prove the cause

Make the smallest change that addresses the demonstrated mechanism. Add a real
endpoint regression test reproducing the startup order, identity, fragmentation,
cancellation, load, or peer-exit condition. Run the focused test repeatedly,
then the affected suite and supported platform matrix.

Report observed facts, supported inference, remaining hypotheses, the fix,
validation, and untested environmental boundaries. Use `technical-writing` for
the final incident or troubleshooting note after the evidence stabilizes.
