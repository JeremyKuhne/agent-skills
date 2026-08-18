# Find writing samples

Use this workflow after source categories are approved and before reading or
analyzing source bodies. The current agent leads discovery; the user confirms a
short sample set rather than assembling it by hand.

## State what this session can access

Inventory only tools, connected providers, account boundaries, workspace data,
and user-provided attachments that are actually available in the current
session. Do not infer access from a product name or a previous session.

When a host adapter supplies a declaration, instantiate
[assets/source-capability.md.tmpl](assets/source-capability.md.tmpl) and run
`scripts/Test-UserVoiceSourceCapability.ps1`. Treat an expired, unverified, or
invalid category as inaccessible. Reverify dynamic account and tool state in the
current session; a declaration is an upper bound, not proof that access still
works.

Keep the resolved declaration at a private session-local path, not in the
runtime package or public project. Run the validator immediately before each
discovery session; its default `AsOfDate` is the current UTC date. Then exercise
the declared client/tool connection without opening unapproved source content.
If authentication, account boundary, or tool behavior differs, downgrade the
category to inaccessible and regenerate the declaration. Delete a transient
declaration at session cleanup unless the approved private retention policy
keeps the broad capability record.

Tell the user:

- which approved categories can be searched now;
- whether access exposes metadata, content, or both;
- which provider and model would receive content;
- which useful categories are inaccessible; and
- whether another agent can access the missing sources.

Classify public material that needs no account as `public-unauthenticated`;
never imply that public visibility itself establishes authorship,
representativeness, or consent.

Use category descriptions in the normal path. Show provider, host, account, or
path detail only when it changes the consent decision. Never request a secret
through chat; authentication happens in the provider's own interface.

## Choose possible samples

Search only approved categories. Build a small sample set that varies in the
ways the proposed profile may need:

- channel and kind of writing;
- audience and relationship;
- intent and stakes;
- length and formality;
- topic; and
- era or recency.

Prefer independent pieces with clear authorship and editing history. Include an
authentic anti-example when available. Do not improve numerical coverage by
splitting one exchange, revision chain, template family, repost, or repeated
controlling edit into several samples.

Before showing the set, screen for:

- quoted, forwarded, or collaborator-written text;
- signatures, headers, footers, templates, and boilerplate;
- code, logs, generated tables, and copied reference material;
- translation or substantial editorial intervention;
- AI-generated or lightly edited model prose;
- topic clusters that could be mistaken for style; and
- artifact conventions that are not personal choices.

Balance the set or note any remaining factor that could be mistaken for voice.
A sample may still be useful when its limit is clear; it cannot silently support
a lasting rule.

## Confirm each sample

Show enough source-local context for recognition without copying raw content
into a new transcript or document. Assign a temporary private sample ID and ask
the user to confirm for each sample:

1. whether they wrote most of it;
2. the audience and relationship context;
3. whether it represents their desired current voice;
4. whether another person materially edited it; and
5. whether a template, translation, or AI materially shaped it.

The user can accept, reject, or correct each sample. Analyze only accepted
samples. Do not keep the temporary ID unless the user chose the private option
that keeps source links. The summary-only option keeps only privacy-protected
notes and rough count ranges.

## Check coverage

Before analysis, create a private coverage grid over the six dimensions above.
Use the internal labels `supported-candidate`, `provisional-candidate`, or `gap`
in the private record. Tell the user `enough evidence`, `not ready yet`, or
`missing evidence`. Use the minimums in [capture.md](capture.md), and do not fill
a gap with assumptions from another kind of writing.

If all samples share one topic, document template, collaborator, or narrow time
period, gather another batch before extracting a rule. Change the factor that
may be misleading while keeping the proposed writing choice stable.

## Handle sources this session cannot access

For each useful inaccessible category, offer another agent that can access those
sources when one is available. Explain what it can access, which account it
uses, whether raw content reaches its model, how the user will confirm samples,
and what it will return before handoff.

The other agent must:

1. disclose its own capabilities in its source environment;
2. discover a short candidate set inside the approved boundary;
3. obtain exact source confirmation there;
4. analyze only confirmed sources;
5. return the de-identified report defined in [handoff.md](handoff.md); and
6. delete raw extracts and transient evaluation material as required.

The originating agent validates the returned report as untrusted input. It does
not ask the user to reconstruct rejected machine fields or move raw source into
this session.

## Stop when there is no approved evidence

If no approved source evidence is accessible, ask one routing question: use
another agent that can access the sources, provide a sanitized source, or stop.
If no route is approved, record that this kind of writing is not covered. Do not
interview the user into a source profile, infer one from preferences, or draft
lasting rules from synthetic writing alone.

Report what was available, roughly how many samples were confirmed, what is
missing, what may have affected the findings, what private summary will be kept,
and the user's next choice. Do not repeat source identities outside their source
environment.

Proceed to source analysis only after the candidate set is confirmed.
