<!-- Describe the change and why it is needed. -->

## Summary

## Behavior contract

<!-- For skill/agent behavior changes. Write N/A for non-behavioral changes. -->

- Positive trigger:
- Near-miss that must not invoke:
- Expected output or artifact:
- Action that must remain gated or forbidden:

## Checklist

- [ ] Markdown lints clean (`npx --yes markdownlint-cli2 --config .markdownlint.jsonc "**/*.md" "#node_modules"`).
- [ ] Links resolve offline (every relative link points to a file in the repo).
- [ ] New or changed skill cores stay portable (no repo-specific paths, project
      names, or links into a particular repository's tree) - see
      [FORMAT.md](../FORMAT.md).
- [ ] Strict portfolio and reference validation pass for every source skill.
- [ ] Isolated installed-artifact tests pass (`Invoke-Pester ./tests`).
- [ ] Portfolio metadata, overlay binding, compatibility, and relationships are
      accurate; the generated catalog is current.
- [ ] Executable helpers/templates have focused tests or a documented reason the
      existing contract suite is sufficient.
