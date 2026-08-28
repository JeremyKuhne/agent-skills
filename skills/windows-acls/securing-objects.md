# Creating secured objects

The rule is short: **supply the descriptor at creation, and never repair an
object that already exists.** Everything below is the reasoning and the traps.

## Create with the descriptor, not after

```csharp
static DirectoryInfo CreateOrOpenDirectoryWithDescriptor(string path)
{
    SecurityIdentifier administrators = new(WellKnownSidType.BuiltinAdministratorsSid, null);
    SecurityIdentifier localSystem = new(WellKnownSidType.LocalSystemSid, null);
    InheritanceFlags inheritance = InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit;

    DirectorySecurity security = new();
    security.SetOwner(administrators);
    security.AddAccessRule(new FileSystemAccessRule(
        administrators, FileSystemRights.FullControl, inheritance, PropagationFlags.None, AccessControlType.Allow));
    security.AddAccessRule(new FileSystemAccessRule(
        localSystem, FileSystemRights.FullControl, inheritance, PropagationFlags.None, AccessControlType.Allow));

    return security.CreateDirectory(path);
}
```

`DirectorySecurity.CreateDirectory` is an extension method on
`System.IO.FileSystemAclExtensions`. From PowerShell it must be called
statically, because PowerShell does not bind extension methods as instance
methods:

```powershell
[System.IO.FileSystemAclExtensions]::CreateDirectory($security, $path)
```

`FileSystemAclExtensions.CreateDirectory` does not prove that it created the
directory. If the path already exists, it returns the existing directory and
does not apply the supplied `DirectorySecurity`. A prior existence check is
racy. For a trust root, use a native create-new helper that treats
`ERROR_ALREADY_EXISTS` as failure, or validate and reject the returned object
before consuming anything below it.

For a file, `FileSystemAclExtensions.Create` with `FileMode.CreateNew` rejects
an existing path and returns the handle for the object it created. Keep and use
that stream rather than reopening the name.

The create-then-`SetAccessControl` alternative is a race: between the create and
the ACL write, the object exists with an inherited descriptor.

## Three measured behaviors of the .NET create helper

These behaviors were measured for `FileSystemAclExtensions.CreateDirectory` with
a `DirectorySecurity` on Windows 11 and are pinned by the bundled tests. Do not
generalize them to arbitrary native `CreateDirectoryW` calls.

**Parent inheritable ACEs are suppressed.** The created object carries only the
ACEs you supplied. It does not merge in the parent's inheritable ACEs, so a
`ProgramData`-shaped `BUILTIN\Users` write grant does not silently appear.

**The result is protected.** `AreAccessRulesProtected` is `true` even though
nothing called `SetAccessRuleProtection`. This is the property that makes the
object immune to a later inheritable ACE added to the parent: Windows propagates
inheritable ACEs down through `SetNamedSecurityInfo` and `SetSecurityInfo`, but
skips protected objects.

The general Windows inheritance documentation describes merging parent ACEs
unless `SE_DACL_PROTECTED` is supplied. The observed .NET create path is narrower
and differs from that general rule, so keep the regression test rather than
treating this as a guarantee for every creation API.

This is usually what you want for a trust root, and it is worth stating in a
comment, because a reader will otherwise assume the object still inherits.

**The helper reuses the descriptor for intermediate directories.** Creating
`a\b\c` in one call produces `a`, `b`, and `c` all carrying the supplied
descriptor, not just the leaf. That is good - it means the whole chain you
create is protected - but it also means a partially created chain is left behind
if creation fails midway. An unelevated caller supplying a descriptor that
excludes itself will get `UnauthorizedAccessException` partway down and cannot
then clean up.

## Owner: what you can and cannot set

Normally, an object's owner may only be a SID present in the token with
`SE_GROUP_OWNER`. An enabled `SeRestorePrivilege` permits assigning another
valid owner SID. That means:

- An **unelevated** caller cannot make `BUILTIN\Administrators` or `SYSTEM` the
  owner. A filtered administrator token carries `Administrators` as *deny-only*,
  which does not qualify either.
- An **elevated** administrator can assign `Administrators`, and by default may
  already get it as the owner of new objects, governed by the "System objects:
  Default owner for objects created by members of the Administrators group"
  policy.
- Elevation alone does **not** make `SYSTEM` assignable. The caller must run as
  `SYSTEM` or hold and enable `SeRestorePrivilege`; the .NET access-control
  commit path does not enable that privilege for an ordinary elevated token.

The failure is **not** where most people put it. `SetOwner` succeeds in memory;
the rejection happens on commit:

```text
SetOwner (in memory)     : SUCCEEDED
SetAccessControl (commit): THREW InvalidOperationException:
                           The security identifier is not allowed to be the owner of this object.
```

Code that wraps only `SetOwner` in a `try` will conclude the assignment worked.
Wrap the commit. When the descriptor is committed by
`FileSystemAclExtensions.CreateDirectory`, an unassignable owner instead surfaces
from that create call as `IOException` ("This security ID may not be assigned as
the owner of this object").

## ACE order changes effective access

Windows does not use a "most specific trustee wins" rule. [How AccessCheck
Works](https://learn.microsoft.com/windows/win32/secauthz/how-dacls-control-access-to-an-object)
says that Windows compares each ACE's trustee with the enabled user and group
SIDs in the caller's token, examines matching ACEs in sequence, and stops when:

- a deny ACE denies a requested right;
- allow ACEs have granted every requested right; or
- the DACL ends with at least one requested right still ungranted.

The last case is an implicit denial. The second case means a broad allow can
complete the check before a later user-specific deny is reached.

Microsoft's [preferred DACL
order](https://learn.microsoft.com/windows/win32/secauthz/order-of-aces-in-a-dacl)
is more precise than "all denies before all allows":

1. Explicit ACEs come before inherited ACEs.
2. Within the explicit group, deny ACEs come before allow ACEs.
3. Inherited ACEs stay ordered by inheritance depth, nearest ancestor first; within each level, deny ACEs come before allow ACEs.

The bundled Windows test writes both orders to one file and reads each descriptor
back from disk. `Allow Everyone:Read` followed by `Deny current-user:Read` is
noncanonical and permits the read. Reversing the two ACEs is canonical and the
same read throws `UnauthorizedAccessException`. The measured .NET and NTFS path
did not repair the noncanonical order during persistence.

Build deny-bearing DACLs in canonical order and verify
`AreAccessRulesCanonical` after reading them back. Do not generalize this into
"user ACEs before group ACEs"; trustee specificity does not control the access
check. For trust validation, do not try to use deny exceptions to rescue a broad
untrusted allow. Reject the allow as described in
[validating-trust.md](validating-trust.md#do-not-subtract-denies-from-allows).

## Rights that mean "can modify"

When you decide whether a principal can tamper with an object, this is the set
that matters. Omitting any of them leaves a hole:

| Right | Why it counts |
| --- | --- |
| `WriteData` / `CreateFiles` | Write file content, or add a file to a directory |
| `AppendData` / `CreateDirectories` | Append, or add a subdirectory |
| `WriteExtendedAttributes`, `WriteAttributes` | Metadata tampering |
| `Delete` | Remove the object |
| `DeleteSubdirectoriesAndFiles` | **Remove a child regardless of the child's own DACL** |
| `ChangePermissions` (`WRITE_DAC`) | Rewrite the DACL, then do anything |
| `TakeOwnership` (`WRITE_OWNER`) | Become owner, then rewrite the DACL |

`DeleteSubdirectoriesAndFiles` is the one reviewers miss. `FILE_DELETE_CHILD` on
a directory is an alternative to `DELETE` on the child, so a principal holding it
can remove and replace a file whose own descriptor denies deletion. This is why
file-level checks are not sufficient; see [validating-trust.md](validating-trust.md).

## Files inherit; do not fight it

`SecureFile`-style helpers that stamp an owner onto individual files add little
once the containing directory is correct. A file created inside a properly
secured directory inherits the right ACEs. Spend the effort on the directory.

If you do write file descriptors, note that `Set-Acl` in PowerShell writes the
SACL and therefore requires `SeSecurityPrivilege`, which an unelevated caller
does not hold. Use the access-control extension methods and name the sections
explicitly:

```powershell
$info = [System.IO.FileInfo]::new($path)
$security = [System.IO.FileSystemAclExtensions]::GetAccessControl($info, 'Access')
# ... modify ...
[System.IO.FileSystemAclExtensions]::SetAccessControl($info, $security)
```

## Registry equivalents

`RegistrySecurity` follows the same descriptor model. When a key is new,
`RegistryKey.CreateSubKey` accepts one so the key is created with its final
descriptor. Choose the view explicitly with
`RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64)`
rather than accepting WOW64 redirection.

`CreateSubKey` is also create-or-open. For a local key that already exists, .NET
opens and returns it without applying the supplied `RegistrySecurity`. A
create-new wrapper must inspect the `RegCreateKeyEx` disposition and reject
`REG_OPENED_EXISTING_KEY`; otherwise validate and reject the returned key before
trusting its values.

For a machine-wide key, the inherited `HKLM\SOFTWARE` descriptor is usually
already correct: administrators and `SYSTEM` write, everyone reads. Verify rather
than assume, but do not add ACEs reflexively.
