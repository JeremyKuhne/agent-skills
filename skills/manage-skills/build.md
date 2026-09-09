# Build a skill

Detail for the [manage-skills](SKILL.md) skill. "Build a skill for X" / "create a
skill" does **not** start by writing a new skill. It starts by finding one.

## The find-first decision tree

Reinventing a skill that already exists - in this repo, the commons, or a public
catalog - is the failure mode this path exists to prevent. Always run
[find.md](find.md) first, then act on the result:

### 1. Run find

Run [find.md](find.md) before writing anything.

### 2. Already installed at the requested host and scope

Do not build. If it does not quite fit, follow [update.md](update.md) and classify
the change before editing any installed copy. A hit at another scope is not
equivalent; route the existing source through [install.md](install.md).

### 3. In the commons

Do not build. Choose scope and required hosts with [install.md](install.md). For
an existing-repository project copy, run [integrate.md](integrate.md) before
writing so the thin overlay comes from repository evidence and semantic overlap
is resolved. For a Copilot project copy:

```pwsh
gh skill install JeremyKuhne/agent-skills <skill> --pin vX.Y.Z `
  --agent github-copilot --scope project
```

Read the selected revision's `metadata.requires` and install its complete
transitive requirement closure at the same pin; `gh skill install` installs only
the named skill. Review each requirement's applicability and source before
installing it.

`--pin` records the exact version so later updates skip it until you deliberately
re-pin. The install reserializes `SKILL.md` frontmatter and adds provenance
metadata (source repo, ref, pin, path, and tree SHA). Commit a project copy; keep
a user copy outside project source control. Compare installed artifacts with the
normalized mirror contract in [update.md](update.md), not a raw `SKILL.md` file
hash.

Without `gh`, check out or download the exact tag/commit, copy the complete
directory for the skill and each transitive requirement (not only each
`SKILL.md`), preserve or add provenance metadata for that immutable revision,
add the local overlay, and compare every copied file list and hash against the
source before running the validators. If an exact revision or complete file set
cannot be obtained, keep installation blocked.

### 4. In a public catalog

Do not build from scratch. Apply the security gate below. If it is good, install
it at the selected scope; if it is close but imperfect, fork it into the commons
and install that. A mediocre public skill is usually worth adapting over a blank
start.

### 5. Nowhere

Build new using the next section.

## Security gate for public sources

Public skills are an instruction-injection supply chain - audits have found a
meaningful fraction carry a critical issue (prompt injection, malicious scripts,
exposed secrets). Before installing anything from a public source:

- **Preview, do not blind-install:**
  `gh skill preview <owner/repo> <skill>@<full-commit-sha>` and read the
  `SKILL.md`, every script, and every `references/` file - not just the summary.
- **Pin** to a tag or commit SHA; never track a moving ref.
- **Never accept `allowed-tools` from a third party**, especially `shell` / `bash`
  - it removes the per-command confirmation. Strip it on import and let the host
  prompt.
- **Prefer provenance-bearing sources** (the curated registry, verified
  publishers) over a random repo from a blog post.
- Treat a cloned repo's `.agents/` as untrusted code: opening it can load skills
  into a trusted session.

## Building a new skill (it exists nowhere)

### Choose canonical source ownership first

Decide where the canonical source lives before writing much. This is independent
of where runtime copies will be installed:

- **Born-repository** - the skill is specific to this repo (its paths, projects,
  or one-off workflow). Author it in a supported project root and leave it; it
  never goes to the commons.
- **Born-personal** - the skill is specific to one person (voice, private context,
  preferences, or an individual workflow). Author it in a local-only directory or
  controlled private source, then install at user scope. Do not put it in a public,
  shared, organization, plugin, or project distribution path.
- **Born-shared** - the skill is generic and other repos will want it. First ask
  the user whether to pursue commons authoring, as required by
  [update.md](update.md).
  Prepare and validate the portable core in the owning commons checkout, but do
  not create a branch, commit, push, or open a PR without that repository's
  explicit approvals. Once the shared change is merged and released, vendor the
  immutable revision with an overlay where needed.

A skill that is mostly generic but needs a few project or user specifics is still
born-shared: the generic part is the core, the specifics are an installation-local
overlay. The test is whether another consumer would want the core unchanged.

### Apply the baseline package checks

Every ownership class still needs a valid, complete skill package:

- Keep a thin top-level `SKILL.md`; move deep detail into bundled sibling or
  `references/` files.
- Make `name` match the directory and write a specific `description` that names
  the requests that should invoke the skill without stealing neighboring work.
- Keep every referenced resource and script inside the package unless the
  owning scope explicitly supplies it through an overlay.
- Run [scripts/Validate-Skills.ps1](scripts/Validate-Skills.ps1) without strict
  portfolio mode when the bundled script is available. Also use the target
  host's diagnostics or a reference Agent Skills validator when available.
- After behavior and routing settle, run `technical-writing` in revise mode.
  Preserve literal triggers, requirement strength, tool and file names,
  permissions, and stop conditions.

The bundled normal validator is the portable fallback; it does not establish an
owning repository's catalog, metadata vocabulary, or publication policy. If a
required owning-scope or host check is unavailable, name that check and stop
before claiming completion. Report optional checks as `not run` rather than
inventing a pass.

### Author a born-shared core

Follow the **owning commons'** format, metadata, catalog, overlay, and publication
rules. A commons that requires the bundled portfolio contract runs:

```pwsh
pwsh scripts/Validate-Skills.ps1 <commons-skills-root> `
  -RequirePortfolioMetadata
```

Use that strict mode only when the owning commons adopts those fields. Add or
regenerate a catalog only when its local policy requires one. Keep repository
paths, cross-references, and examples out of the core; put consumer bindings in
an overlay. For this portfolio contract, an overlay-aware core carries the
loader sentence and a downstream overlay can start from
`assets/overlay.md.tmpl`.

Run every additional validator, link check, artifact-isolation check, and catalog
check required by the owning commons. Its documented format and commands are
authoritative; this portable workflow does not assume every commons has a file
named `FORMAT.md` or the same metadata vocabulary.

### Author a born-repository skill

Write the canonical package in a project root documented by the target host.
Follow the repository's local agent instructions, schema extensions, validation,
and catalog policy. Do not add portfolio fields, a `FORMAT.md`, or a catalog
merely because a shared commons uses them. Run strict portfolio mode only if this
repository explicitly adopts that contract; otherwise use the bundled normal
validator plus the repository and host checks that actually exist.

Repository-specific paths and commands can live directly in a born-repository
skill. An overlay is useful only when the repository deliberately vendors a
separate portable core; do not manufacture a core/overlay split for a package
with one repository owner.

### Author a born-personal skill

Use a local-only canonical directory or a controlled private source and apply
the privacy gate in [install.md](install.md). A personal skill needs no
repository checkout, `FORMAT.md`, catalog, portfolio metadata, repository link
checker, or publication validator. Validate the package with the bundled normal
validator and each available target host's diagnostics, then install only at the
approved user scope. Keep secrets out of the package and do not infer remote
availability from a local install.

### Finish the applicable path

Select and verify runtime targets with [install.md](install.md), then run the
semantic workflow review in [review.md](review.md). For a repository-backed
source, hand file checks to `agent-files-review` and the owning repository's
tools. For a repository-free personal source, use the bundled normal validator,
host diagnostics, and direct link/resource inspection instead. A validator pass
does not establish that the skill invokes correctly or leads an agent to a
finished outcome.
