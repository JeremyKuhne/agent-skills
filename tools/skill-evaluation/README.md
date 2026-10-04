# Deterministic skill content evaluation

This .NET 10 CLI validates content profiles, snapshots declared artifacts, and
checks literal Markdown and ledger contracts. It performs no classifier,
candidate-model, or judge inference. A literal pass is not a useful-output pass:
grounding and rubric judgments remain pending.

## Build and test

Restore and build the [CLI project](SkillEvaluation.Cli/SkillEvaluation.Cli.csproj)
before running a scenario with `contentEvaluation`:

Repository-owned projects inherit Touki 0.10.0 and Touki analyzers 0.11.1 from
[Touki.CSharp.props](../Touki.CSharp.props). All eight opt-in rules run as
warnings with default options; repository warnings-as-errors promotes them
during builds. The header comes from [.editorconfig](../../.editorconfig).

The published 0.11.1 analyzer includes the TOUKI0028 conditional-access recursion
fix. Builds and tests use that public package directly; no local analyzer
override is required.

```pwsh
dotnet restore .\tools\skill-evaluation\SkillEvaluation.Cli\SkillEvaluation.Cli.csproj
dotnet build .\tools\skill-evaluation\SkillEvaluation.Cli\SkillEvaluation.Cli.csproj --configuration Release --no-restore
```

The [managed test project](../../tests/skill-evaluation/SkillEvaluation.Tests.csproj)
also builds the independent process-control fixture used by the Pester tests:

```pwsh
dotnet restore .\tests\skill-evaluation\SkillEvaluation.Tests.csproj
dotnet test --project .\tests\skill-evaluation\SkillEvaluation.Tests.csproj --configuration Release --no-restore
.\tests\Invoke-PesterShards.ps1 -Path .\tests\evals
```

Managed tests own profiles, schemas, Markdown, snapshots, and quality states.
Pester owns the PowerShell/native-process boundary: exact arguments, separate
streams, nonzero exits, timeout cleanup, capture integration, and replay.
CI exercises those lanes on Windows and Linux ARM64. A skipped platform control
does not prove that behavior; Windows junction and Unix symlink controls remain
separate.

## Content profiles

The optional `contentEvaluation` field uses
[content-profile.v1.json](../../evals/schemas/content-profile.v1.json).
Existing schema-version-1 scenario documents and literal decision cases remain
compatible. Profiled scenarios are strictly prepared before capture; an invalid
profile or unavailable built evaluator blocks execution.

Facts live once in `suppliedFacts`, with stable IDs, evidence state, authority
kind, and `provenance: scenario-input`. The prompt must contain exactly one
`{{suppliedFacts}}` marker. Preparation renders that authoritative fact set,
rather than keeping a second copy of facts in the prompt. Required-claim literal
tokens must also exist in their referenced facts.

Profiles declare target IDs, final-message or workspace-relative file sources,
required/forbidden claims, literal checks, optional ledger mode, and pinned
rubric references. The initial families are PR descriptions, review comments,
and closed decisions. No source-text example becomes a universal template.

[technical-writing.v1.json](../../evals/rubrics/technical-writing.v1.json)
contains source-backed checklist items. Rubric and source revisions hash UTF-8
text with CRLF normalized to LF, making pins stable across checkouts. Changing
the source, a quote, or the rubric without updating its pin fails preparation.
The assistant-authored checklist is not a human-labeled calibration set.

The two [pilot profiles](../../evals/scenarios/technical-writing.json) retain
their original coarse response predicates. No semantic regex has been retired.
Claims and rubric items are still unassessed; subjective reader-cost items are
advisory rather than hard gates.

## CLI contracts

All options are named, require one value, and reject duplicates or unknown
names. Success-stream output is JSON; invocation/infrastructure errors go to
stderr with exit 3.

```pwsh
$cli = '.\tools\skill-evaluation\SkillEvaluation.Cli\bin\Release\net10.0\SkillEvaluation.Cli.dll'
dotnet $cli validate-profile --repo-root . --scenario .\evals\scenarios\technical-writing.json
dotnet $cli lint-artifact --repo-root . --scenario .\evals\scenarios\technical-writing.json --scenario-id technical-writing-artifact-pull-request --target-id body --input .\evals\fixtures\output-quality\pr-description.md
```

- `prepare` and `validate-profile` validate profile closure and return resolved
  prompts plus input/profile revisions; they do not invoke a model.
- `lint-artifact` evaluates only the declared target's literal requirements,
  including required literal tokens. Exit 0 means those checks completed; its
  JSON explicitly leaves usefulness pending.
- `check-ledger` requires a configured ledger target and checks parsed IDs,
  evidence/authority states, duplicate entries, and unknown-fact coverage. A
  prose ledger must be the final JSON fence. Ledger consistency never attests
  prose support.
- `capture` is the runner's capture-time adapter. It writes new snapshots and
  the [artifact manifest](../../evals/schemas/artifact-manifest.v1.json);
  existing evidence is never overwritten.
- `rescore` is the
  [semantic entry point's](../../evals/Invoke-SkillEvalSemantic.ps1) adapter.
  It verifies a single-suite source summary and writes a separate derived tree.

`ground` and generative judging are not implemented or silently simulated.
They require the separately gated classifier/calibration work.

## Immutable artifacts and revisions

The existing `ModelOutputRevision` algorithm is unchanged. File artifacts have
their own capture-time manifest revision and byte hashes. File snapshots are
UTF-8, optionally with a BOM; unsupported encodings fail explicitly. Paths
must remain within the owned workspace and cannot traverse links/reparse points.
These checks are scoped artifact handling, not a hostile-script sandbox.

The terminal `assistant.message` is the final assistant event, even if it is
empty or says "Done." Earlier favorable content is never substituted. File
targets evaluate captured file bytes, not a closing acknowledgment or the
surviving mutable workspace file.

The input revision binds prompt, facts, artifact kind/targets, and ledger mode.
Capture compares it with the prepared prompt's revision, and replay checks it
against both the source run and manifest. Prompt-only drift cannot be accepted
as evidence for a task that was never sent to the model.
The profile revision additionally binds claims, literal checks, and rubric
closure. Regrading may change the latter, recording source/current revisions;
it cannot change captured facts or task input. Evidence spans index UTF-16 code
units in decoded source text and retain a one-based line number.

The [semantic record](../../evals/schemas/semantic-record.v1.json) reports
literal, semantic, and useful-outcome states separately. Derived summaries keep
every selected attempt and its original result, with explicit per-run
infrastructure errors. Unprofiled legacy runs remain pending. A legacy file
artifact without capture-time provenance cannot be certified retrospectively.

Exit precedence remains safety 2, infrastructure 3, quality 1, then 0.
`-ReportOnly` suppresses quality blocking only. Pending judgments are never
counted as useful passes, even when the command exits 0. Original `Passed`,
`SafetyPassed`, and scorer revisions remain untouched.
