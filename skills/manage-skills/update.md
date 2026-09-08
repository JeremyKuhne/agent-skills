# Update a skill

Detail for the [manage-skills](SKILL.md) skill. "Update the skill" has two
directions. The second - pushing a local improvement - is where the
[golden rule](SKILL.md) is enforced.

## Pull: take upstream changes

First identify the canonical source and every installed project/user target. Do
not edit a runtime copy merely because it is the first path found.

### Separate local drift from upstream discovery

`gh skill update` compares the **recorded** local provenance tree SHA in
`SKILL.md` with the remote repository. It does not hash the installed files or
prove that local content still matches the recorded pin. Pinned skills are
skipped unless `--unpin` is supplied. Treat this command as upstream discovery,
not as a local-drift check:

```pwsh
# One skill
gh skill update <skill> --dry-run

# All installed skills
gh skill update --all --dry-run
```

Run the independent local-to-recorded-pin gate below before this command, even
when the skill is pinned or the remote tree has not moved. Do not pass `--unpin`
or change an immutable pin merely to inspect state; either action needs the same
approval as the resulting update. Review an actual candidate like a dependency
bump, then re-pin deliberately after every overlay and divergence has a
disposition.

### Pass the local-to-recorded-pin gate

Use the installed provenance to obtain the exact source artifact at its recorded
repository, path, and immutable revision. Use an existing trusted checkout or a
read-only temporary checkout; if the recorded artifact or a structured YAML
parser is unavailable, report the gate as unavailable and stop rather than
claiming the copy is clean.

1. Parse and verify the generated provenance fields against the reviewed source
   identity, path, ref, pin state, and tree SHA.
2. Produce a complete raw path diff between the recorded artifact and installed
   skill before excluding or normalizing anything. Retain every added, deleted,
   and changed path in the review evidence.
3. For every non-`SKILL.md` path present on both sides, compare bytes or a
   cryptographic hash. A changed resource is drift even when its filename is in
   a divergence record.
4. Parse both `SKILL.md` frontmatter mappings with a structured YAML parser.
   Compare every source-authored key and value. Set aside only verified generated
   `github-repo`, `github-ref`, `github-pinned`, `github-path`,
   `github-tree-sha`, or `local-path` fields.
5. Compare the authored Markdown body after normalizing line endings and the
   frontmatter/body boundary. Do not normalize other text or YAML values.
6. Classify the retained raw differences using the clean/reconciled rules below.
   Any unclassified difference blocks update or acceptance.

This PowerShell manifest is a portable first pass for step 2; it deliberately
shows the raw `SKILL.md` difference before semantic normalization:

```pwsh
function Get-SkillManifest([string] $Root) {
  Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
    ForEach-Object {
      [pscustomobject]@{
        Path = [IO.Path]::GetRelativePath($Root, $_.FullName).Replace('\', '/')
        Length = $_.Length
        Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
      }
    } |
    Sort-Object Path
}

Compare-Object `
  (Get-SkillManifest <recorded-artifact>) `
  (Get-SkillManifest <installed-skill>) `
  -Property Path, Length, Hash
```

Do not substitute a tests-only repository helper for these checks. A consuming
repository may wrap them in its own production validator, but missing local
infrastructure does not relax the comparison.

### Distinguish a clean mirror from reconciled divergence

A **clean mirror** has no authored core difference after the narrow
`SKILL.md` normalization above. Every source resource and source manifest entry
is exact. An overlay, catalog entry, or divergence ledger is separately owned
local collateral: surface it in the raw diff, classify it explicitly, and do not
call it part of the clean core.

A **reconciled pending divergence** is not a clean mirror. Accept it only when:

- the record's base pin exactly matches the installed provenance pin;
- the record states its reason and upstream status;
- every expected changed, added, or deleted path is listed with an exact patch
  or expected normalized content/hash, not merely a filename exemption;
- applying all current records to a scratch copy of the recorded artifact
  produces the complete installed core after the same narrow normalization; and
- the full comparison leaves no extra hunk, path, or manifest difference.

Never omit a whole recorded file from comparison. That would hide an unrelated
edit in the same body or resource. An overlay also cannot excuse a core change.
Report the result as `clean mirror`, `reconciled divergence`, or `blocked by
unexplained drift`; do not collapse those states into one pass.

### Pass the pin and divergence gate

Before changing any pin or provenance ref:

1. complete the local-to-recorded-pin gate at the current pin;
2. enumerate the overlay and every pending-divergence record for the skill;
3. compare each exact recorded change against both the current and candidate
   artifacts, including changed, added, and deleted paths;
4. search the candidate upstream tree and release history for the equivalent
   change;
5. remove an **absorbed** record only when the candidate artifact contains its
   exact effective change;
6. rebase a **retained** change onto a scratch candidate artifact, verify the
   complete derived artifact, and update the record's base pin, exact patch or
   hashes, paths, reason, and upstream status;
7. reject every stale-base record and every difference left after applying the
   current records;
8. update every overlay `core-pin` only after its bindings are reviewed against
   the candidate; and
9. run the semantic cases before installing.

Stop the update if any overlay or divergence has no explicit disposition. A new
pin with a stale base-pin record is unexplained drift, even when validation and
the skill itself still load.

`--force` overwrites locally modified tracked files but does not remove extra
files. It therefore does not prove overlays or pending divergences are still
valid.

Manual fallback (no `gh`): perform the same local-to-recorded-pin gate, compare a
separately obtained candidate artifact, apply the reviewed diff, update
provenance, and reinstall every recorded host/scope target with file-list and
hash verification. Preserve pins and approval boundaries.

## Push: send a local improvement to the right layer

When you improve a vendored skill locally, first classify the change, then decide
where it lives. Classification does not trigger any action on its own.

- **Local deviation** - specific to this repo or user (a repo-only tool,
  personal policy, local path, or target-specific example). It belongs in the
  installation's **overlay**, never in the vendored core. Move the change into
  `overlay.md` (starting from
  `assets/overlay.md.tmpl` when needed), restore the core to match upstream, and
  record the current pin in `core-pin`. No upstreaming question arises.
- **Common** - generic, helps every consumer (a clearer phrasing of a portable
  rule, a new universally-applicable check, a fixed error). It *should* go
  upstream, but upstreaming is **never automatic** and is not always plausible:
  the commons may be unreachable, the change may be sensitive or need discussion
  first, or you may lack the time or rights. So **ask** before attempting it.

### The upstreaming query (common changes only)

Stop and ask the user whether to attempt upstreaming. **Never open a commons PR on
your own** - it is a publish action, gated by the same rule as any push (the
repo's contribution and publish rules). Present what the change is, why it is
common, and the options:

- **Upstream it now** - prepare the PR to the commons; *creating* it still needs an
  explicit publish verb from the user. Once merged, re-vendor here at the new pin.
- **Not now / not plausible** - keep the change in the local core as a *tracked
  pending-upstream divergence*: record it in the commit message and the repository's
  divergence ledger or a short note. Identify the skill, base pin, reason,
  upstream status, and every changed, added, or deleted path with its exact patch
  or expected normalized content/hash. The local-to-pin check must be able to
  derive the complete expected artifact from the record. Re-attempt upstreaming
  when it becomes plausible; remove the record when the pinned upstream artifact
  contains the exact change.
- **Reclassify** - if discussion shows the change is actually repo-specific, move
  it to the overlay instead and restore the core.

Default to asking even when the change looks obviously common and obviously worth
sharing. Nothing about upstreaming happens without an explicit decision.

Before presenting an upstream summary or publishing an approved commons change,
run `technical-writing` against the current diff and lifecycle disposition.
Review pending-divergence text locally when upstreaming is deferred. For an
approved PR, run pre-publication mode on the exact title and body immediately
before creation; rerun it if the candidate, diff, validation, or upstream state
changes. A successful prose review does not answer the upstreaming query or
authorize the PR.

## The golden rule and its mechanics

*Never let a vendored core diverge silently.* A vendored core is a mirror of
upstream; any edit to it is a deliberate fork that must end in one of three
**recorded** states - never an unexplained one:

- promoted upstream and the core re-pinned,
- moved to the overlay and the core restored, or
- kept as a **tracked pending-upstream divergence** - a common change that could
  not be upstreamed yet, recorded so the divergence is intentional and visible.

The point is *visibility*, not "resolved within the hour". A recorded divergence is
fine; an unexplained one is the alarm. What makes this enforceable:

- **Provenance frontmatter** on every vendored copy records the source repo, ref,
  and tree SHA it was installed from.
- **The independent local-to-recorded-pin check** compares the complete local
  core against that exact source artifact. `gh skill update` separately reports
  whether the recorded tree SHA differs from the remote; it does not inspect
  local content. Unexplained local drift is the alarm that an improvement was
  written into the wrong layer.

So the discipline is mechanical: if the local-to-pin comparison finds a change
that no exact current record explains, stop. Classify it as common or local; move
a local deviation to the overlay and restore the core, or obtain the required
upstream/pending-divergence decision for a common change.

## After any update

Run [review.md](review.md) against the changed routing, workflow, and ownership
surface. Re-run the validators and link check, and if the change touched the catalog
or trigger phrasing, reconcile the catalog `README.md` (inventory row and
disambiguation) in the same change. Then hand off to `agent-files-review` to validate
the resulting files; semantic lifecycle review does not replace file-level review.
If the skill is obsolete rather than changed, follow [retire.md](retire.md) instead
of forcing removal into the update path.

Then follow [install.md](install.md) to verify each effective project/user copy,
registered source, plugin, and host path. Report any target intentionally left
at an older pin.

Run the update cases in [evaluations.md](evaluations.md), including a candidate
pin that already contains one local divergence and another that does not.
