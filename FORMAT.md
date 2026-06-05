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
---

# Body

Detailed instructions. Reference sibling files with relative Markdown links,
e.g. [detail.md](detail.md).
```

- `name` - lowercase, digits, hyphens; max 64 chars; matches the directory name.
- `description` - what the skill does **and when to use it**, with trigger
  phrasing. This is the entire auto-invocation surface; write it "pushy".

Optional frontmatter: `compatibility` (free-text environment / MCP-dependency
note), `argument-hint`, `user-invocable`, `disable-model-invocation`, `context`
(`inline` or `fork`), and a `metadata` map (e.g. `metadata.portability`).

## Portable-core rules

A core lives in the commons only if it stays generic. Keep out of the core:

- Links to sibling skills, instructions files, `AGENTS.md`, or a repo's `docs/`.
- Repo-specific paths, project names, or target-framework monikers.
- Source-example links into a specific repository's tree.

Anything the core genuinely needs travels as a bundled `references/` doc or a
portable sibling. Everything repo-specific is supplied by the consuming repo's
overlay. A vendored core must pass that repo's link check unchanged.

## Thin core plus sibling files

Keep each `SKILL.md` body small - the whole body loads on every trigger, while
sibling files load only when referenced. When a skill grows past roughly 150
lines, split the deep detail into sibling `*.md` files and leave the core as an
overview that links to them.

## Discovery

Vendor-neutral [Agent Skills](https://agentskills.io/) location, discovered by
GitHub Copilot (VS Code, CLI, cloud agent) and Claude Code, and installable with
`gh skill install JeremyKuhne/agent-skills <skill>`.
