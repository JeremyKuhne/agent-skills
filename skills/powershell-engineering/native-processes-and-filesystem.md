# Observe process and filesystem boundaries

Read this when a PowerShell command launches a native child or changes the
environment or filesystem around one. Define observable behavior before
selecting a process API or test harness; the child and platform own facts that
cannot be established by a mock of the wrapper.

## Name the boundary contract

| Boundary | Contract to record | Independent evidence |
| --- | --- | --- |
| Launch | Executable identity, argument values, working directory, and paths containing spaces | A fresh child that reports what it received |
| Streams | What stdout, stderr, and PowerShell streams mean and how they remain separate | Captured streams from a real child |
| Outcome | Exit code, launch failure, malformed output, timeout, and cancellation as distinct states | Child-process receipts and failure controls |
| Environment | Child-only settings, or the prior presence and value of any setting changed in the caller | Before/after checks on success and failure |
| Filesystem | Owned scratch paths, path semantics, cleanup responsibility, and platform-specific guarantees | Literal-path checks and host-owned behavior tests |

Do not turn a platform observation into a universal guarantee. Complex shared
timeouts, process-tree supervision, or typed cross-process result protocols
belong with an established process library or managed owner when PowerShell is
only orchestrating them.

## Launch and observe the child

- Pass arguments through a mechanism verified for the target program and host;
  do not assume a joined command string preserves a path with spaces. Test the
  exact argument values the child receives.
- Capture the child's exit status before another native invocation can replace
  it. Distinguish a launch failure from a child that started and exited nonzero.
  Parsed stdout alone is not proof of success when the contract requires exit 0.
- Keep stdout and stderr separate. Parse machine-readable stdout with its
  owning parser and treat stderr according to the declared protocol. Do not
  assert cross-stream ordering unless the protocol supplies that evidence.
- When using an API that redirects both streams, drain them without blocking
  the child. If the contract includes timeout or cancellation, observe both
  the outcome and cleanup; do not invent a process-tree supervisor in a small
  wrapper.

## Restore the caller and clean owned files

- Prefer child-scoped environment values. If the wrapper changes its own
  environment, record both whether a variable was present and its exact prior
  value, then restore either the value or absence on every exit path.
- Use a unique workspace for temporary files. Operate on literal paths and
  clean only paths owned by that operation, including when a child fails,
  output parsing throws, or cancellation occurs. Put restoration in a
  `finally` path, not only on success.
- Test paths containing spaces and the applicable filesystem rules on the
  hosts that own them. ACLs, symlinks, case sensitivity, and native loading
  need platform-specific evidence rather than a single-host assumption.

## Choose the smallest real check

Keep pure transformation logic in its owning unit-test lane. For process and
filesystem behavior, run a controlled real child and inspect arguments,
stdout, stderr, exit code, environment before and after, and owned scratch
paths. Cover exit 0, nonzero exit with parseable stdout, malformed stdout,
launch failure, and timeout or cancellation where the command promises them.
Use one reversible negative control, such as accepting valid stdout despite a
nonzero exit or retaining a temporary variable after failure. Rerun that
focused check after repair, then the component gate. Report the hosts and
failure modes actually exercised.
