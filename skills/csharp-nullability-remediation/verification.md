# Verification for nullability remediation

Validation must prove more than disappearance of the original diagnostic. Scale the
checks to the contract that changed.

## Focused loop

After each representative edit:

1. compile the narrowest project and target framework that reaches the site;
2. confirm each nullable or null-forgiving diagnostic observed by the probe is gone;
3. check for new warnings at callers and implementations; and
4. run the nearest behavior test, including the null or invalid-state branch.

Do not edit another category before this loop can distinguish a correct remedy from
a moved warning.

## Target-framework matrix

Run every target whose reference annotations or compiler inputs differ. A modern
target compiling cleanly does not prove an older target sees the same BCL metadata or
nullable-analysis attributes.

When an attribute is absent downlevel, use the repository's approved package or
source generator. Do not hand-roll nullable-analysis attributes solely for the fix.

## Public nullable contracts

For a public method, property, operator, delegate, or interface implementation:

- identify whether emitted nullable metadata changes;
- compile representative consumers, especially warning-as-error consumers;
- follow newly exposed nullable warnings through callers until the warning chain
  closes rather than treating the first clean declaration as completion;
- test overrides and interface implementations for `CS876x` mismatches;
- preserve success/failure semantics for `Try*` APIs; and
- document intentional compatibility impact.

The CLR signature remaining identical is not sufficient validation.

## Behavior checks by category

| Change | Required behavior evidence |
| --- | --- |
| Added guard or throw | Null path throws the intended exception at the intended boundary; valid path is unchanged. |
| Constructor-established invariant | Every constructor establishes it; valid construction exposes only initialized state. |
| Static-constructor invariant | First use initializes successfully; missing dependencies fail at the intended type boundary. |
| Nullable return/output | Callers observe and handle null; success guarantees match annotations. |
| State-dependent storage | Every read is valid-state guarded; reset/clear/default construction is covered. |
| Enumerator state | Before-first, active, after-end, reset, and default-constructed behavior is covered. |
| Framework initialization | Test the real lifecycle or the closest supported integration boundary. |
| Reflection/external lookup | Missing member/result produces a descriptive controlled failure. |
| Intentional invalid test input | The production null-validation path is still exercised. |

## Proportionate performance verification

Nullability remediation is not an optimization project. Follow explicit user and
repository acceptance criteria; the defaults below do not waive a required gate.

| Change | Default performance check |
| --- | --- |
| Compiler-proven redundant suppression removal or annotation-only change that preserves executed expressions | Compilation and correctness tests; no mandatory benchmark or IL inspection. |
| Guard or state-access change | An existing representative benchmark when the changed path is frequent enough to matter; do not benchmark every error-path check. |
| Allocation, layout, loop, or callback rewrite | A bounded original/candidate comparison on the relevant runtime/JIT before accepting the rewrite. |

Select the scenario, acceptance criteria, and run budget before measuring. Start
with one targeted before/after comparison using the existing harness. At most one
confirmatory repeat is the default unless a larger budget is already authorized.
If the necessary benchmark does not exist, surface that gap instead of building
measurement infrastructure automatically.

Report absolute cost with units, relative cost, allocations, execution frequency
when known, and end-to-end significance or its absence of evidence. Statistical
significance alone does not establish practical importance or justify investigation.
A small per-call difference can still matter on a sufficiently frequent path;
do not use a universal nanosecond cutoff.

If results are noisy, report uncertainty rather than rewrite production code from
an unstable comparison. A failed or inconclusive gate is not a pass, but neither
authorizes an open-ended investigation. When the budget is exhausted, stop and
report the remaining risk.

Profiling, IL/JIT disassembly, diagnostic variants, new harnesses, and system-wide
configuration changes require separate approval unless already in scope. Do not
repeatedly escalate through alternative tools after the user declines further work.
Retain a suppression only when repository policy and the retention conditions in
[remediation.md](remediation.md) allow it; otherwise report the unresolved site.

Performance evidence must name the runtime, JIT, scenario, and uncertainty. A single
stopwatch result is not enough.

## Final validation

Before calling the remediation complete:

1. rerun the diagnostic inventory and reconcile every changed count;
2. build every affected target in Release;
3. run the repository's required Release tests;
4. run public-consumer or package checks when annotations changed;
5. satisfy explicit performance gates and run the bounded comparisons above for
   accepted hot-path rewrites; compiler-only or annotation-only changes need no
   timing checks unless an explicit gate requires them;
6. verify generated/vendored exclusions are configuration-based and documented; and
7. when a diagnostic analyzer participates, compile a representative violation and confirm each intended project emits the expected diagnostic.

Report commands that could not run and why. Do not convert an unavailable check into
a pass.

## Completion ledger

Record at least:

| Site/category | Before | Suppressed warning | Remedy or retained suppression | Focused check | Broader check | Residual risk |
| --- | --- | --- | --- | --- | --- | --- |

Separate unresolved sites from completed ones. Count reconciliation is useful, but
it does not replace contract evidence.
