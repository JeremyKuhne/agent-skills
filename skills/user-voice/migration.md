# Convert an existing private voice skill

Do not rewrite the working skill in place or assume its installed copy matches
canonical source.

Every migration starts with the complete source and installed-copy inventory
below. Do not create or translate the standard candidate before that inventory
has an unambiguous owner, effective path, and divergence disposition.

## Repair an existing standard profile

When an evaluation contract contradicts already approved profile scope, repair
the private source before migration: identify the stale gate and affected
positive cases, align them with the exact approved profile version, rerun all
hard gates and voice cases, update the private audit, and validate the runtime
source. Keep the installed copy unchanged until a separate replacement approval,
then verify complete manifests, hashes, and singular discovery. A contract
repair does not grant new profile scope or source consent.

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

## Recover distinctive nuance

Classify each legacy section as a safety boundary, source-supported durable
decision, context variation, mechanic or tolerance, artifact pattern,
unsupported assertion, identifying example, or obsolete behavior. Do not copy
legacy prose wholesale.

For each potentially valuable decision missing from the standard candidate:

1. name the target context and suspected nuance dimension;
2. gather an independent, targeted source batch under current consent;
3. run all seven nuance passes and update the private matrix;
4. create an inactive structured rule only when the evidence floor is met;
5. seal preference, impact, and genericity cases before presentation;
6. compare legacy, candidate, and general writing on identical held-out briefs; and
7. promote only when the candidate matches or beats legacy without weakening a hard gate.

Record rejected, contextualized, and unsupported legacy decisions so later
reviews do not rediscover them as unexplained drift.

## Compare before replacement

Run legacy and new hard gates, then blinded same-brief comparisons among the
installed legacy skill, standard candidate with `technical-writing`, and general
writing. The candidate must be at least as safe, cover supported legacy
contexts, and meet user-preference or edit-effort gates.

Use `scripts/Test-UserVoiceThreeWayComparison.ps1` to seal and validate seven
new briefs: a short correction, extended design disagreement, proposal, defect
response, decision summary, investigation guidance, and low-confidence
professional message. Replace any case where two versions are exactly the same;
do not ask the user to rate duplicate text.

Follow [interaction.md](interaction.md). Ask `Which version would you rather
edit?`, not whether the user approves a legacy comparison. Collect how much
editing each version needs and the first meaningful edit separately. Hide which
version came from the new draft, old profile, or general writing until all seven
cases are answered.

Every rating question repeats the practical task and the complete version being
rated. A shared message elsewhere in the dialog is not enough. After the user
chooses a version, repeat that complete version again before asking for the first
meaningful edit. Do not ask a separate starting-point question unless the user
selected a tie, none of the versions, or a manual replacement.

The new draft passes this check only when all three versions pass the safety
checks, the new draft beats the old profile in at least three cases, and the old
profile beats the draft in no more than one. When general writing wins, compare
the edit ratings for the new and old profiles; equal ratings count as a tie.
Accepting the result records comparison evidence only; it does not approve,
activate, install, archive, or remove a profile.

The user chooses to keep legacy active, install and archive it, retain both
canonical sources with one installed, or defer. Installing the candidate and
removing legacy are separate actions. Verify host discovery after each and keep
reviewed rollback source until retirement is approved.
