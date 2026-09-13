# Skill behavioral evaluations

This directory exercises the published plugin through Copilot CLI programmatic
mode. Deterministic Pester tests validate the runner on every ordinary CI run;
real model scenarios are manual and local-only to avoid unbudgeted CI token use.
Use `-ReportOnly` for local calibration; safety and harness-infrastructure
failures remain blocking.

## Current vertical slices

`scenarios/create-pr.json` covers eight behaviors:

- a positive create-PR request;
- a readability-review near miss;
- dirty `main` without publish approval;
- explicit commit and push approval on a feature branch;
- normalization of hard-wrapped remote Markdown;
- correction of an unsupported validation claim;
- a blocked exact commit message whose claims lack evidence; and
- an overlay-loading sentinel.

`scenarios/technical-writing.json` covers 17 direct behaviors. The common
workflow cases cover explicit drafting, meaning-preserving revision, abstention
when facts are missing, first-person authority, composition with an isolated
personal voice profile, pre-publication review without action, code-readability
and machine-format near misses, and an overlay sentinel. The artifact matrix
adds commit messages, pull request descriptions, issues, review comments,
GitHub Discussions, source comments, public API documentation, and repository
Markdown. Each artifact case includes supplied facts, an unsupported-claim trap,
and a local-only stop.

`scenarios/publishing-workflows.json` covers local-only integration with
`address-pr-feedback`, `manage-skills`, and `engineering-baseline`. These cases
require both the owning workflow and `technical-writing` to invoke while
forbidding the remote action.

`scenarios/manage-skills.json` covers seven behaviors: project integration before
vendoring into an existing repository, local drift despite a pinned unchanged
upstream, exact pending-divergence reconciliation with extra unexplained drift,
ownership-specific authoring gates, intentionally distinct authoring despite an
overlapping shared skill, overlay selection when one-way composition cannot provide
reverse discovery, and a code-readability near miss. The local-drift prompt and near
miss do not name the skill, so they exercise description-based routing. The
project-integration fixture contains a differently named local skill, canonical and
generated agent guidance, documentation-derived bindings, and an unrelated keyword
match. Every scenario is read-only and preserves approval boundaries. The overlap and
composition scenarios require small labeled decision outputs so polarity and
contradictory recommendations are scored as one contract instead of independent
free-prose keyword matches.

`scenarios/create-skill-repo.json` contains seven scenarios for the
repository-local bootstrap workflow. They cover novice-oriented role
explanations, a name-derived sibling destination, question-first handling of an
underspecified request, routing one-skill creation to `manage-skills`,
local-only consumption language, the future effect of upstream search order,
private-upstream containment, and the public remote-action boundary. The runner
stages this skill under the fixture's `.agents/skills/`; it is not copied into
the published plugin fixture.

`scenarios/user-voice.json` covers eight direct behaviors: consent before
source access, a manual copy/paste data handoff, public-destination refusal,
untrusted report rejection, best-self tone filtering, third-party impersonation
refusal, separate private GitHub approval gates, and non-destructive migration.

`scenarios/dotnet-pipes.json` is an opt-in six-case domain suite. It covers a
bounded named-pipe implementation, anonymous-pipe selection for a parent-child
channel, Windows service ACL design without invented managed APIs, pipe-specific
audit findings, listener-starvation troubleshooting, and a `System.IO.Pipelines`
near miss. It is not part of the default release matrix in
`Invoke-SkillEvalMatrix.ps1`.

`scenarios/performance-testing.json` is an opt-in ten-case domain suite. It
covers a valid fresh-process phased measurement, rejection of an exit-zero run
with no discovered/populated work, refusal to compare CPU time across unverified
sampling denominators, evaluated ETW package preflight, live-corpus mutation,
common-mode oracle defects, native call-count evidence, pool-state allocation,
callback exit contracts, and shared-output build serialization. It is not part
of the default release matrix.

`scenarios/roslyn-analyzers.json` is an opt-in two-case routing suite. Its natural
prompts require the analyzer skill for diagnostic, code-fix, and Fix All work, while
routing application runtime performance to `performance-testing`. Both cases use exact
labeled outputs so affirmative plans and explicit refusals cannot satisfy the same
keyword patterns. It is not part of the default release matrix.

[scenarios/dotnet-file-creation.json](scenarios/dotnet-file-creation.json) is an
opt-in 16-case filesystem suite. It covers ordinary preferences and scratch,
public versus credential caches, privileged consumption of user AppData, mixed
audit findings, a novice-facing writer question, durable-save requirements,
administrator exclusions, known hostile preexisting directories, empty roots,
settings scope and roaming, defaults versus policy, and a pipe near miss.
Prompts do not name the skill: 15 cases require observed invocation and the near
miss forbids it while requiring pipe guidance. Six source-backed audits use the
[synthetic fixture](fixtures/dotnet-file-creation-audit/Deployment.md), with the
write tool denied and an unchanged worktree required as defense in depth. The
suite is not part of the default release matrix. See [File I/O acceptance](#file-io-acceptance)
before interpreting a pass as evidence of useful developer guidance.

Four settings cases contrast the two decision entry points: "Where do I save
this?" designs per-user global settings and a roaming/local split; "Am I saving
this right?" audits shared defaults with user overrides and mandatory-policy
precedence. The latter cases check both loading and saving, not folder selection
alone.

Copilot CLI 1.0.63 emits structured JSONL when the model invokes the `skill`
tool. Positive cases require their primary skill invocation, and cross-skill
cases can require companion invocations. Near misses forbid the primary skill.
A unique token exists only in each injected overlay, providing a separate
assertion that the selected core loaded its repository binding.

Each run creates a fresh git repository and a minimal copy of the plugin. A
scenario may seed repository content from a revision-tracked directory beneath
`evals/fixtures/`; that content becomes part of the committed baseline before
the model runs. Fake `git` and `gh` executables are first on the Copilot child
process `PATH`; they return fixture state and log attempted commands without
changing a remote. The runner also compares the real fixture `HEAD` and status
before and after the run so an unexpected bypass is visible.

The Copilot process retains only the credential needed to reach the model.
`--secret-env-vars` strips known and secret-looking environment variables from
shell and MCP tools and redacts them from output. The child process uses a
sandboxed home, Git config, and GitHub CLI config, so persisted `gh` or Git
credentials are unavailable. Built-in and plugin MCP servers are disabled.

## Run locally

Real runs require Copilot CLI 1.0.63 or later and an authenticated Copilot
session or `COPILOT_GITHUB_TOKEN`. Every run uses a fresh isolated
`COPILOT_HOME` by default so personal skills, plugins, and client state cannot
affect public-plugin evidence. OS-backed Copilot authentication may remain
available; otherwise supply a token through the environment. Use
`-IsolateCopilotHome:$false` only for a deliberate local diagnostic, never for
release evidence.

```pwsh
./evals/Invoke-SkillEvals.ps1 `
  -Model gpt-5.4 `
  -RunCount 1
```

Real model runs use eight isolated workers by default. Override concurrency for
diagnostics or constrained environments:

```pwsh
./evals/Invoke-SkillEvals.ps1 `
  -Model gpt-5.4 `
  -RunCount 3 `
  -MaxConcurrency 4
```

Every run owns its workspace, plugin copy, shim log, sandbox home, and
`COPILOT_HOME`. Injected deterministic executors remain serial because their
scriptblocks are intentionally process-local. Summaries restore scenario and
run order after parallel completion and record requested/effective concurrency,
wall time, queue time, setup time, model-process time, and scoring time.

Run the complete five-document release matrix under one shared eight-call
budget:

```pwsh
./evals/Invoke-SkillEvalMatrix.ps1 `
  -Model gpt-5.4 `
  -RunCount 3 `
  -MaxConcurrency 8
```

The matrix allocates the worker budget by document workload and runs documents
concurrently. It never creates more model workers than `-MaxConcurrency`.

`gpt-5.4` is the current baseline. A release run may pass another concrete model
that is available to the evaluation account; retain that model in the published
summary rather than relying on a client default.

Run one scenario while developing the harness:

```pwsh
./evals/Invoke-SkillEvals.ps1 `
  -ScenarioId create-pr-dirty-main-no-approval `
  -RunCount 1 `
  -ReportOnly
```

Select another scenario document explicitly:

```pwsh
./evals/Invoke-SkillEvals.ps1 `
  -ScenarioPath ./evals/scenarios/technical-writing.json `
  -RunCount 1 `
  -ReportOnly
```

The runner loads one scenario document per invocation. Run all six documents
for a capability release that changes skill management, `technical-writing`,
`user-voice`, its private-profile composition contract, or a publishing
workflow.

For an incremental gate, use a prior summary to select only scenarios whose
canonical definition, fixture closure, or candidate dependency closure changed:

```pwsh
./evals/Invoke-SkillEvals.ps1 `
  -ScenarioPath ./evals/scenarios/technical-writing.json `
  -BaselineSummaryPath ./artifacts/baseline/summary.json `
  -RunCount 3
```

Inspect the affected identifiers without running the model:

```pwsh
./evals/Get-SkillEvalAffectedScenarios.ps1 `
  -ScenarioPath ./evals/scenarios/technical-writing.json `
  -BaselineSummaryPath ./artifacts/baseline/summary.json
```

When only deterministic response/command scoring changes, rescore immutable
model output locally. The command verifies each captured output hash, writes a
separate derived summary, and never rewrites source transcripts or JSONL:

```pwsh
./evals/Invoke-SkillEvalRescore.ps1 `
  -ScenarioPath ./evals/scenarios/technical-writing.json `
  -InputDirectory ./artifacts/baseline `
  -OutputDirectory ./artifacts/rescored
```

After a rescore passes, run only each changed scenario three times to measure
fresh model variance. Do not regenerate an unchanged document merely because a
matcher changed.

By default reports go to a unique temporary directory. `summary.json` and
`summary.md` contain the aggregate result; each run retains its invocation,
stdout, stderr, transcript, shim log, and scored evidence. Prompts and
transcripts remain local and are not uploaded automatically. Retain an aggregate
summary with release evidence when needed, then remove local run artifacts.

## File I/O acceptance

The file I/O suite has been authored and its deterministic checks run; no model
baseline is claimed. Each scenario's `reviewCriteria` is a **human-review
rubric**, not a field automatically evaluated by the scorer. Required and
forbidden response patterns are coarse checks, calibrated with synthetic
coherent answers and contradictory additions. They do not prove that generated
code works, that an answer is proportionate, or that a novice understands it.

Run the suite-specific deterministic checks without a model or Copilot CLI:

```pwsh
Import-Module Pester -RequiredVersion 5.7.1
$configuration = New-PesterConfiguration
$configuration.Run.Path = './tests/evals/SkillEval.Tests.ps1'
$configuration.Run.Throw = $true
$configuration.Filter.FullName = 'File I/O behavioral evaluation checks.*'
Invoke-Pester -Configuration $configuration
```

These checks cover schema/pattern validity, affirmative versus negated advice,
contradictions despite matching required phrases, invocation evidence, audit
mutation safety, fixture staging, and the fixture's actual short-read/cache
behavior. Settings checks cover both entry points, scope/roaming advice, a save
that wrongly targets machine defaults, and user values overriding mandatory
policy. Synthetic scorer responses are not candidate model outputs.

Only after approving a model and run budget, a full three-repeat run would use
48 model invocations:

```pwsh
./evals/Invoke-SkillEvals.ps1 `
  -ScenarioPath ./evals/scenarios/dotnet-file-creation.json `
  -Model gpt-5.4 `
  -RunCount 3 `
  -MaxConcurrency 2 `
  -ReportOnly
```

Before calling the candidate effective, review every run against these gates:

1. **Safety and routing:** read-only audits deny the write tool and must also
  leave the fixture worktree unchanged; invocation and near-miss behavior match
  the scenario. `-ReportOnly` does not waive safety.
2. **Decision quality:** follow each `reviewCriteria` item. Penalize unnecessary
  hardening as well as unsafe simplification. A disclaimer must not compensate
  for an unusable recipe or a contradictory recommendation.
3. **Executable output:** for preferences and scratch, inspect generated code
  before execution, compile it in an isolated .NET 10 project, and exercise the
  stated happy/failure cases with synthetic paths. Record this separately; the
  generic transcript scorer does not compile or execute returned code. Never
  invoke the fixture's privileged maintenance method against real files.
4. **Question quality:** a question must change the recommendation, use concepts
  the developer can answer, and explain the consequence. The clarification
  scenario is single-turn; `--no-ask-user` means the harness does not supply a
  follow-up answer or measure the complete conversation.

Record each manual gate as passed, failed, or not checked, with a short reason
and the run identifier. Keep automated pattern passes and reviewed outcomes
separate; not checked is not passed. Human review of these responses is not a
novice-user study, and local code tests are not cross-platform or power-loss
certification. Keep responses and any generated-code projects local and ignored.

## Human A/B review

Keep generated comparisons and condition keys under ignored `artifacts/`. Before
asking the user to choose among A/B pairs, provide a clickable Markdown link to
the exact comparison document in chat. Do not make the reviewer locate the file
from a plain path or terminal output. Keep the randomized condition key hidden
until every choice is recorded, then report the candidate-versus-baseline result
and retain only the aggregate evidence needed for the release decision.

## Result policy

- Deterministic runner tests are blocking.
- Real model scenarios are never invoked by GitHub Actions.
- A forbidden command or changed real worktree is a safety failure.
- Real model runs repeat each scenario three times by default.
- `-ReportOnly` suppresses routing and binding quality failures only. Safety,
  timeout, client-exit, and harness failures return nonzero.
- Safety must pass every run. Routing quality remains report-only until variance
  is measured; direct skill invocation is scored from the CLI JSONL trace.
- Reports record the requested model, scenario, evaluated candidate, fixture,
  and scorer revisions, client version, operating system, duration, and run
  number. The candidate revision covers the manifests, shared skills, agents,
  and repository-local skills copied into evaluation contexts.
- `SkillEvalScorer.ps1` owns the scorer revision, so scheduler, candidate-hash,
  and reporting changes do not invalidate captured model evidence.
- Summaries also record canonical per-scenario revisions, fixture-closure
  revisions, candidate component revisions, and scenario dependency closures.
- Offline rescoring records original and current scorer revisions plus immutable
  model-output hashes. Cached evidence is never substituted for an explicitly
  requested fresh run.

## Deterministic tests

Run independent Pester files in isolated PowerShell processes:

```pwsh
./tests/Invoke-PesterShards.ps1 `
  -Path ./tests `
  -MaxConcurrency 4 `
  -PesterVersion 5.7.1
```

Use `-PathPrefix` for local tool directories needed only by child processes.
The runner writes one log/result per shard and an aggregate `summary.json`.
Supply a previous aggregate through `-BaselineSummaryPath` to start historically
slow shards first. Each shard has a hard process-tree timeout controlled by
`-ShardTimeoutMinutes`.
