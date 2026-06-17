# Scaffold a new repository

The greenfield verb: stand up a new repository built to [baseline.md](baseline.md)
from nothing. Triggered by "create a new repository for a command-line tool",
"scaffold a new library", or "set up a new project with CI and publishing".

Build the local tree directly; stop at the remote boundary (repository creation,
branch protection, publishing) and propose those for explicit approval.

## 1. Confirm the archetype and identity

Pick the archetype - it selects which baseline items apply:

| Archetype | Ships | Adds over the core |
| --------- | ----- | ------------------ |
| **CLI tool** | A `dotnet` tool executable | `PackAsTool` + `ToolCommandName`; a thin arg-parsing entry point |
| **Class library / NuGet package** | A single library package | Full package metadata, SourceLink, package validation |
| **Multi-target library** | A library across a modern TFM and an older one | The library set plus the polyfill strategy for the downlevel target |

Confirm, before writing files, with one short prompt: the repository name, the
target framework(s), the package id and one-line description, the license
(default MIT), and the owner. Do not invent these - if the user did not supply
them, ask once. The literals collected here are what a brownfield repo would
keep in its overlay.

## 2. Lay down the foundation (domains 1-2)

Create the local tree and the centralized build:

- `LICENSE` (the chosen SPDX license), `README.md` (name, install, usage),
  `.gitignore` (toolchain-scoped), `.gitattributes` (`* text=auto`),
  `.editorconfig` (indentation, encoding, naming, severities).
- `Directory.Build.props` / `Directory.Build.targets` with `Nullable=enable`, a
  current `LangVersion`, `ImplicitUsings`, `TreatWarningsAsErrors` (plus a short
  `WarningsNotAsErrors` escape list), `EnableNETAnalyzers` with a chosen
  `AnalysisLevel`, `EnforceCodeStyleInBuild`, and `ContinuousIntegrationBuild`
  gated on the CI environment.
- `Directory.Packages.props` with `ManagePackageVersionsCentrally=true`.
- `global.json` pinning the SDK with a `rollForward` policy.
- The shippable project (library or tool entry point) and a solution.
- For a multi-target library, express the framework set centrally and add the
  downlevel polyfill packages conditioned on the older target - hand the polyfill
  design itself to the polyfill skill a consuming repo names in its overlay.

## 3. Wire testing (domain 3)

- A test project with a maintained runner, referencing the shippable project.
- Coverage collection configured, and a patch-coverage gate to add once CI exists.
- Add a perf or fuzz project only if the tool/library has a hot path or an
  untrusted-input surface - do not scaffold empty ones.

## 4. Wire packaging and versioning (domains 4-5)

- **Library / tool:** complete package metadata (`PackageId`, `Description`,
  `Authors`, `PackageLicenseExpression`, `PackageProjectUrl`, `RepositoryUrl`,
  `RepositoryType`, `PackageReadmeFile`, `PackageTags`), Source Link with symbol
  output, and (library) `EnablePackageValidation`. A CLI tool adds
  `PackAsTool=true` and a `ToolCommandName`.
- Tag-driven deterministic versioning (for example MinVer or
  Nerdbank.GitVersioning) with a chosen tag prefix.
- A release record: start a `CHANGELOG.md`, or decide to curate GitHub Releases
  and note that choice in the README.

## 5. Wire CI/CD (domain 6)

Add the workflows, actions pinned by full commit SHA with the version in a
trailing comment, and a top-level `permissions: contents: read`:

- A build-and-test workflow on push and pull request to the default branch:
  checkout (full history if versioning needs tags), set up the pinned SDK,
  restore, build and test in Release with coverage, and a stable aggregate
  status-check name for branch protection to require. Add concurrency that
  cancels superseded pull-request runs.
- **Library / tool:** a publish workflow triggered by a version tag, using OIDC
  [trusted publishing](https://learn.microsoft.com/en-us/nuget/nuget-org/trusted-publishing)
  (`id-token: write`, a short-lived key) - never a stored long-lived API key.
  Validate the tag against a SemVer pattern before pushing.

## 6. Wire security and governance (domains 7-8)

- `SECURITY.md` (private reporting channel, disclosure expectation),
  `dependabot.yml` (the relevant ecosystems), a CodeQL workflow, `CONTRIBUTING.md`,
  `CODE_OF_CONDUCT.md` (Contributor Covenant), and issue / pull-request templates.
- A `CODEOWNERS` file if there will be more than one owner.

## 7. Wire agent enablement (domain 9)

- An `AGENTS.md` and the generated tool mirror, the skills location, and the
  agent-file gate (frontmatter validation, mirror check, markdown lint, offline
  link check).
- Vendor the universal skill tier and wire the validator, link checker, and
  drift job by handing off to the skill-lifecycle skill and the fleet onboarding
  runbook - do not reinvent that pipeline here. A consuming repository names both
  in its overlay.

## 8. Validate locally

Build and run the tests. Run the repo's agent-file gates over the new agent
files. Confirm a Release `pack` produces a package with the expected metadata
(library / tool). Fix anything red before going near the remote.

## 9. Propose the remote setup (the boundary)

Everything so far was local. The remaining steps are remote or hard to reverse -
**propose each as an exact command and wait for an explicit publishing verb.**
Do not run them silently:

- Create the repository (`gh repo create`, with visibility chosen by the user).
- Push the initial commit and set the default branch.
- Branch protection / a ruleset on the default branch: require the aggregate
  status check, require pull requests, block force-push and deletion. Emit the
  `gh api` call or ruleset JSON for review.
- Enable secret scanning and push protection.
- Register the trusted-publishing policy on the gallery before the first publish.

Present these as a numbered checklist with the exact commands, then stop. The
user runs them, or approves running them, one at a time.

## 10. Report back

Summarize the archetype, the tree created, what was validated locally, and the
remote checklist still awaiting approval. End with the single next action.
