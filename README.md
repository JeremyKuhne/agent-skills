# agent-skills

Shared agent skills and MCP configuration for Jeremy Kuhne's .NET repositories.
This is the **commons**: the single upstream source from which each repository
vendors pinned, provenance-stamped copies of the skills it needs.

It is both a [`gh skill`](https://docs.github.com/copilot/reference/copilot-cli-reference/cli-plugin-reference)
source and a Copilot/Claude plugin marketplace.

> **Status: early.** The distribution scaffolding, MCP configuration, and CI are
> in place, and the first shared skill cores have landed under `skills/`. More
> skills and agent personas arrive in later phases of the rollout. See the design
> doc in the touki repo: `docs/skills-improvement-plan.md`.

## The model

Skills are authored once as a portable **core** and shared from here. Each
consuming repository (touki, madowaku, thirtytwo, ...) holds a **vendored copy**
plus a thin repo-specific **overlay**:

- The **core** is generic: no repo-specific paths, project names, cross-references,
  or source-example links. It must pass a consumer's link check unchanged.
- The **overlay** lives in the consuming repo and carries everything specific to
  it - paths, cross-references to that repo's other skills, example links.

The commons is **bidirectional**: a generic improvement made in any repo flows
back here (when plausible - upstreaming is never automatic), while a repo-specific
tweak stays in that repo's overlay. The lifecycle is driven by the `manage-skills`
skill (`find` / `build` / `update`).

## Consuming a skill

With the GitHub CLI (>= 2.90, needs `gh auth login`):

```pwsh
# Install one skill, pinned to a tag or SHA, into the repo's .agents/skills/.
gh skill install JeremyKuhne/agent-skills <skill> --pin vX.Y.Z

# Later, review upstream drift as a normal diff.
gh skill update <skill>
```

`--pin` records the exact version (and writes provenance: source repo, ref, and
tree SHA into the copy's frontmatter). Commit the vendored copy plus any overlay.

As a plugin (skills + agent personas + MCP servers together):

```pwsh
copilot plugin marketplace add JeremyKuhne/agent-skills
copilot plugin install agent-skills@jeremykuhne-agent-skills
```

Installing the plugin brings in the MCP servers declared in `.mcp.json`. The
client may start them on demand, which runs their commands locally (the NuGet
server launches via `dnx`). Both are pinned to specific, reputable sources;
review `.mcp.json` before installing if that matters in your environment.

## Layout

| Path | Purpose |
| ---- | ------- |
| `skills/` | The shared skill cores (the `gh skill` source). |
| `agents/` | Portable agent personas (e.g. a generic reviewer). |
| `plugin.json` | Plugin manifest (skills + agents + MCP) for the CLI / Claude. |
| `.github/plugin/marketplace.json` | Marketplace listing so the plugin is installable by name. |
| `.mcp.json` | MCP servers the skills rely on (`microsoft-learn`, NuGet). |
| `FORMAT.md` | The skill file format authors follow when contributing a core. |
| `CONTRIBUTING.md` | How to author and validate a shared skill core. |
| `CODE_OF_CONDUCT.md` | The behavior expected of everyone in the project. |
| `SECURITY.md` | How to report a vulnerability privately. |
| `LICENSE` | The MIT license this project is distributed under. |

## Governance

Consumers vendor pinned, provenance-stamped copies, so stability of published
refs matters. The governance gate: a `LICENSE` (MIT), a
[security policy](SECURITY.md), [contribution terms](CONTRIBUTING.md), and a
[code of conduct](CODE_OF_CONDUCT.md); `--pin`ned installs; and immutable
releases so a pinned tag cannot be rewritten after the fact.

## License

[MIT](LICENSE).
