---
name: powershell-engineering
description: Design, implement, test, or review PowerShell scripts and modules, including deciding whether PowerShell is the right implementation boundary. Use for PowerShell APIs, process and stream behavior, structured-data tooling choices, Pester contracts, cross-platform behavior, or generated PowerShell. Do not use for application performance or mechanical Pester 5-to-6 migration; route those to dedicated guidance.
license: MIT
compatibility: Guidance targets PowerShell 7.4 or later and Pester 6.2 or later. Structured formats require a maintained parser, schema tool, compiler, or managed API.
metadata:
  portability: portable
  applicability: universal
  binding: optional-overlay
  risk: local-write
  maturity: experimental
  requires: none
  related: performance-testing, security-review, pre-pr-self-review
---

# PowerShell engineering

If `overlay.md` exists beside this file, read it before acting; it contains
repository-specific bindings. This core remains usable without it.

Treat PowerShell as an implementation choice, not a repository default. Start by
identifying the behavior's natural owner and independent oracle. Keep PowerShell for
PowerShell-native contracts; use a maintained parser, compiler, schema tool,
validator, external CLI, or managed API when that system owns the hard part.

## Route the work

| Subject | Primary boundary |
| --- | --- |
| Parameter binding, pipelines, streams, modules, providers, remoting, or shell entry points | PowerShell with focused Pester or process tests |
| YAML, JSON, XML, Markdown, compiler syntax, or another structured language | Maintained parser or schema API; PowerShell may orchestrate it |
| Managed APIs, typed state machines, or reusable process supervision | Managed implementation and managed tests |
| External tool behavior | Direct integration lane using the real tool |
| Application performance | Use the performance-testing workflow |
| Mechanical Pester 5-to-6 migration | Use a dedicated pester-migration workflow when available |

When the owner is unclear, read [implementation-boundary.md](implementation-boundary.md)
before editing.

## Workflow

1. **Read local bindings.** Gather supported hosts, exact commands, generated-file
   ownership, compatibility promises, and publication rules from the overlay or
   repository. Keep those facts out of the portable core.
2. **Name the contract.** State the subject, implementation owner, independent oracle,
   accepted forms, rejected forms, and explicitly deferred forms. Do not derive expected
   behavior solely from the current implementation or a reviewer example.
3. **Choose the implementation boundary.** Compare PowerShell with one credible native
   owner. If a maintained parser or typed API owns the semantics, call it rather than
   reproducing its grammar in PowerShell.
4. **Choose the test lane.** Use Pester for PowerShell behavior, managed tests for managed
   assets and typed policy, and direct integration for compilers, CLIs, operating systems,
   or generated artifacts. A harness is not the oracle.
5. **Add the cheapest failing control.** Construct a negative case from the contract
   before repairing the behavior. Include a false-positive control when discovery or
   routing could capture unrelated content.
6. **Implement the smallest owned change.** Prefer PowerShell 7.4 language and platform
   APIs. Preserve the declared compatibility floor or name the break explicitly. Do not
   grow syntax blacklists to approximate another language or a security boundary.
7. **Validate immediately.** Run the narrow failing control after the first edit, then
   the component gate. Run broader repository checks only after the focused contract is
   green. Keep real host or process behavior in its owning integration lane.
8. **Review and stop.** Check error records, streams, exit behavior, cleanup, environment
   restoration, platform assumptions, generated output, and evidence claims that apply to
   the changed boundary. Report completed checks and remaining unknowns separately.

## Non-negotiable rules

- Use structured APIs for structured data. Regex and line scanning may enforce only a
  deliberately narrow literal-text contract.
- Do not claim arbitrary command reachability, sandboxing, or hostile-script resistance
  unless a separately accepted security design owns that claim.
- Test PowerShell-native behavior through public entry points or fresh processes when
  module state, environment, streams, or exit codes matter.
- Keep compatibility floors distinct from exact repository execution locks.
- Treat a new grammar class, ownership conflict, or repeated review expansion as a
  premise question, not an invitation to add another patch layer.

## Completion

Report the chosen boundary and why, the contract and oracle, the focused and broader
checks that actually ran, supported hosts exercised, compatibility impact, and deferred
forms. Do not describe a parser substitute, green harness, or successful command as proof
of behavior it did not observe.
