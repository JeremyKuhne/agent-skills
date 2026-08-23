<!-- DO NOT EDIT. Generated mirror of /AGENTS.md. Edit AGENTS.md and run: ./tools/Validate-AgentFiles.ps1 -Fix -->
# AGENTS.md

Instructions for AI agents working in this repository. This file applies to any
tool that supports the [AGENTS.md](https://agents.md/) convention.

This file is the single source of truth. `.github/copilot-instructions.md` is a
generated mirror for GitHub Copilot clients; never edit the mirror directly.
After changing this file, run `./tools/Validate-AgentFiles.ps1 -Fix` and commit
both files.

For contributor-facing guidance, see [CONTRIBUTING.md](../CONTRIBUTING.md), the
skill format contract in [FORMAT.md](../FORMAT.md), and the release process in
[RELEASING.md](../RELEASING.md).

## Repository role

This repository is the commons for shared Agent Skills, portable agent personas,
and their GitHub Copilot plugin distribution. Consuming repositories vendor
version-pinned skill copies and add repository-specific behavior in overlays.

The distinction is load-bearing:

- A core under `skills/` is portable and self-contained. Keep out repository
  names, local paths, target-framework choices, links to sibling skills, and
  source examples from one consumer.
- A consuming repository's `overlay.md` owns its paths, commands, local
  cross-references, examples, and policy bindings.
- The workflow under `.agents/skills/create-skill-repo/` is local to this
  commons. It is not a published core and must not enter the shared catalog or
  plugin manifest.

## Repository layout

| Path | Purpose |
| --- | --- |
| `skills/` | Portable skill cores published through `gh skill` and the plugin. |
| `agents/` | Portable agent personas. |
| `.agents/skills/` | Repository-local workflows that are not distributed. |
| `evals/` | Deterministic harness code and manual model-evaluation scenarios. |
| `tests/` | Pester contracts for skills, agents, distribution, and scaffolding. |
| `tools/` | Catalog and repository-maintenance scripts. |
| `plugin.json` | GitHub Copilot plugin manifest. |
| `.github/plugin/marketplace.json` | Plugin marketplace metadata. |
| `.mcp.json` | MCP server declarations shipped with the plugin. |

## Authoring skills and agents

Before editing `AGENTS.md`, `SKILL.md`, `*.agent.md`, `*.instructions.md`,
`*.prompt.md`, their validators, or their workflows, read
[skills/agent-files-review/SKILL.md](../skills/agent-files-review/SKILL.md) and run
its checklist. Use [skills/manage-skills/SKILL.md](../skills/manage-skills/SKILL.md)
for skill lifecycle and semantic changes.

For a shared skill core:

- The directory name and frontmatter `name` must match exactly.
- The `description` must state what the skill does and when it should trigger.
- Fill every portfolio metadata field documented in [FORMAT.md](../FORMAT.md).
- Keep the core concise. Put deep detail in bundled sibling files or
  `references/` so it travels with the core.
- Declare hard dependencies in `metadata.requires`. Do not create undeclared
  sibling-file dependencies or links to optional related skills.
- Keep personalized profiles, identifying source material, private evidence,
  and born-personal runtime packages out of this public repository. Public
  fixtures must be synthetic.

Shared personas under `agents/` must remain portable and read-only unless their
declared role requires mutation. Refer to workflows and skills by role rather
than assuming a consuming repository's paths.

Use [skills/technical-writing/SKILL.md](../skills/technical-writing/SKILL.md) for
durable human-facing prose and immediately before publishing text. Use
[skills/pre-pr-self-review/SKILL.md](../skills/pre-pr-self-review/SKILL.md) before
opening or updating a pull request.

## Generated files

- Edit `AGENTS.md`, then run `./tools/Validate-AgentFiles.ps1 -Fix` to regenerate
  `.github/copilot-instructions.md`.
- Edit skill metadata or catalog prose above the generated block in
  `skills/README.md`, then run `./tools/Update-SkillCatalog.ps1 -Apply`.
- Never hand-edit the generated portfolio matrix or the Copilot instruction
  mirror.
- Keep `plugin.json` and `.github/plugin/marketplace.json` versions aligned.
  Release tags must match both; see [RELEASING.md](../RELEASING.md).

## Editing discipline

- Start from the owning file, test, validator, or workflow. Read only enough
  surrounding code to identify the controlling behavior and a focused check.
- Preserve user changes in a dirty worktree. Never discard, overwrite, or
  reformat unrelated edits.
- Keep changes scoped. Do not mix a portable-core improvement with a consumer
  binding or unrelated catalog cleanup.
- Use structured parsers and APIs for structured data. Do not extend a regex
  parser beyond the subset its contract documents.
- Keep prose concise and concrete. Do not use HTML entities. Match surrounding
  Markdown wrapping and keep wrapped list prose on its content indentation.
- Prefer relative Markdown links for repository files. Every relative link must
  resolve in the current branch and in any generated mirror or installed
  artifact that carries it.

## Validation

Run the narrowest relevant check immediately after an edit, then run the full
deterministic gates before publication.

For agent-instruction changes:

```pwsh
./tools/Validate-AgentFiles.ps1
./tools/Test-AgentFileLinks.ps1
```

The local link script covers agent customization files. CI's offline lychee
step checks every Markdown file in the repository.

For skill and catalog changes:

```pwsh
./skills/manage-skills/scripts/Validate-Skills.ps1 ./skills -RequirePortfolioMetadata
Get-ChildItem ./skills -Directory | ForEach-Object {
    npx --yes skills-ref@0.1.5 validate $_.FullName
}
./tools/Update-SkillCatalog.ps1
```

For repository-wide validation:

```pwsh
npx --yes markdownlint-cli2 --config .markdownlint.jsonc "**/*.md" "#node_modules"
./tests/Invoke-PesterShards.ps1 -Path ./tests
```

Distribution or release changes also require the plugin smoke test, synthetic
consumer, and applicable scaffold canaries listed in
[RELEASING.md](../RELEASING.md).

Real model evaluations are manual and may consume paid capacity. Ask the user
before starting any model run or trace. Never add real model invocations to
GitHub Actions, and do not publish raw prompts or transcripts by default. The
deterministic evaluation harness tests remain part of ordinary Pester runs.

## Working with the user

Editing, committing, pushing, and pull-request operations are separate approval
boundaries.

- A request to implement, investigate, fix, review, or address feedback
  authorizes local work only.
- Creating or rewriting a commit requires an explicit commit instruction in the
  user's latest message.
- Pushing requires an explicit push instruction in the user's latest message.
- Creating, editing, merging, closing, replying on, or resolving a pull request
  requires an explicit instruction for that remote action. A message can
  authorize several boundaries only when it names them.
- Approval from an earlier message or review round does not carry forward.

If the latest message does not authorize the next boundary, stop after local
validation, summarize the pending diff, and ask one short question. Assume tool
approval prompts may be bypassed; self-enforce these boundaries before every
commit and remote write.

Work on a feature branch and never commit directly to `main`. Stage by explicit
path. Do not force-push, rewrite published history, delete branches, or use a
destructive Git command without specific approval.
