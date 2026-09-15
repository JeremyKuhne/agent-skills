# PowerShell test ownership inventory

- Status: ownership dispositions and bounded canary accepted on 2026-09-15;
  awaiting merge
- Inventory baseline: `main` at
  `021330653daea94fae0c5b9389e9e9c7cb1218ea`
- Scope: repository Pester and MSTest suites, deterministic validators,
  integration entry points, generated validation surfaces, and established
  external validators
- Purpose: choose the test or validation lane from the subject, implementation
  owner, and independent oracle rather than from the current file extension
- Non-goal: this inventory migrates no test, validator, or production code

The engineering plan's older `9c0f860` planning baseline identifies where the
program began. This inventory intentionally snapshots the later `main` commit
that contains the merged plan reset. No implementation milestone landed between
those points; the different SHAs represent chronology, not conflicting trees.

## Accepted decisions

1. Use the ownership dispositions below as the P0r direction.
2. Use the exact six-test `TrustedFileWrites` contract as the managed canary.
3. Complete P0r when this record merges, then begin P0c, the portable
  engineering course-correction skill. Do not implement the canary until P0c
  lands.

The maintainer accepted these decisions on 2026-09-15. The inventory records
that decision; it does not implement a migration.

## Method and counts

PowerShell's parser identified real Pester command ASTs, excluding `Describe`
and `It` text embedded in synthetic fixture strings. Managed declarations were
counted from source and checked against actual test discovery.

| Surface | Observed count |
| --- | ---: |
| Tracked Pester files | 16 |
| Real `Describe` blocks | 38 |
| Real `Context` blocks | 30 |
| Static `It` declarations | 344 |
| Managed test projects | 1 |
| MSTest classes | 4 |
| Static MSTest methods | 29 |
| Discovered managed tests | 36 |
| Generated Pester test templates | 6 |
| Generated validator or smoke scripts | 3 |
| Generated workflow templates | 8 |

Static declaration counts are inventory checks, not executed-test counts.
Parameterized Pester and MSTest cases expand during discovery.

The eight workflow templates comprise three under the repository-local
create-skill-repo workflow and five under the portable engineering-baseline
skill.

| Pester file | Describe | Context | Static It |
| --- | ---: | ---: | ---: |
| `tests/create-skill-repo/CreateSkillRepository.Tests.ps1` | 2 | 0 | 17 |
| `tests/csharp-nullability-remediation/NullabilityRemediation.Tests.ps1` | 1 | 0 | 11 |
| `tests/dotnet-file-creation/FileCreation.Tests.ps1` | 1 | 7 | 43 |
| `tests/engineering-baseline/ScaffoldDefaults.Tests.ps1` | 1 | 0 | 1 |
| `tests/engineering-baseline/Update-Scaffold.Tests.ps1` | 2 | 0 | 6 |
| `tests/engineering-baseline/WorkflowTemplates.Tests.ps1` | 1 | 0 | 6 |
| `tests/evals/SkillEval.Tests.ps1` | 7 | 0 | 59 |
| `tests/manage-skills/Install-UserSkill.Tests.ps1` | 2 | 0 | 26 |
| `tests/manage-skills/Validate-Skills.Tests.ps1` | 1 | 13 | 62 |
| `tests/repository/AgentFiles.Tests.ps1` | 3 | 0 | 13 |
| `tests/repository/InstalledSkills.Tests.ps1` | 1 | 0 | 5 |
| `tests/repository/RepositoryContracts.Tests.ps1` | 6 | 0 | 43 |
| `tests/repository/SyntheticConsumer.Tests.ps1` | 2 | 0 | 3 |
| `tests/user-voice/UserVoice.Tests.ps1` | 6 | 0 | 19 |
| `tests/windows-acls/WindowsAcl.Tests.ps1` | 1 | 10 | 28 |
| `tests/winui-win32-hosting/Priority0.Tests.ps1` | 1 | 0 | 2 |
| **Total** | **38** | **30** | **344** |

## Ownership rules

- **Pester** owns behavior whose subject is PowerShell: parameter binding,
  functions and modules, streams, error records, mocks, PowerShell AST
  contracts, and PowerShell process entry points.
- **MSTest** owns managed assets, typed repository policy, managed state
  machines, and BCL or operating-system facts consumed as .NET guidance.
- **Established validators** own standard syntax and format contracts before a
  repository test reimplements them. Repository-specific policy may wrap their
  parsed output but must not emulate their grammar.
- **Direct integration lanes** own real compiler, CLI, package, platform, and
  generated-consumer behavior. A unit framework may launch the lane, but the
  external system remains the oracle.
- **Split** means a current block combines subjects with different owners. It is
  not permission to duplicate the same assertion in two frameworks.
- Pester and MSTest are harnesses, not oracles. An oracle must come from an
  accepted contract, specification, schema, maintained parser or validator,
  deliberately independent fixture, verified prior behavior, or observed
  platform result.

Each target cell below uses this order: natural lane; parser, API, or tool;
coverage domain; disposition and migration risk.

## Current Pester ownership

### PowerShell implementation and orchestration

| ID | Current block | Subject and implementation owner | Oracle and current evidence | Target |
| --- | --- | --- | --- | --- |
| PS01 | `Update-ScaffoldVersions policy helpers` | `Update-ScaffoldVersions.ps1` license allowlist function | Accepted SPDX subset and table-driven positive/negative values; broader SPDX grammar is not specified | Pester; function call; PowerShell coverage; keep, but replace the parser if its grammar expands (low) |
| PS02 | `Update-ScaffoldActions policy helpers` | `Update-ScaffoldActions.ps1` action-path, version, and jq quoting helpers | GitHub action path form, `System.Version` ordering, and literal jq escape contract | Pester plus a focused jq process check; PowerShell coverage; keep and strengthen (low) |
| PS03 | `New-DotnetRepo defaults` | PowerShell script parameter default | Accepted starting-skill list inspected through the PowerShell AST | Pester and PowerShell AST; PowerShell metadata coverage; keep (low) |
| PS04 | `Get-GitRepositoryInspection` | `Install-UserSkill.ps1` classification of Git diagnostics | Accepted Git exit/diagnostic classes, including negative cases | Pester mocks plus focused real-Git cases; PowerShell coverage; keep (low) |
| PS05 | `Install-UserSkill.ps1` | PowerShell installation, privacy boundary, atomic replacement, and host routing | Filesystem state, environment restoration, accepted privacy policy, and mocked external responses | Pester for script behavior plus a separate real-CLI integration lane; PowerShell coverage; split external behavior, otherwise keep (medium) |
| PS06 | `Synthetic consumer provenance` | `Get-GitHubSkillRef` in `Invoke-SyntheticConsumer.ps1` | Fixture Git repository and canonical tag/SHA forms | Pester with real Git; PowerShell coverage; keep (low) |
| PS07 | `Synthetic consumer output ownership` | PowerShell entry-point rejection of an existing output directory | Nonzero exit and unchanged sentinel filesystem state | Pester fresh process; PowerShell coverage; keep (low) |
| PS08 | `Skill evaluation evidence scoring` | PowerShell scoring and safety policy in `SkillEval.psm1` | Accepted response/evidence state table and synthetic logs | Pester; module functions; PowerShell coverage; keep after separating schema parsing (medium) |
| PS09 | `Skill evaluation command shims` | PowerShell-generated command wrappers and concurrent evidence logging | Process output, serialized log records, and no-mutation help/dry-run cases | Pester fresh processes; PowerShell/process coverage; keep (medium) |
| PS10 | `Skill evaluation exit policy` | PowerShell result-to-exit decision function | Explicit quality, safety, and infrastructure state table | Pester; pure function; PowerShell coverage; keep (low) |
| PS11 | `Skill evaluation worker allocation` | PowerShell work-distribution algorithm | Explicit worker budget and workload result | Pester; pure function; PowerShell coverage; keep and add boundary cases (low) |
| PS12 | `Skill evaluation runner` | PowerShell suite orchestration, candidate identity, and injected executor | File hashes, isolated homes, executor receipts, and mutation negative case | Pester fresh processes; PowerShell/process coverage; keep (medium) |
| PS13 | `Evidence report validation` | `Test-UserVoiceEvidenceReport.ps1` command behavior | Accepted report contract and adversarial transformed reports | Pester for command behavior; Markdown parser or narrowed literal contract; PowerShell coverage; split parser policy (medium) |
| PS14 | `Private profile scaffolding` | User-voice PowerShell scaffold/build scripts | Filesystem state, Git state, consent/audit decisions, and failure non-mutation | Pester fresh processes; PowerShell coverage; keep, with schemas separated (medium) |
| PS15 | `Private repository scanning` | `Test-UserVoiceRepository.ps1` Git/privacy checks | Fixture history, repository boundaries, mocked GitHub visibility, and hook state | Pester plus real-Git integration; PowerShell coverage; keep, split real service behavior (medium) |
| PS16 | `Existing skill migration` | `New-UserVoiceMigration.ps1` non-mutating staging | Before/after source hashes and generated manifest | Pester fresh process; PowerShell coverage; keep, parse generated schemas independently (low) |
| PS17 | `New-SkillRepository` script behavior | `New-SkillRepository.ps1` parameters, rejection, and generation transaction | Accepted input table, non-mutation failures, and generated filesystem state | Pester for PowerShell behavior; PowerShell coverage; split generated artifacts and external tools (large) |

### Managed assets and platform facts currently under Pester

None of these groups assert PowerShell semantics. PowerShell supplies setup,
skips, exception unwrapping, and assertions only.

For MF01 and MF02, the independent contract is the skill's documented safety
behavior plus externally observable filesystem state; the C# source is the
implementation, not the expected-value source. For MF03 through MF07, published
.NET API contracts and host observations are the oracle. Platform observations
remain scoped to the hosts on which they were measured, as recorded in
`skills/dotnet-file-creation/references/research.md`; they are not generalized
to unmeasured hosts.

| ID | Current context or block | Subject and implementation owner | Oracle and current evidence | Target |
| --- | --- | --- | --- | --- |
| MF01 | `Ordinary application preferences` | `OrdinaryPreferences.cs` | Managed exceptions, filesystem state, staging cleanup, Unix modes | MSTest with `System.IO`; managed coverage; migrate (medium) |
| MF02 | `Trusted-parent recipes` | `TrustedFileWrites.cs` | Managed exceptions, path result, file contents, staging cleanup, mode/ACL behavior | MSTest with `System.IO`; managed coverage; migrate, proposed canary subset (medium) |
| MF03 | `Temporary state` | .NET temporary-directory and file APIs | Observed path, file length, and host mode bits | MSTest platform facts; no repository-code coverage; migrate (low) |
| MF04 | `Explicit permissions` | .NET Unix mode APIs | Platform exceptions and observed mode round trips | MSTest platform facts; no repository-code coverage; migrate (medium) |
| MF05 | `Creation semantics that are the same everywhere` | .NET path and file APIs used by the skill guidance | BCL results and real filesystem/junction behavior | MSTest platform facts; no repository-code coverage; migrate (low) |
| MF06 | `Creation semantics that differ by platform` | OS file sharing, deletion, case, and attribute behavior | Real kernel/filesystem outcomes on each host | MSTest platform matrix; no repository-code coverage; migrate (medium) |
| MF07 | `Where the runtime puts per-user and machine state` | .NET special-folder behavior | Fully qualified existing paths and Linux XDG overrides | MSTest platform facts; no repository-code coverage; migrate (low) |
| WA01 | `Elevation baseline` | Windows test-host token and privilege state | Windows token APIs and CI host state | MSTest Windows integration; no repository-code coverage; migrate as lane guard (medium) |
| WA02 | `Descriptor-bearing creation` | .NET filesystem and registry ACL APIs | Resulting descriptor/owner and existing-object preservation | MSTest Windows integration; managed/platform coverage; migrate (medium) |
| WA03 | `DACL representation` | `RawSecurityDescriptor` null versus empty DACL | Binary and SDDL round trip | MSTest; managed platform facts; migrate (low) |
| WA04 | `Ownership is the part an unelevated caller cannot forge` | Windows owner-assignment behavior | Resulting owner SID and privilege outcome | MSTest Windows integration; platform facts; migrate (medium) |
| WA05 | `A DACL on its own proves nothing` | Windows owner rights despite a restrictive DACL | Real create/rewrite access result | MSTest Windows integration; platform facts; migrate (medium) |
| WA06 | `ACE order changes effective access` | Windows authorization order | Real access result and descriptor order | MSTest Windows integration; platform facts; migrate (medium) |
| WA07 | `Descriptor evaluation and exact operations` | `authz.dll`, filesystem, and registry exact-right operations | Native granted mask and managed operation outcome | MSTest with pinned P/Invoke declarations; platform facts; migrate (large) |
| WA08 | `Directory rights govern the namespace, not just the object` | Windows parent/child delete rights | Real namespace deletion result | MSTest Windows integration; platform facts; migrate (medium) |
| WA09 | `Inheritance` | Windows ACL inheritance and protection | Enumerated ACEs, flags, and parent/child outcomes | MSTest Windows integration; platform facts; migrate (large) |
| WA10 | `Reparse points` | Windows junction and descriptor behavior | Reparse metadata, descriptors, and real deletion outcome | MSTest Windows integration; platform facts; migrate (medium) |
| WU01 | `WinUI Win32 hosting Priority 0 assets`: source set | Minimal-host asset manifest | Accepted generated/shipped file manifest | Managed artifact contract or project item validation; none; replace Pester assertion (low) |
| WU02 | Same block: x64/ARM64 build | Minimal WinUI host project | `dotnet build` exit and artifacts on Windows | Direct Windows build matrix; external behavior; remove Pester wrapper after parity (medium) |

### Structured repository, artifact, and documentation policy

| ID | Current block | Subject and implementation owner | Oracle and current evidence | Target |
| --- | --- | --- | --- | --- |
| RP01 | `Agent instruction mirror` | `Validate-AgentFiles.ps1` transformation | `AGENTS.md` source, explicit link-rewrite contract, byte parity, negative whitespace fixtures | Pester while implementation is PowerShell; PowerShell coverage; keep. Not a managed canary (low) |
| RP02 | `Agent customization links` | `Test-AgentFileLinks.ps1` behavior | Existing/missing fixture targets and artifact boundary | Pester for script behavior plus lychee parity study; PowerShell coverage; keep or replace after proven overlap (medium) |
| RP03 | `Agent file CI contract`: workflow assertions | Repository workflow policy | Accepted workflow object model; current regex is implementation-shaped | Managed YAML parser or established workflow validator, absent today; no PowerShell coverage; migrate (medium) |
| RP04 | Same block: plugin client helpers | `Invoke-PluginSmoke.ps1` PowerShell functions and entry point | Version fixture, native header/mode, and real Copilot install outcome | Pester for pure PowerShell helpers plus direct CLI smoke; split (medium) |
| RP05 | `Installed skill artifacts`: mirror normalization | `SkillArtifactTestHelpers.ps1` PowerShell functions | Source/installed semantic equality and permitted provenance fields | Pester while helper is PowerShell; PowerShell coverage; keep, replace regex parsing when policy moves (medium) |
| RP06 | Same block: required closure | Test-local recursive helper, not production behavior | The test's own fixture and implementation; no independent production subject | Delete self-test or move closure into the owning validator, then test there (medium) |
| RP07 | Same block: link boundary | Test-local Markdown-link helper | The test's own regex plus filesystem fixture; independent grammar oracle missing | Replace with owning parser/validator; no coverage target until implementation exists (medium) |
| RP08 | Same block: install every core | Real `gh skill install` and repository validator behavior | Installed artifact, provenance, declared closure, and link state | Direct integration lane; external/generated behavior; retain after removing helper self-tests (medium) |
| RP09 | `Pester shard runner` | `Invoke-PesterShards.ps1` and Pester worker/result protocol | Accepted state table, child exit, summary JSON, timeout, and process outcome | Pester fresh-process tests while runner is PowerShell; PowerShell coverage; keep (large) |
| RP10 | `Skill catalog contracts` | Catalog generator, portfolio metadata, relationship graph, and privacy policy | Source skills, accepted metadata vocabulary, graph rules, generated bytes | Split: Pester for PowerShell generator; skills-ref for portable format; managed repository policy for graph/privacy (large) |
| RP11 | `Agent contracts` | Portable agent inventory and metadata | Accepted agent schema, catalog, and recognized tool identifiers | Managed Markdown/frontmatter validator or established agent validator; none; migrate (medium) |
| RP12 | `Distribution manifest contracts` | `plugin.json`, marketplace JSON, and `.mcp.json` | JSON schemas, exact component paths, version identity, and tag context | MSTest with `System.Text.Json` plus direct tag integration; none/managed policy; migrate (medium) |
| RP13 | `Workflow pin contracts` | Active and generated GitHub Actions references | Parsed `uses` nodes, immutable SHA policy, and readable version comments | Managed YAML parser or established workflow validator; none; migrate (medium) |
| RP14 | `Workflow execution contracts` | Trigger, lane, artifact, and no-model-run policy | Accepted workflow object model and CI observation | Managed YAML parser plus direct CI evidence; none/external; migrate and split (large) |
| RP15 | `Validate-Skills.ps1`: driver and quiet behavior | PowerShell command aggregation, output, and exit behavior | Fixture directories, stream output, and process exit | Pester; PowerShell coverage; keep (low) |
| RP16 | Same file: portable frontmatter shape, names, and descriptions | Agent Skills format | `skills-ref@0.1.5` and the published format contract; custom parser duplicates a subset | Replace duplicate grammar checks with skills-ref; test only repository additions separately (large) |
| RP17 | Same file: portfolio metadata and overlays | Repository portfolio and binding policy | Approved vocabulary, source graph, core/pin identity | Managed schema/graph validator; managed coverage; migrate (medium) |
| RP18 | Same file: list indentation, entities, XML-like tags, and length | Repository readability policy | `.markdownlint.jsonc` where expressible; explicit literal policy otherwise | Established Markdown parser/linter first; narrow residual validator; no PowerShell coverage by default (large) |
| RP19 | `Cost-aware scaffold workflow contracts` | Generated GitHub Actions semantics | Accepted trigger/job/permission object model; regex text is not an oracle | Managed YAML parser or established workflow validator, absent today; no PowerShell coverage; migrate (medium) |
| RP20 | `C# nullability remediation skill contract` | Human guidance and C# examples | Portable artifact shape, compiled examples, links, and model evaluation; keyword presence is not semantic evidence | skills-ref, Markdown/link tools, compiler tests, and evaluations; delete redundant prose sniffing (medium) |
| RP21 | `Decision interview` | Human-facing repository-creation guidance | Markdown structure, valid links/commands, and behavioral evaluation; current prose substrings are implementation-shaped | Established Markdown/link/shell checks plus evaluations; delete or narrow literal interface checks (medium) |
| RP22 | `New-SkillRepository`: generated artifacts | Rendered JSON, YAML, Markdown, tests, and client layouts | Owning parsers, generated validators, compiler/build, and accepted manifest contract | Structured validators and direct generated-repository canary; external/generated coverage; split from PS17 (large) |
| RP23 | `Skill evaluation scenario contract` | Scenario JSON shape plus domain regex/scoring rules | Versioned scenario schema and domain-approved expected outcomes | Split: JSON schema/MSTest for shape; Pester for PowerShell scoring; managed/external plus PowerShell coverage (large) |
| RP24 | `File I/O behavioral evaluation checks` | Synthetic C# defect reproduction plus response scoring | Compiled synthetic program outcomes and accepted scorer contract | Direct `dotnet` integration for defects; Pester for scorer; split (large) |
| RP25 | `User voice package assets` | Shipped asset manifest and embedded workflow/template structure | Approved package manifest and owning parsers; current hardcoded list is only a snapshot | Managed artifact validator plus YAML/PowerShell parsers; none/managed policy; migrate (medium) |
| RP26 | `Portable workflow acceptance suite` | Bundled `Run-Tests.ps1` integration | Child exit and structured per-test receipt; current success text/count is weak | Direct integration lane; remove redundant Pester wrapper when CI consumes receipt (medium) |

## Existing managed ownership

| ID | MSTest class | Subject and owner | Oracle and evidence | Decision |
| --- | --- | --- | --- | --- |
| MT01 | `AnonymousPipeTests` | Managed anonymous-pipe and child-process behavior | BCL stream state, payload, process exit, and capture limit | Keep MSTest; managed/BCL coverage; cross-platform (medium) |
| MT02 | `PipeFramesTests` | Managed binary frame protocol | Exact bytes, complete payload, exception type, and length bounds | Keep MSTest; managed coverage; strong independent protocol cases (low) |
| MT03 | `NamedPipeEchoTests` | Managed server/client concurrency, timeout, cancellation, and recovery | Payload, task/exception state, and subsequent-client success | Keep MSTest; managed coverage; cross-platform integration (large) |
| MT04 | `ProgramTests` | Managed sample CLI argument contract | Exit code and public stderr forms | Keep MSTest; managed/process coverage; add successful command cases separately (low) |

The current `MSTest.Sdk/4.2.3` project proves that MSTest and Microsoft Testing
Platform are already supported repository infrastructure. It does not imply that
unrelated managed tests belong in the dotnet-pipes project.

## Validator and integration ownership

| ID | Entry point | Subject and oracle | Natural owner and disposition |
| --- | --- | --- | --- |
| VE01 | `tools/Validate-AgentFiles.ps1` | Deterministic mirror transform; `AGENTS.md` and explicit rewrite rules | Keep PowerShell tool and Pester behavior tests while scope stays literal; use a Markdown parser if semantics expand |
| VE02 | `tools/Test-AgentFileLinks.ps1` | Agent-customization link boundaries; real target existence | Keep pending a measured parity comparison with lychee; do not maintain a second Markdown grammar without unique behavior |
| VE03 | `skills/manage-skills/scripts/Validate-Skills.ps1` | Portable format plus repository-only policy | Split: skills-ref owns standard format; managed parser/schema owns repository policy; retain a thin PowerShell entry point only if useful |
| VE04 | `tools/Update-SkillCatalog.ps1` | Generated portfolio matrix; source metadata and byte idempotence | Keep PowerShell generator initially; consume parser-backed normalized metadata and test generator behavior in Pester |
| VE05 | `tests/Invoke-PesterShards.ps1` | Pester discovery, isolation, process timeout, and result state | Keep PowerShell/Pester ownership until the retained-test inventory proves a managed host is warranted |
| VE06 | `tests/plugin/Invoke-PluginSmoke.ps1` | Real plugin install and source/distribution inventory | Direct pinned Copilot CLI integration; Pester only for isolated PowerShell helpers |
| VE07 | `tests/repository/Invoke-SyntheticConsumer.ps1` | Real local/remote skill installation and artifact closure | Direct `gh skill`/Git integration; Pester for PowerShell guards and helper behavior |
| VE08 | `tests/engineering-baseline/Invoke-ScaffoldCanary.ps1` | Generated .NET repository restore, build, test, and pack | Direct `dotnet` integration; Pester only for PowerShell helper behavior |
| VE09 | `evals/Invoke-SkillEvals.ps1`, matrix, and rescore entry points | Manual model execution and deterministic aggregation | Pester for PowerShell orchestration; manual model lane remains separately approved |
| VE10 | Inline release-tag workflow script | Tag syntax and plugin/marketplace version identity | Extract to a typed or narrowly scoped validator; test with `System.Text.Json` and semantic version cases |

### Established validators

| ID | Tool | Owned contract | Repository action |
| --- | --- | --- | --- |
| EX01 | `markdownlint-cli2` | Configured Markdown syntax/style | Keep; do not duplicate configured rules in Pester |
| EX02 | `lychee --offline` | Repository Markdown link resolution | Keep; prove any custom link check's unique artifact-boundary behavior |
| EX03 | `skills-ref@0.1.5` | Portable Agent Skills frontmatter and format | Keep pinned; remove duplicate grammar ownership from repository PowerShell |
| EX04 | .NET compiler, `dotnet test`, and `dotnet pack` | C# compilation, managed tests, and package construction | Keep as direct integration oracles; a Pester wrapper adds no semantic authority |

## Generated consumers

Generated files need the same subject-based ownership as repository files. A
`.Tests.ps1.tmpl` suffix does not make its generated contract PowerShell-native.

| ID | Generated family | Current subject | Decision |
| --- | --- | --- | --- |
| GT01 | `validation/tests/Repository.Tests.ps1.tmpl` | Generated role roots, unresolved tokens, and install state | Split generated PowerShell entry-point behavior from repository/artifact policy; migrate policy with P1c results |
| GT02 | `distribution/{agents,marketplace,mcp,plugin}/tests/*.Tests.ps1.tmpl` | Agent Markdown plus marketplace, MCP, and plugin manifests | Generate managed/parser-backed contract tests or invoke a generated validator; do not retain Pester for JSON/Markdown by default |
| GT03 | `evaluations/tests/EvaluationScenarios.Tests.ps1.tmpl` | Scenario JSON identity and prompt shape | Generate schema-backed validation; retain Pester only for generated PowerShell scorer behavior |
| GT04 | `validation/tools/{Validate-Repository,Test-SkillLinks}.ps1.tmpl` | Consumer metadata and link policy | Keep ergonomic wrappers only around the chosen parser/validator contracts; preserve consumer portability explicitly |
| GT05 | `distribution/marketplace/tests/Invoke-PluginSmoke.ps1.tmpl` | Generated real plugin installation | Keep as direct pinned CLI integration, with isolated helper tests in the implementation language |
| GT06 | Three create-skill-repo workflow templates and five engineering-baseline workflow templates | Generated CI trigger, install, validation, publication, and release semantics | Parse rendered YAML and run generated canaries; source-text regex is insufficient |

## Proposed managed canary

### Recommendation: `TrustedFileWrites` core behavior

The first canary should move a bounded, cross-platform subset of
`tests/dotnet-file-creation/FileCreation.Tests.ps1` into a dedicated MSTest
project that compiles the existing `skills/dotnet-file-creation/assets/TrustedFileWrites.cs`
source. This is a migration, not duplicate permanent coverage.

Why this is the strongest discriminator:

- the production subject is C#, not a PowerShell script;
- MSTest can assert the original exception types directly instead of unwrapping
  `MethodInvocationException` from PowerShell;
- the test project can produce managed coverage for the actual asset;
- the core subset needs no new parser, external CLI, elevation, or service;
- it runs on the same Windows and Linux hosts already used by the repository;
- failure would directly disprove the proposed boundary before broader work.

#### Accepted

- Create one dedicated managed test project for the dotnet-file-creation asset.
- Compile the existing `TrustedFileWrites.cs` in the test project with a linked
  `<Compile Include="../../skills/dotnet-file-creation/assets/TrustedFileWrites.cs" Link="TrustedFileWrites.cs" />`
  item. Do not copy the source or create a speculative production project.
- Migrate exactly these six existing `It` declarations from the
  `Trusted-parent recipes` context:
  - `rejects unsafe application keys before creating a file: <Key>`;
  - `requires a fully qualified parent and does not create missing parents`;
  - `maps a device-like key to a safe leaf and refuses to overwrite it`;
  - `removes scratch on normal disposal`;
  - `publishes a new destination and replaces it without leaving staging files`;
    and
  - `cleans its staging file when the destination cannot be replaced`.
- Remove only those six Pester declarations after managed parity passes. Keep
  every other declaration in the `Trusted-parent recipes` context unchanged
  until a separately approved migration preserves its platform coverage.
- Run the managed cases in required CI jobs on `windows-latest` and
  `ubuntu-24.04-arm`; record exact-head job identities, discovered, passed,
  failed, skipped, and duration counts. Local runs do not satisfy this exit
  evidence.
- Compare implementation size, assertion clarity, defect classes, compiler and
  analyzer diagnostics, runtime, executable coverage visibility, and maintenance
  cost with the previous Pester slice. Record source and test line counts, new
  dependencies and helpers, and any platform-specific setup so the comparison
  is reproducible.

#### Rejected

- Migrating all seven file-creation contexts in the canary.
- Moving any PowerShell implementation test merely to standardize on MSTest.
- Adding a generic process host, coverage merger, repository manifest, YAML
  parser, or shared test framework.
- Keeping duplicate Pester and MSTest assertions after parity.
- Treating successful translation as approval for wholesale migration.

#### Deferred

- `OrdinaryPreferences.cs`.
- Unix umask, Unix mode, Windows ACL inheritance, open-reader replacement, and
  other platform-specific `TrustedFileWrites` cases. Their current Pester tests
  remain in place; deferral does not delete or weaken them.
- Pure BCL path, temporary-file, sharing, attribute, and special-folder facts.
- The Windows ACL suite.
- Managed coverage collection and thresholds beyond a canary comparison report.

### Strongest alternatives not selected

| Candidate | Why it is credible | Why it is not first |
| --- | --- | --- |
| `OrdinaryPreferences` | Managed production code, direct exceptions, filesystem state, and no parser or service dependency | Its core behavior is a smaller create-and-save wrapper; `TrustedFileWrites` exercises a richer security boundary, exclusive creation, delete-on-close, atomic replacement, and cleanup failure behavior without adding platform-only cases |
| Distribution manifest contracts | Uses built-in JSON APIs and cleanly removes non-PowerShell Pester policy | It tests repository policy but does not prove managed coverage for shipped executable code |
| Workflow template contracts | Directly tests the parser-versus-regex premise | It requires selecting and pinning a YAML parser and rendering strategy before the first canary |
| Agent instruction mirror | Small and important transformation | The implementation under test is PowerShell; MSTest would only replace the launcher and would not improve implementation-language coverage |
| Windows ACL facts | No PowerShell behavior and naturally expressible in C# | Windows-only privileges and P/Invoke make feedback asymmetric and the first migration unnecessarily large |

## Premises falsified

- A Pester file is not necessarily a PowerShell test. Seventeen file/ACL context
  groups and both WinUI checks use Pester only as a launcher/assertion library.
- Moving every repository-format test to MSTest is also too coarse. Tests of
  PowerShell validators belong in Pester while those validators remain
  PowerShell; standard grammars belong to maintained parsers or validators.
- `AgentFiles.Tests.ps1` is not a clean managed canary. Its primary subjects are
  two PowerShell tools and a PowerShell plugin-smoke script.
- Existing green tests do not establish independent policy. Test-local closure
  and Markdown-link helpers in `InstalledSkills.Tests.ps1` partly test their own
  implementations.
- One aggregate coverage number cannot describe this suite. It contains
  executable PowerShell, executable managed assets, BCL/kernel facts, generated
  behavior, external integrations, and documentation policy.
- One Pester file may remain temporarily split across harnesses. In the canary,
  the six accepted `TrustedFileWrites` declarations move to MSTest while
  `OrdinaryPreferences`, pure BCL facts, and deferred platform-specific
  `TrustedFileWrites` declarations remain in the existing Pester file.

## Exit decision

The maintainer accepted the following on 2026-09-15:

1. the dispositions in this inventory;
2. the bounded `TrustedFileWrites` core-behavior canary; and
3. P0c landing before P1a or P1c implementation resumes.

P0r completes when this accepted decision record merges.
