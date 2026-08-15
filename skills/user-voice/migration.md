# Convert an existing private voice skill

Do not rewrite the working skill in place or assume its installed copy matches
canonical source.

Every migration starts with the complete source and installed-copy inventory
below. Do not create or translate the standard candidate before that inventory
has an unambiguous owner, effective path, and divergence disposition.

## Inventory

Locate canonical source plus every project, user, plugin, custom, linked,
registered, synchronized, and remote copy visible to each host. Verify source
privacy, compare file lists and hashes, record active precedence and duplicate
names, and stop while ownership, divergence, or effective path is unresolved.

## Stage an empty standard candidate

Run `scripts/New-UserVoiceMigration.ps1` with the source and an undiscovered
private staging root. It creates a source manifest, parsed metadata, empty
standard candidate, migration map, and install inventory. It never copies source
prose, examples, evidence, profile rules, or identity into the candidate.
When the existing skill is in a private GitHub repository, pass
`-ExistingSkillPrivateGitHubSource`; the migration verifies its reachable
history and current visibility before inventory. Keep the staging root local
unless it independently passes the private-source workflow.

Classify legacy content:

| Existing content | Standard disposition |
| --- | --- |
| Routing and safety | Generic runtime `SKILL.md` |
| Durable writing behavior | Canonical private profile |
| Sources and calibration | De-identified maintenance cards |
| Behavioral cases | Sanitized private evaluations |
| Installation notes | Generated install guide and target ledger |
| Raw examples or messages | Drop after approved extraction |

For every removed instruction, identify its canonical replacement. Preserve
grounding, authority, privacy, local-output, and remote-action boundaries. Move
user-specific composition into the profile and exact provenance out of the
runtime package. Drop accidental mechanics and tone hazards.

## Compare before replacement

Run legacy and new hard gates, then blinded same-brief comparisons among the
installed legacy skill, standard candidate with `technical-writing`, and general
writing. The candidate must be at least as safe, cover supported legacy
contexts, and meet user-preference or edit-effort gates.

The user chooses to keep legacy active, install and archive it, retain both
canonical sources with one installed, or defer. Installing the candidate and
removing legacy are separate actions. Verify host discovery after each and keep
reviewed rollback source until retirement is approved.
