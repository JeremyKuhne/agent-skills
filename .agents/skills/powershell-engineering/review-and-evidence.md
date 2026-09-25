# Review PowerShell changes and evidence

Read this before calling a PowerShell change ready. Review the accepted
contract and the code actually proposed, not a nearby pattern or the current
implementation's output.

## Choose the review boundary

- Identify the changed entry points, callers, generated counterparts, supported
  hosts, and independent behavior oracle. Compare the diff with the promised
  scope. If it introduces a new grammar class or implementation owner, stop
  and revisit the boundary instead of adding another local exception.
- Check public parameter binding, value types and array shape, output and error
  streams, native exit handling, environment restoration, generated outputs,
  and host compatibility where the change touches them. Use the matching
  on-demand guide for each affected contract; do not make every review an
  unrelated sweep or substitute a parser check for runtime evidence.
- For each consequential claim, name a negative control that would fail if the
  behavior were wrong. A passing test derived solely from the implementation
  is not an independent oracle.

## Bind receipts to the final tree

1. Record the tested commit and any uncommitted changes that affect the run.
   Check positive discovery, process and worker status, failure counts, and
   intentional skips for the focused component before accepting its receipt.
   Keep managed, PowerShell, generated-artifact, and host evidence in their
   owning lanes.
2. After a code or test edit, rerun the affected focused check. Before
   publication, run the required broader gates on the final snapshot and
   compare its diff with the claimed test cases, supported hosts, and PR text.
   A copied receipt from an earlier snapshot is stale even when every test
   in that run passed. Do not silently refresh expected results from the
   changed implementation.
3. Report the tested snapshot, failures, skips, and missing host or behavior evidence.
4. Leave unsupported claims unverified until their owning lane runs.
5. Reject an unrelated green gate as evidence for a missing behavior lane.
6. Recheck the exact published head before calling a PR ready.
