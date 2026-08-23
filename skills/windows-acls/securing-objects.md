# Creating secured objects

The rule is short: **supply the descriptor at creation, and never repair an
object that already exists.** Everything below is the reasoning and the traps.

## Create with the descriptor, not after

```csharp
static void CreateProtectedDirectory(string path)
{
    var administrators = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null);
    var localSystem = new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null);
    var inheritance = InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit;

    var security = new DirectorySecurity();
    security.SetOwner(administrators);
    security.AddAccessRule(new FileSystemAccessRule(
        administrators, FileSystemRights.FullControl, inheritance, PropagationFlags.None, AccessControlType.Allow));
    security.AddAccessRule(new FileSystemAccessRule(
        localSystem, FileSystemRights.FullControl, inheritance, PropagationFlags.None, AccessControlType.Allow));

    security.CreateDirectory(path);
}
```

`DirectorySecurity.CreateDirectory` is an extension method on
`System.IO.FileSystemAclExtensions`. From PowerShell it must be called
statically, because PowerShell does not bind extension methods as instance
methods:

```powershell
[System.IO.FileSystemAclExtensions]::CreateDirectory($security, $path)
```

The create-then-`SetAccessControl` alternative is a race: between the create and
the ACL write, the object exists with an inherited descriptor.

## Three behaviors of create-with-descriptor

All three are pinned by the bundled tests.

**Parent inheritable ACEs are suppressed.** The created object carries only the
ACEs you supplied. It does not merge in the parent's inheritable ACEs, so a
`ProgramData`-shaped `BUILTIN\Users` write grant does not silently appear.

**`SE_DACL_PROTECTED` is set.** `AreAccessRulesProtected` is `true` on the result
even though nothing called `SetAccessRuleProtection`. This is the property that
makes the object immune to a later inheritable ACE added to the parent: Windows
propagates inheritable ACEs down through `SetNamedSecurityInfo` and
`SetSecurityInfo`, but skips protected objects.

This is usually what you want for a trust root, and it is worth stating in a
comment, because a reader will otherwise assume the object still inherits.

**Intermediate directories get the same descriptor.** Creating `a\b\c` in one
call produces `a`, `b`, and `c` all carrying the supplied descriptor, not just
the leaf. That is good - it means the whole chain you create is protected - but
it also means a partially created chain is left behind if creation fails midway.
An unelevated caller supplying a descriptor that excludes itself will get
`UnauthorizedAccessException` partway down and cannot then clean up.

## Owner: what you can and cannot set

An object's owner may only be a SID present in the creating token with
`SE_GROUP_OWNER`. That means:

- An **unelevated** caller cannot make `BUILTIN\Administrators` or `SYSTEM` the
  owner. A filtered administrator token carries `Administrators` as *deny-only*,
  which does not qualify either.
- An **elevated** caller can, and by default already gets `Administrators` as the
  owner of objects it creates, governed by the "System objects: Default owner for
  objects created by members of the Administrators group" policy.

The failure is **not** where most people put it. `SetOwner` succeeds in memory;
the rejection happens on commit:

```text
SetOwner (in memory)     : SUCCEEDED
SetAccessControl (commit): THREW InvalidOperationException:
                           The security identifier is not allowed to be the owner of this object.
```

Code that wraps only `SetOwner` in a `try` will conclude the assignment worked.
Wrap the commit.

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

`RegistrySecurity` follows the same model, and `RegistryKey.CreateSubKey` accepts
one so the key is created with its final descriptor. Choose the view explicitly
with `RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64)`
rather than accepting WOW64 redirection.

For a machine-wide key, the inherited `HKLM\SOFTWARE` descriptor is usually
already correct: administrators and `SYSTEM` write, everyone reads. Verify rather
than assume, but do not add ACEs reflexively.
