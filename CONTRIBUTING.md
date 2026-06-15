# Contributing

Contributions are welcome. This repository is the **commons**: the upstream source
of portable skill cores that each consuming repository vendors. See the
[README](README.md) for the sharing model and [FORMAT.md](FORMAT.md) for the file
format.

## Pull requests

By submitting a pull request you:

1. Confirm that you wrote the content (or otherwise have the right to contribute
   it), **and**
2. Agree that your contribution is licensed under the MIT License that governs
   this project (see [LICENSE](LICENSE)).

You retain copyright to your work; you simply grant Jeremy W. Kuhne and all
downstream users a perpetual, irrevocable MIT license to use, modify, and
redistribute it.

## Authoring a skill

Each skill is a directory under `skills/` containing a `SKILL.md` plus optional
sibling files. The directory name must match the `name` field in `SKILL.md`
exactly, or the skill silently fails to load. [FORMAT.md](FORMAT.md) is the full
reference; the essentials:

- Keep the `SKILL.md` body small - it loads on every trigger. Push deep detail
  into sibling `*.md` files that load on demand.
- Write the `description` to say what the skill does **and when to use it**, with
  trigger phrasing - that line is the entire auto-invocation surface.
- Keep cores **portable**. No repo-specific paths, project names, target-framework
  monikers, or links into a particular repository's tree. Anything a core truly
  needs travels with it as a bundled `references/` doc or a portable sibling;
  everything repo-specific belongs in the consuming repo's overlay.

## Validating locally

CI runs two checks on every push and pull request; run them before opening a PR:

```pwsh
# Lint Markdown (auto-discovers .markdownlint.jsonc).
npx --yes markdownlint-cli2 "**/*.md" "#node_modules"

# Offline link check (same engine as CI; requires the lychee binary).
lychee --no-progress --offline "**/*.md"
```

Both must pass. Because the link check runs `--offline`, every relative link must
resolve to a file that exists in the repository.

## Style

- Use plain ASCII in prose: a hyphen (`-`), not an em-dash or an HTML entity.
- Prefer short, declarative sentences and match the surrounding document's voice.
