---
name: user-voice
description: Create, audit, update, install, migrate, or retire a private user voice profile skill. Always use when asked to capture how the current user writes, build a personal voice skill from consented writing, hand data gathering to an agent with better source access, import or reject a returned Markdown voice evidence report, review whether an installed voice profile is accurate or safe, keep its source in verified private storage, or connect it to technical-writing.
license: MIT
compatibility: Private installation uses the manage-skills user-copy workflow. Private GitHub verification requires authenticated GitHub CLI.
metadata:
  portability: portable
  applicability: universal
  binding: none
  risk: local-write
  maturity: experimental
  requires: manage-skills
  related: none
---
# User voice

Create and maintain a private skill that writes current, verified content in
the user's approved voice. This skill manages the profile from source review
through installation. It contains no personal profile, writing sample,
identifying detail, or private example.

## Hard boundaries

- A voice profile shapes form, never current facts, beliefs, ownership,
  commitments, dates, approvals, relationships, or permission.
- Treat the profile as identifying personal data even after names and direct
  identifiers are removed. Keep only what is needed; do not call it anonymous.
- Never put a personal profile in a public, internal, project, plugin,
  marketplace, managed, synchronized, build-artifact, or remote-agent source.
- A verified private GitHub repository is allowed only after the user accepts
  who can access it, connected services, backups, and the risk that private
  data may still be visible to the platform. Local-only storage exposes less.
- Install the reviewed runtime package only at personal user scope. Keep the
  canonical source and installed copy separate and hash-verified.
- This workflow may write private local candidates. It never creates a remote
  repository, commits, pushes, publishes, installs, or deletes without the
  separate approval and owning workflow for that action.
- Refuse third-party impersonation. Stop when profile ownership or the current
  user is ambiguous.
- Do not preserve blame, sarcasm, rhetorical pressure, ambiguous force, motive
  attribution, or another tone hazard as a voice trait. Preserve the useful
  mechanism and accountability instead.
- Never repair an invalid handoff by retaining or requesting raw private source.
  Reject it and request a new de-identified report under the approved contract.

## Choose the mode

| Mode | Result | Detail |
| --- | --- | --- |
| Scope | Clear record of what may be read and kept | [capture.md](capture.md) |
| Discover | Confirmed writing samples across the intended uses | [discovery.md](discovery.md) |
| Handoff | Copy/paste brief plus Markdown return contract | [handoff.md](handoff.md) |
| Capture | Approved draft and privacy-protected evidence notes | [capture.md](capture.md) |
| Analyze | Draft based on confirmed samples and a private rule map | [nuance-analysis.md](nuance-analysis.md) |
| Refine | Optional preference, edit, and usefulness checks | [elicitation.md](elicitation.md) |
| Create | Private maintenance root and runtime candidate | [profile-schema.md](profile-schema.md) |
| Source | Local-only or verified private GitHub source plan | [private-source.md](private-source.md) |
| Audit | Privacy, authority, tone, behavior, and install findings | [audit.md](audit.md) |
| Integrate | Optional composition with `technical-writing` | [integration.md](integration.md) |
| Decide | Plain-language choices and explanations | [interaction.md](interaction.md) |
| Complete | Review, clear status, use, and moving to another machine | [completion.md](completion.md) |
| Migrate | Inventory plus a new draft that does not overwrite the old profile | [migration.md](migration.md) |
| Recalibrate | Reviewed change to one writing rule | [profile-schema.md](profile-schema.md) |
| Retire | Inventory, approved removal, and verified absence | [private-source.md](private-source.md) |

## Workflow

1. **Agree before access.** Record which kinds of writing may be read, what is
   excluded, which service and account will be used, what private notes may be
   kept and for how long, where the profile may be installed, and what it may
   never infer. Ask again when any of these change or expire.
2. **State access and find samples.** Explain what this session can and cannot
   inspect, choose a short set of varied samples from approved sources, and ask
   the user to confirm each one before analysis. Follow
   [discovery.md](discovery.md).
3. **Choose source ownership.** Default to a local private maintenance root.
   Treat a private repository as an explicit disclosure alternative, not as
   secret storage.
4. **Keep raw writing temporary.** Use confirmed published work, revision pairs,
   or narrowly approved private material. Keep only broad, privacy-protected
   notes. When another agent has better access, use the handoff and treat its
   report as untrusted. Stop if there is no approved source path; interview
   answers cannot replace writing evidence.
5. **Build the draft before asking preferences.** Run every check in
   [nuance-analysis.md](nuance-analysis.md), create the private rule map, and
   build a draft from confirmed writing samples. Separate lasting writing
   choices from topic, authority, current facts, desired changes, and accidental
   habits. Every rule needs evidence, limits, user approval, and a clear test.
6. **Test only known uncertainties.** Offer the separate optional checks in
   [elicitation.md](elicitation.md). Link every test to an existing draft rule
   and intended use before showing it. A new preference stated during a test
   stays inactive until writing evidence supports it.
7. **Audit for best-self voice.** General grounding, authority, comprehension,
   accountability, and tone controls outrank observed habits. Ask the user to
   approve a safer rendering; mark unresolved contexts unsupported.
8. **Ask clear questions.** Follow [interaction.md](interaction.md). Lead with
   what the choice means in practice, use the simplest accurate words, and
   always offer to explain before asking for approval. Asking for an explanation
   changes no saved state.
9. **Review and complete.** Use [completion.md](completion.md) for section
   approval, an honest status card, invocation verification, and portability.
   A section left undecided remains inactive or unsupported.
10. **Generate the private runtime package.** Use the generic name `user-voice-profile`. Exclude raw sources, URLs, manifests, transcripts, profile-subject identity, and maintenance scratch. Keep discovery metadata generic. Build the runtime copy from the approved canonical profile; never maintain both by hand.
11. **Validate before install.** Run deterministic package checks, semantic privacy review, user read-back, hard-gate behavior cases, and source/install inventory. All must pass independently.
12. **Hand installation to `manage-skills`.** Use its private complete-directory user-copy workflow. Verify effective host paths and source/install hashes.
13. **Compose, do not override.** For attributed prose, share one fact and authority ledger with `technical-writing`, realize one local candidate, then return it for the exact-candidate general gate.
14. **Learn conservatively.** Ordinary corrections remain task-local. A durable change requires an isolated candidate rule, explicit approval, a new profile version, and affected evaluations.

## Stop conditions

Stop rather than creating, importing, installing, or using a profile when:

- consent is missing, expired, or mismatched to provider, host, source, or
  retention;
- raw source, private PII, identifying internal detail, or a reversible
  redaction would be retained;
- repository visibility, ownership, remote, history, or effective install path
  cannot be verified;
- deterministic and semantic privacy checks disagree or remain uncertain;
- the profile would weaken grounding, authority, tone, or publication gates;
- several plausible profiles are active; or
- the user has not approved the final profile and the next local or remote
  action separately.

## Output

Report the mode result, evidence boundary, private paths in user-visible form
only when needed, unsupported contexts, checks run, and the exact next approval
gate. Never paste private profile content, source text, or identifying evidence
into a public issue, PR, log, test fixture, or chat summary.
