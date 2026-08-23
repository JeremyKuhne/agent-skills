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
It 'runs elevated on Windows CI' -Skip:(-not $env:CI) {
    Test-CallerIsElevated | Should -BeTrue -Because 'Windows CI images run elevated'
}
```

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

**Well-known SIDs from PowerShell.** Use the enum overload; a string does not
bind and PowerShell will try the `byte[]` constructor:

```powershell
[System.Security.Principal.SecurityIdentifier]::new(
    [System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
```

**Test the descriptor, not effective access.** Building a synthetic
`DirectorySecurity` in memory and asserting your validator's verdict is fast,
deterministic, and needs no privileges. Reserve filesystem round-trips for the
handful of claims that are genuinely about Windows behavior.

## What to pin

Pin the claims your guidance depends on, so a Windows change breaks the test
rather than the product:

- Parent inheritable ACEs are suppressed when a descriptor is supplied at
  creation, and the object comes back protected.
- A later inheritable ACE on the parent does not propagate into a protected
  child.
- An inherit-only ACE appears on the container as inherit-only and on a child as
  effective.
- `FILE_DELETE_CHILD` on a parent defeats a child's `Deny Delete`.
- Deleting through an ancestor junction reaches the real target.
- Ownership assignment succeeds or fails according to elevation.

The bundled test file in this skill's repository implements exactly these.
