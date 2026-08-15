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

Create and maintain a private skill that realizes current, verified content in
the user's approved best voice. This core owns profile lifecycle and audit. It
contains no natural person's profile, source material, profile-subject identity,
or private example.

## Hard boundaries

- A voice profile shapes form, never current facts, beliefs, ownership,
  commitments, dates, approvals, relationships, or permission.
- Treat the profile as identifying personal data even after direct PII is
  removed. Minimize it; do not claim it is anonymous.
- Never put a personal profile in a public, internal, project, plugin,
  marketplace, managed, synchronized, build-artifact, or remote-agent source.
- A verified private GitHub repository is permitted only after the user accepts
  its collaborators, administrators, integrations, backups, and residual
  visibility risk. Local-only source is lower exposure.
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
| Scope | Versioned consent and source plan | [capture.md](capture.md) |
| Handoff | Copy/paste brief plus Markdown return contract | [handoff.md](handoff.md) |
| Capture | Approved profile and de-identified evidence cards | [capture.md](capture.md) |
| Create | Private maintenance root and runtime candidate | [profile-schema.md](profile-schema.md) |
| Source | Local-only or verified private GitHub source plan | [private-source.md](private-source.md) |
| Audit | Privacy, authority, tone, behavior, and install findings | [audit.md](audit.md) |
| Integrate | Optional composition with `technical-writing` | [integration.md](integration.md) |
| Migrate | Source/install inventory plus a non-destructive standard candidate | [migration.md](migration.md) |
| Recalibrate | Versioned candidate rule after explicit approval | [profile-schema.md](profile-schema.md) |
| Retire | Inventory, approved removal, and verified absence | [private-source.md](private-source.md) |

## Workflow

1. **Scope before access.** Record supported artifacts, unsupported contexts,
   source classes, exclusions, provider and host, retention, expiry, installed
   hosts, and authority boundaries. Reconfirm changed or expired consent.
2. **Choose source ownership.** Default to a local private maintenance root.
   Treat a private repository as an explicit disclosure alternative, not as
   secret storage.
3. **Gather without retaining raw text.** Use user-selected published work,
   revision pairs, or narrowly approved private material. Keep only broad,
   de-identified evidence cards. When another agent has better access, use the
   manual handoff and treat its report as untrusted.
4. **Build the profile first.** Separate durable voice, context register,
   mechanics, desired evolution, content, authority, and accidental signal.
   Every rule needs scope, evidence class, confidence, counterevidence, user
   approval, and an observable check.
5. **Audit for best-self voice.** General grounding, authority, comprehension,
   accountability, and tone controls outrank observed habits. Ask the user to
   approve a safer rendering; mark unresolved contexts unsupported.
6. **Generate the private runtime package.** Use the generic name `user-voice-profile`. Exclude raw sources, URLs, manifests, transcripts, profile-subject identity, and maintenance scratch. Keep discovery metadata generic. Build the runtime copy from the approved canonical profile; never maintain both by hand.
7. **Validate before install.** Run deterministic package checks, semantic
   privacy review, user read-back, hard-gate behavior cases, and source/install
   inventory. All must pass independently.
8. **Hand installation to `manage-skills`.** Use its private complete-directory
   user-copy workflow. Verify effective host paths and source/install hashes.
9. **Compose, do not override.** For attributed prose, share one fact and
   authority ledger with `technical-writing`, realize one local candidate, then
   return it for the exact-candidate general gate.
10. **Learn conservatively.** Ordinary corrections remain task-local. A durable
    change requires an isolated candidate rule, explicit approval, a new profile
    version, and affected evaluations.

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
