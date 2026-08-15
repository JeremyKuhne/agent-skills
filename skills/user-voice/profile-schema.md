# Profile and runtime package

## Canonical profile

Create and obtain approval for `voice-profile.md` before generating a runtime
skill. Use this structure:

1. **Scope and version** - profile schema, integration contract, supported and
   unsupported contexts, evidence era, status, and last validation.
2. **Best-self center** - approved writing decisions, not personality or
   biography.
3. **Durable rhetorical and epistemic traits** - information order, evidence,
   mechanism, certainty, disagreement, ownership, and stopping behavior.
4. **Context matrix** - variation by channel, audience, intent, stakes, and
   length.
5. **Mechanics** - distributions and tolerances, not caricatured signatures.
6. **Preferred moves** - conditions plus synthetic examples only when needed.
7. **User-approved dislikes** - stated or repeatedly corrected preferences,
   never inferred harmful habits.
8. **Grounding and authority exclusion** - profile evidence supplies no current
   content or permission.
9. **Confidence and conflicts** - counterevidence and unsupported behavior.
10. **Evaluation status** - hard gates, voice cases, blinded preference, edit
    effort, model, client, and date.

Every rule records ID, claim, scope, evidence class (`observed`, `stated`,
`validated`, or `uncertain`), confidence, count bands, counterevidence, user
approval, and an observable check. Absence alone never establishes `never`.

## Runtime package

Generate only:

```text
user-voice-profile/
  SKILL.md
  references/
    voice-profile.md
    evaluations.md
  INSTALL.md
```

Exclude raw samples, exact source manifests, URLs, revision history, prompts,
transcripts, model output, user identity, maintenance scratch, and private PII.
Use generic discovery metadata and the fixed runtime name
`user-voice-profile`.

The runtime contract distinguishes draft, revise, and review; reads only the
profile during ordinary use; requires current-case facts and first-person
authority; ends with local text; refuses third-party impersonation; and returns
control to `technical-writing` for the exact-candidate gate.

Record `profile-schema-version: 1` and
`integration-contract: technical-writing-user-voice-v1`. Unknown versions fail
closed to general writing and request an audit.

After private semantic editing, mark the canonical profile approved only when
the consent ledger, deterministic package check, semantic privacy review, and
user read-back are also complete. Run
`scripts/Build-UserVoiceProfile.ps1 -MaintenanceRoot <private-root>` to copy the
approved canonical profile into the runtime package atomically and rerun strict
package validation. Do not edit the installed copy directly.

## Recalibration

An explicit profile-update request creates an inactive candidate rule. A first
ordinary correction stays task-local. A second or third independent recurrence
may prompt once about reviewing a durable candidate. Silence, unexplained edits,
and accepted model prose are never approval.

Show the isolated rule, scope, evidence class, and affected contexts. On
approval, version the profile and rerun affected behavior and tone cases. Keep
facts, current context, ownership, and commitments out of the profile.
