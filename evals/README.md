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

`scenarios/manage-skills.json` covers project integration before vendoring into
an existing repository. Its synthetic workspace contains a differently named
local skill, canonical and generated agent guidance, documentation-derived
bindings, and an unrelated keyword match. The scenario requires a read-only
classification, proposed overlay, separate deduplication approval, and the
optional-record question.

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
