# Measure coverage in the owning component

Read this when a change claims PowerShell or managed executable coverage,
adds a coverage exception, or proposes a percentage gate. Choose the tested
subject and collector before interpreting a report.

## Match source to the collector

| Subject | Owning evidence |
| --- | --- |
| PowerShell functions or modules executed in a Pester shard | Pester 6 coverage in the shard that exercises that component |
| A PowerShell script launched in a child process | Coverage collected inside that child process; the parent shard does not instrument it by implication |
| Managed code | Managed coverage through its own test runner and report |
| Rendered PowerShell | Exercise and measure the generated copy if it is the executable subject, not only its template source |

Inventory executable source paths, owning tests, execution modes, and platforms.
Add a manifest field only when a collector or gate consumes it; an unused label
cannot turn a skipped or uninstrumented component into covered code.

## Keep evidence separate

- Report managed and PowerShell coverage separately by owning component. Do
  not add their percentages or let a heavily tested domain mask another.
- Establish component report-only baselines after test ownership is settled.
  Require a reviewed decision before enabling a threshold or ratchet; do not
  promote a provisional global target into a gate.
- Measure the applicable changed branches and error paths. Enumerate critical
  state-table outcomes with explicit tests even when a line percentage looks
  high. Coverage shows execution, not correctness or an independent oracle.
- Keep skipped, unsupported, and uninstrumented code visible. Unknown coverage
  is neither zero nor full coverage; name the missing collector or host.

## Review exceptions

Allow a percentage exception for a thin wrapper, generated template, or
platform-only source only with a specific owner, rationale, and mapped
behavioral or platform test. Keep the source visible in reports and run its
owning behavior lane when available. A skipped platform test is not evidence
that its source was covered.

Use a synthetic fault or changed-branch control to check that the owning test
fails when a critical path is omitted. Run the focused component check, then
the relevant full gate. Report collectors, exercised hosts, missing evidence,
and approved exceptions without manufacturing a cross-domain percentage.
