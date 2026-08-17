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
4. **Context matrix** - runtime behavior compiled from the private nuance matrix
   by channel, artifact, audience, relationship, intent, stakes, length, and
   formality.
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
approval, runtime status (`inactive` or `active`), and an observable check.
Approval records the user's judgment; activation additionally requires the
context release gates. Absence alone never establishes `never`.

## Private nuance matrix

Schema version 2 requires `nuance-matrix.md` in the private maintenance root.
Start from [assets/nuance-matrix.md.tmpl](assets/nuance-matrix.md.tmpl). The
matrix never enters the runtime package.

Each `context-NNN` block records:

- channel and artifact;
- audience and relationship;
- intent and stakes;
- length and formality;
- direct-evidence count band, diversity dimensions, and attained evidence floor;
- all seven nuance-pass results;
- unresolved gaps;
- candidate rule IDs and independent validation case IDs;
- genericity-control status, confidence, runtime status, and user status.

A pass result is either `observed: <de-identified decision>` or
`not-observed`. All seven fields are mandatory; a missing pass cannot be
treated as neutral. Minimum retention stores category-level diversity and
count bands only. Auditable retention keeps opaque source-to-context mappings
in a separate private ledger, never in the matrix or runtime package.

Matrix compilation fails unless:

- context IDs and rule IDs are unique and well formed;
- every active runtime rule is user approved and maps to at least one supported context;
- every supported context reaches its evidence floor, has approved rules, passes independent validation and genericity control, and is user approved;
- provisional and unsupported contexts compile to general-writing fallback;
- confidence does not exceed the evidence and validation state; and
- all pass results, conflicts, counterevidence, and gaps are explicit.

Run `scripts/Test-UserVoiceNuanceMatrix.ps1 -Path <matrix> -ProfilePath
<canonical-profile>` before compiling or approving schema version 2.

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

Do not put current installation status, installed paths, active-host claims, or
rollback state in `voice-profile.md`. Those values change independently of voice
behavior and become stale inside copied runtime packages. Keep them in the
private audit, installation record, and generated completion card.

The runtime contract distinguishes draft, revise, and review; reads only the
profile during ordinary use; requires current-case facts and first-person
authority; ends with local text; refuses third-party impersonation; and returns
control to `technical-writing` for the exact-candidate gate.

Schema version 1 is the legacy four-file contract without a separately validated
maintenance matrix. New profiles use `profile-schema-version: 2`; version 2
retains the four-file runtime package and adds the private matrix gate. Both use
`integration-contract: technical-writing-user-voice-v1`. Unknown versions fail
closed to general writing and request an audit.

Record `profile-version` independently. `profile-schema-version` changes only
when the file contract changes; `profile-version` changes when approved voice
behavior changes. Keep candidate, canonical, installed, and rollback versions
distinct, and activate only one runtime profile per user and host.

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

A correction introduced during elicitation remains an inactive hypothesis when
it lacks source evidence. It cannot raise confidence or become a durable rule
until targeted evidence supports it and an independent validation batch passes.
