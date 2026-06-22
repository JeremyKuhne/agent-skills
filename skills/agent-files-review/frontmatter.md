# Agent-file frontmatter and naming

Per-file-type frontmatter and naming rules for the `agent-files-review`
checklist. Check the entry for the file type you changed; the operational
workflow (mirror, links, validator, whitespace) stays in [SKILL.md](SKILL.md).

## `*.instructions.md` (path-specific instructions)

- Frontmatter must include a non-empty `applyTo` glob.
- Glob is comma-separated, relative to repo root. Quote the value for safety.
- The validator only checks `applyTo`'s presence and emptiness; it does not
  verify that the glob actually matches anything. Sanity-check by eye.

## `*.agent.md` (custom agents)

- Frontmatter must include `description`.
- If `tools` is present, it must be a YAML list. Either form is accepted by
  the validator:

  ```yaml
  tools: ['search', 'edit']
  ```

  ```yaml
  tools:
    - search
    - edit
  ```

- The repo's authoring rules forbid end-of-line comments; document optional
  fields with comment lines *above* them in any examples.

## `SKILL.md` (`.agents/skills/<name>/SKILL.md`)

- `name` is **required** and must:
  - match `^[a-z0-9-]{1,64}$`
  - equal the parent directory name exactly
- `description` is required; make it specific enough that another agent
  can decide when to load it.
- A name/dir mismatch causes the skill to silently fail to load. Always
  verify by running the validator.

## `*.prompt.md` (reusable prompts)

- No required frontmatter, but `description` is recommended for the slash
  menu UX.
