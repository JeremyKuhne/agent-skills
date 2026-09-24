# Design Pester 6 tests for PowerShell contracts

Read this when a PowerShell command, function, or module needs tests, or when
an existing Pester suite passes without exercising a required failure path.
Choose the harness from the behavior's owner, not the current test file.

## Choose the owning test lane

| Subject | Owning evidence |
| --- | --- |
| Pure PowerShell function, pipeline, parameter binding, or module behavior | Pester 6 through the public PowerShell entry point |
| YAML, JSON, XML, or other language syntax and repository policy | Maintained parser or schema API, with tests in its owning component |
| Managed state machines, parsers, or test infrastructure | Managed tests; Pester only if a PowerShell wrapper is itself under test |
| Streams, exit codes, environment, timeouts, or process cleanup | Fresh-process behavior tests, not a mock of the command being checked |
| Generated PowerShell | Render and execute the generated copy; do not infer behavior from template text |

If ownership is mixed, split the assertions by subject. A green Pester suite
does not prove managed policy or another language's grammar.

## Derive cases before implementation

1. State the accepted contract and its independent oracle. For each input or
   state, name the expected output, error, or absence; do not copy expected
   values from the current function or from a newly observed failure.
2. Include valid boundary cases and the complement of rejected states. Keep
   missing, null, false, zero, empty, malformed, and unsupported distinct when
   the contract distinguishes them.
3. Use table-driven Pester cases for equivalent inputs. Make data needed by
   `-ForEach` available at discovery time; use `BeforeAll` for run-time setup,
   not as the source of discovery-time cases.
4. Exercise the public function or command. Mock external dependencies only
   where isolation is needed; a mock of the behavior being asserted is not
   independent evidence.
5. Add one reversible negative control: weaken a required rejection, type
   check, or state transition and confirm the focused test fails. Restore the
   original behavior and rerun the same check before widening scope.

Prefer assertions on concrete types, values, error identity, and streams over
truthiness or only checking that output is nonempty. Keep fixtures and mutable
module or environment state isolated between cases; restore state on failure.

## Validate the execution receipt

Use the supported PowerShell and Pester compatibility floors, then run through
the consuming repository's exact-version, isolated entry point when it has
one. A minimum-version declaration is not an exact CI execution lock.

- Require positive discovery for the intended component. Zero failed tests
  with zero discovered tests is not a passing behavior check. An intentional
  skip-only shard can be structurally complete but is not evidence that the
  skipped behavior ran; report it separately from executed behavior.
- Require `Result = Passed` from a completed worker with no timeout or worker
  error and a process exit code of 0 before accepting a passing receipt.
- Reconcile `TotalCount` with `PassedCount`, `FailedCount`, `SkippedCount`,
  `NotRunCount`, and `InconclusiveCount`. Never count skipped work as passed.
- Require zero `FailedCount`, `FailedBlocksCount`, `FailedContainersCount`,
  `NotRunCount`, `InconclusiveCount`, and infrastructure failures for a passing
  receipt. Report intentional skips separately.
- Run the narrow failing control first and the component suite after repair.
  Exercise real process, host, or platform boundaries in their owning lanes.
- Report the hosts and gates that actually ran. A single current-host Pester
  pass does not prove minimum-host or cross-platform compatibility.

Mechanical Pester 5-to-6 conversion belongs to a dedicated migration workflow
when available; do not reproduce it here or change a runner to compensate for
a test-ownership mistake.
