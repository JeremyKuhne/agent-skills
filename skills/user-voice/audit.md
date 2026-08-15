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
- Run hard gates before voice preference and compare against general writing on
  identical sanitized briefs.
- Measure factual fidelity, context fit, authority safety, user preference,
  substantive edit effort, model calls, duplicated questions, and generation
  rounds.
- Require one fact ledger and no more than one full composition pass.

## Audit disposition

Return `Blocked`, `Provisional`, or `Ready for user approval`. Name unsupported
contexts, source and install locations, checks run, material findings, required
repair, and the exact next approval gate without quoting private content.
