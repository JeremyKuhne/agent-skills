# PowerShell engineering plan

- Status: implementation in progress; P1 complete
- Assessment date: 2026-09-13 local time; package and review evidence extends
  through 2026-09-14 UTC
- Planning baseline: `main` at `9c0f860567385374a3dd454ccb2a18398a6324c4`
- Scope: PowerShell runtime and API contracts, Pester, static analysis,
  coverage, process isolation, generated scripts, typed infrastructure, and
  reusable agent guidance
- Related work: [Sol and Luna evaluation plan](dual-model-evaluation-plan.md)
  and [PR review effectiveness plan](pr-review-effectiveness-plan.md)
- Release boundary: one documented breaking pre-1.0 minor release, delivered
  through multiple focused pull requests

## Milestones and current status

This plan starts after the deterministic-client work merged through PR #87. The
assessment and architectural decisions are complete. Implementation and pull
request publication are approved; release and model evaluation remain separate
approval boundaries.

The implementation agent owns local work and evidence. The repository
maintainer accepts milestone exits and authorizes commits, pushes, pull request
writes, releases, and model runs. Use `Not started`, `Ready`, `In progress`,
`Awaiting decision`, `Blocked`, and `Done`. Status last reviewed: 2026-09-13.

| ID | Milestone | State | Depends on | Exit evidence and decision |
| --- | --- | --- | --- | --- |
| P0 | Baseline and engineering decisions | Done | None | Current script, test, analyzer, Pester 6, and coverage evidence recorded; runtime, API, coverage, C#, skill, and release decisions accepted. |
| P1 | Central toolchain and Pester 6 cutover | Done | P0 | One manifest owns PowerShell 7.4, Pester 6.2.0, and PSScriptAnalyzer 1.25.0; the Pester 6 parity canary passes; every active test, workflow, template, and instruction uses 6.2.0; 5.7.1 remains only in historical evidence. |
| P2 | Canonical isolated test execution | Ready | P1 | Every CI Pester invocation goes through the hardened process-per-file runner; Linux runs the full minimum-host suite, Windows runs focused platform suites, and a scheduled latest-runtime full suite is defined. |
| P3 | Portable PowerShell engineering skill | Ready | P1 | A portable `powershell-engineering` core and repository overlay cover contracts, Pester 6, process behavior, structured data, platforms, coverage, and review; seeded scenarios catch the known defect classes. |
| P4 | Breaking runtime and named-only API migration | Not started | P1, P3 | All operational and shipped scripts require PowerShell 7.4; explicit compatibility fixtures are the only exceptions; every parameterized script and advanced function disables positional binding; AST contracts and migration notes pass. |
| P5 | Static-analysis gate | Not started | P1, P4 | A curated correctness profile is globally clean; other PSScriptAnalyzer diagnostics cannot be added on changed lines; suppressions are narrow, justified, and tested where behavioral risk remains. |
| P6 | Typed test host and coverage gate | Not started | P2 | A C# 14 test host owns process supervision, schema parsing, coverage merge, and git-diff mapping; per-shard reports merge deterministically; component command floors, patch-line coverage, total-regression checks, and reviewed exceptions block applicable pull requests. |
| P7 | Evaluation infrastructure extraction | Not started | P6 | Shared process, timeout, hash, result-schema, and aggregation logic moves from `SkillEval.psm1` into the typed core without changing the PowerShell entry-point contracts; focused and full parity suites pass. |
| P8 | Breaking release and effectiveness decision | Not started | P3-P7 | Migration guidance and release notes are complete; all seeded defects fail before their fixes and pass after; two consecutive substantive PowerShell pull requests have zero valid post-publication reviewer findings; the maintainer records release and follow-up decisions. |

P3 may proceed while P2 is being completed once P1 fixes the runtime and Pester
contracts. P5 and P6 may be developed in parallel after their dependencies are
stable. Do not combine all milestones into one migration pull request.

### P1 implementation evidence

The structured [toolchain manifest](../tools/powershell-toolchain.json) now owns
PowerShell 7.4, Pester 6.2.0, PSScriptAnalyzer 1.25.0, .NET SDK 10.0.x, C# 14,
and the primary, Windows, and scheduled host lanes. The
[toolchain validator](../tools/Test-PowerShellToolchain.ps1) checks the manifest,
every Pester test requirement, active workflow and template copies, runner and
documentation examples, and the three skill compatibility declarations.

The isolated Pester 6.2.0 canary ran all 16 test files through the process-per-file
runner on PowerShell 7.6.6. It completed in 82.839 seconds with 613 tests: 600
passed, 13 were intentionally skipped, and none failed, were not run, were
inconclusive, or reported block, container, or infrastructure failures. The 148
toolchain contract tests and the empty `-ForEach` compatibility control explain
the increase from the 464-test assessment baseline. An independent search found
no active Pester 5.7.1 or minimum-version Pester 5 test requirement; historical
baseline documents retain their observed versions.

## Executive decision

Raise PowerShell engineering to the same standard used for typed production
code. The solution is not just more Pester tests or a higher coverage number. It
combines a supported runtime, one test entry point, strict public and structured
contracts, adversarial fixtures, static analysis, measurable coverage, process
isolation, and typed infrastructure for the parts PowerShell makes hardest to
reason about.

Adopt these decisions:

| Area | Decision |
| --- | --- |
| Runtime | Require PowerShell 7.4 or later for every operational and shipped script and generated template. Permit a different version only in an explicitly labeled compatibility-test fixture. |
| Pester | Pin stable Pester 6.2.0 everywhere. Run one formal parity canary, then remove 5.7.1 in the same milestone rather than maintaining a long dual-run period. |
| Isolation | Keep the hardened process-per-file runner initially. Do not replace its process-tree timeout and isolation with Pester 6 experimental parallelism until a measured parity experiment justifies it. |
| CI hosts | Run the full suite on the pinned minimum PowerShell 7.4 Linux host. Keep focused Windows lanes for ACL, filesystem, WinUI, plugin, and other Windows behavior. Run a full current-stable PowerShell suite on a schedule. |
| Parameters | Make every parameterized script and every advanced function named-only with `PositionalBinding = $false`. This is part of the breaking release, not a silent compatibility change. |
| Static analysis | Pin PSScriptAnalyzer 1.25.0. Block a curated correctness profile globally and block new default diagnostics on changed lines. Do not require an immediate cleanup of all historical style warnings. |
| Coverage | Collect coverage for every pull request that changes executable PowerShell. Merge per-shard coverage in typed code. Require 80% command coverage per in-process core component, 90% executable-line coverage on changed code, no unexplained total regression, and complete enumerated critical-state coverage. |
| Exceptions | Thin wrappers, generated templates, and platform-only code may be exempt from the percentage gate only through a reviewed manifest entry mapping them to behavioral or platform tests. They remain visible in reports. |
| Typed boundary | Keep PowerShell as the orchestration shell. Move process supervision, timeout handling, hash and identity verification, versioned report DTOs, result aggregation, and coverage-diff logic into a C# 14 core when touched substantially. |
| First extraction | Migrate the Pester shard runner to the shared C# process/report core first, then migrate evaluation scheduling and evidence aggregation incrementally. |
| Skill | Publish one portable `powershell-engineering` skill with focused sibling pages and a repository overlay. Land it immediately after the toolchain cutover so later milestones use it. |
| Delivery | Deliver focused pull requests under one breaking pre-1.0 minor release. |
| Outcome | Require deterministic seeded-defect coverage and two consecutive substantive PowerShell pull requests with zero valid post-publication reviewer findings. |

## Why the current suite missed real defects

The repository has substantial tests, but they do not yet define the full
behavioral contract. PR #87 repeatedly exposed dimensions that ordinary happy
paths and source assertions omitted:

- inserting a parameter changed positional binding;
- a string `"false"` became Boolean true through PowerShell coercion;
- a version-shaped prefix accepted a malformed fourth component;
- unverified source evidence became verified during rescoring;
- a binary hash covered startup but not the complete operation;
- a generated script and its repository counterpart drifted;
- a script declared an older host than the APIs it called;
- copied validation evidence became stale after the tested tree changed.

These are not primarily line-coverage failures. They are missing contract
classes. Several flawed lines were already executed by positive tests. A useful
PowerShell test strategy must therefore combine coverage with adversarial value
classes, state tables, compatibility snapshots, and mutation controls.

## Verified baseline

### Repository inventory

The planning-baseline tree contained:

- 63 `.ps1` files, one `.psm1` file, and 11 PowerShell script templates;
- 16 `*.Tests.ps1` files;
- 31 PowerShell files under shared skill trees, one under `.agents/`, eight
  under `evals/`, 21 under `tests/`, and three under `tools/`;
- 39 scripts declaring PowerShell 7.0, 22 declaring 7.2, and three declaring no
  minimum;
- 21 shipped skill scripts, of which 18 declare 7.0 and three declare 7.2;
- 13 Pester files declaring only `ModuleVersion = '5.0.0'` and three with no
  Pester module requirement;
- 33 parameterized scripts and 53 advanced functions; 39 of those functions do
  not carry an explicit `CmdletBinding` attribute.

Three CI paths invoke Pester directly rather than using the hardened shard
runner. Pester 5.7.1 is copied across workflows, the runner, tests, and examples.
No PSScriptAnalyzer or Pester code-coverage gate is configured.

### Pester 6.2.0 canary

Pester 6.2.0 is the stable PowerShell Gallery release published on 2026-09-09.
Its supported PowerShell Core floor is 7.4. A disposable clean-process canary
used the existing shard runner and produced exactly the Pester 5.7.1 result:

- 16 shards;
- 464 tests;
- 451 passed;
- 13 intentionally skipped;
- zero failed, unexecuted, or infrastructure-failed work;
- 83.381 seconds;
- schema-version-2 runner output remained compatible.

This makes the framework cutover low risk for the current suite. The migration
still needs explicit checks for Pester 6 per-file discovery/run behavior, empty
`-ForEach` data, mock fallback changes, removed legacy assertions, hidden test
files, and configuration validation. Do not rewrite existing `Should -Be`
assertions merely to adopt the new `Should-*` syntax.

### Coverage baseline

The authoritative disposable Pester 6.2.0 baseline used an explicit manifest of
36 executable source files and included the evaluation harness:

- all 464 tests passed with the same 451/13 split;
- run time was 169.885 seconds;
- Pester command coverage was 33.83%;
- Cobertura executable-line coverage was 1,940 of 5,510 lines, or 35.21%;
- `SkillEval.psm1` measured 84.0%;
- `SkillEvalScorer.ps1` measured 96.2%;
- many entry points and scripts exercised in child PowerShell processes measured
  0% in the parent collector.

An earlier 30-file run omitted the root evaluation files and is not a valid
production baseline. Do not cite its 24.15% command or 26.0% line figures as the
repository baseline.

The corrected baseline demonstrates why a raw global floor is inappropriate.
Coverage must be collected in the canonical isolated shards, merged across
processes, and interpreted by component. An exception removes a file from the
percentage gate only after proving its behavior elsewhere; it does not remove
that file from the inventory or report.

### Static-analysis baseline

A disposable PSScriptAnalyzer 1.25.0 scan examined the 64 tracked `.ps1` and
`.psm1` files and reported:

- 307 diagnostics;
- 192 warnings;
- 115 information diagnostics;
- zero errors;
- 96 `PSAvoidUsingPositionalParameters` findings;
- 86 `PSAvoidUsingWriteHost` findings;
- 38 `PSUseSingularNouns` findings;
- 28 `PSUseShouldProcessForStateChangingFunctions` findings.

Turning every default warning into an immediate blocker would create a noisy
cleanup project and encourage broad suppressions. The initial gate instead owns
correctness rules explicitly and prevents new default diagnostics on changed
lines while the historical set is reduced deliberately.

## Target engineering contract

### Runtime and toolchain

Create one structured repository manifest, provisionally
`tools/powershell-toolchain.json`, containing at least:

- minimum PowerShell version: 7.4;
- Pester version: 6.2.0;
- PSScriptAnalyzer version: 1.25.0;
- supported primary and scheduled host lanes;
- C# language version: 14.0 and the repository .NET SDK requirement.

Scripts and CI read the manifest where practical. A validator checks unavoidable
literal copies such as `#Requires`, generated workflow text, and bootstrap
commands. Any compatibility fixture using another version must declare its
purpose and be excluded by an exact path, not a wildcard directory.

### Public API compatibility

For every parameterized script and every advanced function:

- use `[CmdletBinding(PositionalBinding = $false)]`;
- invoke it with named parameters in source and documentation;
- validate mandatory paths, enums, numeric bounds, and mutually exclusive
  states at the boundary;
- snapshot parameter names, types, mandatory status, defaults, and output/exit
  schemas through AST or command metadata tests;
- treat a removed or renamed parameter, changed default, output-schema change,
  or exit-code change as an explicit compatibility decision.

Do not convert every simple private helper into an advanced function merely to
satisfy this rule. Once a function is advanced, however, named-only binding is
mandatory.

### Structured and external data

Data crossing a process, JSON, YAML, environment, filesystem, or CLI boundary is
untrusted until validated:

- require exact primitive types instead of PowerShell truthiness or coercion;
- distinguish missing, null, false, zero, empty, malformed, and unsupported;
- use structured parsers such as `SemanticVersion` instead of prefix regexes;
- validate the complete token, not only a matching prefix;
- version report schemas and reject unknown incompatible shapes;
- never make derived evidence stronger than its source;
- use one shared synthetic value corpus against core, wrapper, and rendered
  generated implementations.

Known PR #87 seeds include malformed fourth-component versions, trailing junk,
string and numeric Boolean substitutes, missing versus explicit-false evidence,
old-but-valid versions, and hash mutation during an operation.

### Test layers

Every substantive PowerShell component selects the applicable layers and records
why an omitted layer is unnecessary:

1. **Parser and static contract:** every file parses; runtime and toolchain
   requirements, parameter metadata, exports, generated ownership, and schema
   declarations match policy.
2. **Pure unit tests:** table-driven boundary and equivalence classes for logic
   separated from process, filesystem, environment, and network adapters.
3. **State-table tests:** enumerate every valid state and the complement for
   report protocols, trust flags, retries, timeouts, and workflow transitions.
4. **Fresh-process tests:** assert command line, stdout, stderr, information and
   warning streams, exit code, timeout, process-tree cleanup, environment
   restoration, and behavior from paths containing spaces.
5. **Platform tests:** run filesystem modes, ACLs, native loading, symlinks, and
   path semantics on the operating systems that own those contracts.
6. **Generated-artifact tests:** render templates, parse the result, and execute
   focused behavior from the generated copy rather than asserting source text
   alone.
7. **Fault and mutation controls:** prove the test fails when a critical check is
   removed, a type is coerced, a parser is weakened, a report goes stale, or a
   worker exits in each invalid state.
8. **Integration tests:** exercise real external tools only through explicit,
   pinned, isolated entry points and preserve identity evidence.

Tests are evidence only when their expected values come from the contract or an
independent oracle. An assertion copied from the current implementation is not
an independent check.

### Canonical test execution

Retain process-per-file execution while Pester 6 parallel execution is
experimental. The canonical runner must provide:

- one fresh PowerShell process per test file;
- hard process-tree timeouts;
- explicit PowerShell and Pester paths/versions;
- complete worker/result state validation;
- honest aggregate counts and infrastructure errors;
- deterministic result, log, test-result, and coverage artifacts;
- component-to-test selection for focused validation;
- a clean environment contract and explicit opt-ins for external tools.

Every CI path that executes Pester goes through this runner. Focused platform
jobs pass an explicit test subset rather than opening a separate in-process
execution model.

### Static analysis

Define a pinned PSScriptAnalyzer settings file and a typed changed-line gate.
The initial correctness profile should cover, directly or through custom AST
checks:

- parse errors and runtime compatibility;
- use of undefined variables and unsafe null/property access;
- positional binding on scripts and advanced functions;
- native-command exit handling;
- state-changing commands without the required confirmation semantics;
- environment mutation without restoration;
- known aliases or constructs that behave differently across hosts;
- unstructured parsing where a supported structured parser owns the format.

Default diagnostics outside the curated profile remain visible. They fail only
when introduced on changed lines until their existing occurrences are reviewed
and removed. Suppressions require a concrete reason and cannot hide a seeded
correctness defect.

### Coverage

Store the explicit executable-source inventory and reviewed exceptions in a
structured manifest, provisionally `tests/powershell-coverage.json`. Each entry
names its component, source path, owning tests, execution mode, platform, and
exception rationale when applicable.

Collect Pester 6 coverage inside every canonical shard that owns an in-process
source component. Merge Cobertura files and Pester command data in the C# test
host. A PowerShell-changing pull request runs the applicable coverage shards;
it does not instrument all 36 files in every child.

After one report-only baseline pull request, enforce:

- at least 80% command coverage for each in-process core component;
- at least 90% executable-line coverage on changed PowerShell lines;
- no unexplained regression in the owning component's total coverage;
- 100% enumerated coverage for critical state tables, independent of percentage;
- a reviewed behavioral or platform-test mapping for every percentage
  exception.

Publish the merged report as an artifact. Keep coverage service-independent; the
repository-owned C# gate parses coverage and git diffs. Establish hosted p50 and
p90 duration after five runs rather than turning the local 169.885-second
measurement into an unsupported CI service-level target.

### Typed C# 14 core

Build a small repository-owned C# 14 test infrastructure component. It owns the
contracts PowerShell has repeatedly made fragile:

- process start, asynchronous stream capture, cancellation, timeout, and process
  tree termination;
- environment construction and restoration;
- executable identity and hash checks;
- versioned JSON DTOs and validation;
- worker/result state machines and aggregate accounting;
- deterministic Cobertura merge and changed-line mapping;
- machine-readable receipts.

Migrate the shard runner first while preserving its PowerShell command line and
schema. Keep a thin PowerShell wrapper for contributor ergonomics. After parity
and coverage gates pass, migrate shared evaluation process/report logic in small
slices. Do not rewrite domain scoring or every skill script into C#.

### Portable PowerShell engineering skill

Create a portable `powershell-engineering` core after P1 so later implementation
uses the accepted runtime and Pester contracts. Keep its `SKILL.md` concise and
route deep detail to bundled pages for:

- API and compatibility design;
- structured data and PowerShell type semantics;
- Pester 6 test design and negative controls;
- native processes, streams, environment, and filesystem behavior;
- cross-platform and minimum-host validation;
- coverage, static analysis, generated scripts, and review.

The repository overlay supplies exact paths, toolchain versions, commands,
coverage thresholds, platform lanes, generated-file ownership, and publication
rules. Use the upstream `pester-migration` skill for mechanical v5-to-v6 changes;
do not duplicate it.

Evaluate the skill with synthetic forms of the defects observed in PR #87. The
agent must identify the contract class, add a failing control before the fix,
choose a structured parser or exact type check, preserve compatibility or name a
break, and run the correct focused and full gates.

## Focused delivery sequence

Use separate pull requests for these changes while holding the breaking release
until all required compatibility migrations are complete:

1. P1 completed: added the toolchain manifest and validation, proved Pester 6.2.0
  parity, removed 5.7.1 from active surfaces, and updated generated workflows
  and guidance.
2. Route every CI Pester invocation through the isolated runner; establish the
   PowerShell 7.4 Linux full lane, focused Windows lanes, and scheduled current
   stable lane.
3. Add the portable skill, repository overlay, and seeded deterministic
   scenarios.
4. Raise all operational and shipped scripts/templates to PowerShell 7.4 and
   migrate parameterized scripts and advanced functions to named-only binding,
   with AST compatibility tests and migration documentation.
5. Add the PSScriptAnalyzer correctness profile and changed-line no-new gate.
6. Add the C# 14 process/report core, migrate the shard runner, collect and merge
   per-shard coverage, and enable report-only coverage artifacts.
7. Enable the component, patch, total-regression, state-table, and exception
   gates after the baseline is reviewed.
8. Move evaluation process/report infrastructure into the typed core in focused
   parity-backed slices.
9. Publish the breaking pre-1.0 minor release only after P8 acceptance.

Every pull request updates this plan with current evidence rather than copied
transient check state. No pull request combines a portable skill semantic change
with unrelated runtime cleanup or a broad C# rewrite.

## Acceptance and measurement

A milestone is complete only when its executable exit evidence is recorded and
the maintainer accepts the associated policy or compatibility decision. Green
coverage and lint are necessary, not sufficient.

Track from the first implementation pull request:

- local and hosted wall time, queue time, and retries;
- Pester discovery, pass, skip, not-run, failed block/container, and
  infrastructure counts;
- command and executable-line coverage by component and patch;
- analyzer findings by rule, severity, existing versus changed line, and
  suppression;
- fault and mutation controls executed;
- platform lanes exercised and skipped behavior;
- review findings by contract class, whether valid, and whether a seeded test or
  skill rule should have caught them;
- human repair time and number of commit/review rounds.

The engineering program succeeds when:

1. every seeded defect class fails under its negative control and passes after
   repair;
2. every applicable runtime, analyzer, coverage, contract, platform, generated,
   and integration gate is green;
3. no executable PowerShell path bypasses the canonical toolchain and runner;
4. exceptions remain explicit, current, and behaviorally covered;
5. two consecutive substantive PowerShell pull requests receive zero valid
   post-publication reviewer findings.

A higher coverage percentage that does not reduce valid escaped defects is not a
success. If reviewer findings continue, classify them, add the missing contract
class, and rework the skill or gates before raising thresholds mechanically.

## Boundaries

The repository maintainer authorized implementation, commits, pushes, pull
request creation and updates, Copilot code-review requests, feedback iteration,
and squash merges on 2026-09-13. This authorization does not include a release,
remote policy change, dependency installation in contributor environments, or
model run. Toolchain provisioning must be isolated and pinned. Real model
evaluations of the new skill require separate approval for model, scenarios,
repetitions, budget, and concurrency.

Do not fold this work into the dual-model experiment or the pull-request process
plan. Those plans may consume the stronger test infrastructure, but this plan
owns PowerShell runtime, API, test, analyzer, coverage, and typed-infrastructure
quality.
