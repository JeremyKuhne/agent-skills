# Review PowerShell static analysis

Read this when a PowerShell change adds or suppresses an analyzer diagnostic,
changes a static gate, or claims compatibility from a source check. Assign
each question to a parser, analyzer, typed policy, or runtime test that can
actually decide it.

## Choose the owner of each check

| Question | Owning evidence |
| --- | --- |
| Is PowerShell source syntactically valid? | The PowerShell parser and its parse errors |
| Does a script or advanced function use required parameter metadata? | PowerShell AST or command metadata, scoped to the accepted form |
| Does source violate a supported analyzer rule? | An exact, reviewed PSScriptAnalyzer rule and version |
| Does an external language or workflow satisfy its semantics? | That format's maintained parser or typed policy, not a PowerShell regex |
| Does an API work on the minimum supported host? | Execution on that host; a parse-only check is not runtime evidence |

Use a curated correctness profile to detect specified risks such as undefined
variables, unsafe property access, positional binding, native exit handling,
unrestored environment changes, or unsupported host constructs when an
available rule or bounded AST check can establish them. Record the exact
tool/version and local paths in the consuming repository's overlay. Do not
grow syntax blacklists to model arbitrary command reachability or security.

## Separate correctness from historical diagnostics

- Define the accepted correctness profile and keep it globally clean. Add a
  new rule only with a clear owner, accepted and rejected forms, and a
  negative control that makes the gate fail.
- Keep default diagnostics outside the curated profile visible. Preserve a
  baseline for existing occurrences and reject new ones on changed lines;
  do not silently expand that baseline or require an unrelated style sweep.
- Run the focused check for the changed component before the broader gate.
  Report parser failures, curated findings, new default findings, and legacy
  diagnostics separately. A green analyzer run is not proof of host behavior.

## Govern suppressions

Identify the exact rule and site, state the concrete reason, and keep the
suppression as narrow as the supported contract allows. Before accepting it,
remove or mutate the protected check and verify that the corresponding
behavioral or static test fails. Reject a blanket suppression that conceals
a seeded correctness defect. Record any still-visible diagnostics and the
independent test evidence rather than describing suppressed code as clean.
