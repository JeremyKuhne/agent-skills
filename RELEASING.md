# Releasing

This repository has one pre-1.0 release line for the skill source and the
Copilot plugin. A release tag `vX.Y.Z`, `plugin.json` version `X.Y.Z`, and the
matching marketplace plugin entry are the same distribution version.

`main` carries the intended next version. CI permits an untagged commit, but when
`HEAD` has a `vX.Y.Z` tag the repository contract test requires both manifests to
contain exactly `X.Y.Z`.

## Version changes

- Patch: corrections that preserve skill routing, metadata contracts, and
  required tools.
- Minor: a new skill or agent, a new optional capability, or an additive metadata
  or overlay contract change.
- Major: removal or rename of a skill/agent, a newly required dependency or
  overlay, incompatible trigger behavior, or a breaking distribution change.

Before 1.0, breaking changes may use a minor bump, but the release notes must
label them **Breaking** and give consumers an explicit migration.

## Release gate

Run from a clean checkout of the candidate commit:

```pwsh
npx --yes markdownlint-cli2 --config .markdownlint.jsonc "**/*.md" "#node_modules"
./tools/Validate-AgentFiles.ps1
./tools/Test-AgentFileLinks.ps1
./skills/manage-skills/scripts/Validate-Skills.ps1 ./skills -RequirePortfolioMetadata
Get-ChildItem ./skills -Directory | ForEach-Object {
    npx --yes skills-ref@0.1.5 validate $_.FullName
}
./tools/Update-SkillCatalog.ps1
Invoke-Pester ./tests
./tests/plugin/Invoke-PluginSmoke.ps1
./tests/repository/Invoke-SyntheticConsumer.ps1
./tests/engineering-baseline/Invoke-ScaffoldCanary.ps1 -Archetype library -TestRunner mstest
```

The pull request must also have a green stable scaffold matrix. The weekly
preview canary is advisory for the current release but must have a tracked issue
when red.

Real model evaluations are manual and local to control token use; do not add
them to a pull-request, tag, or scheduled workflow. For a capability release or
a change to skill routing, safety rules, overlays, or the evaluation harness,
run one report-only calibration locally, then run the current model baseline as
a gate:

```pwsh
./evals/Invoke-SkillEvals.ps1 `
  -Model gpt-5.4 `
  -RunCount 1 `
  -OutputDirectory ./eval-calibration `
  -ReportOnly
```

```pwsh
./evals/Invoke-SkillEvals.ps1 `
  -Model gpt-5.4 `
  -RunCount 3 `
  -OutputDirectory ./eval-results
```

Every safety assertion must pass in every run. Investigate any routing or
binding failure; do not average a forbidden action into a passing score. Keep
the summary with the release evidence, but do not publish raw transcripts by
default.

After the candidate commit is pushed and before tagging, prove the exact SHA can
be installed as a pinned consumer artifact:

```pwsh
$candidateSha = git rev-parse HEAD
./tests/repository/Invoke-SyntheticConsumer.ps1 `
  -SourceRepository JeremyKuhne/agent-skills `
  -Pin $candidateSha
```

## Cut the release

1. Update both manifests to `X.Y.Z` and regenerate the skill catalog.
2. Summarize added, changed, deprecated, removed, fixed, and security-relevant
   behavior. Call out metadata, overlay, compatibility, or required-tool changes.
3. Merge the candidate only after all release gates pass.
4. Create annotated tag `vX.Y.Z` on that commit and push it. Tag CI reruns the
  validators, plugin smoke, pinned synthetic consumer, Pester, and stable
  scaffold canaries against the tagged commit.
5. Create a GitHub Release from the tag only after tag CI is green.
6. Verify the release is immutable in repository settings. Tag CI's synthetic
  consumer must have recorded `vX.Y.Z` provenance and source tree SHAs.
7. Re-pin the reference consumer only after its overlay, link, and build canaries
   pass against the new tag.

Never move or recreate a published tag. A correction after publication is a new
patch release.
