# Research: Windows access control behavior for application state

Evidence base for the `windows-acls` skill. Every claim below is either measured
on a live system or cited to primary documentation. Where the two disagree, or
where a widely held belief turned out to be wrong, that is called out.

Measurements were taken on Windows 11 with .NET 10 and PowerShell 7.6. The
measuring token was **medium integrity with `BUILTIN\Administrators` present as
deny-only** - a filtered administrator token. That is strictly more privileged
than a plain standard user, so a capability denied to it is denied to a standard
user as well.

The claims marked *pinned* are enforced by the bundled Pester tests.

---

## 1. `%ProgramData%` is shared, not trusted

Default DACL on `C:\ProgramData`:

```text
NT AUTHORITY\SYSTEM:(OI)(CI)(F)
BUILTIN\Administrators:(OI)(CI)(F)
CREATOR OWNER:(OI)(CI)(IO)(F)
BUILTIN\Users:(OI)(CI)(RX)
BUILTIN\Users:(CI)(WD,AD,WEA,WA)
```

The last entry is the problem. `WD` (create files / write data) and `AD` (create
subdirectories / append data) are granted to `BUILTIN\Users` with
`CONTAINER_INHERIT`. A standard, medium-integrity, non-elevated caller can
therefore create a top-level directory under `%ProgramData%`, and owns what it
creates.

A child created there **without** an explicit descriptor inherits:

```text
Allow BUILTIN\Users  ReadAndExecute, Synchronize   inherited=True
Allow BUILTIN\Users  Write                          inherited=True
```

*Pinned:* "inherits a parent inheritable ACE when the child is created without a
descriptor".

**Consequence.** Any design that lazily creates `%ProgramData%\<Product>` on
first use and then trusts it is exploitable: whichever principal runs first owns
the directory that privileged code later consumes.

Microsoft's guidance treats `%ProgramData%` as the machine-wide *sharing*
location and explicitly recommends an admin-write-only location when machine-wide
data must be *trusted*.

---

## 2. Supplying a DACL at creation changes three things

Creating a directory with an explicit `DirectorySecurity` under a parent that has
inheritable ACEs produced:

```text
### explicit descriptor, top level
    owner = REDMOND\<user>
    Allow Everyone:ReadAndExecute, Synchronize     inherited=False
    Allow NT AUTHORITY\SYSTEM:FullControl          inherited=False
    Allow BUILTIN\Administrators:FullControl       inherited=False
    Allow BUILTIN\Users:ReadAndExecute, Synchronize inherited=False
```

### 2a. Parent inheritable ACEs are suppressed

No `BUILTIN\Users: Write` appears, and every rule reports `IsInherited == false`.
The supplied DACL is the whole DACL.

*Pinned:* "suppresses parent inheritable ACEs when the child is created with a
descriptor".

### 2b. The measured .NET result is protected

`AreAccessRulesProtected` is `true` on the result, even though nothing called
`SetAccessRuleProtection`. This was the single most surprising measurement in
this research, and it is load-bearing for the enterprise scenario in section 5.

This result is narrower than the general Windows creation rule. The automatic
inheritance documentation describes merging inheritable parent ACEs into an
unprotected creator DACL. `FileSystemAclExtensions.CreateDirectory` instead
returned a protected child with no inherited ACEs.

A follow-up experiment set `DiscretionaryAclAutoInherited` explicitly on the
creator `DirectorySecurity` through a `RawSecurityDescriptor`, verified that the
flag survived the round trip, and invoked the same .NET create helper under a
parent carrying an inheritable `BUILTIN\Users:Write` ACE. The result was still
protected, had no `Users` rule, and had no inherited rules. The absence of
`SE_DACL_AUTO_INHERITED` is therefore not the explanation for this BCL path.
This experiment does not establish how a direct native creation call behaves.

*Pinned:* "marks a directory created with an explicit descriptor as protected"
and "protects an explicit descriptor even when it is marked auto-inherited".

### 2c. Intermediate directories receive the same descriptor

Creating `root\a\b\c` through `FileSystemAclExtensions.CreateDirectory` and
inspecting every level showed the supplied descriptor at all four, not only at
the leaf. This is behavior of the .NET helper, which loops over missing path
components with one descriptor; it is not a property of one native
`CreateDirectoryW` call.

*Pinned:* "applies the explicit descriptor to the intermediate directories it
creates".

Side effect worth knowing: if the supplied descriptor excludes the creating
caller, creation of a nested path fails partway with
`UnauthorizedAccessException`, leaving intermediates behind that the same caller
then cannot delete.

---

## 3. The owner is forgery-proof; the DACL is not

| Attempt from a medium-integrity token | Result |
| --- | --- |
| Create a directory whose DACL is exactly `Administrators:FullControl, SYSTEM:FullControl` | **Succeeded** |
| Owner of that directory | The creating user, not `Administrators` |
| `SetOwner(BUILTIN\Administrators)` in memory | **Succeeded** |
| Committing that owner with `SetAccessControl` | **Threw** `InvalidOperationException: The security identifier is not allowed to be the owner of this object.` |
| `SetOwner(NT AUTHORITY\SYSTEM)` then commit | **Threw**, same |
| Owner rewrites the DACL to restore its own `FullControl` | **Succeeded** |

Two conclusions:

**A DACL proves nothing.** Any caller can produce a trusted-looking DACL, and
because an owner implicitly retains `READ_CONTROL` and `WRITE_DAC`, that caller
can undo it whenever convenient. A validator that checks only access rules can be
satisfied and then bypassed.

**An owner of `Administrators` or `SYSTEM` cannot be forged.** A SID may own an
object only if the creating token carries it with `SE_GROUP_OWNER`. A filtered
administrator token carries `Administrators` as deny-only, which does not
qualify.

Elevation changes the `Administrators` case, not the `SYSTEM` case. An ordinary
elevated administrator token can assign `Administrators` because that group is
owner-enabled. Assigning an unrelated SID such as `SYSTEM` requires the caller
to run as that identity or to enable `SeRestorePrivilege`; the .NET
`SetAccessControl` path does not enable it on the caller's behalf. The per-PR
Windows test expects the ordinary elevated runner to reject `SYSTEM` ownership.

### Correction to a common description

The rejection is frequently described as "SetOwner throws". It does not. Measured
precisely:

```text
SetOwner (in memory)     : SUCCEEDED
SetAccessControl (commit): THREW InvalidOperationException:
                           The security identifier is not allowed to be the owner of this object.
owner on disk            : REDMOND\<user>
```

Code that wraps only the `SetOwner` call in a `try` concludes the assignment
worked. The check must wrap the commit. This document originally carried the
incorrect version; the bundled test now pins the correct one.

*Pinned:* "assigns a new owner only when the caller is elevated", "does not gain
permission to assign SYSTEM merely by being elevated", "creates objects with the
token default owner", "lets any caller create a directory whose DACL names only
Administrators and SYSTEM", and "lets the owner rewrite a DACL that grants the
owner nothing".

### ACE order changes effective access

Microsoft documents both parts of the mechanism: Windows [examines matching ACEs
in sequence and stops](https://learn.microsoft.com/windows/win32/secauthz/how-dacls-control-access-to-an-object)
when a deny rejects a requested right or allows have granted every requested
right, and the [preferred
order](https://learn.microsoft.com/windows/win32/secauthz/order-of-aces-in-a-dacl)
puts explicit denies before explicit allows.

The test wrote two protected DACLs to the same file and read each descriptor
back before attempting `File.ReadAllText`:

| On-disk DACL order | Canonical | Result |
| --- | --- | --- |
| `Allow Everyone:Read`, `Deny current-user:Read` | No | Read returned the file contents |
| `Deny current-user:Read`, `Allow Everyone:Read` | Yes | Threw `UnauthorizedAccessException` |

The allow-first descriptor remained noncanonical on disk. Its first ACE matched
the caller through `Everyone` and granted the complete read request, so Windows
stopped before reaching the user-specific deny. Reversing the two ACEs reached
the deny first and rejected the same operation.

This is not a general user-before-group precedence rule. Windows compares all
enabled user and group SIDs in the token; ACE sequence, type, mask, and
inheritance determine the result.

*Pinned:* "grants read when a matching allow completes the check before a later
deny".

### Authz reads an effective access mask

Two tests exercised `AuthzAccessCheck` with `MAXIMUM_ALLOWED` against security
descriptors read back from disk:

| Client context | DACL | Result |
| --- | --- | --- |
| Current process token through `AuthzInitializeContextFromToken` | Deny current user write; allow current user read | Granted mask included `ReadData` and excluded `WriteData` |
| Current user SID through `AuthzInitializeContextFromSid` | Allow `BUILTIN\Users` read | Granted mask included `ReadData`, proving group expansion on the measured host |

The SID result is deliberately narrower than the token result. Microsoft says
the token context is more complete and accurate. `AuthzInitializeContextFromSid`
attempts S4U token-group retrieval and may fall back to account group data that
omits logon-characteristic groups. The group-expansion test establishes the
observed local result, not equivalence between SID and token contexts.

The legacy `GetEffectiveRightsFromAcl` API was not used. Its documentation says
it omits owner rights, privileges, logon-session groups, and resource-manager
policy, and fails when an ACL contains an inherited deny ACE.

Two further tests measured the managed alternatives. The token was an enabled
member of `BUILTIN\Users`, yet a user-specific deny still blocked reading a file
that allowed that group, so `IsInRole` did not answer the file-access question.
On a second protected file, `FileSystemAclExtensions.Create` with
`FileMode.Open` granted an exact `ReadData` request and denied an exact
`WriteData` request.

*Pinned:* "gets maximum allowed rights from the current access token",
"resolves group rights when initialized from the current user SID", "does not
infer file access from enabled group membership", and "opens an existing file
with an exact managed rights request".

---

## 4. Directory rights govern the namespace

A file was given a protected DACL containing an explicit
`Deny  <current user>  Write, Delete`, inside a parent the same user could write:

```text
blocked  : direct write to the file      (UnauthorizedAccessException)
SUCCEEDED: direct delete of the file
SUCCEEDED: create a replacement at the same path
final content at package.msi: 'attacker payload'
```

The deny was real - the file could not be modified in place - and irrelevant. The
parent granted `FILE_DELETE_CHILD`, which Windows accepts as an alternative to
`DELETE` on the child, so the file was removed and replaced.

**Validating a file's own descriptor is unsound.** The parent controls whether
the object at that name can be swapped for a different one. This is why trust
must be anchored on directories.

*Pinned:* "removes and replaces a file whose own DACL denies delete when the
parent allows it".

---

## 5. Inheritance, and the enterprise scenario

### Inherit-only ACEs grant nothing here and everything below

An ACE with `CONTAINER_INHERIT | OBJECT_INHERIT | INHERIT_ONLY` appears on the
container with `PropagationFlags.InheritOnly` and on a child as an effective rule
with `PropagationFlags.None`.

A validator that filters inherit-only rules out would approve a root that hands
write access to every descendant.

*Pinned:* "carries an inherit-only ACE on the container and an effective one on
the child".

### A later parent change does not reach a protected child

The question that decides whether enterprise ACL management breaks an
application: if IT adds an inheritable ACE to `C:\ProgramData` **after** the
product directory exists, does it propagate in?

Measured, with a child created through the .NET explicit-descriptor overload
(therefore protected per section 2b), then adding
`NETWORK SERVICE:(OI)(CI)FullControl` to the parent:

```text
### child after the parent change
    Allow Everyone:ReadAndExecute            inherited=False
    Allow NT AUTHORITY\SYSTEM:FullControl    inherited=False
    Allow BUILTIN\Administrators:FullControl inherited=False
    ...
>>> Did NOT propagate.
```

This matches the documented rule: `SetNamedSecurityInfo` and `SetSecurityInfo`
propagate inheritable ACEs to children, and the documentation states that setting
`SE_DACL_PROTECTED` is how you ensure a child is not affected by inheritable
ACEs.

**So IT hardening `C:\ProgramData` does not break a product directory created
with an explicit descriptor.** Grandchildren are equally unaffected, because they
inherit from the protected child rather than from `ProgramData`.

*Pinned:* "does not propagate a later parent ACE into a protected child".

### What does still fail closed

| Enterprise action | Result under root-anchored validation |
| --- | --- |
| Inheritable ACE added to `C:\ProgramData` | No effect; the product keeps working |
| ACE granting modification rights added **directly** to the product root | Rejected |
| Product root pre-created by script or image without an explicit descriptor | Rejected - it inherits `BUILTIN\Users: Write` and genuinely is user-writable |

The last two are correct rejections: in both cases a non-administrator principal
can modify the tree. Widening the trusted principal set is not a fix, because an
IT-added service account is indistinguishable from an account an attacker
controls.

---

## 6. Reparse points

**Junctions need no elevation.** `New-Item -ItemType Junction` and `mklink /J`
succeed for a standard user. *Symbolic* links require
`SeCreateSymbolicLinkPrivilege` or Developer Mode - a meaningful asymmetry when
reasoning about what an attacker can plant.

**`GetAccessControl` reports the junction's own descriptor**, not the target's.
Measured with a target carrying a distinctive protected DACL and a junction
inheriting an ordinary one, the two differed.

This means a junction planted by a standard user is already caught by an owner
check. Keeping an explicit reparse-point check is still worthwhile so the
argument does not rest on this implementation detail.

**Deleting through an ancestor junction reaches the real target.**
`Directory.Delete(path, recursive: true)` refuses to recurse through a reparse
point only in the final path segment; Windows resolves an ancestor junction
before that check runs. Deleting `junction\child` removed the real target's
`child`.

Privileged recursive deletion of a path assembled from untrusted components is
the sharpest primitive in this area.

*Pinned:* "creates a directory junction without requiring elevation", "reports
the junction descriptor rather than the target descriptor", "deletes through an
ancestor junction into the real target".

---

## 7. Root-anchored validation is sufficient

Given sections 1 through 6, validating a single root is enough against an
unprivileged attacker only when the path to that root is also trusted. Let `T`
be the expected machine-principal set: normally `{Administrators, SYSTEM}`, with
`TrustedInstaller` added only for a known OS-provisioned root.

If root `R` satisfies:

1. every ancestor of `R` prevents unprivileged replacement or rename of the next component;
2. `R` is not a reparse point;
3. `R`'s owner is in `T`; and
4. no allow ACE on `R` - including inherit-only - grants modification rights to any principal outside `T`

then an unprivileged user `U`:

- cannot replace `R` through an ancestor, by (1);
- cannot create, delete, or rename anything directly in `R`, by (4);
- cannot therefore introduce a junction or a permissively ACLed child;
- cannot own `R` itself, by (3) and section 3;
- and by induction cannot do any of the above at any depth, because every
  descendant either inherits `R`'s admin-only ACEs or was created by privileged
  code with an explicit descriptor.

Once premise (1) is established, per-component validation *below* `R` excludes
no additional unprivileged attacker. Without that premise, an attacker who can
modify an ancestor can replace the validated root through an ancestor junction.
Default `%ProgramData%\<Product>` satisfies the premise; redirected and custom
roots require their own proof.

Cost: `O(1)` descriptor reads per process instead of `O(depth)` per operation.

**What it does not buy.** Nothing against an administrator, and nothing against a
process running as the same account when the root is per-user. For integrity
against a same-user process, verify a signature over the content in the process
that consumes it, rather than trusting placement.

---

## 8. CI runs elevated

GitHub's documentation states plainly: *"Windows virtual machines are configured
to run as administrators with User Account Control (UAC) disabled."*

The `Administrators` ownership measurement in section 3 inverts there. A
negative test of the form "an unprivileged caller cannot do X" is vacuous on
such a runner, because the caller is privileged. `SYSTEM` ownership does not
invert merely because the token is elevated; it still requires enabled
`SeRestorePrivilege`.

The bundled tests branch on elevation at run time rather than skipping, and
carry one guard test asserting the CI expectation so a runner-image change
surfaces as a failure. The pull-request workflow runs both filesystem fact suites
in its existing Windows job when either skill, its tests, or the workflow changes.

---

## Open questions

- Why the .NET create helper returns a protected DACL. The documented general
  rule predicts inheritance for an unprotected creator descriptor, and manually
  setting `SE_DACL_AUTO_INHERITED` did not change the measured result. The tests
  pin the BCL behavior without claiming it for direct native creation.
- Behavior when `%ProgramData%` is redirected to a non-default location, where
  the standard descriptor is not guaranteed.
- ReFS and network redirector behavior; all measurements here are local NTFS.
