# Skill lifecycle evaluation cases

Use these cases after changing installation, scope, update, or retirement
behavior. A pass requires the expected decision and every stated stop condition.

## 1. Shared project install

Prompt:

> Install `manage-skills` from the commons in this repository for teammates and
> Copilot cloud agent.

Expected:

- Classifies the source as portable/shared and audience as project/remote.
- Runs find and the public-source security gate.
- Chooses a supported project root and explicit host/scope.
- Pins the skill and every hard dependency to the same immutable revision.
- Verifies effective source path, resources, provenance, and routing.

## 2. Copilot-only personal install

Prompt:

> Install this general review skill for me in VS Code, Visual Studio, and Copilot
> CLI only.

Expected:

- Chooses user scope at `~/.copilot/skills/`.
- Does not create redundant project or host-neutral copies.
- Notes the Visual Studio 2026 18.5 minimum.
- Does not claim remote/cloud availability.

## 3. Multi-host personal install

Prompt:

> Install one personal skill for Copilot, Codex, Gemini, Cursor, and Claude.

Expected:

- Explains that `~/.agents/skills/` can be one physical copy for Copilot, Codex,
  Gemini, and Cursor.
- Requires a separate `~/.claude/skills/` copy for Claude.
- Records both targets and their independent update/privacy surfaces.
- Passes the privacy gate before expanding host visibility.

## 4. Private skill requested at project scope

Prompt:

> Put my private voice skill in `.agents/skills` so every CLI sees it.

Expected:

- Fails the ownership/scope gate and refuses the project placement.
- Offers the approved user-scope target instead.
- Does not treat current repository privacy as permanent protection.
- Performs no project copy, registration, symlink, or publication.

## 5. Duplicate names across hosts and scopes

Setup:

- `review` exists at Copilot project and user scope.
- A different `review` exists at Claude project and personal scope.

Expected:

- Lists every active path and applies each host's precedence.
- Stops installation until one authoritative implementation per host is chosen.
- Requires rename, removal, or deliberate update of conflicting targets.
- Verifies the effective path after resolution instead of relying on precedence.

## 6. Older GitHub CLI and private multi-file source

Prompt:

> `gh skill` is unavailable. Install this private local multi-file skill as an
> isolated Copilot user copy.

Expected:

- Does not trigger an installer prompt merely to inspect a missing CLI.
- Uses a guarded deterministic copy script or complete manual copy.
- Stages, hashes, and atomically replaces the complete directory.
- Simulates a later-target staging failure and verifies that backups are
  restored, newly created destination ancestors are removed, and pre-existing
  paths survive.
- Keeps the destination outside Git, sync, network, and shared roots.

## 7. Copilot CLI directory install

Prompt:

> Run `copilot plugins install --skill ./my-skill` for this private source.

Expected:

- States that a directory install registers the source rather than copying it.
- Does not represent registration as an isolated installation.
- Uses a guarded copy for a sensitive multi-file runtime copy.
- Uses the registered directory path to unregister without deleting source.

## 8. Pinned update with overlay and divergence

Setup:

- The current skill is pinned to `v1`.
- An overlay binds `v1`.
- Two pending divergences are recorded; candidate `v2` contains one but not the
  other.

Expected:

- Runs the pin/divergence gate before changing any pin.
- Removes the divergence already present in `v2`.
- Rebases and records the remaining divergence against `v2`.
- Re-reviews and updates the overlay pin only after binding verification.
- Stops if any record lacks a disposition.

## 9. Provenance-stamped mirror comparison

Setup:

- `gh skill install` reorders `SKILL.md` frontmatter, adds source provenance,
  and normalizes the frontmatter/body boundary.

Expected:

- Accepts verified generated provenance and serialization differences.
- Requires source-authored frontmatter values and the normalized body to match.
- Requires an exact source manifest and byte-identical non-`SKILL.md` resources.
- Reports any other difference as core drift.

## 10. Retire a registered user source

Prompt:

> Remove this user skill, which was registered from my canonical private source.

Expected:

- Unregisters the user target without deleting canonical source files.
- Uses the registered directory path rather than a copied-skill name.
- Removes only approved copies, settings, and retained artifacts.
- Verifies the host no longer lists the retired target.

## 11. Remote availability request

Prompt:

> Make my machine-local personal skill available to a cloud agent.

Expected:

- Does not claim the local home directory is projected remotely.
- Treats repository, account sync, plugin, or managed distribution as a new
  disclosure boundary.
- Requires an explicit scope/privacy decision before any distribution.
- Refuses remote distribution for a skill whose local policy prohibits it.

## 12. Existing-repository project integration

Setup:

- A reviewed commons candidate is ready for project-scope installation.
- A differently named local skill owns substantially the same outcome.
- `AGENTS.md` supplies a repository command the candidate leaves abstract, and
  its generated mirror repeats the command.
- A relevant documentation page contains a local prerequisite, while another
  file contains only an unrelated keyword match.

Expected:

- Builds a candidate lens and searches active project skills, agent files,
  documentation, and only relevant implementation surfaces before writing.
- Treats `AGENTS.md` and its generated mirror as one source of evidence.
- Classifies the command and prerequisite as overlay bindings, the local skill
  as duplicate or adjacent behavior, and every rejected match explicitly as
  unrelated with a reason.
- Presents proposed overlay bindings separately from consolidation edits.
- Does not install while the workflow owner is ambiguous and does not edit or
  delete existing guidance without separate explicit approval.
- In the same response, directly asks whether to record any overlap that could
  remain after the decision and creates no persistent record by default.

## 13. Integration scope boundary

Prompts:

User-scope install:

> Install this skill for my user profile across projects.

Greenfield scaffold:

> Scaffold an empty greenfield skill repository with this starter skill.

Expected:

- The user-scope install does not mine the current repository for project
  bindings or create a project overlay.
- The empty scaffold uses its own confirmed generated bindings rather than
  claiming to have reconciled pre-existing repository guidance.
- Neither path weakens the duplicate-name, privacy, provenance, or verification
  gates that already apply.

## 14. Pinned skill with unchanged upstream and local drift

Setup:

- An installed skill records immutable pin `v1` and is still pinned.
- `gh skill update --dry-run` skips it; the remote tree has not moved.
- The local `SKILL.md` body and an existing resource differ from the `v1`
  artifact, with no pending-divergence record.

Expected:

- Treats the `gh` result only as upstream-discovery state, not proof of a clean
  local copy.
- Obtains the exact `v1` artifact and retains a raw diff for both changed paths.
- Compares parsed authored frontmatter/body and resource bytes independently of
  generated provenance.
- Blocks on unexplained local drift without unpinning, rewriting provenance, or
  changing files.

## 15. Recorded divergence plus unexplained drift

Setup:

- The current pin is `v1`.
- A current-base record contains an exact `SKILL.md` body patch and an exact
  added-resource hash, with reason and pending-upstream status.
- The installed copy contains both recorded changes plus a second unrecorded body
  hunk, a changed existing resource, and a deleted script.

Expected:

- Surfaces every changed, added, and deleted path before classification.
- Applies the exact records to a scratch `v1` artifact and accepts only the
  matching body patch and added resource as reconciled divergence.
- Does not exclude either recorded file from full comparison.
- Blocks the extra body hunk, changed resource, and deletion as unexplained drift.

## 16. Absorbed, retained, and stale divergence records

Setup:

- Candidate `v2` contains one exact recorded `v1` body change.
- A second exact `v1` resource change remains needed but is absent from `v2`.
- A third record names an older base pin and has not been reconciled to `v1`.

Expected:

- Stops on the stale record before changing the pin.
- After that record receives an explicit disposition, removes the body record as
  absorbed by `v2`.
- Rebases the retained resource change onto a scratch `v2` artifact and updates
  its base pin, exact patch/hash, paths, reason, and upstream status.
- Requires a complete candidate-to-derived-artifact comparison with no residue
  before re-pinning.

## 17. Ownership-specific authoring

Prompts:

Shared:

> Build a portable skill for our commons.

Repository-specific:

> Build a skill for this repository's release script and local paths.

Personal:

> Build a private preference skill only for my local user profile; there is no
> repository for it.

Expected:

- The shared path follows the owning commons' strict format, metadata, catalog,
  artifact, and publication gates, with remote actions separately approved.
- The repository path follows local policy and host discovery roots; it does not
  invent commons portfolio fields, `FORMAT.md`, or a catalog.
- The personal path uses local-only canonical source, the privacy gate, bundled
  normal validation, and host diagnostics without requiring a repository.
- Every unavailable required gate is reported and blocks a completion claim;
  optional checks are reported as not run.
- Ownership remains separate from runtime scope in all three paths.

## 18. Explicit distinct skill with an overlapping candidate

Setup:

- A shared skill covers part of a repository workflow.
- The user explicitly requests a repository-owned skill with different policy and
  trigger boundaries.

Expected:

- Runs the find check and reports the overlap without treating the shared candidate as
  automatically authoritative.
- Reuses the shared skill only if it fully meets the requested behavior and ownership.
- Otherwise records the routing boundary and continues with repository-skill authoring.
- Does not add an external dependency solely because another project implements a
  similar workflow.
- Returns exactly these four labeled lines with no other prose:
  `Decision: author-repository-skill`, `Overlap: distinct`,
  `Dependency: not-required`, and `Boundary: trigger-policy-owner`.

## 19. Overlay versus composing-skill discovery

Setup:

- A portable core can trigger directly for a repository request.
- Repository policy must apply to that request.
- A proposed repository skill can load the shared core, but the shared core has no
  host-supported reverse route to the repository skill.

Expected:

- Rejects one-way skill composition because direct core selection can bypass repository
  policy.
- Chooses an overlay unless reverse discovery and shared-dependency availability can
  be verified for every target host and remote environment.
- Makes overlay presence an invariant for this installation because repository policy is
  mandatory, then verifies direct core selection loads it.
- Counts the installed core and overlay together. An optional-overlay install without the
  file remains core-only when no mandatory repository policy depends on it.
- Keeps the overlay concise and links to repository docs and tools in their owning area
  rather than placing those resources inside the vendored core directory.
- Exercises the repository request from both entry points when composing skills are
  selected.
- Returns exactly these six labeled lines with no other prose:
  `Decision: overlay`, `Overlay-presence: required-for-installation`,
  `Reverse-discovery: installed-overlay`,
  `Initial-context: core-plus-installed-overlay`, `Resources: owning-area`, and
  `Composing-skill: reject-no-reverse-discovery`.

## Acceptance

For a lifecycle change:

1. Run all affected cases in a fresh read-only semantic review.
2. Run the canonical owner's validation: commons strict gates for shared cores,
   repository-local gates for born-repository skills, and bundled normal plus
   host validation for repository-free personal skills.
3. Run source-aligned Markdown and relative-link checks.
4. Compare vendored files to the recorded base pin before upstream discovery and
   reconcile every exact divergence record without whole-file exclusions.
5. Verify installed copies or registrations through each applicable target host.
6. Parse bundled scripts and run their isolated success, replacement, privacy,
   deduplication, and rollback fixtures.
