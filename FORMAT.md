# Agent Skills format reference

Format for the shared skill cores under `skills/` in this commons. These are
**portable cores**: generic content that any consuming repository can vendor
unchanged. Repo-specific material belongs in the consuming repo's overlay, not
here.

## Layout

```text
skills/
  <skill-name>/
    SKILL.md           # required
    <sibling>.md       # optional: deep detail, loaded on demand
    references/        # optional: bundled docs that travel with the skill
    assets/            # optional: templates / scaffolding the skill uses
    scripts/           # optional: executable helpers
```

The directory name **must** match the `name` field in `SKILL.md` exactly, or the
skill silently fails to load.

## `SKILL.md` format

```markdown
---
name: skill-name
description: One-sentence summary of what the skill does and when to use it.
metadata:
  portability: portable
  applicability: universal
  binding: optional-overlay
  risk: advisory
  maturity: canary
  requires: none
  related: another-skill
---

# Body

Detailed instructions. Reference sibling files with relative Markdown links,
e.g. [detail.md](detail.md).
```

- `name` - lowercase, digits, hyphens; max 64 chars; matches the directory name.
- `description` - what the skill does **and when to use it**, with trigger
  phrasing. This is the entire auto-invocation surface; write it "pushy".

Use `compatibility` when the workflow requires a particular runtime, CLI, MCP
server, network capability, or operating system. Other optional Agent Skills
fields are `argument-hint`, `user-invocable`, `disable-model-invocation`,
`context` (`inline` or `fork`), and `allowed-tools`.

## Portfolio metadata

Every core in this commons carries these string-valued `metadata` keys. CI
validates the values and generates the portfolio matrix in
[skills/README.md](skills/README.md).

| Key | Values | Meaning |
| --- | --- | --- |
| `portability` | `portable` | The installed core is self-contained. `semi-portable` and `repo-specific` are recognized for downstream catalogs but cannot be published as commons cores. |
| `applicability` | `universal`, `git-github`, `agent-customization`, `dotnet`, `dotnet-framework`, `dotnet-project-gated`, `tool-shipped`, `repo-local` | Which repositories should carry the skill. Applicability is independent of portability. |
| `binding` | `none`, `optional-overlay`, `required-overlay` | Whether the core consumes a sibling `overlay.md`. |
| `risk` | `advisory`, `local-write`, `remote-write` | The strongest action the workflow may take. Use this to scale review and evaluation depth. |
| `maturity` | `experimental`, `canary`, `stable` | The assurance level. Promotion requires the release gates appropriate to that level. |
| `requires` | `none` or comma-separated skill names | Hard dependencies that must be installed with this core. Keep this list small. |
| `related` | `none` or comma-separated skill names | Optional companions and handoffs. A related skill is never an undeclared file dependency. |

Relationship names must resolve to another source core and the `requires` graph
must remain acyclic. The generated matrix is updated with:

```pwsh
./tools/Update-SkillCatalog.ps1 -Apply
```

## Human-facing prose contract

A skill other than `technical-writing` that normally creates durable
human-facing prose or remotely publishes text must declare `technical-writing`
in `metadata.requires`. Use it while drafting or revising the candidate and run
pre-publication mode after the text and its evidence stabilize. The owning skill
retains evidence collection, domain validation, approval, and the remote action.

Routine conversational status and session-only summaries do not create this
dependency. An optional handoff in `metadata.related` is sufficient when a skill
can complete its own review correctly without producing or publishing the prose.

## Personal profile contract

A portable core may create or audit a personal profile, but the personalized
output is a separate born-personal skill. Never add a natural person's profile,
source samples, identity, private evidence, migration output, or installed
runtime package under `skills/`, plugin assets, project skill roots, tests, or
public artifacts. Public fixtures must be entirely synthetic.

Keep canonical personal source local-only by default or in a GitHub repository
whose `PRIVATE` visibility is verified at the current operation. Install a
reviewed complete copy only at personal user scope. Do not encode the private
runtime package in public `metadata.requires` or `metadata.related`; use a
generic optional runtime convention and preserve a no-profile fallback.

The shared core may contain generic templates, scanners, and lifecycle policy.
Discovery metadata and templates must contain no user name, source path,
private URL, profile trait, or identifying example.

## Portable-core rules

A core lives in the commons only if it stays generic. Keep out of the core:

- Links to sibling skills, instructions files, `AGENTS.md`, or a repo's `docs/`.
- Repo-specific paths, project names, or target-framework monikers.
- Source-example links into a specific repository's tree.

Anything the core genuinely needs travels as a bundled `references/` doc or a
portable sibling. Everything repo-specific is supplied by the consuming repo's
overlay. A vendored core must pass that repo's link check unchanged.

Do not link to a related skill from a core. Name it in prose and in
`metadata.related`; the consuming repo may not have installed it. A required
skill belongs in `metadata.requires` and the installed-artifact test installs
that declared bundle before resolving links.

## Overlay contract

`overlay.md` is the standard sibling for repository-specific bindings. A core
with `binding: optional-overlay` or `binding: required-overlay` includes this
exact loader instruction near the top of `SKILL.md`:

> If `overlay.md` exists beside this file, read it before acting; it contains
> repository-specific bindings. This core remains usable without it.

For `required-overlay`, change the final sentence to state that the overlay is
required; the strict validator also fails when the file is absent.

An overlay starts with:

```markdown
---
core: skill-name
core-pin: vX.Y.Z
---
```

`core` must match the directory and `core-pin` records the tag or SHA the
bindings were reviewed against. Start from
`skills/manage-skills/assets/overlay.md.tmpl`. When re-pinning the core, update
`core-pin` and re-review the bindings. The overlay may link to repository files;
the portable core may not.

## Thin core plus sibling files

Keep each `SKILL.md` body small - the whole body loads on every trigger, while
sibling files load only when referenced. When a skill grows past roughly 150
lines, split the deep detail into sibling `*.md` files and leave the core as an
overview that links to them.

## Discovery

Vendor-neutral [Agent Skills](https://agentskills.io/) location, discovered by
GitHub Copilot (VS Code, CLI, cloud agent) and Claude Code, and installable with
`gh skill install JeremyKuhne/agent-skills <skill>`.

## Validation

Skill Markdown must not contain HTML entities. Write the character directly or
use plain words instead; Unicode text is valid.

Wrapped prose inside a list item must stay on the paragraph's starting column.
CommonMark accepts lazy or deeper indentation and standard markdownlint does not
enforce consistent prose alignment; the bundled skill validator does.

Run the strict bundled policy and the reference specification validator:

```pwsh
./skills/manage-skills/scripts/Validate-Skills.ps1 ./skills -RequirePortfolioMetadata
Get-ChildItem ./skills -Directory | ForEach-Object {
  npx --yes skills-ref@0.1.5 validate $_.FullName
}
./tools/Update-SkillCatalog.ps1
```

CI additionally installs every skill in isolation, resolves links inside the
installed artifact, validates agents and manifests, and smoke-tests the plugin.
