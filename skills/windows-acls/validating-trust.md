# Validating trust in a shared location

You need this only when privileged code must consume a location it did not just
create. If the installer provisioned the object, validate once and move on. If
nothing provisioned it, this is the fallback and it must fail closed.

## Anchor at a root, not at every component

Validate **one** root directory. Once that root grants no modification rights to
any principal outside the trusted set, an unprivileged user cannot create,
replace, rename, or delete anything below it, so every descendant follows by
induction.

Walking each component of a path adds cost and no protection against an
unprivileged attacker. It only detects deliberate administrator changes deep in
the tree, and administrators are already trusted in this model.

Cache the result for the process lifetime. Only an administrator can invalidate
it, and if an administrator is hostile the check was never the defense.

## What to check, in order

1. **Not a reparse point.** A junction can be created by a standard user with no
   elevation at all. Check `FileAttributes.ReparsePoint` on the root itself.
2. **Owner is a trusted machine principal** - `BUILTIN\Administrators` or
   `SYSTEM`. This is the load-bearing check.
3. **No allow ACE grants modification rights to anyone else.** Include the full
   right set from [securing-objects.md](securing-objects.md), and include
   **inherit-only** ACEs.

Deny ACEs and additional read-only allow ACEs are fine. Do not require an exact
ACE list.

## Why the owner and not the DACL

A DACL is forgeable. Any caller, at any integrity level, can create a directory
whose DACL names only `Administrators` and `SYSTEM`. It looks perfect.

But the creator is still the **owner**, and an owner implicitly retains
`READ_CONTROL` and `WRITE_DAC`. So the attacker can lock themselves out to pass
your check and unlock again the moment they want to tamper. A DACL-only check is
worthless on its own.

An owner of `Administrators` or `SYSTEM`, by contrast, cannot be produced by an
unelevated caller at all: a SID may own an object only if the creating token
carries it with `SE_GROUP_OWNER`, and a standard user's token does not.

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

- Reject directory separators and `..`.
- Reject the volume separator `:`.
- Reject a trailing dot or trailing space. Windows strips both, so a component
  ending in a dot or a space aliases the same name without it.
- Canonicalize with `Path.GetFullPath` and then verify containment against the
  root, comparing with `OrdinalIgnoreCase` and a trailing separator so that
  `C:\root2` does not pass as a child of `C:\root`.

A legacy device-name blocklist (`CON`, `NUL`, `LPT1`) is not needed on current
Windows; path normalization no longer reinterprets those as devices in a
qualified path, and a containment check catches anything that does normalize
elsewhere.

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
