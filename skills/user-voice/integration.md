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
