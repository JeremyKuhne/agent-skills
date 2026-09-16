# PowerShell toolchain policy contract

- Status: accepted by the maintainer on 2026-09-15
- Baseline: `main` at `7e68d294300fbb9ddc649e90cbea4eefda35d621`
- Milestone: P1b parser-backed toolchain policy
- Scope: contract only; this document adds no manifest, parser, validator, or CI
  behavior

## Accepted decision

The maintainer accepted the manifest schema, parser ownership, accepted and
rejected forms, negative controls, implementation slices, and deferrals below
on 2026-09-15. That acceptance authorizes the contract and makes P1b ready; it
does not by itself authorize later commit, push, pull request, or merge
operations.

P1b will centralize only policy that its first executable gate consumes. It will
not recreate the parser code from PR #88 or PR #89, infer structured syntax with
regular expressions, or add fields for later milestones merely because their
values are currently known.

## Current baseline

PR #94 established the PowerShell 7.4 test floor, Pester 6.2 compatibility
floor, and exact Pester 6.2.0 execution lock. PR #95 routed repository and
generated-repository Pester execution through the canonical isolated runner.
The current tree has no `tools/powershell-toolchain.json`, no managed toolchain
validator, and no PSScriptAnalyzer gate.

Current executable sources of truth are distributed:

- tracked Pester tests and generated test artifacts declare
  `#Requires -Version 7.4` and a Pester `ModuleVersion` of `6.2.0`;
- [Invoke-PesterShards.ps1](../tests/Invoke-PesterShards.ps1) defaults its exact
  execution version to 6.2.0 and imports that exact version in each worker;
- active and generated workflow jobs that execute Pester install version 6.2.0
  and invoke the isolated runner;
- both managed test projects use `MSTest.Sdk/4.2.3`, target `net10.0`, and run
  directly through `dotnet test`; and
- the file-creation matrix runs behavior on `ubuntu-24.04-arm` and
  `windows-latest`, with coverage only on Windows.

These facts constrain the contract but are not themselves an independent
parser-backed gate.

## Ownership and implementation boundary

P1b implementation will use these owners:

| Concern | Owner | Independent oracle |
| --- | --- | --- |
| Manifest JSON | `System.Text.Json` with explicit DTOs and unknown-member rejection | This accepted schema and its negative-control table |
| Workflow YAML | YamlDotNet 18.1.0 | This accepted workflow object model and rendered workflow fixtures |
| PowerShell syntax and commands | `System.Management.Automation.Language.Parser` from `System.Management.Automation` 7.4.20 | PowerShell AST node types and this accepted command model |
| Repository policy | A new managed MSTest project under `tests/powershell-toolchain/` | This document, deliberately mutated fixtures, and current hosted behavior |
| Portable skill format | `skills-ref@0.1.5` | Agent Skills format; P1b does not duplicate it |
| Markdown and links | markdownlint and offline lychee | Existing repository configurations; P1b does not parse Markdown |

The managed project will pin `MSTest.Sdk/4.2.3`, YamlDotNet 18.1.0, and
`System.Management.Automation` 7.4.20. Package references use exact versions
in its project file and checked-in NuGet lock data. The project enables
`RestorePackagesWithLockFile`; canonical validation first runs `dotnet restore
--locked-mode`, then `dotnet test --no-restore`, so validation cannot silently
regenerate the lock. Validation must not download schemas or execute workflow
commands. `System.Management.Automation` 7.4.20 is available from NuGet.org and
contains the required public parser API; the broader
`Microsoft.PowerShell.SDK` package is not required.

The project may keep policy code beside its tests until a second production
consumer justifies a separate command-line tool. P1b does not add a generic
process host or a new PowerShell wrapper around managed tests.

## Initial manifest

P1b may add `tools/powershell-toolchain.json` with exactly this version-one
shape:

```json
{
  "schemaVersion": 1,
  "powerShell": {
    "testMinimumVersion": "7.4"
  },
  "pester": {
    "compatibilityMinimumVersion": "6.2.0",
    "executionVersion": "6.2.0"
  }
}
```

All properties are required. Property names are case-sensitive. Unknown
properties, duplicate properties at any object depth, comments, trailing
commas, non-string version values, and a non-integer schema version are
rejected. `schemaVersion` is the single raw JSON token `1`; the validator checks
`JsonElement.GetRawText()` before conversion, so numerically equivalent tokens
such as `1.0` and `1e0` are rejected.

`testMinimumVersion` is the exact two-component ASCII decimal string `"7.4"`.
`compatibilityMinimumVersion` and `executionVersion` are the exact
three-component ASCII decimal string `"6.2.0"`. Decimal components contain
only `0` or a nonzero digit followed by zero or more digits. Leading or trailing
whitespace, leading zeros, a `v` prefix, a missing or extra component,
prerelease text, build metadata, and wildcards are rejected.

`testMinimumVersion` is the floor for retained Pester tests and the shard runner;
it is not yet the floor for every operational or shipped script.
`compatibilityMinimumVersion` is written into Pester test requirements as a
minimum. `executionVersion` is the exact version installed and selected by the
runner and CI.

## Contract table

Each row is independently change-controlled. Changing an accepted value or
adding a new accepted form requires updating this document and its negative
controls before implementation.

| Surface | Subject, owner, and oracle | Accepted forms | Rejected forms | Deferred forms | Executable P1b gate |
| --- | --- | --- | --- | --- | --- |
| Manifest structure | Repository toolchain policy; managed validator; accepted JSON schema above | Exact version-one object with the four required scalar values | Missing, null, duplicate, unknown, wrong-case, wrong-type, noncanonical, or unsupported-version members | Additional tools, hosts, SDKs, analyzers, coverage, and per-file inventories | Deserialize with `System.Text.Json`; reject malformed JSON and every shape outside the closed DTO |
| Retained test host | Tracked Pester tests and generated Pester test artifacts; PowerShell parser; manifest `testMinimumVersion` | One script requirement whose minimum version is exactly 7.4 | Missing or duplicate requirement; lower or higher literal; dynamic text; parse error | Operational and shipped scripts, compatibility fixtures, and a future floor | Parse tracked tests directly and parse scaffolded test output; compare AST requirements with the manifest |
| Pester compatibility | Retained Pester tests and generated Pester test artifacts; PowerShell parser; manifest compatibility floor | One Pester module requirement using `ModuleVersion = '6.2.0'`; key order and quoting may vary semantically | Missing Pester requirement, `RequiredVersion`, lower or higher floor, duplicate Pester entry, dynamic value, malformed module specification | Compatibility with another Pester minor or major | Read module specifications from the AST; never search comments or strings |
| Canonical runner | [Invoke-PesterShards.ps1](../tests/Invoke-PesterShards.ps1); PowerShell parser; manifest execution version | PowerShell 7.4 requirement; typed `PesterVersion` default exactly 6.2.0; worker import uses that parameter with `RequiredVersion` | Missing or dynamic default, different version, unpinned import, alias, or direct ambient-module execution | Moving process supervision to C# and changing the runner schema | Inspect parameter and command ASTs and retain existing behavioral state-table tests |
| Repository Pester jobs | Active workflow jobs; YamlDotNet plus PowerShell parser; this row and PR #95's hosted behavior | Ordinary Linux `scaffold-linux` runs all tests; ordinary Windows `scaffold-windows` conditionally runs the exact `windows-acls` and `dotnet-file-creation` set; scheduled Windows `scaffold-windows` runs all tests; each uses `shell: pwsh` | Direct `Invoke-Pester`, missing runner, extra or missing focused path, wildcard path, dynamic command name, another shell, or a newly discovered Pester job absent from the contract | Adding Pester to scaffold-only Linux jobs, new platform lanes, or changing component ownership | Parse workflow mappings and sequences, then parse each `run` scalar as PowerShell; compare static command and path ASTs with this topology |
| Pester bootstrap | Jobs that invoke the runner; YamlDotNet plus PowerShell parser; manifest execution version | A preceding same-job `pwsh` step installs Pester with `-RequiredVersion 6.2.0`; unrelated flags may vary | Missing, later, cross-job, conditional-incompatible, dynamic, floating, or mismatched installation | Pre-provisioned runner images and alternate package sources | Resolve ordered steps in parsed YAML and inspect the install command AST |
| Generated Pester execution | `New-SkillRepository.ps1` output; generated-repository canary; same parser stack | The runner emitted by the scaffolder is byte-identical to the canonical runner in that checkout; team-CI and distribution workflows invoke it for all tests after exact installation | Raw-template parsing, unresolved template tokens, direct `Invoke-Pester`, a divergent emitted runner, or source-text-only evidence | A separately versioned portable runner package and later line-ending changes after the generated repository is committed | Generate validated, team-CI, and distribution fixtures; compare source and emitted bytes, parse emitted files, and execute the generated runner |
| Managed file-creation behavior | `dotnet-file-creation` workflow job and managed test project; YamlDotNet and `dotnet test`; the accepted [test-ownership inventory](powershell-test-ownership-inventory.md) and PR #93's hosted behavior | Matrix rows are `{ ubuntu-24.04-arm, coverage: false }` and `{ windows-latest, coverage: true }`; both run the same Release project directly in an explicit `pwsh` step | Missing or duplicate host, string/numeric/null coverage values, omitted or different shell, Pester wrapper, wrong project, or non-Release execution | Additional architectures and coverage on unsupported collectors | Parse typed matrix values and the PowerShell command AST; run the project on both hosted rows |
| Managed file-creation coverage | Windows coverage step and [coverage.config.xml](../tests/dotnet-file-creation/coverage.config.xml); XML parser and report inspection | Coverage runs only on the `windows-latest` row when `matrix.coverage == true`, uses the linked project and checked-in settings file, emits Cobertura, and verifies the `TrustedFileWrites` source has covered lines | Coverage on the ARM64 row, overlapping or missing behavior/coverage conditions, wrong settings/project/format, empty report, or unrelated source | Thresholds, ratchets, aggregation, and coverage on every architecture | Parse YAML condition/scalars and XML settings; retain hosted Windows report validation |

## Known implementation delta

The current non-coverage file-creation step omits `shell`, so GitHub selects the
host default. P1b implementation must make that step explicitly `pwsh` before
the managed command contract can pass. The command already runs unchanged in
PowerShell on Windows; the implementation PR must prove the same Ubuntu ARM64
behavior through exact-head CI. No other current-tree mismatch is accepted by
this contract.

## Workflow parsing rules

YamlDotNet owns mappings, sequences, scalar styles, booleans, nulls, anchors,
aliases, and comments. The validator must not infer those constructs from lines
or indentation. Policy-bearing mappings reject duplicate keys, merge keys,
anchors, and aliases; accepting those forms would require a separate contract.

A parsed `run` scalar is PowerShell source only when its step declares
`shell: pwsh`. Every P1b-owned command step must declare that shell explicitly;
an omitted or inherited shell is rejected. The PowerShell parser owns commands,
parameters, arrays, variables, quoting, comments, and invocation operators.
P1b accepts only statically resolvable command names and values needed by the
table:

- direct literal runner paths;
- direct literal `./tests` paths; and
- the current focused `$paths` variable only when it is assigned exactly once in
  the same scalar to an array of literal paths and is not mutated or splatted.

Aliases, wildcard paths, environment-derived values, expression-built command
names, dot-sourced workflow helpers, nested `pwsh -Command`, and cross-step value
flow are rejected rather than partially interpreted. Supporting one of those
forms requires a new contract decision.

Raw workflow templates are not YAML inputs. The create-skill-repo tests render
representative validated, team-CI, and distribution repositories through the
real scaffolder. The managed policy tests consume those emitted workflows and
test files. This keeps placeholder expansion owned by the scaffolder and YAML
semantics owned by YamlDotNet.

## Required negative controls

The implementation test matrix must contain at least these independent
mutations. Each mutation fails before its repair and identifies the violated
contract row.

| Class | Required mutations |
| --- | --- |
| JSON shape | Missing property; explicit null; wrong primitive type; unknown property; duplicate property; unsupported schema version; `schemaVersion` tokens `1.0` and `1e0`; malformed JSON |
| Version text | Lower version; higher version; one component; an extra component; leading zero; leading or trailing whitespace; `v` prefix; prerelease; build metadata; wildcard; numeric instead of string |
| PowerShell requirements | Missing host requirement; wrong host floor; missing Pester module; `RequiredVersion` substituted for `ModuleVersion`; duplicate or dynamic module requirement; syntax error |
| Runner lock | Missing or changed default; unpinned import; literal import that bypasses the parameter; dynamic or aliased invocation |
| Workflow structure | Malformed YAML; job missing; unexpected additional Pester-invoking job; wrong host; missing or reordered bootstrap; wrong shell; direct Pester call; dynamic runner command; wildcard or wrong path set |
| YAML scalar forms | Plain, single-quoted, double-quoted, literal, and folded scalars that parse to the same accepted PowerShell command; comments and unrelated strings must not count as commands; duplicate keys, merge keys, anchors, and aliases are rejected on policy-bearing nodes |
| Typed matrix values | Missing, null, string, numeric, or duplicate `coverage`; omitted/extra host row; coverage conditions both true, both false, missing, or swapped |
| Managed commands | Omitted or different shell; wrong project; Debug configuration; missing coverage setting; wrong output format; Pester wrapper; empty or wrong-source coverage report |
| Generated artifacts | Missing runner; byte drift; unresolved token; direct Pester call; one representative generated runner failure propagated through its summary and process exit |

Fixtures must be deliberately constructed from this table. They must not copy
whatever errors the first implementation happens to emit as their oracle.

## Explicit deferrals

The initial manifest and validator do not own:

- PowerShell floors for operational, shipped, or non-Pester scripts, or
  named-only parameter binding; P4 owns those breaking changes;
- PSScriptAnalyzer version, settings, diagnostics, or changed-line policy; P5
  owns them when the analyzer is installed and executed;
- coverage percentages, source inventories, exception maps, report merging, or
  changed-line coverage; P6 owns them;
- .NET SDK, target framework, C# language, Node.js, npm, GitHub CLI, Copilot CLI,
  or GitHub-hosted image versions as manifest fields;
- workflow triggers, permissions, concurrency, action pin comments, release
  policy, or model-run prohibition beyond the rows above;
- Markdown, Agent Skills frontmatter, links, JSON distribution manifests, XML
  beyond the named coverage settings, or arbitrary PowerShell script policy;
- the dotnet-pipes workflow and semantic interpretation of arbitrary shell
  languages; and
- a generic process host, schema service, or repository-wide policy framework.

Existing validators retain those contracts until their owning milestone or a
separate accepted migration replaces them.

## Implementation sequence after acceptance

1. Add only the managed MSTest project scaffolding, exact package references,
  and checked-in lock file. This setup adds no manifest or policy behavior.
2. Encode the accepted fixtures, rejected mutations, and expected diagnostics
  before adding validator behavior or the repository manifest.
3. Add the closed version-one manifest and implement JSON and PowerShell
  requirement checks, then the active workflow
   and generated-fixture checks, then the managed file-creation lane checks.
4. Add one CI gate that restores the managed policy project with
  `dotnet restore --locked-mode` and tests it with `dotnet test --no-restore`.
5. Remove only Pester assertions that the managed gate demonstrably duplicates;
   retain PowerShell behavior and scaffold transaction tests.
6. Run focused managed tests, generated canaries, both existing managed suites,
   full isolated Pester parity, and repository validation.
7. Record exact-head CI, review findings, and the accepted completion decision in
   the engineering plan.

A parser limitation, unsupported current form, or new grammar class stops the
implementation for a contract decision. It does not authorize a regex fallback
or another serial parser patch.

## Accepted implementation gate

The maintainer accepted this contract after confirming:

- the manifest has exactly the four policy values above;
- the package and lock strategy is acceptable;
- the active and generated workflow topology is complete;
- the managed file-creation matrix and coverage split match P1c;
- every rejected class has a negative control;
- every deferred concern remains absent from the manifest and implementation;
  and
- migrated assertions are removed only after managed parity.
