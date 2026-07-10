# Fleet onboarding status

The concrete, changing state of onboarding each repository into the commons. The
repo-agnostic methodology this applies - the audit buckets, the five-stage
pipeline, the producer and drift loops, and the governance gate - lives in the
generic [onboarding runbook](onboarding-plan.md). This document is its living
fleet companion: update it as repos onboard.

## Fleet status

`Last checked` is the date a maintainer verified the repository state, not the
date this document happened to be edited. Re-check stale rows before making a
fleet decision.

| Repo | Owner | Commons pin | Consumes commons | Produces | Onboarding state | Last checked |
| ---- | ----- | ----------- | ---------------- | -------- | ---------------- | ------------ |
| **touki** | `JeremyKuhne` | mixed `v0.7.0`-`v0.8.1` | 13 commons cores | the universal and domain cores | **Onboarded** - reference consumer | 2026-07-09 |
| **filtrace** | `JeremyKuhne` | N/A | nothing yet | the `filtrace` tool-shipped skill | **Producer only** - does not consume the starting tier | 2026-06-16 |
| **madowaku** | `JeremyKuhne` | N/A | nothing yet (4 local forks) | `cswin32-interop`, `cswin32-com` | **Not onboarded** - forks to reconcile | 2026-06-16 |
| **thirtytwo** | `JeremyKuhne` | N/A | nothing (no `.agents/`) | none | **Greenfield** - needs scaffolding first | 2026-06-16 |
| *(future repos)* | TBD | N/A | - | - | Use the generic checklist in the [runbook](onboarding-plan.md) | Not checked |

## Per-repo onboarding checklists

Each checklist applies the [onboarding runbook](onboarding-plan.md) to one repo;
the stage and section references point into that document.

### filtrace (producer -> add consumer)

filtrace already produces its tool-shipped skill; onboarding makes it a
*consumer* of the universal tier so its own development gets the same review and
PR discipline.

- [ ] Audit: only `filtrace` exists locally (the canonical tool skill) - no forks.
- [ ] Scaffold if needed: confirm `.agents/skills/` catalog + validator + link
      checker + `agent-files.yml` exist; stand up any missing piece.
- [ ] Vendor the universal tier (`security-review`, `pre-pr-self-review`,
      `create-pr`, `address-pr-feedback`, `agent-files-review`), each `--pin`ned,
      with overlays for filtrace paths. Include `manage-skills` (now in the commons
      as of `v0.8.0`).
- [ ] Domain: vendor `performance-testing` (filtrace has a perf surface) and
      `scratch-buffer-strategy` as applicable.
- [ ] Leave `filtrace`'s own skill as the canonical source; do not vendor it back
      into itself.
- [ ] Wire the drift job; run both gates green.

### madowaku (merge consumer + producer)

The richest reconciliation: madowaku carries four local forks and owns two
CsWin32 skills the commons lacks.

- [ ] Audit and bucket the four local skills:
  - `performance-testing` -> **Fork**: reconcile against the commons core; its
    generic parts already match, so it should drop to core + a ~20-line overlay.
  - `cswin32-interop`, `cswin32-com` -> **Local-generic**: promote both into the
    commons as a new `cswin32` domain group, then vendor back.
  - `publish-release` -> **Local-specific**: keep local (dual-stream release
    detail is repo-bound).
- [ ] Vendor the universal tier with overlays for madowaku's
      `net10.0-windows...` moniker and `madowaku.perf` project.
- [ ] If fuzzing is wanted, stand up `madowaku.fuzz` to match the repo layout,
      then vendor `fuzz-testing` and bind the project in its overlay.
- [ ] Reconcile against madowaku's *different* instruction set (`interop`,
      `msbuild`, `tests` - no `perf`/`polyfills`); a core linking to a missing
      instruction file fails its link check.
- [ ] Run both gates green; record every fork resolution in the ledger.

### thirtytwo (greenfield consumer)

- [ ] Stage 2 scaffold first: stand up `.agents/skills/` + catalog + `FORMAT.md`
      + validator + link checker + `agent-files.yml` + `AGENTS.md`.
- [ ] Vendor the universal tier, plus the `cswin32-interop` / `cswin32-com`
      domain skills (they apply here, unlike touki).
- [ ] Record thirtytwo's `src/<root>` + `<root>_tests` layout in each applicable
      overlay.
- [ ] Stand up `src/`-nested perf/fuzz projects before vendoring those
      project-gated skills.
- [ ] Run both gates green.

## Fleet deduplication and promotion ledger

The live tracker of what must flow up, come down, or be reconciled across the
fleet. Each row ends in a recorded state; an unexplained divergence is the alarm.

| Item | Origin | Kind | Target | Status |
| ---- | ------ | ---- | ------ | ------ |
| `cswin32-interop` | madowaku (fork) | Local-generic, domain | Promote to commons as a `cswin32` group | **Pending** - madowaku not yet onboarded |
| `cswin32-com` | madowaku (fork) | Local-generic, domain | Promote to commons | **Pending** |
| `performance-testing` | madowaku (fork) | Fork of commons core | Reconcile to core + overlay | **Pending** |
| `manage-skills` | touki (local) | Local-generic, universal | Promote to commons, vendor back | **Resolved** - commons `v0.8.0`, vendored `v0.8.1` |
| `fuzz-testing` | touki (local) | Local-generic, domain (project-gated) | Promote to commons | **Resolved** - commons `v0.8.0`, vendored `v0.8.1` |
| `roslyn-analyzers` | touki (local) | Domain (project-gated) | Promote to commons | **Resolved** - commons `v0.8.0`, vendored `v0.8.1` |
| `il-copy-inspection` | touki (local) | Domain portable core | Promote to commons | **Resolved** - commons `v0.8.0`, vendored `v0.8.1` |
| `dotnet-polyfills` | commons (born-shared) | Domain, consume side | Vendor into touki with overlay | **Resolved** - born in commons `v0.8.0`, vendored `v0.8.1` |
| `polyfill-dotnet-api` | touki (local) | Domain, authoring side | Keep local; defer the source survey to `dotnet-polyfills` | **Resolved** - kept local, slimmed to defer |
| `performance-testing` | touki | Vendored `v0.7.0` | - | **Resolved** - byte-identical to commons |
| `publish-release` | touki, madowaku | Local-specific (both) | Keep local in each | **Resolved** - no shared core |
| `run-tests-on-wsl` | touki | Local-specific | Keep local | **Resolved** |
| `filtrace` | filtrace | Tool-shipped (canonical) | Vendor into consumers from the tool repo | **Resolved** - vendored into touki |

The first three rows are the open onboarding/promotion backlog; resolving them is
the bulk of bringing madowaku - and then filtrace and thirtytwo - fully into the
commons.
