# Validating trust in a shared location

You need this only when privileged code must consume a location it did not just
create. If the installer provisioned the object, validate once and move on. If
nothing provisioned it, this is the fallback and it must fail closed.

## Anchor at a root, not at every component

Validate **one** root directory only after establishing that every ancestor from
the volume root to that directory prevents unprivileged users from replacing or
renaming it. Once that premise and the root check both hold, an unprivileged user
cannot create, replace, rename, or delete anything below the root, so every
descendant follows by induction.

`%ProgramData%\<Product>` satisfies the ancestor premise on a default Windows
installation: standard users can create new top-level entries but cannot replace
an existing administrator-owned product directory. A deeper, redirected, or
custom root may not. Provision it under trusted ancestors or validate the chain
before relying on a cached root verdict.

Walking each component of a path adds cost and no protection against an
unprivileged attacker. It only detects deliberate administrator changes deep in
the tree, and administrators are already trusted in this model.

Cache the result for the process lifetime only when the ancestor premise holds.
Then only a trusted principal can invalidate it, and if that principal is
hostile the check was never the defense.

## What to check, in order

1. **Not a reparse point.** A junction can be created by a standard user with no
   elevation at all. Check `FileAttributes.ReparsePoint` on the root itself.
2. **Owner is an expected machine principal** - normally
   `BUILTIN\Administrators` or `SYSTEM`. `NT SERVICE\TrustedInstaller` is also
   valid for a known OS-provisioned root; do not admit arbitrary service
   accounts. This is the load-bearing check.
3. **A DACL is present and is not NULL.** Both an absent DACL and a NULL DACL grant access to everyone. An empty DACL instead grants no access. Inspect the raw descriptor's `DiscretionaryAclPresent` control flag and `DiscretionaryAcl`; do not infer this property from an empty projected rule collection.
4. **No allow ACE grants modification rights to anyone else.** Include the full
   right set from [securing-objects.md](securing-objects.md), and include
   **inherit-only** ACEs.

Deny ACEs and additional read-only allow ACEs are fine. Do not require an exact
ACE list.

## Why DACL presence matters

No DACL is not the same as a DACL with no ACEs. Windows grants access when the
descriptor has no DACL or has a NULL DACL; an empty DACL reaches the end without
granting any requested right and therefore denies access. A validator that
reduces both cases to "no matching allow rule" can approve an object that is
open to everyone.

## Do not subtract denies from allows

[ACE order changes effective
access](securing-objects.md#ace-order-changes-effective-access). A user-specific
deny blocks a group allow only when the deny is reached before earlier allows
complete the access check. Masks, inheritance, and noncanonical order all affect
that result.

This validator intentionally does not calculate deny exceptions. If an allow
ACE grants modification capability to an untrusted principal, reject the root
regardless of deny ACEs or DACL order. This makes the verdict independent of
group membership and ordering details instead of treating a broad grant as safe
because one current user appears to be denied.

## Why the owner and not the DACL

A DACL is forgeable. Any caller, at any integrity level, can create a directory
whose DACL names only `Administrators` and `SYSTEM`. It looks perfect.

But the creator is still the **owner**, and an owner implicitly retains
`READ_CONTROL` and `WRITE_DAC`. So the attacker can lock themselves out to pass
your check and unlock again the moment they want to tamper. A DACL-only check is
worthless on its own.

An expected machine owner, by contrast, cannot be produced by an unelevated
caller: a SID may normally own an object only if the token carries it with
`SE_GROUP_OWNER`, and a standard user's token does not. Assigning an unrelated
owner requires enabled `SeRestorePrivilege`.

## Why inherit-only ACEs count

An ACE with `PropagationFlags.InheritOnly` grants **nothing on the container
itself** and everything on its descendants. Because root-anchored validation is
an induction over descendants, a validator that filters out inherit-only rules
would pass a root that hands write access to every child.

Read rules with both `includeExplicit` and `includeInherited` set to `true`, and
do not filter on `PropagationFlags`.

## Capability, not exact equality

Requiring an exact set of ACEs - "exactly these four, with exactly these
inheritance flags" - rejects harmless additions. Enterprise management tools,
backup agents, and auditing configurations legitimately add read ACEs. Exact
matching turns those into a hard failure in an ordinary workflow.

Check the property you actually need: *no untrusted principal can modify this*.

## Reject, never repair

When validation fails, stop. Do not apply the correct descriptor and continue.

Repairing an object somebody else created leaves their data in place under a
descriptor that now looks trustworthy - the worst possible outcome, because every
later check passes. Rotate to a fresh location, or fail with a targeted recovery
message that names the path.

## What a passing check does and does not buy you

It buys: no unprivileged principal can substitute, modify, or redirect anything
under that root.

It does not buy: protection from an administrator, or protection from a process
running as the same account when the root is per-user. If you need integrity
against a same-user process, validate content rather than location - verify a
signature over the bytes you are about to consume, in the process that consumes
them.

## Path-shape checks worth keeping

Independent of descriptors, when a caller-supplied component becomes part of a
path:

- Require the trusted root to pass `Path.IsPathFullyQualified`.
  `Path.IsPathRooted` is insufficient because Windows drive-relative and
  root-relative paths are rooted but still depend on current-directory state.
- Join it to the trusted root with `Path.Join`, not `Path.Combine`, so a
  rooted component cannot discard the root.
- Reject directory separators and `..`.
- Reject the volume separator `:`.
- Reject a trailing dot or trailing space. Windows strips both, so a component
  ending in a dot or a space aliases the same name without it.
- Canonicalize the joined path with `Path.GetFullPath(joinedPath, root)`. The
  explicit fully qualified base avoids the process current directory and
  Windows per-drive current-directory state. Then verify containment against
  a root prefix that ends in one separator so that `C:\root2` does not pass as a
  child of `C:\root`. Retain the separator already present on a filesystem root;
  do not append a second one. Use `Ordinal` for a fail-closed check. If casing
  aliases must be accepted, first probe the filesystem for that root and use
  `OrdinalIgnoreCase` only when the probe shows it is case-insensitive.

Reject legacy device basenames such as `CON`, `NUL`, and `LPT1` when Windows 10
or Server 2022 is supported; those systems can still reinterpret them in a
qualified path. Newer Windows 11 behavior differs, so do not use one version's
normalization as a cross-version security boundary.

## Deletion is the sharpest edge

`Directory.Delete(path, recursive: true)` refuses to recurse through a reparse
point only in the **final** path segment. An ancestor junction is resolved by
Windows before that check runs, so deleting `junction\child` removes the real
target's `child`.

Privileged recursive deletion of a path you did not construct entirely from
trusted components is the highest-severity primitive in this area. Prefer:

- Deleting specific known filenames rather than recursing.
- Refusing to descend into any entry carrying `FileAttributes.ReparsePoint`.
- Deleting only below a root the privileged process created itself in this
  operation.
