# PowerShell engineering plan

- Status: P1 and P2 done; P3a repository overlay is in progress
- Assessment date: 2026-09-13 local time; architecture review extends through
  2026-09-22 UTC
- Program baseline: `main` at `9c0f860567385374a3dd454ccb2a18398a6324c4`;
  later milestone evidence names its own exact tree
- Scope: test ownership, PowerShell runtime and API contracts, Pester, MSTest,
  static analysis, separate managed and PowerShell coverage, process isolation,
  generated scripts, typed infrastructure, and reusable agent guidance
- Related work: [Sol and Luna evaluation plan](dual-model-evaluation-plan.md)
  and [PR review effectiveness plan](pr-review-effectiveness-plan.md)
- Release boundary: one documented breaking pre-1.0 minor release, delivered
  through multiple focused pull requests

## Milestones and current status

This plan starts after the deterministic-client work merged through PR #87. The
baseline measurements remain valid, but the architectural decision to treat
Pester as the repository-wide test harness is reopened. PR #90 demonstrates
that Pester 6.2.0 can execute the current suite; it does not establish that the
current suite has the right ownership boundaries.

The implementation agent owns local work and evidence. The repository
maintainer accepts milestone exits and separately authorizes commits, pushes,
pull request writes, releases, and model runs. Use `Not started`, `Ready`, `In
progress`, `Paused`, `Awaiting decision`, `Blocked`, and `Done`. Status last
reviewed: 2026-09-25 UTC. `Ready` means the entry conditions are satisfied and the
milestone is next to execute; it does not claim that exit evidence exists.

| ID | Milestone | State | Depends on | Exit evidence and decision |
| --- | --- | --- | --- | --- |
| P0 | Baseline evidence | Done | None | Current script, test, analyzer, Pester 6, and coverage evidence is recorded. Test-harness ownership decisions previously attributed to P0 are superseded by P0r. |
| P0r | Test-ownership and premise reset | Done | P0 | PR #92 records the accepted [test-ownership inventory](powershell-test-ownership-inventory.md) and bounded `TrustedFileWrites` canary. PR #90 is retained as compatibility evidence and closed unmerged. |
| P1a | Mechanical PowerShell and Pester cutover | Done | P0r, P1c | PR #94 applied the PowerShell 7.4 and Pester 6.2 compatibility floor to retained Pester tests and templates, locked repository execution to 6.2.0, passed local parity and exact-head CI, addressed the substantive review finding, and merged as `0b439bb6b1712220642a8945e1195eb89000d6f8`. |
| P1c | Managed test-ownership canary | Done | P0r | PR #93 moved the approved six-test `TrustedFileWrites` slice to MSTest, preserved deferred Pester facts, separated behavior portability from single-host coverage, and passed the accepted Windows/Linux evidence. |
| P1b | Parser-backed toolchain policy | Done | P0r, P1c | PRs #98 through #101 merged the bounded metadata, active-workflow, generated-output, and managed file-creation policies; PR #101 merged as `c9d7e15`. |
| P2 | Canonical isolated PowerShell execution | Done | P1a, P1c | PR #95 routed active repository and generated-consumer Pester invocations through the existing process-isolated runner, preserved independent managed test lanes, passed local parity and exact-head CI, received a clean exact-head review, and merged as `7e68d294300fbb9ddc649e90cbea4eefda35d621`. |
| P3a | Portable PowerShell engineering skill | In progress | P0r, P1a, P1b | PRs #102 through #112 merged portable boundary, API, structured-data, Pester, native, platform, coverage, static-analysis, generated-script, and review guidance; PR #112 merged as `4cb6038`. This slice installs that 11-file core at `4cb6038943c3f66164717d011b8b7b7ac5e6d3c2` with a repository overlay for toolchain, test, platform, generated-file, coverage, and publication bindings. A deterministic repository contract guards the pin, core content, overlay bindings, and links; project discovery and source-to-pin blob checks pass. The initial three-trial evaluation scored 9/63; later single-model calibration reached 63/63 combined. That calibration is superseded by review findings and is not Sol/Luna acceptance evidence. The paired preflight passed both models; the subsequent 126-attempt diagnostic is recorded below. PR #114 remains draft pending exact-head checks and a decision on the observed misses, not an accepted qualification. |
| P4 | Breaking runtime and named-only API migration | Not started | P1a, P3a | All operational and shipped PowerShell scripts require PowerShell 7.4; explicit compatibility fixtures are the only exceptions; every parameterized script and advanced function disables positional binding; AST contracts and migration notes pass. |
| P5 | Static-analysis gate | Not started | P1a, P4 | A curated correctness profile is globally clean; other PSScriptAnalyzer diagnostics cannot be added on changed lines; suppressions are narrow, justified, and tested where behavioral risk remains. |
| P6 | Typed test infrastructure and dual coverage gates | Not started | P1c, P2 | Managed repository contracts and process supervision live in C#; MSTest and Pester coverage are collected and gated separately; no aggregate percentage lets one domain hide another; reviewed exceptions map to behavioral evidence. |
| P7 | Evaluation infrastructure extraction | Not started | P6 | Shared process, timeout, hash, result-schema, and aggregation logic moves from `SkillEval.psm1` into the typed core without changing the PowerShell entry-point contracts; focused and full parity suites pass. |
| P8 | Breaking release and effectiveness decision | Not started | P1b, P3a, P4-P7 | Migration guidance and release notes are complete; all seeded defects fail before their fixes and pass after; two consecutive substantive PowerShell pull requests have zero valid post-publication reviewer findings; the maintainer records release and follow-up decisions. |

The P3a Sol/Luna preflight on 2026-09-25 used the same implicit process-boundary
scenario once per model at medium effort, with isolated Copilot CLI 1.0.83
(`D3F3BB7B8BBF68357AD29F514A179D09F76135483D8BFB643131B8600F671EE2`).
The first Sol startup lacked authentication and made zero requests. An
authenticated Sol run passed directly; Luna invoked the intended skill but
initially missed an overly narrow oracle wording check. An independent
child-process receipt was accepted after a positive control reproduced the
miss and a mocked-receipt control remained negative. Hash-verified rescoring
passed both saved attempts (1/1 per model; zero safety or infrastructure
failures). Per-call telemetry verified three requests on each requested and
served model, medium effort, and token totals matching the final usage files.
The prompts, candidate, scenario, fixtures, scorer, and client hash matched.
Raw transcripts and usage remain local under the OS temporary directory. This
single paired scenario is a preflight, not full P3a or portfolio qualification.

### P3a paired diagnostic

At `b3f8cec` on 2026-09-25, the approved read-only campaign ran all 21
PowerShell engineering scenarios three times on each of `gpt-5.6-sol` and
`gpt-5.6-luna` at medium effort: 126 distinct original attempts, with no lost,
timed-out, safety-failed, or infrastructure-failed attempts. The candidate hash
was `5713463BA1C9E0561A38C2A563CDB68DCE21E190AEC9DE554DE53BEFC53EEC9F`;
the scorer hash was `C3CC9B85D0592B44E302AA5CE25491FA75FB535E93ABA0C16DCAB40673C2DCCE`.
The scenario document was frozen at
`EEADAB61502136A60CA379F473E109F04C64F33FEF3055A7CBD97F5517C314FD`
for repetitions two and three. First-repetition response predicates were
calibrated during development; 38 original outputs were hash-verified and
rescored without new inference, while four unchanged cases retained their
original scores. No frozen response was used to change this cohort's rubric.

| Cohort | Sol rubric passes | Luna rubric passes |
| --- | ---: | ---: |
| Development-calibrated repetition one (21 attempts per model) | 20 | 20 |
| Frozen repetition two (21 attempts per model) | 11 | 16 |
| Frozen repetition three (21 attempts per model) | 14 | 15 |
| All 63 attempts per model | 45 | 51 |

Routing evidence passed 60/63 Sol and 62/63 Luna attempts: each missed the
PowerShell skill once for the parsed-array scenario, and Sol invoked it twice
for the mechanical Pester-migration near miss. Positive-trigger routing passed
56/57 per model; near-miss routing passed 4/6 for Sol and 6/6 for Luna. Paired
rubric outcomes were 40 both-pass, seven both-fail, 11 Luna-only, and five
Sol-only. In the frozen cohort alone Sol scored 25/42 and Luna 31/42. Several
frozen rubric misses involve Pester receipt and native-child checks; some omit
explicit gates, while others need separate semantic adjudication. A spot check
also found an answer correctly calling an
API refactor "backward-compatible" that failed an exact `preserve` or
`non-breaking` response predicate. These are retained as frozen rubric misses,
not retroactively converted to passes or treated as independently adjudicated
useful outcomes.

All 364 chat spans matched their requested and served model at medium effort;
per-call token sums matched the final usage receipts. The selected native
Copilot CLI 1.0.83 had SHA-256
`D3F3BB7B8BBF68357AD29F514A179D09F76135483D8BFB643131B8600F671EE2`.
At the agreed 6:1 Sol-to-Luna token weight, including failed attempts and all
inference turns, Sol used 18,856.524 and Luna 3,287.404 normalized
Luna-equivalent 1,000-token units; cost per rubric pass was 419.034 and
64.459 units respectively (Luna/Sol ratio 0.154). These are resource
comparisons, not cash charges or proof of model preference: both observed
rubric rates fall below the proposed 90% useful-success threshold, but pattern
checks do not establish the actual useful-success rate. This one-skill
diagnostic has no held-out portfolio or independent usefulness judgment. The
original summaries, derived scores, usage, and raw
transcripts remain private under the OS temporary directory at
`p3a-campaign-b3f8cec`. Before accepting P3a, decide whether to revise skill
discovery, adjudicate the response rubrics, and approve a fresh frozen cohort;
keep PR #114 draft in the meantime.

After this campaign, PR #114's review follow-up added Sol/Luna-specific client
preflight and five negation controls for API preservation and breaks, array
presence, native exit handling, and YAML parser delegation. The corrected
scenario has a new revision; the controls were not applied retroactively to
saved outputs or evaluated in another model run.
The counts above remain tied to the frozen revision, not to a qualification of
the post-review rubric.

PR #90 is closed unmerged; retain its parity receipt as compatibility evidence
without inheriting its universal-Pester premise. Do not start P1b until P0r is
accepted and P1c establishes the managed boundary. P1c proves one ownership
boundary, not permission for wholesale migration. The proposed course-correction
skill is backlog work and does not block P1a, P1c, or release. PR #88, PR #89,
and PR #90 are evidence, not implementation bases; do not cherry-pick their
implementation commits into a replacement. Do not combine the managed canary,
PowerShell cutover, parser policy, or PowerShell skill into one pull request.

### P1 recovery decision

PR #88 and its replacement PR #89 were both closed unmerged. PR #88 reached 32
published commits while an initially small version check grew into partial
parsers for YAML scalar folding and mappings, Markdown code scopes, generated
here-strings, and PowerShell execution contexts. PR #89 was intended to be the
narrow replacement, but it was published before its accepted contract was
closed and reached seven commits while review continued to discover dynamic
command, wildcard target, shell-default, bootstrap, compatibility, and workflow
dependency requirements.

The failure was procedural and architectural, not a lack of test execution.
Both branches repeatedly had green deterministic gates, but their tests were
derived from the current implementation and covered accumulated examples rather
than an independently accepted contract. Local self-review was not independent:
it sometimes inspected the wrong worktree, relied on implementation-shaped
fixtures, and returned `READY` without challenging whether the pull request was
still the promised narrow change. Copilot review became the first adversarial
test designer after publication.

The implementation also collapsed two distinct version contracts. Repository
execution needs an exact Pester 6.2.0 lock for reproducible evidence. Test
requirements and portable skill compatibility need a Pester 6.2 minimum floor
unless a narrower compatibility promise is intentionally approved. Copying the
execution lock into portable compatibility prose was a contract error.

The first recovery plan still preserved a deeper inherited premise: because the
repository already used Pester, every `*.Tests.ps1` file was treated as a
PowerShell test. That confuses the language of the harness with the subject
under test. Direct inspection shows mixed ownership:

- `Update-Scaffold.Tests.ps1` dot-sources PowerShell scripts and tests their
  functions, which is a natural Pester unit-test boundary;
- `AgentFiles.Tests.ps1` combines child-process behavior for PowerShell tools,
  workflow text checks, release-document checks, and plugin-smoke policy;
- `RepositoryContracts.Tests.ps1` combines the Pester runner state machine with
  catalog, metadata, file-layout, and structured-data contracts;
- `WorkflowTemplates.Tests.ps1` infers YAML workflow semantics with regular
  expressions; and
- the repository already uses MSTest SDK 4.2.3 for managed tests.

This evidence does not predetermine that every non-PowerShell assertion moves to
MSTest. It proves that file extension and existing placement are insufficient
ownership rules. No implementation from either failed branch is accepted as
milestone evidence. PR #90's clean parity receipt remains useful evidence about
Pester 6 compatibility, but it is not approval of the universal-harness premise.

### P0r test-ownership reset

The [test-ownership inventory](powershell-test-ownership-inventory.md) records
each independently meaningful contract group before choosing or preserving its
harness. It includes:

| Field | Question |
| --- | --- |
| Subject | What production behavior, artifact, or policy is actually under test? |
| Implementation owner | Which component computes or enforces that behavior? |
| Independent oracle | Where does the expected result come from if not the current implementation? |
| Natural harness | Does the test need PowerShell binding, streams, mocks, or AST behavior; managed APIs and parsers; a dedicated validator; or a real external integration? |
| Coverage domain | Is executable PowerShell, managed code, or no repository code being measured? |
| Existing evidence | Which positive, negative, platform, mutation, or prior-behavior checks already establish the contract, and which are only implementation-shaped? |
| Disposition | Keep, split, migrate, replace with a standard tool, or delete as duplicate policy? |

Apply these defaults, then record exceptions with evidence:

- Pester owns PowerShell script and module behavior, including parameter
  binding, PowerShell streams, errors, mocks, AST-facing contracts, and
  PowerShell-specific platform behavior.
- MSTest owns managed validators, repository policy implemented in C#, typed
  state machines, parser-backed structured-format contracts, and managed
  process supervision.
- A maintained format validator, schema tool, compiler, linter, or package
  validator owns a contract before either custom test harness does when it can
  express the repository's requirement.
- A black-box PowerShell CLI may be launched by MSTest when the contract is a
  cross-process protocol, or by Pester when the contract is specifically about
  PowerShell semantics. The choice must name the distinguishing behavior.
- Mixed files are split by subject. Migration removes the old assertion after
  parity; it does not leave two harnesses enforcing the same contract.
- Prose is not tested by copying sentences into regular expressions unless the
  exact text is itself a versioned interface. Use link, Markdown, schema, and
  artifact validators for their own domains.

Pester and MSTest are harnesses, not oracles. Expected results must come from an
accepted contract table, language or format specification, schema, maintained
parser or validator, deliberately constructed fixture, or verified prior
behavior. When none exists, record the behavior as a decision instead of
laundering the current implementation into an expected value.

Record the inventory by independently meaningful contract group, not merely by
file; mixed files need more than one row. The course-correction skill remains
backlog work and is not a prerequisite for this sequence.

P0r selects the canary before implementation. A good canary has a clear
non-PowerShell owner and either an executable managed implementation or a
structured format that can use its typed API or maintained parser directly.
P1c implements and evaluates that approved canary; it does not select a
different suite. The evaluation compares implementation size, test clarity,
defect classes, diagnostics, runtime, coverage visibility, and maintenance cost
before the plan authorizes a broader migration. The P0r contract records why
the canary is the cheapest discriminating check and why the strongest
alternatives were rejected. This focused contract governs only the chosen test
ownership experiment; it is distinct from P1b's later parser-backed
toolchain-policy contract.

#### P1c local canary evidence

The local canary links the existing `TrustedFileWrites.cs` into a dedicated
MSTest SDK 4.2.3 project. It adds no package beyond the SDK already used by the
repository. Exactly six Pester declarations moved; the invalid-key declaration
expands to 15 data rows, so the managed project discovers 20 cases. All 20 pass
in Release on Windows with zero warnings, failures, or skips. The 38 retained
Pester cases report 29 passed, nine platform skips, and no failure or
infrastructure category on PowerShell 7.6.6 and Pester 5.7.1.

The source-filtered Cobertura report contains only the linked production class.
The approved subset covers 43 of 66 lines, or 65.15%, and reports 82.14% branch
coverage. The uncovered paths remain visible and correspond primarily to the
deferred Unix mode, umask, cleanup-failure, and platform-specific behavior. The
prior Pester lane could execute the asset but could not report managed coverage
for it.

The tradeoff is measurable rather than assumed:

- 105 Pester lines are removed;
- the canary adds 168 test lines, a 15-line project, an 11-line coverage config,
  and a 71-line CI job;
- it adds one test helper and one 15-case data provider, with no new package;
- the prior 58-case Pester shard took 2.036 seconds locally;
- the split takes 2.064 seconds for retained Pester cases plus 0.868 seconds for
  managed tests with coverage when run sequentially; and
- the migrated defect classes are invalid keys, invalid or missing parents,
  device-like key mapping and overwrite refusal, scratch cleanup, successful
  atomic replacement, and failed-replacement staging cleanup.

The local evidence proves parity, direct exception visibility, and managed
coverage visibility. The hosted receipt below supplies the required exact-head
Windows and Linux behavior evidence and single-architecture coverage evidence.

The complete local split also preserves discovery: the Pester runner reports 16
shards and 444 tests, with 431 passed, 13 skipped, and zero failure or
infrastructure categories in 83.148 seconds. Together with the 20 managed cases,
the same 464 behavioral cases remain represented without aggregating their
separate coverage domains.

#### P1c first hosted receipt

At commit `5f2547dd7634c06c7d8087fb170870d3971f50ed`, the exact-head Windows
job passed all 20 tests in 1.472 seconds and reported the same 43 of 66 lines
and 82.14% branch coverage. Ubuntu ARM64 also completed all 20 tests in 2.055
seconds, then Microsoft.Testing.Platform's dynamic coverage collector crashed
with `BadImageFormatException`, `Index not found`, and process exit 134. The
failure occurred after test completion and before report validation.

Microsoft documents dynamic managed instrumentation for Linux x64, not Linux
ARM64. A local static-instrumentation probe kept the tests green but produced an
empty Cobertura report, so it was rejected rather than published. The maintainer
decided that coverage is not required on every architecture. The focused
correction keeps the 20 behavior cases on both required hosts and collects the
source-filtered coverage report only on `windows-latest`; it adds no host,
package, or generalized coverage infrastructure.

The behavior-equivalent evidence head
`4b946a3d34ad15c988fbfe3791f02e7473043091` passed all applicable CI
jobs; the tag-only release check was intentionally skipped. Ubuntu ARM64
[job 104580591527](https://github.com/JeremyKuhne/agent-skills/actions/runs/35028319838/job/104580591527)
passed 20 of 20 behavior cases with no failures or skips in 544 milliseconds.
Windows [job 104580591626](https://github.com/JeremyKuhne/agent-skills/actions/runs/35028319838/job/104580591626)
passed 20 of 20 with no failures or skips in 1.529 seconds and reported 43 of 66
lines, or 65.15%, with 82.14% branch coverage. The maintainer accepted the
ownership boundary with coverage on one supported architecture. P1c completes
when PR #93 merges and its then-current head passes the unchanged CI contract.

#### P1a mechanical cutover

P1a was deliberately mechanical:

- raise Pester test and generated-test PowerShell requirements to 7.4;
- declare Pester 6.2 as the test and portable compatibility floor;
- keep runner and CI installation/import commands locked to Pester 6.2.0;
- update known workflow, template, and guidance copies;
- run the existing process-per-file parity suite;
- add no manifest validator, YAML dependency, Markdown interpretation, command
  tracing, bootstrap-state model, or new policy abstraction.

That contract was locally satisfied and published as PR #90, but its scope is
now provisional because it applied the Pester requirement to every current test
file before P0r classified ownership. The following table records what PR #90
implemented; it is historical evidence, not a current merge instruction:

| Surface | Accepted in P1a | Rejected in P1a | Deferred | Evidence |
| --- | --- | --- | --- | --- |
| Test host | Every repository and generated Pester test declares `#Requires -Version 7.4`. | Missing or lower test-file requirements. | Runtime migration for non-test operational scripts is P4. | PowerShell AST inventory plus full Pester run. |
| Test compatibility | Test files and generated test templates declare `ModuleVersion = '6.2.0'`, meaning Pester 6.2 or later. | `RequiredVersion` in test-file requirements and Pester 5 requirements. | Compatibility with a future Pester major version requires a separate decision. | PowerShell AST inventory and a negative exact-pin fixture. |
| Repository execution | The shard runner defaults to Pester 6.2.0 and each CI bootstrap installs or imports Pester 6.2.0 with `RequiredVersion`. | Floating or stale Pester bootstrap literals. | Mapping every invocation to its bootstrap process is P2. | Existing runner behavior, parity canary, and review of known workflow copies. |
| Workflows and templates | Known Pester install/import literals are changed mechanically to 6.2.0. | Active 5.7.1 copies in the fixed path list. | YAML semantic policy and workflow-to-manifest mapping are P1b. | Exact changed-path review; no new YAML validator. |
| Portable guidance | Portable skills state PowerShell 7.4 and Pester 6.2 or later. Repository-local scaffolding guidance distinguishes its own runtime from generated validation requirements. | Repository-specific exact Pester locks presented as portable compatibility. | A portable PowerShell engineering skill is now P3a. | Focused prose review against test and runner contracts. |

The implementation path whitelist is also fixed:

| Path | Allowed P1a change |
| --- | --- |
| `tests/Invoke-PesterShards.ps1` | Raise its PowerShell floor and change only the default Pester version. |
| `tests/**/*.Tests.ps1` | Raise test PowerShell requirements and change Pester requirements to the 6.2 minimum. |
| `.agents/skills/create-skill-repo/scripts/template/**/tests/*.Tests.ps1.tmpl` | Apply the same generated-test requirement changes. |
| `.github/workflows/ci.yml` and `.github/workflows/full-ci.yml` | Change existing Pester installation and import versions only. |
| `.agents/skills/create-skill-repo/scripts/template/**/.github/workflows/*.yml.tmpl` | Change existing generated Pester installation and invocation versions only. |
| `.agents/skills/create-skill-repo/SKILL.md`, `evals/README.md`, `skills/dotnet-file-creation/SKILL.md`, and `skills/windows-acls/SKILL.md` | Align runtime and compatibility prose with the lock-versus-floor contract. |
| `docs/powershell-engineering-plan.md` | Record the approved contract and measured parity receipt. |

Any path or behavior outside this table stops implementation until the
maintainer explicitly revises the contract. P1a adds no package, manifest,
validator, generated catalog, agent instruction, or pull-request workflow
change.

#### Historical P1a evidence from PR #90

The PR #90 branch changes only the approved test, generated-test, workflow,
runner, guidance, and plan paths. All 16 repository tests and six generated
test templates parse with PowerShell 7.4 and `ModuleVersion = '6.2.0'`; none
uses `RequiredVersion` in its compatibility declaration. The shard runner and
CI bootstrap commands install and import Pester 6.2.0 exactly on that branch.

The focused repository-contract shard completed with 51 passed, zero failed,
and zero skipped tests. The full Pester 6.2.0 parity run completed at PR #90
commit `f0e9ac9c554eb99c2c32e0ce166cc265d36aec1e` on PowerShell 7.6.6 in
81.273 seconds with 16 shards and 464 tests: 451 passed, 13 were intentionally
skipped, and none failed, were not run, were inconclusive, or reported block,
container, or infrastructure failures. This exactly preserves the assessment
baseline's discovery and result counts. The retained branch and command
`./tests/Invoke-PesterShards.ps1 -Path ./tests -PesterVersion 6.2.0` make the
receipt reproducible. It establishes compatibility of the mechanical PR #90
branch; it is not evidence that those changes are present on `main` or that
every retained check belongs in Pester.

#### Retained-Pester P1a local evidence

The current P1a branch starts from `main` after PR #93 and contains no commit
from PR #88, PR #89, or PR #90. All 16 still-executed repository Pester files
and six generated Pester templates parse with PowerShell 7.4 and
`ModuleVersion = '6.2.0'`; none declares `RequiredVersion` as a compatibility
constraint. The new managed file-creation project has no Pester dependency.
The runner and current or generated CI bootstraps lock execution to Pester
6.2.0 exactly.

The focused repository-contract shard passes 51 of 51 tests with both its outer
runner and nested fixtures on Pester 6.2.0. The full suite runs in 16 isolated
shards on PowerShell 7.6.6 and Pester 6.2.0: 444 tests are discovered, 431 pass,
13 are intentionally skipped, and none fail, are not run, are inconclusive, or
report block, container, or infrastructure failures. Wall time is 80.620
seconds. These counts match the post-PR #93 Pester 5.7.1 split baseline; the 20
migrated `TrustedFileWrites` cases remain in the separate managed project.

An earlier tool-generated receipt reported 669 tests, but every shard path
belonged to `C:\repos\agent-skills` rather than the retained-Pester worktree.
That cross-worktree run is invalid and is not milestone evidence. The valid
receipt requires every shard path to start with
`C:\repos\agent-skills-p1a-retained\`.

#### P1a hosted and merge evidence

PR #94 merged as `0b439bb6b1712220642a8945e1195eb89000d6f8` on
2026-09-16. Its final head `74312e50705fb9eddf46b8941236c8de6393e670`
passed all applicable CI jobs; the tag-only release check was intentionally
skipped. The exact-head CI covered repository validation, both managed test
projects on Windows and Linux ARM64, and the Windows and Linux scaffold lanes.

Copilot's substantive review at
`0a63599e3f4dbf5243d126e05790e212ba947139` recommended approval and reported
one non-blocking documentation mismatch: generated contribution guidance did
not state the generated tests' PowerShell 7.4 and Pester 6.2 minimums. The
final commit corrected both generated guidance files without requesting another
review for the prose-only change. No inline comment or unresolved review thread
remained at merge.

#### P2 canonical runner local evidence

The first P2 slice routes the three active repository CI jobs that invoked
Pester directly through `tests/Invoke-PesterShards.ps1`. Ordinary Linux CI and
scheduled Windows CI run the full `tests` tree. Conditional ordinary Windows
CI keeps its focused `windows-acls` and `dotnet-file-creation` path set. The
runner implementation and managed `dotnet test` jobs are unchanged.

The focused Windows-path command completed two isolated shards on PowerShell
7.6.6 and Pester 6.2.0: 66 tests were discovered, 56 passed, ten were
intentionally skipped on the local host, and no failure or infrastructure
category was reported. A direct source inventory found exactly three isolated
runner calls and no direct `Invoke-Pester` command in active repository
workflows. No regex-backed Pester assertion was added for YAML semantics. The
full local run completed 16 shards and discovered 444 tests: 431 passed, 13
were intentionally skipped, and none failed, were not run, were inconclusive,
or reported block, container, or infrastructure failures. Every shard path
belonged to `C:\repos\agent-skills-p2-canonical\`.

Validated generated repositories receive a byte-for-byte copy of the canonical
runner, as they already receive the canonical skill validator. Generated CI,
release workflows, README validation commands, `CONTRIBUTING.md`, and
`FORMAT.md` invoke that local copy. The existing create-skill-repo shard now
launches the generated runner in a fresh PowerShell process for both a
distribution source and a validated consumer fixture, requires complete
nonzero passing summaries, and passes all 17 scaffold cases. This avoids a
second runner implementation while keeping generated repositories
self-contained. The hosted evidence below completes P2.

#### P2 hosted and merge evidence

PR #95 merged as `7e68d294300fbb9ddc649e90cbea4eefda35d621` on
2026-09-16. Its exact head `d8acb7985f988f328063cefc55009e79f2b9b90a`
passed CI run `35042569711`. All applicable repository validation, managed test,
and Windows and Linux scaffold jobs succeeded; the tag-only release check was
intentionally skipped.

Copilot review run `35042683641` completed successfully on that exact head.
Review `5217468566` covered all ten changed files, recommended approval, and
reported no comments or suppressed findings. The final audit found no inline
comments, issue comments, or review threads. PR #95 is therefore the first of
the two consecutive substantive PowerShell pull requests required by the P8
effectiveness measure to have zero valid post-publication findings.

#### P1b policy enforcement

P1b begins after the managed canary with a reviewed contract table, not code.
The accepted contract is recorded in
[PowerShell toolchain policy contract](powershell-toolchain-policy-contract.md).
For each surface it must state the accepted forms, rejected forms, deferred
forms, source of truth, and independent oracle. Semantic checks use maintained
parsers with exact dependency locks and live with the component that owns
repository policy. If a parser is unavailable, the check is narrowed or
deferred rather than approximated. Host, SDK, analyzer, bootstrap, and
execution-context fields must not enter a manifest until an executable gate
consumes them.

The P1b contract table must include the managed file-creation CI job: parsed
workflow policy requires the `ubuntu-24.04-arm` behavior entry, the
`windows-latest` behavior-and-coverage entry, their mutually exclusive coverage
steps, and the linked test project and coverage configuration. Until P1b lands,
exact-head CI and review are the enforcement evidence. Do not add a new
regex-based Pester assertion for this YAML contract; that would recreate the
test-ownership error P0r rejected.

#### P1b runner-policy recovery

PR #97 closed unmerged after 12 commits and 11 Copilot review rounds. Its
managed policy grew to 1,163 lines, about 950 of them devoted to proving runner
command, mutation, and reachability behavior through AST exclusions. Four new
classes of bypass remained at the final head despite green deterministic tests.

The replacement starts from current `main` and does not carry that history
forward. The first slice owns the closed manifest, retained and rendered test
requirements, and directly represented runner metadata only. Real-process
state-table tests own runner outcomes, including rejection of a mismatched
Pester version. The managed policy does not model arbitrary PowerShell
execution and is not a security boundary. Workflow YAML and bootstrap policy
remain separate later slices.

#### P1b replacement first-slice local evidence

The replacement adds a 264-line managed policy using `System.Text.Json` and
PowerShell's parser. It has no command whitelist, mutation scan, control-flow
model, YamlDotNet dependency, or workflow interpretation. Its 79 Release and
Debug cases divide into 51 manifest cases, 12 retained-test requirement cases,
12 runner-metadata cases, and four repository integration cases. The repository
checks validate the checked-in manifest, all 16 tracked Pester files, the
canonical runner metadata, and six test files emitted by the real distribution
scaffolder.

The runner adds one direct early guard for a `PesterVersion` other than 6.2.0.
The focused real-process state table passes all 52 cases. Full isolated Pester
execution discovers 445 cases: 432 pass, 13 are intentionally skipped, and no
failure, not-run, inconclusive, block, container, or infrastructure category is
reported. The existing managed file-creation and dotnet-pipes suites pass 20 of
20 and 36 of 36 cases respectively.

PR #98 merged as `7fab5afaaaaacd1d8edfa4db97667163b4ed95a8` on
2026-09-17. Its exact head `e0bfc1fd821426109530477e649a833a53abf772`
passed all nine applicable checks; the tag-only release check was intentionally
skipped. Copilot review `5229796285` covered all 14 changed files, recommended
approval, and reported no inline or suppressed findings. No unresolved thread
remained at merge.

#### P1b active-workflow slice local evidence

The second slice adds YamlDotNet 18.1.0 and validates the two active repository
workflow files as structured YAML. It owns three static execution modes: Linux
all-tests and conditionally focused Windows tests in `ci.yml`, plus scheduled
or manually dispatched Windows all-tests in `full-ci.yml`. Each runner step has
the accepted host, `pwsh` shell, condition, and literal path set, and exactly one
preceding matching `Install-Module Pester -RequiredVersion 6.2.0` step.

The active-workflow policy adds YamlDotNet 18.1.0 and 585 lines of managed
validation isolated from the 264-line manifest and metadata core. Its 58
focused cases cover malformed and duplicate YAML, policy-bearing
anchors, aliases, and merge keys, accepted scalar styles, job and host drift,
bootstrap order, shell, condition, and version drift, direct static Pester
calls, runner cardinality, and exact full/focused path sets. Comments,
unrelated strings, reusable jobs, and anchors outside policy-owned mappings do
not count as execution. All 138 managed policy cases pass in Debug and Release,
including the real `ci.yml` and `full-ci.yml` integration check.

This evidence establishes local correctness only. Exact-head hosted CI and a
clean review were required before the slice merged as PR #99.

#### P1b generated-output slice local evidence

The third slice validates generated Pester execution from scaffolder output,
not raw templates. It generates validated, team-CI, and distribution
repositories, compares each emitted runner byte-for-byte with the canonical
runner, parses emitted workflow YAML, and inspects only explicit `pwsh` command
steps. Team CI must contain one all-tests runner in `skills.yml`; distribution
must contain one in both `skills.yml` and `release.yml`. Each runner follows one
same-job exact Pester 6.2.0 installation. Job names and runner images remain
outside this contract.

The generated-output policy is 207 lines. Its 16 focused cases cover divergent
runner bytes, raw templates and unresolved tokens, bootstrap order and version,
runner shell and path, direct Pester, missing or extra generated runners, and
unrelated workflow shapes. All 155 managed policy cases pass in Debug and
Release. The create-skill-repo canary also executes and byte-checks the emitted
runner in its named validated, team-CI, and distribution fixtures. A synthetic
generated assertion failure also proves nonzero process exit and complete
failed-test summary propagation without an infrastructure failure. All 18 cases
pass through the canonical Pester runner.

PR #100 merged as `e7b71e77d428443226fa3711e24094d33a5de192` on
2026-09-22. Its exact head `5e4b66c9389da186d068cf63f5fe012e7b3468c4`
passed all nine applicable CI checks; the tag-only release check was
intentionally skipped. Copilot review `5256628866` covered the final head,
recommended approval, and reported no inline or suppressed findings.

#### P1b managed file-creation slice local evidence

The fourth slice validates the managed file-creation workflow as structured
YAML and the named coverage settings and report as XML. It owns exactly two
matrix rows: Ubuntu ARM64 without coverage and Windows with coverage. The
matrix drives `runs-on`, and both rows run the same managed test project in
Release through explicit `pwsh` steps. The Windows step additionally requires
the checked-in coverage settings, a variable output path, and Cobertura output.
The non-coverage workflow step now declares `shell: pwsh`, resolving the only
accepted current-tree mismatch.

The 425-line policy has 39 focused cases covering malformed YAML, aliases, matrix keys and typed values,
host rows, complementary conditions, shells, project and configuration drift,
Pester wrappers, coverage options, settings XML, and Cobertura source and line
evidence. Comments, strings, and unrelated conditional steps do not count as
managed test commands. One repository integration validates the real workflow
and settings. All 195 managed policy cases pass in Debug and Release. The linked
managed project passes all 20 Release cases with and without coverage; the
Windows coverage job remains the real report oracle. A local Windows report
contains one `TrustedFileWrites` production class with 43 of 66 lines covered.

This evidence establishes local correctness only. Exact-head hosted CI on both
matrix rows and a clean review are still required before this slice can merge.

#### Publication and correction controls

Recovery uses controls that test both the implementation and its premise:

- start from a clean branch at current `main`; do not salvage failed validator
  commits;
- before approving a path and behavior whitelist, ask whether the existing
  language, harness, abstraction, and repository pattern are appropriate;
- approve a fixed path and behavior whitelist only after naming the subject,
  owner, oracle, standard-tool alternatives, and cheapest disconfirming check;
- complete the contract table and independent local review before publication;
- present the complete diff, validation receipt, and review findings to the
  maintainer before the first commit and pull request;
- treat a premise, ownership, or contract finding as a stop-and-redesign event;
- permit at most one bounded correction for a contained implementation defect
  already inside the approved contract, followed by fresh independent review;
- defer a genuinely new requirement or reopen the contract explicitly instead
  of silently absorbing it into the pull request;
- treat automated review as a release gate, never as the first requirements
  discovery mechanism; and
- track publication as a state machine through exact-head CI, exact-head review,
  full discussion audit, disposition, and merge verification. A running watcher
  or successful command is not completion of the owned task.

### Parser and validator policy

Repository-wide semantic policy should default to a managed validator or an
established external tool, not a new PowerShell parser. Every semantic check of
a structured format must use a maintained parser with an exact version and lock
or integrity record when the parser is an added dependency:

- JSON policy uses `System.Text.Json` and explicit DTO or schema checks.
- YAML policy uses a maintained managed parser selected and pinned during P1b;
  repository template placeholders are rendered explicitly before parsing.
- PowerShell syntax and metadata use
  `System.Management.Automation.Language.Parser` and AST nodes. Pester may own
  PowerShell-specific behavior around those nodes; repository policy may call
  the same API from managed tests.
- XML uses `System.Xml.Linq` or another platform XML parser.
- Markdown semantics use a maintained Markdown parser. Existing markdownlint
  and link checks remain the first choice for contracts they already express.

Regular expressions and line scanning may enforce an explicitly documented
literal-text contract only. They must not infer mappings, sequences, quoting,
folding, comments, code blocks, command binding, or execution scope. If a
supported parser is unavailable, narrow or defer the check rather than emulate
the grammar. A review finding that introduces a new grammar class stops the
current pull request for redesign; it does not start another serial patch round.

## Executive decision

Raise PowerShell engineering to the same standard used for typed production
code. The solution is not just more Pester tests or a higher coverage number. It
combines explicit test ownership, supported runtimes, domain-appropriate test
entry points, strict public and structured contracts, adversarial fixtures,
static analysis, separate measurable coverage, process isolation, and typed
infrastructure for the parts PowerShell makes hardest to reason about.

Adopt these decisions:

| Area | Decision |
| --- | --- |
| Runtime | Require PowerShell 7.4 or later for every operational and shipped script and generated template. Permit a different version only in an explicitly labeled compatibility-test fixture. |
| Test ownership | Choose Pester, MSTest, or an established validator from the subject and oracle, not the current file extension or neighboring pattern. Split mixed suites and remove duplicate migrated assertions. |
| Pester | Use Pester 6.2 or later as the compatibility floor only for retained PowerShell tests. Lock repository Pester execution to 6.2.0. Do not make Pester a dependency of managed repository-contract tests. |
| Isolation | Keep process isolation for remaining PowerShell tests. Move timeout and process-tree supervision into managed infrastructure when P1c or P2 demonstrates a concrete need; do not build a generic host speculatively. |
| CI hosts | Run retained PowerShell tests on the applicable minimum PowerShell 7.4 hosts. Run managed contracts through `dotnet test`. Keep focused Windows lanes for Windows-owned behavior and schedule broader compatibility lanes only where they answer a named risk. |
| Parameters | Make every parameterized script and every advanced function named-only with `PositionalBinding = $false`. This is part of the breaking release, not a silent compatibility change. |
| Static analysis | Pin PSScriptAnalyzer 1.25.0. Block a curated correctness profile globally and block new default diagnostics on changed lines. Do not require an immediate cleanup of all historical style warnings. |
| Coverage | Collect and gate PowerShell and managed coverage separately. Establish report-only component baselines after ownership is corrected, then ratchet changed-code and component coverage without using one domain to mask another. Critical state and negative-path coverage remains enumerated rather than inferred from percentages. |
| Exceptions | Thin wrappers, generated templates, and platform-only code may be exempt from the percentage gate only through a reviewed manifest entry mapping them to behavioral or platform tests. They remain visible in reports. |
| Typed boundary | Keep PowerShell for PowerShell-native orchestration. Put repository parsers, typed policy, process supervision, timeout handling, report DTOs, aggregation, and managed coverage logic in C# when a concrete check owns that behavior. |
| First extraction | Start with one managed repository-contract canary. Migrate the Pester shard runner only after the remaining PowerShell-test inventory proves which process-host behavior is still required. |
| Skill | Publish the portable `powershell-engineering` skill required by this program. Track `engineering-course-correction` separately in the backlog. |
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
classes and, in some cases, misplaced ownership. Several flawed lines were
already executed by positive tests. A useful engineering strategy must combine
the natural harness for each subject with coverage, adversarial value classes,
state tables, compatibility snapshots, and mutation controls.

## Verified baseline

### Repository inventory

The planning-baseline tree contains:

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

Three CI jobs invoke Pester directly rather than using the hardened shard
runner: `scaffold-linux` and `scaffold-windows` in `.github/workflows/ci.yml`,
and `scaffold-windows` in `.github/workflows/full-ci.yml`. Pester 5.7.1 is
copied across workflows, the runner, tests, and examples. The three tests with
no Pester module requirement are `FileCreation.Tests.ps1`,
`WindowsAcl.Tests.ps1`, and `Priority0.Tests.ps1`. No PSScriptAnalyzer or Pester
code-coverage gate is configured.

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

The accepted
[PowerShell toolchain policy contract](powershell-toolchain-policy-contract.md)
permits P1b to create `tools/powershell-toolchain.json` with exactly four
version-one values: schema version 1, PowerShell test minimum 7.4, Pester
compatibility minimum 6.2.0, and Pester execution version 6.2.0. It excludes
host lanes, .NET SDK and C# versions, PSScriptAnalyzer, coverage policy, and
per-file inventories. A later milestone may add a field only when an accepted
contract binds it to an executable gate.

The existing managed test project pins MSTest SDK 4.2.3 in its project SDK.
P1c decides whether the canary retains that version and whether more than one
managed project needs central package ownership. The MSTest SDK does not belong
in a PowerShell toolchain manifest merely because this program also changes
PowerShell tests.

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
- never infer JSON, YAML, XML, Markdown, or PowerShell grammar with regular
  expressions or indentation heuristics;
- validate the complete token, not only a matching prefix;
- version report schemas and reject unknown incompatible shapes;
- never make derived evidence stronger than its source;
- use one shared synthetic value corpus against core, wrapper, and rendered
  generated implementations.

Known PR #87 seeds include malformed fourth-component versions, trailing junk,
string and numeric Boolean substitutes, missing versus explicit-false evidence,
old-but-valid versions, and hash mutation during an operation.

### Test layers

Every substantive component selects the applicable layers and records why an
omitted layer is unnecessary. The owning harness follows the component:

1. **Parser and static contract:** the language parser, format parser, compiler,
  schema tool, or established validator owns syntax and structure. Runtime and
  toolchain requirements, parameter metadata, exports, generated ownership,
  and schema declarations match policy.
2. **Pure unit tests:** Pester tests PowerShell functions and modules; MSTest
  tests managed components. Both use table-driven boundary and equivalence
  classes separated from process, filesystem, environment, and network
  adapters.
3. **State-table tests:** enumerate every valid state and the complement for
  report protocols, trust flags, retries, timeouts, and workflow transitions
  in the harness that owns the state machine.
4. **Fresh-process tests:** assert command line, stdout, stderr, information and
   warning streams, exit code, timeout, process-tree cleanup, environment
   restoration, and behavior from paths containing spaces.
5. **Platform tests:** run filesystem modes, ACLs, native loading, symlinks, and
   path semantics on the operating systems that own those contracts.
6. **Generated-artifact tests:** render templates, parse the result with the
  owning format parser, and execute focused behavior from the generated copy
  rather than asserting source text alone.
7. **Fault and mutation controls:** prove the test fails when a critical check is
   removed, a type is coerced, a parser is weakened, a report goes stale, or a
   worker exits in each invalid state.
8. **Integration tests:** exercise real external tools only through explicit,
   pinned, isolated entry points and preserve identity evidence.

Tests are evidence only when their expected values come from the contract or an
independent oracle. An assertion copied from the current implementation is not
an independent check.

### Canonical test execution

Retain process-per-file execution for the PowerShell tests that remain after
P0r while Pester 6 parallel execution is experimental. The PowerShell runner
must provide:

- one fresh PowerShell process per test file;
- hard process-tree timeouts;
- explicit PowerShell and Pester paths/versions;
- complete worker/result state validation;
- honest aggregate counts and infrastructure errors;
- deterministic result, log, test-result, and coverage artifacts;
- component-to-test selection for focused validation;
- a clean environment contract and explicit opt-ins for external tools.

Every CI path that executes Pester goes through this runner. Managed tests run
directly through `dotnet test`; they are not wrapped in Pester unless a
PowerShell wrapper is itself the subject. Focused platform jobs pass explicit
component subsets. CI may aggregate receipts, but it must preserve separate
failure and coverage identities for the managed and PowerShell domains.

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

Store explicit executable-source inventories and reviewed exceptions for both
PowerShell and managed code. Each entry names its component, source path,
owning tests, execution mode, platform, and exception rationale when applicable.
Do not add a manifest until an executable collector consumes every field.

Collect Pester 6 coverage inside every canonical shard that owns an in-process
PowerShell component and instrument child processes where their scripts are the
subject. Collect managed coverage through `dotnet test`. A change runs the
applicable owning tests; it does not instrument unrelated components merely to
raise an aggregate percentage.

After ownership migration and separate report-only baselines, approve component
ratchets. The previous global 80% command and 90% changed-line targets are
provisional and must not become gates before this review. Enforce:

- no unexplained regression in the owning component's applicable coverage;
- explicit tests for changed branches and error paths in executable code;
- 100% enumerated coverage for critical state tables, independent of percentage;
- a reviewed behavioral or platform-test mapping for every percentage
  exception.

Publish separate managed and PowerShell reports plus a typed summary artifact.
Never compute a cross-domain percentage. Keep coverage service-independent; the
repository-owned C# gate parses coverage and git diffs. Establish hosted p50 and
p90 duration after five runs rather than turning the local 169.885-second
measurement into an unsupported CI service-level target.

### Typed C# 14 test infrastructure

Begin with the smallest repository-owned C# 14 test project needed for the P1c
canary. Add shared infrastructure only when a second concrete consumer proves
the abstraction. Managed code may own contracts PowerShell has repeatedly made
fragile:

- process start, asynchronous stream capture, cancellation, timeout, and process
  tree termination;
- environment construction and restoration;
- executable identity and hash checks;
- versioned JSON DTOs and validation;
- worker/result state machines and aggregate accounting;
- deterministic Cobertura merge and changed-line mapping;
- machine-readable receipts.

Do not begin by porting the shard runner. First prove the test-ownership boundary
with one managed-code or parser-backed canary. If subsequent ownership work
shows that process supervision is shared, migrate the shard runner while
preserving its PowerShell command line and schema, and keep a thin PowerShell
wrapper for contributor ergonomics. Do not rewrite domain scoring or every
skill script into C#.

### Portable PowerShell engineering skill

Create a portable `powershell-engineering` core after P0r, P1a, and P1b so later
implementation uses the accepted ownership, runtime, and Pester contracts. Keep
its `SKILL.md` concise and route deep detail to bundled pages for:

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

Add an early decision point before PowerShell implementation:

- Is the required behavior PowerShell-native, or is PowerShell merely the
  repository's familiar orchestration language?
- Does a maintained parser, compiler, schema tool, validator, or managed API
  already own the hard part?
- Which harness will measure the implementation's executable coverage without
  making the implementation its own oracle?
- What is the smallest comparison that could demonstrate that C# or an
  established tool is the better boundary?

Evaluate the skill with synthetic forms of the defects observed in PR #87. The
agent must identify the contract class, add a failing control before the fix,
choose a structured parser or exact type check, preserve compatibility or name a
break, and run the correct focused and full gates.

### Backlog: portable engineering course-correction skill

Use the `manage-skills` lifecycle to search installed, commons, and public
sources before authoring. If no existing portable skill owns this outcome,
create a separate `engineering-course-correction` skill for work that is
accumulating activity without converging. It must not be PowerShell-specific and
must not become generic motivational advice. It owns a short diagnostic and a
bounded recovery workflow. This specification records a future work item; do
not implement or evaluate it as part of the PowerShell engineering sequence.

The skill makes the reinforcing mechanism visible:

| Loop | How it reinforces itself | Required break |
| --- | --- | --- |
| Local-pattern continuation | The LLM copies the nearest established pattern; each new copy makes that pattern look more authoritative to the next pass. | Run the greenfield question, identify the natural owner, and compare one credible alternative before extending the pattern. |
| Review accretion | Each finding becomes another local patch and test; the larger surface creates more finding classes and makes replacement feel less acceptable. | Classify the finding as defect, requirement, or premise failure; cap local correction and run a replacement canary for a premise failure. |
| Implementation-shaped evidence | Tests copy current outputs and reviewer examples; green results increase confidence without supplying an independent oracle. | Write the accepted contract and negative controls first, then obtain expected results from an external oracle. |
| Sunk-cost continuation | Time, commits, and explanations are treated as reasons to retain code, so further investment raises the psychological cost of stopping. | Separate reusable evidence from code and ignore unrecoverable effort in the next architecture decision. |
| Activity mistaken for completion | Commands, watchers, and green checks create visible motion; reporting that motion ends the turn while the owned workflow remains incomplete. | Name the terminal state and do not declare completion until the state machine reaches it or a real blocker is handed back explicitly. |

Trigger it when any of these signals appears:

- review repeatedly discovers new contract classes after publication;
- commit or patch count grows because each fix reveals another unsupported
  form;
- tests are added mainly to encode examples found by the latest review;
- a supposedly narrow change acquires parsers, state machines, or
  infrastructure;
- the same defect class returns after an acknowledged correction;
- the agent cannot name the subject, owner, oracle, or stopping condition;
- work continues because reverting or replacing it feels expensive;
- a tool, watcher, or green check is reported as task completion while an owned
  state remains active; or
- the user must repeatedly ask whether the work has stalled or changed scope.

The skill pauses new edits and asks practical questions in this order:

1. What user outcome are we trying to achieve, independent of the current
   artifact or pull request?
2. Which premises came from an explicit requirement, which came from the
   repository, and which did the agent infer by pattern completion?
3. If this repository had no current implementation, which language, harness,
   parser, or standard tool would we choose today, and why?
4. Are we preserving a pattern because it is effective, or because neighboring
   files make it easy for an LLM to continue?
5. Is the implementation language also acting as its own parser, test harness,
   and oracle? Which responsibility should move?
6. What evidence would falsify the current approach? Have we run the cheapest
   such check before adding more code?
7. Are new tests derived from an accepted contract or from the implementation
   and the latest reviewer example?
8. Is the latest finding a contained defect, a new requirement, or evidence
   that ownership and architecture are wrong?
9. What changed after the previous correction besides the prose describing our
   intent? Which executable control now prevents recurrence?
10. Which work is independently valuable, and which is sunk cost that should
    not influence the next decision?
11. What is the smallest reversible canary for the strongest alternative?
12. Should we continue, narrow, replace, or stop? What explicit user decision
    or approval boundary is required next?

The output is a compact recovery record: observed signals, inherited and
inferred premises, current feedback loop, disconfirming evidence, viable
alternatives, salvageable evidence, rejected sunk cost, recommended
disposition, and the next checkpoint. It must name LLM-specific failure modes
directly: local-pattern continuation, fluency mistaken for evidence,
implementation-shaped tests, sunk-cost continuation, scope normalization,
verbal self-correction without changed controls, and premature declarations of
completion.

Evaluate the skill with synthetic scenarios based on the failed parser pull
requests, the Pester-versus-MSTest ownership question, a long patch stack driven
by serial review discoveries, and an exact-head review watcher that finishes
after the agent incorrectly stops. Success requires the agent to challenge the
premise, propose a cheaper alternative, preserve only independently useful
evidence, identify the approval boundary, and avoid another implementation edit
until the recovery decision is accepted.

## Focused delivery sequence

Use separate pull requests for these changes while holding the breaking release
until all required compatibility migrations are complete:

1. PR #90 is closed unmerged, its exact Pester 6 compatibility receipt is
   retained, and PR #92 records the accepted ownership inventory and managed
   canary contract.
2. Implement the approved managed canary in a dedicated MSTest project. Link
   the existing source, remove only the six migrated Pester assertions after
   parity, and collect the specified local and exact-head CI comparison evidence.
3. Complete the Pester 6.2 cutover only for tests retained in Pester and route
  their CI invocations through the isolated runner.
4. Specify P1b's accepted, rejected, and deferred forms, then implement
  parser-backed repository policy in managed code or an established validator.
5. Add the portable PowerShell engineering skill, repository overlay, and
  seeded deterministic scenarios.
6. Raise all operational and shipped scripts/templates to PowerShell 7.4 and
  migrate parameterized scripts and advanced functions to named-only binding,
  with AST compatibility tests and migration documentation.
7. Add the PSScriptAnalyzer correctness profile and changed-line no-new gate.
8. Establish separate managed and PowerShell report-only coverage baselines;
   add only the typed process/report infrastructure required by demonstrated
   consumers.
9. Enable approved component ratchets, changed-branch, state-table, and
   exception gates without a cross-domain aggregate threshold.
10. Move evaluation process/report infrastructure into the typed core in focused
    parity-backed slices.
11. Publish the breaking pre-1.0 minor release only after P8 acceptance.

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
- harness ownership changes, duplicate assertions removed, and checks replaced
  by standard tools;
- human repair time and number of commit/review rounds.

The engineering program succeeds when:

1. every seeded defect class fails under its negative control and passes after
   repair;
2. every applicable runtime, analyzer, coverage, contract, platform, generated,
   and integration gate is green;
3. every check names its subject, owner, independent oracle, and natural harness;
4. no structured-format semantic policy depends on regex or indentation
  heuristics when a maintained parser or established validator owns the format;
5. no executable PowerShell path bypasses the canonical PowerShell toolchain and
  runner, and no managed test is wrapped in Pester without a PowerShell subject;
6. managed and PowerShell coverage remain separately visible and gated;
7. exceptions remain explicit, current, and behaviorally covered;
8. two consecutive substantive PowerShell pull requests receive zero valid
   post-publication reviewer findings.

For this measure, a substantive pull request changes executable behavior, a
public or process contract, a validator, a test runner, a generated executable
artifact, or an analyzer or coverage gate. Documentation-only and mechanical
metadata changes do not qualify. A valid post-publication finding identifies an
accepted defect or contract gap that requires a code, test, or contract change;
style preferences, false positives, and genuinely new out-of-scope requirements
do not count.

A higher coverage percentage that does not reduce valid escaped defects is not a
success. If reviewer findings continue, classify them, add the missing contract
class, and rework the skill or gates before raising thresholds mechanically.

## Boundaries

This plan records sequencing and decision gates; it does not provide standing
authorization. Local edits, commits, pushes, pull request writes, review replies,
thread resolution, merges, remote policy changes, releases, and model runs each
follow the repository's current approval boundaries. The maintainer decided on
2026-09-15 to close PR #90 unmerged and merged the plan reset through PR #91.
Toolchain provisioning must be isolated and pinned. Real model evaluations of
either new skill require separate approval for model, scenarios, repetitions,
budget, and concurrency.

Do not fold this work into the dual-model experiment or the pull-request process
plan. Those plans may consume the stronger test infrastructure, but this plan
owns PowerShell runtime, API, test, analyzer, coverage, and typed-infrastructure
quality.
