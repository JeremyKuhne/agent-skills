# Compose with technical writing

## Precedence

Apply current verified facts and task instructions first, then current
authority and privacy, general grounding/comprehension/tone gates, artifact and
audience constraints, applicable profile rules, and finally generic defaults.
The profile is never a peer source of truth.

## Efficient flow

1. `technical-writing` builds one fact and authority ledger plus reader and output contract.
2. For attributed first-person prose, it conditionally invokes an available personal `user-voice-profile` after the contract is fixed.
3. The profile realizes one local candidate without retrieving sources, re-deciding facts, or inferring authority.
4. `technical-writing` applies its exact-candidate grounding, comprehension, and tone gate once.
5. A lightweight conformance check compares only material repairs with approved, high-confidence profile rules. It does not regenerate the draft.
6. The publishing workflow retains its separate approval and remote action.

If grounding, authority, privacy, or tone fails, general writing blocks or
repairs the clause. Do not offer a profile-consistent unsafe alternative. A
material voice change affects information order, certainty, stance, force, or
an approved context rule; show the compliant candidate and conflict to the user.

## Runtime discovery

The fixed personal name `user-voice-profile` is the provisional default because
it is generic and creates no public dependency. `technical-writing` must remain
complete when it is absent. Never add the private package to public `requires`
or `related` metadata.

If more than one plausible profile is active or ownership is unclear, ask which
one applies rather than merging them. An unknown schema or integration contract
returns to general writing and requests an audit.

Revalidate routing after a material model or client update. Host-specific custom
agents may list both skills explicitly as a limited fallback; do not fork
`technical-writing` into a private overlay by default.

## One-ledger walkthrough

For one supported attributed-writing case:

1. `technical-writing` records current facts, inferences, unknowns, ownership, commitments, permission, reader, and output contract once.
2. It verifies exactly one compatible `user-voice-profile` is discoverable and passes the fixed contract without loading maintenance evidence.
3. It sends only the ledger, output contract, and applicable context to the profile. No historical source is retrieved.
4. The profile applies only approved rules mapped to a supported context and returns one local candidate without adding facts or authority.
5. `technical-writing` checks that exact candidate for grounding, authority, comprehension, and tone. It repairs or blocks unsafe clauses without asking the profile to regenerate.
6. The calling workflow seeks any publication approval separately.

Record model calls and generation rounds. More than one full composition pass,
recursive skill invocation, a second fact ledger, or a profile-supplied current
claim fails the integration check.

## Supported-host verification

For each client named in the completion card, test a fresh session with both a
natural attributed-writing request and an explicit profile request. Verify one
profile is discovered, fixed constraints reach it, the returned artifact stays
local, and the exact-candidate gate resumes. Also test profile absence, an
unsupported context, an unknown schema, and duplicate plausible profiles; each
must fall back or ask one narrow ownership question without claiming voice fit.

Machine-local verification establishes nothing about cloud agents, code review,
or another remote session.
