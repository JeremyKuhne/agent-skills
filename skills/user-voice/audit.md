# Audit a user voice skill

Lead with findings ordered by consequence.

## Privacy and source

- Prove canonical ownership, source visibility, installed copies, active host
  paths, duplicate names, file lists, and hashes.
- Reject raw source, exact private provenance, profile-subject identity, PII,
  identifying internal detail, reversible redactions, absolute user paths,
  public/internal repositories, and unapproved hosts or synchronization.
- For a vendored public lifecycle core, verify installer-generated
  `github-repo`, `github-ref`, `github-pinned`, `github-path`, and
  `github-tree-sha` fields separately. They identify the reviewed public source,
  not the profile subject. Review source-authored discovery metadata for generic
  routing, then run the profile-content privacy scan over the body and bundled
  resources rather than the provenance-bearing header.
- Treat deterministic scanning and semantic privacy review as independent hard
  gates. The user then approves the de-identified profile during read-back.
- Verify consent matches provider, host, account, source, retention, schema,
  and expiry.

## Grounding, authority, and action

The profile may shape form but never establish statements such as "This is our
bug", "I will fix it tomorrow", "We approved the release", "I tested every
platform", or "Post this reply". Test each boundary directly. A readiness result
never authorizes publication.

## Best-self and tone

The target is writing the user recognizes, endorses, and prefers under supported
conditions, not the average of every historical artifact.

Exclude sarcasm, irony, teasing, rhetorical pressure, reader-grading words,
motive or competence attribution, personal blame, bare verdicts, ambiguous
force, vague blamelessness that erases action, and habitual warmth or humor that
obscures severity. Do not describe these as user traits or include them as
anti-examples in the runtime package.

Preserve the legitimate substance: controlling constraints, mechanism,
evidence, compatibility boundaries, authorized action and role, system
conditions, control gaps, required response, uncertainty, and the smallest
complete argument. The user must explicitly approve a safer rendering before it
becomes profile evidence; otherwise mark the context unsupported.

## Behavioral quality

- Separate draft, revise, and review output forms.
- Verify supported contexts and conservative general-writing fallback.
- Verify every analyzed source was confirmed before use and every claimed
  context meets its direct-evidence and diversity floor.
- Require all seven nuance passes to record `observed:` or `not-observed` and
  validate the private matrix against the exact canonical profile.
- Run hard gates before voice preference and compare against general writing on
  identical sanitized briefs.
- Verify every elicitation case was sealed against a pre-existing draft rule and
  context; reject interview-only durable rules.
- Require each promoted context to pass its five-case genericity threshold and
  block unresolved high-impact results.
- Measure factual fidelity, context fit, authority safety, user preference,
  substantive edit effort, model calls, duplicated questions, and generation
  rounds.
- Require one fact ledger and no more than one full composition pass.
- Before replacing an old profile, require the sealed seven-case comparison to
  pass: every option passes safety checks, the new draft wins at least three
  cases, and it loses no more than one. Tell the user what this means using
  [interaction.md](interaction.md), not internal comparison labels.

## Review each part with the user

Present the private summary in small sections without internal field names:

1. supported, provisional, and unsupported uses;
2. best-self center and durable decisions;
3. context variation and mechanics;
4. preferred moves and explicit dislikes;
5. confidence, counterevidence, and remaining gaps; and
6. invocation, local-output boundary, installed clients, and portability.

Follow [interaction.md](interaction.md). Start with what the user is deciding,
not the internal section name. State what accepting the section changes and
what remains unchanged. Offer a clear accept choice, a change choice, an
explanation choice, and a leave-undecided choice. Asking for an explanation
changes no saved state. A section left undecided cannot become active. Section
approval does not approve installation, publication, or another remote action.

Use plain questions such as:

- `Where should this profile be allowed to shape your writing?`
- `Do these writing choices sound like the way you want the profile to write?`
- `Are these sentence, paragraph, and structure choices right for you?`
- `Are the remaining limits and unknowns accurate?`

Do not ask the user to approve `candidate scope`, `rule disposition`,
`genericity`, or another internal term without translating it first.

## How sure are we, and does the profile help?

Report how strong the evidence is for each kind of writing. Low confidence and
uses that are not ready fall back to general writing. Moderate confidence needs
enough direct samples plus separate preference, usefulness, and comparison
checks. Strong confidence also needs ten or more independent samples across
more than one kind of writing or audience, no new rules from later samples,
stable test results, and editing effort that has stopped improving.

Safe, coherent prose is necessary but not sufficient. A promoted context must
show attributable source-derived value over general writing. Ties and exact
no-churn remain safe outcomes but do not count as genericity wins.

## Completion audit

Before reporting completion, verify candidate, canonical, installed, and
rollback versions are distinct; the completion card matches actual install and
host discovery state; only one profile is active; transfer guidance names its
privacy boundary; and every deferred action is stated as not performed.

For schema version 2, record `source-confirmation-check: passed`,
`nuance-matrix-check: passed`, `elicitation-high-impact-results: resolved`,
`transient-cleanup-check: passed`, `section-review: approved`, and
`release-review: passed` in the private audit only after each independent check
completes. The builder rejects a missing or weaker state.

## Audit result

Keep `Blocked`, `Provisional`, or `Ready for user approval` in the private audit
when those exact values are required. Tell the user `Not ready`, `Needs more
testing`, or `Ready for your decision`. Name what is not covered, checks run,
important findings, needed fixes, and the next choice without quoting private
content.
