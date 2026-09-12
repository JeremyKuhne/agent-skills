# Audit filesystem I/O

Use for "am I saving this right?", "check my code to make sure I'm following
best practices for IO", a file I/O audit, or a review of storage handling.
This workflow is **read-only by default**. Do not edit source, change ACLs,
delete data, or migrate storage unless
the user asks for those actions. Isolated tests with synthetic data are allowed;
do not probe destructive cases against the user's real files.

## Start from actual operations

1. Begin with the named file, call site, or feature. For a general audit, find
   filesystem reads, writes, opens, moves, deletes, and their storage helpers.
   Follow wrappers to the code that selects the path, mode, permissions, and
   error/recovery behavior. Reuse tests and existing storage abstractions.
2. Trace each relevant path from its source to its use. Identify the process's
   privilege, who can choose the path or edit the data, and what the consumer
   does with it. Per-user AppData is writable by its owner without elevation;
   it is not an administrator-approved policy store.
3. Classify the data and consequence: disposable scratch, rebuildable cache,
   replaceable preferences, irreplaceable documents, credentials, or privileged
   configuration. Inspect concurrent writers and known deployment overrides.
   Keep confidentiality separate from whether data can be recreated.
4. Apply the ordinary defaults from [SKILL.md](SKILL.md). Escalate only when
   evidence or a required guarantee crosses one of its boundaries. Inspect
   configuration before asking; a hypothetical shared mount is not a defect.

For application settings, use the same
[scope and mobility decisions](persisted-files.md)
as a new design. Trace where defaults and policy come from, precedence, which
keys are user-owned, and where saves write them. Check both the read/merge path
and write path; a correct directory alone does not make the design correct.

If the request says only "I/O", start with filesystem correctness and security
and state that scope. Route pipes, sockets/networking, deep performance, database
internals, and broad serialization security to their specialist workflows.
Still report an obvious boundary issue found in a file consumer.

## Check for consequential problems

| Area | What to check |
| --- | --- |
| Location and authority | Empty/relative roots, ambient working-directory dependence, user-controlled environment overrides in privileged code, user-editable configuration treated as trusted policy |
| Settings scope and roaming | Per-user "global" confused with all users; device-specific data in roaming storage; Windows roaming assumptions applied to Linux/macOS; sync guarantees inferred from a special-folder name |
| Defaults and policy | Effective values written back to shared defaults or copied into every user store, lost inheritance/reset behavior, lower-trust providers overriding mandatory policy |
| Paths | Root replacement, traversal, filename collisions, unauthorized destinations, links/reparse points in attacker-writable trees; normalization is not authorization |
| Reads | Partial reads treated as complete, unbounded input allocation, malformed/truncated content accepted, defaults that hide a consequential read failure |
| Creation and overwrite | `Exists`/create races, accidental truncation, stale trailing bytes, existing untrusted entries adopted, complete output required but partial output exposed |
| Lifetime and failure | Leaked streams/handles, unawaited writes, cancellation leaving apparently complete output, disk-full/access/sharing failures swallowed, cleanup hiding the original error |
| Permissions and trust | Creation-time protection appropriate to the data, actual lower-privilege writers, ACL/mode assumptions crossing an authority boundary |
| Publication and coordination | Replaced metadata matters, readers hold incompatible handles, lost read-modify-write updates, durability claimed without a supporting protocol |
| Deletion and cleanup | Scope too broad, user input controls recursion, link races, active files swept by age alone, deletion described as secure erasure |
| Portability | Casing assumptions, rooted-relative Windows paths, platform guards, different sharing/delete semantics, appropriate cache/state locations |

Use [paths.md](paths.md), [permissions.md](permissions.md),
[persisted-files.md](persisted-files.md), [temporary-files.md](temporary-files.md),
and [platform-differences.md](platform-differences.md) only for the checks reached.
Do not require all files to use one recipe or assume the bundled helpers are
necessary in an application with a suitable existing abstraction.

## Ask a question only when it changes the finding

Translate unresolved technical requirements into product consequences:

| Evidence still missing | Question and recommendation |
| --- | --- |
| Settings scope | "Just this person, or everyone on this computer?" Global across one person's projects is normally per-user storage. |
| Mobility | "Should this follow the person to another computer?" Separate portable preferences from device-specific values; a folder choice alone does not enable sync. |
| Authority | "Is this a default people can change, or a rule they must not override?" Keep user overrides separate from enforced policy. |
| Recovery importance | "Is this the only copy, or can it be recreated?" Recommend sibling staging for ordinary preferences, a stronger save/store protocol for irreplaceable state. |
| Writer ownership | "Can two copies update this file?" Explain that a later save can overwrite the earlier changes. |
| Path authority | "Can another person choose this destination?" Explain which reads/writes/deletes that enables. |
| Privacy | "Does this contain credentials or another person's private data?" Explain that a cache may be disposable but still sensitive. |

Do not ask the user to certify a DACL, inspect `umask`, or select `fsync` flags.
Gather technical evidence yourself where available. If it is unavailable,
report the specific unknown and its consequence. Do not invent hostile users,
multiple writers, or power-loss requirements merely to justify hardening.

## Report in three categories

Lead with findings by consequence, grounded in file/line and the controlling
operation. For each, give evidence, a concrete failure or abuse scenario, the
smallest adequate fix, and a focused check. Keep these categories distinguishable:

- **Defect:** current code violates an established requirement or has a reachable
  correctness/security bug. Example: an elevated helper obeys a deletion path
  from an ordinary user's editable settings without authorization.
- **Conditional risk:** a missing fact could make the code unsuitable. State the
  exact condition, ask the question if needed, and give the two dispositions.
  Example: last-writer-wins storage is fine for one writer, but loses updates if
  independent instances must merge changes.
- **Accepted tradeoff:** the code fits the ordinary use and its loss/recovery
  policy. Example: direct cache writes plus validation/rebuild, or normal
  preference saves without a power-loss guarantee. Do not list these as defects
  or demand unnecessary changes.

Admin/root compromise and hostile processes with the same effective authority
are outside these permission recipes, not automatic audit findings. Continue to
check actual lower-privilege input into elevated operations, even within one
user's profile. Excluding a powerful attacker does not exclude ordinary-user
tampering with machine policy.

End with scope inspected, checks actually run, significant accepted limitations,
and gaps. If there are no material findings, say so. A source audit or a few
passing tests is not certification of all deployments or crash recovery. Prefer
an existing credential store, transaction, service-owned directory, or simpler
location before proposing custom native hardening; consequential redesign needs
approval.
