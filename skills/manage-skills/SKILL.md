---
name: manage-skills
description: Manage Agent Skills across discovery, creation, installation, review, and removal. Use for scope, overlays, provenance, or sync.
license: MIT
compatibility: Uses host-native skill discovery. GitHub CLI 2.90 or later enables provenance-aware cross-host install and update. The bundled user-copy installer requires PowerShell 7 and git; private GitHub sources also require GitHub CLI.
metadata:
  portability: portable
  applicability: universal
  binding: optional-overlay
  risk: remote-write
  maturity: canary
  requires: agent-files-review, technical-writing
  related: none
---

# Manage skills

If `overlay.md` exists beside this file, read it before acting; it contains
repository-specific bindings. This core remains usable without it.

Keep source ownership separate from installation scope. A portable core can be a
project or user install; a repository-specific skill belongs to that repository; a
personal skill can remain outside every repository.

## Route the request

| Ask | Do | Detail |
| --- | --- | ------ |
| Find or compare | Search installed, commons, then public sources; check applicability. | [find.md](find.md) |
| Create or build | Search first, then reuse, adapt, or author according to the requested ownership and behavior. | [build.md](build.md) |
| Install or vendor | Choose owner, scope, hosts, and destination; integrate project installs. | [install.md](install.md) |
| Review | Check routing, execution, context cost, portability, and lifecycle placement. | [review.md](review.md) |
| Update or sync | Compare the installed artifact with its pin; classify common changes and local deviations. | [update.md](update.md) |
| Retire or remove | Find dependents and installed targets before removal. | [retire.md](retire.md) |

Start with the selected detail page. Load only additional pages that its branch
explicitly invokes. Creation starts with `find`; project installation into an existing
repository also runs `integrate`; create, install, and update finish with `review` and
the canonical owner's file checks.

## Choose ownership and composition

- **Shared core:** portable behavior another repository can consume unchanged.
- **Repository skill:** one repository's paths, policy, or distinct workflow.
- **Personal skill:** one person's private or cross-project behavior.

When a shared core needs repository specialization, choose the integration mechanism
deliberately:

- Use an **overlay** when repository policy must be discovered whenever the shared core
  runs. The mandatory loader gives one routing identity and reverse discovery from the
  shared core to repository policy.
- Use a **composing repository skill** when it owns a distinct trigger or outcome and can
  reliably load the shared dependency. Also prove the shared skill cannot bypass required
  repository policy; a local-to-shared reference alone is one-way discoverability.

Initial context is `SKILL.md` plus every file the workflow unconditionally instructs the
agent to read. The mandatory overlay loader therefore puts `overlay.md` in initial
context. Keep it to direct bindings and routing. Put repository-only documentation and
tools with their owning area, then link to them from the overlay instead of placing them
in the vendored core directory.

## Preserve the source boundary

A vendored core remains an unchanged mirror of its immutable pin. Classify every local
core edit:

- common behavior -> ask before upstreaming, then re-pin after it lands;
- repository deviation -> move it to the overlay; or
- common change not yet upstreamed -> record an exact pending divergence.

Never leave unexplained core drift. See [update.md](update.md) for the comparison and
pin workflow.

## Validate and stop

Follow the canonical owner's rules. Use `agent-files-review` and `technical-writing` for
repository-backed sources. For repository-free personal skills, use the bundled validator,
host diagnostics, and direct resource checks.

- Validate a skill with [scripts/Validate-Skills.ps1](scripts/Validate-Skills.ps1).
- Use [scripts/Install-UserSkill.ps1](scripts/Install-UserSkill.ps1) only after the
  user-scope privacy and target checks in [install.md](install.md).
- Start a downstream overlay from [assets/overlay.md.tmpl](assets/overlay.md.tmpl) after
  completing [integrate.md](integrate.md).
