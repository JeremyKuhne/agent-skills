# Scaffold locally

Run the bundled `scripts/New-SkillRepository.ps1` only after the decision
summary is confirmed. Pass every resolved choice explicitly. The script is
noninteractive, requires an empty destination, and never creates or modifies a
remote repository.

For example:

```pwsh
./scripts/New-SkillRepository.ps1 `
  -Root C:\src\team-skills `
  -Name team-skills `
  -Description 'Shared Agent Skills for the team.' `
  -Role hybrid `
  -Infrastructure team-ci `
  -Visibility private `
  -Audience team `
  -Owner Contoso `
  -Clients github-copilot,claude-code `
  -SelectedSkills manage-skills,security-review `
  -ResolvedSkills manage-skills,agent-files-review,technical-writing,security-review `
  -SkillsRef v1.2.3
```

`ResolvedSkills` is mandatory when `SelectedSkills` is nonempty. Resolve it
through the skill-lifecycle workflow from the exact selected source revision;
the script rejects an implicit or incomplete declaration rather than guessing
dependencies from a moving branch.

## Generated roles

- **Source** creates `skills/`, source format guidance, and a source catalog.
- **Consumer** creates `.agents/skills/` for pinned runtime copies and their
  overlays.
- **Hybrid** creates both roots and keeps canonical source distinct from
  runtime dependencies.

Do not put canonical authored skills under `.agents/skills/`. Do not treat a
vendored runtime copy as source merely because it is committed.

## Infrastructure presets

The generator composes real template sets:

- `base` supplies repository identity, roots, ignore rules, license, and a
  README tailored to role, visibility, clients, upstreams, and consumption.
- `validation` adds the bundled skill validator, catalog generator, Markdown
  and relative-link configuration, and Pester contracts.
- `ci` adds deterministic validation and report-only drift workflows,
  dependency updates, contribution guidance, and selected governance.
- `distribution` adds only explicitly selected release, plugin, marketplace,
  agent, or MCP files.
- `evaluations` adds the optional behavioral evaluation harness.

Omitted capabilities must not appear as dead README instructions or empty
manifests.

## Starter skills

Resolve the complete transitive requirement closure before invoking the script
and show direct versus dependency-added choices. Install every selected skill
from the same immutable source revision. If `gh skill` or the source is
unavailable, the generator records exact pending commands and does not claim
the skills were installed.

Generate an overlay for repository-specific bindings without editing the
vendored core. Record the chosen upstream order in the `manage-skills` overlay.

## README

The generated README must describe only selected behavior:

- purpose, role, audience, and visibility-safe identity;
- `skills/` versus `.agents/skills/` where applicable;
- selected skills and requirement closure;
- consumption commands valid for the selected visibility and distribution;
- selected client roots, upstream order, trust policy, pinning, and provenance;
- validation, contribution, update, and release commands that exist; and
- explicit limitations for omitted infrastructure or unverified clients.

Local-only output contains no fictional remote URL or remote install command.
Private output states its access requirement without implying public
availability.

## Validate

Run every generated local check, then inspect `git status` if Git was selected.
At minimum, verify the expected tree and README conditionals. For Validated or
higher, run the generated validator, catalog check, Markdown lint, relative-link
check, and Pester contracts using only files in the generated repository.

If generation fails, report whether the script removed the newly created tree
or left a recovery report. Never describe a partial tree as complete.
