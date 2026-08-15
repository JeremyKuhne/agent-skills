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

## Prefer user-selected evidence

Ask for three to five representative published works before broad discovery:

- blogs, articles, documentation, and design documents;
- GitHub issues, pull requests, and review comments;
- published talks, transcripts, or interviews; and
- other work whose authorship and editing history the user can explain.

Ask why each is representative and whether it was edited, collaborative,
templated, translated, or AI-assisted. Ask for one authentic anti-example the
user would no longer write. Public evidence is valid; the personalized skill
source still must remain private.

Prioritize revision pairs and user-selected exemplars, then verified human-only
work, controlled elicited writing, ordinary history, and finally labeled
assisted work. Do not silently learn from lightly edited model prose.

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

## Evidence cards

Retain only opaque IDs and controlled values for source class, channel,
audience, intent, stakes, era, authorship, representativeness, observations,
and counterevidence. Use count bands (`1-2`, `3-5`, `6-10`, `10+`), not exact
counts that recreate a source inventory.

`De-identified` means data-minimized and unlinkable to a private source by the
retained report alone; it does not mean anonymous. Omit or broaden a field when
its value or combination could identify a person, organization, customer,
project, repository, message, relationship, timeline, or event. Candidate-rule
prose describes an abstract writing decision, never a recognizable topic,
story, product, or phrase.

## Evidence sufficiency

Use corpus targets as heuristics, not guarantees. A provisional profile may use
10-15 clean samples across supported contexts. A reusable profile normally
needs 25-50 samples with at least five in each important stratum and a sealed,
stratified holdout.

Stop when two stratified batches add no high-confidence rule, important rules
remain stable under resampling, every supported context has direct evidence,
the user confirms high-impact rules and counterexamples, held-out preference
beats general writing, edit effort plateaus, and every boundary case passes.
