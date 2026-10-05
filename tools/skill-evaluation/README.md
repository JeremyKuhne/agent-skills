# Skill content evaluation

This .NET 10 CLI validates content profiles, snapshots declared artifacts, and
checks literal Markdown and ledger contracts. Those capture/rescore paths remain
deterministic and do not invoke a model. A separate manual `ground` command
supports pinned CPU diagnostics for explicit development probes. Candidate and
judge inference are not implemented. Literal or raw-classifier passes never
establish useful-output qualification.

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
Grounding contract tests use synthetic assets and deterministic backend scores,
not learned inference. The separate
[ONNX project](SkillEvaluation.Onnx/SkillEvaluation.Onnx.csproj) pins ONNX Runtime
1.30.0 and Microsoft.ML.Tokenizers 2.0.0; the core stays inference-independent.
Native/learned readiness still requires owning-host evidence and approved runs.
The adapter selects one native `dotnet` application in discovery order, including
hosts where several PATH entries resolve the same command.
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
  Non-fake sources require a valid executable hash and the JSON Boolean
  `CopilotExecutableEvidenceVerified: true`. Missing, false, or mistyped
  verification is an infrastructure failure.
- `validate-review-packets` validates development controls, pinned rubric
  closure, exact evidence, declared literal results, and paired single edits.
  Exit 0 means preparation is valid, not that proposed labels are human truth.
- `export-review-packets` writes a separate JSON and Markdown review packet
  with rendered inputs, applicable criteria, proposals, and UTF-16 source spans.
  The source bank remains unchanged; an existing nonempty output is rejected.
- `validate-grounding-assets` checks a local
  [asset manifest](../../evals/schemas/grounding-assets.v1.json), owned paths,
  immutable source declarations, exact byte lengths, and raw SHA-256 pins.
  It does not download assets, tokenize, or run a model.
- `validate-grounding-review` checks the completed review document's
  [grounding projection](../../evals/schemas/grounding-review-projection.v1.json)
  against the source bank. It preserves human decisions separately from
  proposals and performs no inference.
- `ground` requires explicit `--report-only true`, locally provisioned pinned
  assets, a complete separate review record, and a disjoint output directory.
  It preflights every declared pair before dispatching any classifier input,
  then writes JSON/Markdown
  [diagnostics](../../evals/schemas/grounding-diagnostic.v1.json).
  Missing, malformed, changed, or overlength input fails explicitly with exit 3.

The PowerShell semantic entry point preserves CLI exits 0 through 3 for valid summaries.
Setup and process failures, missing or malformed summaries, and unexpected
child exits write a diagnostic to stderr and exit 3 without success output.

Generative judging is not implemented or silently simulated. The manual
grounding command does not grant classifier calibration or inference approval.

## Manual CPU grounding diagnostics

The bundled [NLI profile](../../evals/models/nli-deberta-v3-base.v1.json)
contains only public metadata and pins, not weights. It names the
`cross-encoder/nli-deberta-v3-base` revision
`6c749ce3425cd33b46d187e45b92bbf96ee12ec7`, its declared Apache-2.0 source,
the upstream floating-point ONNX export, SentencePiece/canonical tokenizer
files, and supporting configurations/card. Quantized exports and moving
aliases are not interchangeable with this profile.

Provision the exact files locally, verify their licensing, and keep them out
of the repository. There is no downloader or automatic fallback. Copy the
bundled declaration into that owned asset directory; paths can be relocated,
but role, byte, source, and hash identities must still match the supported
profile.

For example, after provisioning the two ignored input directories:

```pwsh
$assetRoot = '.\artifacts\grounding-assets'
$reviewRoot = '.\artifacts\human-review'
Copy-Item -LiteralPath .\evals\models\nli-deberta-v3-base.v1.json -Destination (Join-Path $assetRoot 'runtime-profile.json')
dotnet $cli validate-grounding-assets --asset-root $assetRoot --manifest runtime-profile.json
dotnet $cli validate-grounding-review --repo-root . --packets .\evals\fixtures\output-quality\review-packets.v1.json --review-owner $reviewRoot --review human-review.json
```

Only after separate approval of exact inference terms:

```pwsh
$diagnostics = Join-Path ([IO.Path]::GetTempPath()) "skill-grounding-$([guid]::NewGuid().ToString('N'))"
dotnet $cli ground --repo-root . --packets .\evals\fixtures\output-quality\review-packets.v1.json --asset-root $assetRoot --manifest runtime-profile.json --review-owner $reviewRoot --review human-review.json --output-directory $diagnostics --report-only true
```

The native backend uses maintained SentencePiece segmentation, exact
`[CLS] premise [SEP] claim [SEP]` structure, canonical attention/segment IDs,
and a complete 512-token limit. All pairs are tokenized and checked before
the lazy inference session opens. Inputs are never silently truncated or
skipped. The pinned graph exposes `input_ids` and `attention_mask`, with
contradiction/entailment/neutral label order. CPU execution is sequential,
batch size 1, with one intra/inter-op model thread.

Asset, source-bank/profile, and review revisions are checked before and
after computation. The grounding revision binds those inputs, the actual
backend/dependency/native-binary identity, platform/runtime, and complete
preprocessing tensors. Exact raw-score ties remain unassessed instead of
selecting an arbitrary verdict. Nonfinite or malformed scores are errors.
The tokenizer package pin is checked against its informational/product version;
its intentionally stable assembly binding version is not the package version.

Only declared development claim/fact probes are evaluated. This is not
automatic sentence extraction, complete prose grounding, required-claim
coverage, omission detection, or a hostile-script sandbox. Source facts
retain evidence state and authority kind even though the classifier consumes
their text; model confidence cannot override those metadata or human judgments.

The completed human record is treated as a local declaration, not a signature
or authenticated calibration certificate. The adapter validates its grounding
projection, exact bank/artifact/claim/fact identities, timestamps, and complete
unique probe labels; documentary and rubric bookkeeping outside that projection
is not independently certified. Completeness counters require positive Int32
JSON number representations; overflow and decimal/exponent forms fail explicitly.
Synthetic test reviewers/backends are visibly marked in diagnostic evidence.

Complete pairs require at least one premise token and one claim token before
their separators. Malformed late pairs reject the entire cohort before any
prediction. Known native-loader failures retain infrastructure exit 3 and their
underlying diagnostic, including CLR type-initialization wrappers; unrelated
initialization defects are not silently classified as native-loader failures.

Every result remains `qualityStatus: pending`, `usefulOutcome: pending`, and
`calibrationStatus: pending`, with zero useful passes. Agreement with reviewed
development controls is diagnostic, not held-out accuracy. Existing captured
results, their safety status, and the deterministic semantic replay path are
not rewritten or automatically connected to this command. No learned call was
added to CI.

## Development review packets

The [packet bank](../../evals/fixtures/output-quality/review-packets.v1.json)
contains eight distinct base scenarios, four per pilot family, and eight
single-defect twins. Its [schema](../../evals/schemas/review-packets.v1.json)
permits only development data with assistant-proposed labels. The public bank
contains no human approval or calibration certificate; completed human
decisions must be supplied as a separate record. It is not a sealed acceptance set.
Nested profiles are validated from their original JSON, not reconstructed
typed values. Missing required fields, invalid enum casing, and forbidden
null properties are rejected rather than silently becoming verified facts
or valid defaults.

The new [rubric revision](../../evals/rubrics/technical-writing.v2.json) adds
source-backed task fidelity. Existing capture scenarios still pin revision 1:
no current pilot profile, historical criterion, or regex was rewritten.
These eight development inputs are outside the scheduled scenario inventory.

Controls cover invented validation and completion, changed test counts,
certainty upgrades, omitted validation gaps, invented ownership, wrong force,
and omitted mechanism. Seven defective twins still pass their literal checks.
The changed-count control retains the original number inside a quoted code
example; token presence alone cannot establish the reported result.

```pwsh
dotnet $cli validate-review-packets --repo-root . --packets .\evals\fixtures\output-quality\review-packets.v1.json
$review = Join-Path ([IO.Path]::GetTempPath()) "skill-quality-review-$([guid]::NewGuid().ToString('N'))"
dotnet $cli export-review-packets --repo-root . --packets .\evals\fixtures\output-quality\review-packets.v1.json --output-directory $review
```

The initial review is the plan's bounded 16-artifact, 30-60 minute session.
Record actual minutes, corrections, source-backed reasons, and unresolved
labels separately. A successful export records no human review and cannot
promote a proposed pass to useful success.

Exact unique quotations resolve to UTF-16 offsets and one-based lines;
optional supplied spans must match. Omission evidence identifies the whole
artifact instead of inventing a quote. Twins share unchanged inputs, belong to
one base-case cluster, and reproduce exactly one declared edit. Their declared
hard-item flips must match, with unrelated verdicts unchanged.

Fourteen explicit claim/fact probes are declared for separately approved CPU
diagnostics. They are not an exhaustive prose-grounding pass. Three-way proposals distinguish
entailment, contradiction, and neutrality; support-only scores cannot be
converted into contradiction verdicts.

The export intentionally exposes proposed labels for human review. Do not feed
it to a blinded judge or count it as reviewed held-out calibration. Source,
profile, rubric, runtime, and engine-binary revisions bind the preparation
receipt. It performs no classifier or judge inference.

## Immutable artifacts and revisions

The existing `ModelOutputRevision` algorithm is unchanged. File artifacts have
their own capture-time manifest revision and byte hashes. File snapshots are
UTF-8, optionally with a BOM; unsupported encodings fail explicitly. Paths
must remain within the owned workspace and cannot traverse links/reparse points.
The owned root, its ancestors, and each relative-path segment are checked.
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
