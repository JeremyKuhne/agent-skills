# Testing ACL behavior, and the CI elevation trap

## Windows CI runs elevated

GitHub-hosted Windows runners are configured to run as administrators with User
Account Control disabled. Azure Pipelines Microsoft-hosted Windows agents behave
the same way.

That single fact inverts a whole class of assertions:

| Assertion | Developer workstation | Windows CI |
| --- | --- | --- |
| `SetOwner(Administrators)` then commit | Throws | Succeeds |
| Owner of a newly created directory | The calling user | `BUILTIN\Administrators` |
| Writing to `%ProgramData%\Something` created by another account | Denied | Allowed |
| A "standard user cannot do X" negative test | Passes | **Silently passes for the wrong reason, or fails** |

A test that encodes "an unprivileged caller cannot forge this" is not testing
anything on CI, because the caller is privileged.

## Branch at run time; do not skip

The instinct is `-Skip:(-not $isElevated)`. Resist it. A skipped elevated-only
test never runs on a workstation, and a skipped unelevated-only test never runs
in CI, so half your assertions are dead in every environment.

Branch inside the test so both environments assert something:

```powershell
It 'assigns a new owner only when the caller is elevated' {
    $security = Get-DirectorySecurity -Path $path -Sections Owner
    { $security.SetOwner($administrators) } | Should -Not -Throw   # in-memory, always succeeds

    if (Test-CallerIsElevated) {
        { Set-DirectorySecurity -Path $path -Security $security } | Should -Not -Throw
        Get-OwnerSid -Path $path | Should -Be $administrators
    }
    else {
        { Set-DirectorySecurity -Path $path -Security $security } | Should -Throw
        Get-OwnerSid -Path $path | Should -Be $originalOwner
    }
}
```

Add one guard test that pins the environment itself, so a runner-image change is
visible rather than silent:

```powershell
It 'runs elevated on Windows CI' -Skip:(-not ($env:CI -or $env:TF_BUILD)) {
    Test-CallerIsElevated | Should -BeTrue -Because 'Windows CI images run elevated'
}
```

`CI` covers GitHub Actions; `TF_BUILD` covers Azure Pipelines.

If you genuinely need to exercise unelevated behavior in CI, you must launch a
medium-integrity process; there is no in-process way to drop the token. That is
usually more machinery than the coverage is worth. Branching plus the guard test
is the pragmatic answer.

## Detecting elevation

```powershell
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
[System.Security.Principal.WindowsPrincipal]::new($identity).IsInRole(
    [System.Security.Principal.WindowsBuiltInRole]::Administrator)
```

On a filtered administrator token this returns `false`, which is what you want:
the question is "can this token act as an administrator right now", not "is this
account a member of the group".

## Practical pitfalls

**`Set-Acl` needs `SeSecurityPrivilege`.** It writes the SACL, so it fails for an
unelevated caller with *"The process does not possess the 'SeSecurityPrivilege'
privilege"*. Use the extension methods and name the sections:

```powershell
$info = [System.IO.DirectoryInfo]::new($path)
$security = [System.IO.FileSystemAclExtensions]::GetAccessControl($info, 'Access')
[System.IO.FileSystemAclExtensions]::SetAccessControl($info, $security)
```

**Clean up before the harness does.** A test that writes a descriptor excluding
the caller leaves a directory the harness cannot delete, and the whole run fails
in teardown rather than in the test. Restore caller access in a `finally`, and do
not recurse into reparse points while doing it.

**Junctions need no elevation.** `New-Item -ItemType Junction` works for a
standard user, so reparse-point tests run anywhere. *Symbolic* links are
different: they need `SeCreateSymbolicLinkPrivilege` or Developer Mode. Prefer
junctions in tests unless you are specifically testing symlink behavior.

**In-memory versus committed.** `SetOwner`, `AddAccessRule`, and
`SetAccessRuleProtection` mutate a detached object. Assert on the object read
back from disk, not on the one you just modified.

**Descriptor-bearing create is still create-or-open.**
`FileSystemAclExtensions.CreateDirectory` returns an existing directory without
applying its `DirectorySecurity`. `RegistryKey.CreateSubKey` likewise opens an
existing local key before it uses the supplied `RegistrySecurity`. A normal
return does not prove creation or descriptor application.

**A NULL DACL is not an empty DACL.** An absent or NULL DACL grants access to
everyone; an empty DACL grants no access. Inspect the raw descriptor when that
distinction is part of a validator's contract.

**ACE order is observable behavior.** Do not prove ordering by inspecting only
the descriptor built in memory. Write it, read it back, assert
`AreAccessRulesCanonical` and raw ACE order, then perform the access that should
succeed or fail. The bundled test uses a protected file DACL so inherited ACEs
cannot obscure the result.

**Elevation is not `SeRestorePrivilege`.** An elevated administrator can assign
`Administrators` as owner because that SID is owner-enabled in the token.
Assigning unrelated `SYSTEM` ownership additionally requires
`SeRestorePrivilege` to be enabled; the .NET commit path does not enable it for
the caller.

**Well-known SIDs from PowerShell.** Use the enum overload; a string does not
bind and PowerShell will try the `byte[]` constructor:

```powershell
[System.Security.Principal.SecurityIdentifier]::new(
    [System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
```

**Separate descriptor policy, descriptor evaluation, and operations.** Build a
synthetic `DirectorySecurity` in memory when testing a validator's own
fail-closed policy. When the claim is about one operation, perform it or open
the object with exact `FileSystemRights` or `RegistryRights`; reserve
`AuthzAccessCheck` for the mask a client context receives from supplied
descriptors. Never present that snapshot, ACE enumeration, or
`WindowsPrincipal.IsInRole` as proof that a later object operation will succeed.
See [effective-access.md](effective-access.md).

## What to pin

Pin the claims your guidance depends on, so a Windows change breaks the test
rather than the product:

- Parent inheritable ACEs are suppressed when a descriptor is supplied at
  creation, and the object comes back protected.
- Descriptor-bearing directory and registry creation leaves an existing
  object's descriptor unchanged.
- A directory created with a trusted owner succeeds only when that owner is
  assignable by the caller's token.
- A NULL DACL remains distinguishable from an empty DACL after a managed binary
  descriptor round trip.
- A matching broad allow before a user deny can complete the access check, while
  canonical deny-before-allow order rejects the same read.
- `AuthzAccessCheck(MAXIMUM_ALLOWED)` returns the expected read-without-write
  descriptor mask for the current token, and a SID-based context resolves the
  current user's group grant on the measured host.
- Enabled `BUILTIN\Users` membership does not imply access when a separate ACE
  denies the current user, an exact managed `ReadData` file open can succeed
  while an exact `WriteData` open is denied, and registry handles honor exact
  `QueryValues` versus `SetValue` requests.
- A later inheritable ACE on the parent does not propagate into a protected
  child.
- An inherit-only ACE appears on the container as inherit-only and on a child as
  effective.
- `FILE_DELETE_CHILD` on a parent defeats a child's `Deny Delete`.
- Deleting through an ancestor junction reaches the real target.
- `Administrators` ownership assignment follows elevation, while assigning
  `SYSTEM` requires a matching token or enabled `SeRestorePrivilege`.

The bundled test file in this skill's repository implements exactly these.

These are **fact-regression tests**: they detect when platform behavior no longer
matches the prose. They are not skill evaluations and do not test trigger
routing or whether an agent applies the guidance correctly; those require model
eval scenarios separately.
