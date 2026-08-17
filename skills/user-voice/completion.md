# Review and complete a user voice profile

Say clearly what is ready and what is not. Creating a draft, approving it,
installing it, and publishing text are separate decisions.

## Review the draft

Use the review sequence in [audit.md](audit.md) and the question rules in
[interaction.md](interaction.md). Explain where the profile may be used, how it
would shape the writing, how strong the evidence is, what conflicts remain, and
what is still missing. Do not expose source identities, private paths, internal
IDs, raw options, or file-format details in the normal path.

Lead each section with the practical question. For example, ask `Where should
this profile be allowed to shape your writing?`, not `Approve candidate scope?`.
Offer `These uses look right`, `Change the list`, `Explain what each category
means`, and `Leave these uses undecided`. A request for explanation changes
nothing; explain first, then ask again. A section left undecided remains
inactive or unsupported.

After all sections, ask whether this exact draft should become the approved
profile. State that approval does not install it or allow any remote action.

## Completion card

Return this card with only verified values:

```text
Profile state: <draft, not approved | approved and ready to install | installed and checked>

Use it naturally:
- Rewrite this design note in my voice.
- Review this comment for fit with my voice.

Where it can help:
- Ready to use: <kinds of writing>
- Not ready yet; uses general writing: <kinds of writing>
- Not covered: <kinds of writing>

Installed in: <checked local clients or not installed>
Can it send or post: No
Private evidence kept: <summary only or summary plus private source links>
Moving to another machine: <reviewed private setup guide or not prepared>
Next check: <date or reason to review again>
Next decision: <specific choice or none>
```

Do not say `installed and checked` until complete manifests and hashes match and
fresh-session discovery passes for each named client. Do not show an install
path, hash, consent ID, schema version, or commit unless advanced detail is
requested or the value changes the next decision.

Generate the card from verified maintenance state with
`scripts/New-UserVoiceCompletionCard.ps1 -MaintenanceRoot <private-root>`.
That command reports draft or approved source state. After the separate install
action and fresh-session checks, generate installed state with all applicable
discovery roots and checked clients:

```pwsh
scripts/New-UserVoiceCompletionCard.ps1 `
-MaintenanceRoot <private-root> `
-InstalledProfilePath <installed-profile> `
-DiscoveryRoot <applicable-skill-roots> `
-InstalledClient <checked-client-names> `
-InvocationVerification passed
```

Before it can emit `installed and checked`, the generator validates both
runtime packages, compares their complete file and hash manifests, and requires
one discovered current profile. It does not prove where the private source
repository came from; run the visibility, owner, path, and history checks in
[private-source.md](private-source.md) separately.

The real builder performs the package check against the exact approved profile
and records it as passed only after the checked runtime replaces the prior
private runtime source. Do not mark that check passed before the build.

## Check that it works

For every named client, run the checks in [integration.md](integration.md): one
natural request, one explicit request, fallback without the profile, unsupported
context, unknown schema, and duplicate-profile handling. Record only the overall
results in the completion card.

## Present the verified state

Do not ask the user to repeat facts the workflow can verify. The completion card
must state whether the profile is drafted, approved, installed, and checked;
which clients were tested; what writing is ready; what remains off; which
actions the profile cannot perform; and whether another-machine setup exists.

Ask a question only when the user must make a real choice or when available
evidence conflicts. If the user expresses a misunderstanding, clarify it with
the verified facts; do not turn normal completion into a quiz.

The normal path is novice-ready after two consecutive first-time-user pilots
complete source confirmation, any selected handoff, draft review, and the
verified completion summary without schema repair or developer intervention.
