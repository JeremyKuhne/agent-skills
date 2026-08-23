---
name: windows-acls
description: Decide where Windows application state belongs and how to secure it with ACLs. Use when choosing a location for per-user or machine-wide state, creating a directory or registry key that elevated code will later trust, validating that a shared path has not been hijacked, reviewing code that calls DirectorySecurity/FileSecurity/SetAccessControl/SetOwner/SetAccessRuleProtection, diagnosing "access is denied" or descriptor mismatches that only reproduce off CI, or writing tests for ACL behavior. Also use when asked "where should this config/cache/state file go", "is ProgramData safe", "how do I ACL this folder", "can a standard user tamper with this", or when a security review flags a path an elevated process reads, writes, or deletes.
license: MIT
compatibility: Guidance and bundled tests target Windows. The behavioral tests require PowerShell 7 and Pester 5.7 or later on Windows; they skip elsewhere.
metadata:
  portability: portable
  applicability: dotnet
  binding: optional-overlay
  risk: local-write
  maturity: canary
  requires: none
  related: dotnet-file-creation, security-review, cswin32-interop
---

# Windows ACLs and state locations

If `overlay.md` exists beside this file, read it before acting; it contains
repository-specific bindings. This core remains usable without it.

Most Windows ACL bugs are not wrong rights. They are **state stored in the wrong
place**, or **trust placed in a directory nobody proved they own**.

## The three rules

1. **Per-user state needs no ACL work.** The user profile is already private.
   Writing custom ACLs there usually makes things worse, not safer.
2. **A shared location is not trustworthy because of where it is.** The default
   `%ProgramData%` descriptor lets any standard user create a top-level
   directory. If your code creates `%ProgramData%\YourApp` lazily at first run,
   whoever runs first owns it.
3. **The owner is the check that matters.** A DACL is forgeable by any caller;
   an expected machine owner such as `BUILTIN\Administrators` or `SYSTEM` is not.
   And because an owner keeps `WRITE_DAC` implicitly, a caller who owns an object
   can rewrite its DACL at any time - so a DACL-only check proves nothing.

## Decide the location first

| State | Location | ACL work |
| --- | --- | --- |
| Per-user, roams with the profile | `Environment.SpecialFolder.ApplicationData` | None |
| Per-user, machine-local (caches, logs) | `Environment.SpecialFolder.LocalApplicationData` | None |
| Per-user, disposable | `Path.GetTempPath()` | None |
| Machine-wide, small, must be trusted | **HKLM registry key created by the installer** | Installer sets it |
| Machine-wide, file-shaped, must be trusted | Directory provisioned **by the installer** with a locked descriptor | Installer sets it |
| Machine-wide, immutable payload | Under `Program Files` | None; write requires elevation |
| Machine-wide, recreatable cache | Prefer per-user; a shared cache is a trust boundary you must then defend | See below |

Full reasoning, including why "shared" is usually a mistake and when to use no
file at all, is in [choosing-a-location.md](choosing-a-location.md).

## If you must create a secured location at run time

Supply the DACL **at creation**. Never create then repair - a directory that
already exists may be someone else's.

```csharp
var security = new DirectorySecurity();
security.AddAccessRule(new FileSystemAccessRule(
    new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null),
    FileSystemRights.FullControl,
    InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit,
    PropagationFlags.None,
    AccessControlType.Allow));
// ... SYSTEM, plus read-only rules for Users if the tree must be readable.
security.CreateDirectory(path);
```

Passing a `DirectorySecurity` with an explicit DACL to
`FileSystemAclExtensions.CreateDirectory` does three things people do not
expect, all measured in the bundled tests:

- It **suppresses** the parent's inheritable ACEs.
- The created directory comes back with **`SE_DACL_PROTECTED`**, so a later edit
  to the parent does not propagate in.
- The .NET helper applies the descriptor to **intermediate** directories it
  creates, not just the leaf.

Details and the pitfalls in [securing-objects.md](securing-objects.md).

## If you must trust a shared location you did not just create

Anchor at one root and check it once, but only when every ancestor of that root
also prevents unprivileged replacement. Under that premise, once the root grants
no modification rights outside the trusted principals, an unprivileged user
cannot create anything below it, so descendants follow by induction.

Check, in this order:

1. Not a reparse point.
2. Owner is an expected machine principal, normally `BUILTIN\Administrators` or
   `SYSTEM`. Admit `TrustedInstaller` only for a known OS-provisioned root.
3. No allow ACE - **including inherit-only ACEs** - grants write, append, delete,
   delete-child, `WRITE_DAC`, or `WRITE_OWNER` to any other principal.

Reject; never repair. Repairing leaves the attacker's data in place under a
descriptor that now looks trustworthy. Validate by capability, not by exact ACE
equality, or enterprise ACL customization will break you.
[validating-trust.md](validating-trust.md) has the rationale and the trap list.

## Testing

**Windows CI images run elevated.** GitHub-hosted Windows runners are configured
to run as administrators with UAC disabled. An assertion like "a caller cannot
take Administrators ownership" passes on a developer workstation and **inverts**
in CI. Branch on elevation at run time rather than skipping, so both environments
assert something. See [testing-and-ci.md](testing-and-ci.md).

## Evidence

Every behavioral claim here is pinned by tests and recorded with measurements in
[references/research.md](references/research.md). Primary documentation is
indexed in [references/documentation.md](references/documentation.md).

## Related skills

When a finding is about untrusted input reaching a privileged sink rather than
about placement, hand off to a security review workflow. When the work needs
Win32 access-control APIs that the BCL does not surface, use the repository's
Win32 interop skill. For creating the files and directories themselves, and for
the cross-platform equivalents of these rules, use the .NET file creation skill.
A consuming repository wires the concrete cross-references in its overlay.
