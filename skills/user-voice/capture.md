# Capture a user voice profile

## Consent ledger

Before source access, record an opaque consent ID and schema version plus:

- supported and excluded artifact families, audiences, and contexts;
- approved source classes and broad era bands;
- excluded folders, topics, and third-party material by category;
- analysis provider, client, account, and local or remote processing mode;
- raw-source exposure, derived-data retention, and expiry trigger;
- approved installation hosts and roots; and
- facts, authority, relationships, commitments, and actions that the profile
  must never infer.

Analysis consent and installation consent are independent. Reconfirm before
access when the provider, host, account, source scope, processing mode,
retention, consent schema, or expiry changes.

## Plain-language approval

Keep the versioned ledger internal. Before each material step, show only the
decision the user is making:

| Step | Explain | Approval |
| --- | --- | --- |
| What may be searched | Places and kinds of writing to include or exclude | Decide before looking for samples |
| Available writing samples | What this session can access and what it can show | Decide before opening content |
| Reading your writing | Exact confirmed samples, service exposure, and temporary handling | Decide before reading the samples |
| Keeping private notes | What summary will be saved, where, and for how long | Decide before saving evidence |
| Building and installing | What enters the usable profile and which clients may receive it | Decide separately after reviewing the profile |

Use ordinary language: "I can search these approved places in this session. I
cannot reach these others. I will temporarily read the confirmed items, retain
only the selected private evidence summary, and will not send, post, install, or
publish anything." Follow [interaction.md](interaction.md): offer to continue,
change the choice, explain it in more detail, or leave it undecided. Account
access does not by itself allow source analysis, and source approval does not
allow installation or publication.

## Discover before asking

After the user approves source categories, state what the current agent can and
cannot inspect in this client and account. Search only approved, accessible
categories and propose a short sample set across the channels, audiences,
relationships, intents, stakes, lengths, topics, and eras the profile may
support. Do not ask the user to assemble a set the agent can find itself.

Before analyzing any sample, show enough context for the user to recognize
it and ask whether:

- the user wrote most of it;
- its audience and relationship context are correctly classified;
- it represents the user's desired current voice; and
- another person, template, translation, or AI materially shaped it.

Reject unconfirmed samples. Treat repeated boilerplate, templates, reposts,
fragments from one exchange, and variants with the same controlling edit as one
source. Balance topic and context so subject matter, organizational convention,
and artifact structure do not masquerade as voice.

If a useful approved category is inaccessible, offer another agent that can
access those sources. Explain what it can retrieve, what it must return, and
what raw content must remain there. User-selected works and sanitized excerpts
remain valid fallbacks. Ask one routing question when no approved evidence is
accessible; if the user declines or no route is available, stop without
constructing a source profile from interview answers.

Prioritize confirmed revision pairs and user-selected exemplars, then verified
human-only work, ordinary history, and finally labeled assisted work. Use
controlled elicitation only to refine or validate source-derived rules. Do not
silently learn from lightly edited model prose.

## Private source access

For email, document stores, or local files:

1. Narrow access to the user's authored material, approved source classes,
   channels, audiences, and era bands.
2. State the provider, selected source slice, transient exposure, and retention
   behavior. Obtain a second explicit confirmation before raw access.
3. Strip headers, addresses, quoted replies, forwarded text, signatures,
   footers, templates, logs, code, attachments, and collaborator edits.
4. Analyze small context-matched batches. Do not export or persist raw bodies.
5. Replace every person, organization, customer, private repository, internal
   project, code name, issue, build, host, URL, date, and event with a broad
   category before retaining a note.
6. Delete transient extracts after the decision and verify that prompts,
   transcripts, logs, artifacts, and generated packages retained none.

If provider access is not approved, use truly local preprocessing or ask the
user for sanitized excerpts. Do not reinterpret permission to inspect an
account as permission to send its contents to a model.

## Private evidence notes

Retain only opaque IDs and controlled values for source class, channel,
audience, intent, stakes, era, authorship, representativeness, observations,
and counterevidence. Use count bands (`1-2`, `3-5`, `6-10`, `10+`), not exact
counts that recreate a source inventory.

Call these notes de-identified only when the saved summary alone cannot be
traced back to a private source. This does not make it anonymous. Omit or
broaden any detail that could identify a person, organization, customer,
project, repository, message, relationship, timeline, or event. Describe only
the general writing choice, never a recognizable topic, story, product, or
phrase.

## How much evidence is enough

Use these minimums to decide whether the draft is ready for another step. They
are not statistical guarantees:

- any source-derived draft needs five independent, clean, user-confirmed
  samples across at least two relevant situations;
- a kind of writing that is not yet ready needs three independent samples
  spanning at least two relevant audiences, relationships, purposes, levels of
  risk, lengths, or levels of formality;
- moderate confidence needs five independent samples spanning at least three
  relevant situation values plus independent preference and impact validation;
  and
- strong confidence needs ten or more independent samples across at least two
  forms or audiences, source and rule saturation, stable independent
  validation, and plateaued edit effort.

`Independent` excludes repeated boilerplate, templates, reposts, fragments from
one exchange, and variants with the same controlling edit. If a floor is not
met, record the gap and keep the context out of active runtime support.

Stop when two balanced batches add no strong rule, important rules stay stable
when the samples change, every intended use has direct evidence, the user
confirms important rules and examples that do not fit, new preference tests beat
general writing, editing effort stops improving, and every safety case passes.
