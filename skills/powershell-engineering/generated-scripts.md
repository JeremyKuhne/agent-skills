# Review generated PowerShell

Read this when a generator, template, checked-in copy, or packaged PowerShell
script changes. Treat generated files as outputs, not independent sources of
truth.

## Establish ownership

- Identify the generator, its authoritative inputs, every owned output, and the
  documented regeneration command. Get repository paths, tool versions, and
  publication bindings from the consuming repository's overlay. If ownership
  is unclear, stop before editing an output or guessing a regeneration command.
- Change the generator or its inputs, then regenerate all affected outputs. Do
  not hand-edit a generated copy to fix a defect or silently overwrite unrelated
  local changes. If an output is deliberately maintained by hand, remove it
  from the generated set and document the ownership change.
- Apply the public API and minimum-host contracts to the generated script that
  users run, not only to its template or generator.

## Prove agreement and behavior

1. Generate from the intended inputs in an isolated workspace or output
   directory, leaving checked-in outputs untouched. Compare each checked-in
   and distributable counterpart with the fresh output. Fail on a stale,
   missing, or extra owned artifact; an in-place overwrite is not a passing
   drift check.
2. Make a reversible stale-copy or missing-output change and verify that the
   comparison gate fails. Restore the artifact and rerun the gate. If generation
   includes volatile data, define and test the narrow normalization separately;
   do not ignore arbitrary differences.
3. Exercise the generated entry point through its owning behavior tests. Use
   independent expected results for binding, output, errors, and supported
   hosts as applicable. Matching generated text does not prove that it runs
   correctly or that the declared minimum host can execute it.

Report the inputs and outputs checked, the failed drift control, the behavior
lane that ran, and any host or packaged artifact not exercised.
