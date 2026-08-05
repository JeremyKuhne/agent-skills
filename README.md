# agent-skills

Shared agent skills and MCP configuration for Jeremy Kuhne's .NET repositories.
This is the **commons**: the single upstream source from which each repository
vendors pinned, provenance-stamped copies of the skills it needs.

It is both a [`gh skill`](https://docs.github.com/copilot/reference/copilot-cli-reference/cli-plugin-reference)
source and a GitHub Copilot CLI plugin marketplace.

> **Status: pre-1.0 and in active fleet use.** The repository currently ships 18
> shared skill cores and two reviewer agents. Deterministic source,
> isolated-install, plugin, scaffold, and synthetic-consumer gates are in place.
> A `create-pr` model-evaluation vertical slice is operational; portfolio-wide
> routing and outcome coverage remain future work.

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
skill (`find` / `build` / `review` / `update` / `retire`).

## Consuming a skill

With the GitHub CLI (>= 2.90, needs `gh auth login`):

```pwsh
# Install one skill, pinned to a tag or SHA, into the repo's .agents/skills/.
gh skill install JeremyKuhne/agent-skills <skill> --pin vX.Y.Z

# Later, review upstream drift as a normal diff.
gh skill update <skill>
```

`gh skill install` installs only the named skill; it does not resolve the
portfolio's `metadata.requires` relationships. Check the **Requires** column in
the [skills catalog](skills/README.md#portfolio-contract) and install every hard
dependency at the same pin. For example, `cswin32-com` requires
`cswin32-interop`:

```pwsh
gh skill install JeremyKuhne/agent-skills cswin32-interop --pin vX.Y.Z
gh skill install JeremyKuhne/agent-skills cswin32-com --pin vX.Y.Z
```

`--pin` records the exact version (and writes provenance: source repo, ref, and
tree SHA into the copy's frontmatter). Commit the vendored copy plus any overlay.

As a plugin (skills + agent personas + MCP servers together):

```pwsh
copilot plugin marketplace add JeremyKuhne/agent-skills
copilot plugin install agent-skills@jeremykuhne-agent-skills
```

Installing the plugin brings in the MCP servers declared in `.mcp.json`. The
client may start them on demand: the NuGet server runs locally via `dnx` and is
version-pinned (`NuGet.Mcp.Server@1.4.3`), while `microsoft-learn` is a hosted
HTTP endpoint on an official Microsoft domain. Review `.mcp.json` before
installing if that matters in your environment.

The plugin install is smoke-tested with GitHub Copilot CLI. The skill cores use
the vendor-neutral Agent Skills format and can be vendored for other compatible
hosts, including Claude Code, but this repository does not currently claim a
CI-tested Claude plugin-marketplace install.

## Layout

| Path | Purpose |
| ---- | ------- |
| `skills/` | The shared skill cores (the `gh skill` source). |
| `agents/` | Portable agent personas (e.g. a generic reviewer). |
| `plugin.json` | GitHub Copilot CLI plugin manifest (skills + agents + MCP). |
| `.github/plugin/marketplace.json` | Marketplace listing so the plugin is installable by name. |
| `.mcp.json` | MCP servers the skills rely on (`microsoft-learn`, NuGet). |
| `FORMAT.md` | The skill file format authors follow when contributing a core. |
| `RELEASING.md` | Shared SemVer, release gates, and immutable-tag procedure. |
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
