# Check and refine the draft

These checks are optional. They test uncertain parts of a draft built from
confirmed writing samples. They do not invent the profile. Keep completed
source work and the draft when the user declines a check.

## Seal cases before presentation

Create a private batch manifest from
[assets/elicitation-batch.md.tmpl](assets/elicitation-batch.md.tmpl). Each case
names the draft profile version, one existing `context-NNN`, one existing
`rule-NNN`, the controlled contrast, candidate placement, order, and expected
decision. Hash the normalized fact ledger, authority ledger, output contract,
and brief for each condition; both condition hashes must match. Record the one
client/model condition and separate hard-gate results. Do this before generating
or showing options.

Run `scripts/Test-UserVoiceElicitationBatch.ps1` with
`-RequirePresentationReady`. Reject a case whose rule or context does not exist
or whose rule is not mapped by that context. A preference introduced by the
user without source support becomes a new inactive hypothesis; it cannot raise
confidence or enter runtime until targeted source evidence and a separate batch
support it.

Do not retrofit that new hypothesis into the current batch. Record it separately
with `resolution: evidence-gap`, gather source evidence, add an inactive draft
rule and matrix mapping, then seal a new batch.

## Blind preference pass

Offer batches of three to five separately approved cases. For each case:

1. hold facts, authority, artifact, audience, length target, and safety gates constant;
2. vary one source-derived voice decision;
3. generate complete synthetic option A and option B;
4. verify both options pass hard gates;
5. blind and counterbalance the profile condition; and
6. ask for A, B, both, neither, no preference, or a manually written option C.

Do not name the tested dimension or reveal candidate placement before the
response. Record choices without interim interpretation. A manual option is
evidence about this case, not automatically a durable rule.

## Let the user edit a draft

Show one complete block produced by the draft profile and ask the user to
edit it directly. Preserve meaning, authority, and required content while
comparing the edit. Keep only meaningful writing choices in the private record,
show that summary for confirmation, then delete the raw edit and temporary
diff. Do not ask for a separate rewrite as homework.

## Check whether the change helps

Compare the exact baseline and candidate output only when they differ. Check
identity mechanically before asking the user anything. For a changed pair, ask
whether the candidate is much better, better, the same, worse, or much worse,
then ask what material edit remains.

When outputs are identical, record `exact-identity: yes`, `state:
auto-no-churn`, and `result: no-churn`; the user does not assess that case.
An unexplained worse result remains unresolved and blocks promotion.

## Check for value beyond general writing

For every kind of writing that may become ready for use at moderate or strong
confidence, run exactly five new cases against general `technical-writing`
under one client/model condition. Keep the facts, authority, requested output,
and safety checks identical. Hide which option came from the draft profile and
vary which option appears first.

The validator proves that the manifest declares equal contract hashes and
passed hard gates for both conditions. The evaluation owner must still verify
that the generated options came from those sealed inputs and the recorded
client/model condition; structural validation cannot prove model provenance.

The draft profile adds enough value in that kind of writing only when:

- hard gates pass in both conditions for every case;
- the profile wins by preference or lower substantive edit burden in at least
  three cases;
- the profile loses no more than one case;
- exact ties and no-churn are not counted as wins; and
- every win maps to an observed nuance decision rather than topic, verbosity,
  or an intentionally weak baseline.

Do not lower the threshold after seeing results. Fewer than five new cases or a
failed threshold means the profile is not ready for that kind of writing.

Present the result using [interaction.md](interaction.md). Do not ask whether to
approve a `genericity interpretation`. Ask whether the draft profile added
useful value beyond clear general writing. Include `Explain this result in more
detail`. If selected, explain the comparison, threshold, likely wording
differences, effect of accepting the result, and what remains inactive. Change
no state until the user answers the decision again.

## Finish a test round

A result is unresolved when it would change a rule's wording, scope,
confidence, mechanics, counterevidence, context matrix, or supported state; when
a manual edit conflicts with the rule; or when a changed output receives an
unexplained worse rating.

Resolve it by accepting a revised source-supported candidate, rejecting the
hypothesis, recording a bounded tolerance, or preserving an evidence gap. Rerun
an affected independent case when the rule remains active. High-impact pending
results block promotion.

Stop a loop when the tested distinctions reproduce independently, countercases
are equal or better, substantive edit effort is none or minor and stable across
two consecutive batches, no unresolved result would change the profile, or the
user declines. Report confidence and remaining gaps by context, not as one
global score.

After collection, run the batch validator with `-RequireResolved`, update only
confirmed abstractions, delete raw options and edits, and rerun affected matrix,
hard-gate, and genericity checks. Run
`scripts/Test-UserVoiceTransientCleanup.ps1 -MaintenanceRoot <private-root>` at
each cleanup checkpoint; a retained raw option, edit, scoring block, or transient
path blocks release.
