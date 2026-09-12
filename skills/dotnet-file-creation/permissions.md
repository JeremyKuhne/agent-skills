# Permissions across platforms

## Ordinary protection versus a hardened guarantee

Ordinary, unelevated applications can rely on normal account protections in
OS-managed per-user storage, request restrictive Unix creation modes, and inherit
the normal Windows profile ACL. This is a reasonable default for replaceable
preferences, not proof against hostile local accounts or tampered deployment
configuration. The [entry point](SKILL.md) identifies when to escalate.

Windows per-user AppData is normally writable by its owning user **without
elevation**. That is necessary for ordinary apps to save settings. It is not
normally writable by every account, and it is not a protected source of
administrator policy. Privileged code must not trust its contents merely because
it is a special directory. Mode bits and ACLs cannot protect against a fully
privileged administrator/root or hostile code with the same effective authority.

Do not require the checks below for every ordinary save. Apply them when defending
against other unprivileged accounts, protecting sensitive data under an explicit
access-denial requirement, or using a directory that those accounts can alter.
Prefer moving to private storage or trusted provisioning over writing a new
native validator.

## Hardened prerequisite: a trusted parent

The hardened recipes defend against other unprivileged accounts. They require a
parent provisioned for the intended application identity, with trusted contents
and a path that those accounts cannot redirect. Hostile code with the same
effective authority, fully privileged administrators/root, and a compromised
storage server are outside this boundary. Still trace lower-privilege input into
elevated code; the same username does not make user-editable data privileged
policy.

Establish all of the following before claiming hardened path-based protection:

- The parent and relevant ancestors have trusted owners. Untrusted accounts
  cannot replace the parent, redirect an ancestor, or change their access policy.
- Untrusted accounts cannot create, modify, or replace entries inside the parent.
  Do not adopt preexisting content from an earlier untrusted directory.
- Confidential files have effective access restricted to the intended identity
  and explicitly trusted administrators. On Windows, verify file-inheritable
  ACEs as well as the directory DACL; denying directory listing or traversal
  alone is insufficient, because traversal checks can be bypassed by privilege.
- The filesystem enforces the relevant permission model. Inspect Unix ACLs where
  present, including macOS extended ACLs; `GetUnixFileMode` does not report all
  effective access. Treat network and permission-emulating mounts separately.

Trusted provisioning can establish these prerequisites. Otherwise use a
platform-specific, root-anchored ownership and effective-access check that does
not itself traverse attacker-replaceable ancestors. On Windows include
`DELETE`, parent `FILE_DELETE_CHILD`, and rights to change the DACL or owner.
On Unix include ancestor replacement rights, ownership, modes, and ACLs.
**Stop when this evidence is unavailable.** A successful `GetFolderPath`,
`CreateDirectory`, `GetUnixFileMode`, or `ResolveLinkTarget` is not a trust check.

## What the runtime actually exposes

There is no cross-platform permission API. The runtime gives you two
platform-specific ones and expects you to branch.

| API | Platform | Attribute |
| --- | --- | --- |
| `FileStreamOptions.UnixCreateMode` (setter) | Unix | `[UnsupportedOSPlatform("windows")]` |
| `File.GetUnixFileMode` / `SetUnixFileMode` | Unix | `[UnsupportedOSPlatform("windows")]` |
| `Directory.CreateDirectory(path, UnixFileMode)` | Unix | `[UnsupportedOSPlatform("windows")]` |
| `FileSystemAclExtensions`, `DirectorySecurity`, `FileSecurity` | Windows | `[SupportedOSPlatform("windows")]` |

All four Unix members throw `PlatformNotSupportedException` on Windows with
*"Unix file modes are not supported on this platform."* CA1416 flags an
unguarded call at build time, so keep that analyzer on.

Note where the attribute sits on `UnixCreateMode`: on the **setter**, not the
property. Reflecting over the `PropertyInfo` shows nothing, and reading the
property is always safe. Only the assignment is platform-gated.

## Create a new file without a permission-repair window

```csharp
FileStreamOptions options = new()
{
    Mode = FileMode.CreateNew,
    Access = FileAccess.Write,
    Share = FileShare.None,
};

if (!OperatingSystem.IsWindows())
{
    options.UnixCreateMode = UnixFileMode.UserRead | UnixFileMode.UserWrite;
}

using FileStream stream = File.Open(path, options);
```

`path` must be a fully qualified, application-controlled destination, not an
unchecked user-supplied path. The creation mechanism works for ordinary storage
too; the stronger trusted-parent prerequisite applies when claiming hardened
protection. `CreateNew` refuses an existing entry instead of truncating or
adopting it. It does not secure ancestors or publish a complete payload atomically
to readers.

CA1416 recognizes both `OperatingSystem.IsWindows()` and
`RuntimeInformation.IsOSPlatform(OSPlatform.Windows)`. Guard the
`UnixCreateMode` assignment: the setter, not the getter, is platform-specific.

On Windows an ordinary app can rely on normal per-user ACL inheritance under
its stated environment assumptions. A hardened claim requires a verified
inheritable ACL or an explicit descriptor at creation. If that stronger policy
is needed and unavailable, prefer a provisioned directory before custom Windows
ACL code. A user-profile path is not sufficient evidence of hardened protection.

## Set the mode at creation

`File.WriteAllText` followed by `File.SetUnixFileMode` can expose the file between
the calls. With default Unix creation mode `666` and umask `022`, a new file is
`644`; whether another account can reach it depends on the parent and ACLs.

Setting the mode through `FileStreamOptions` closes it, because the mode is
passed to the underlying `open` call.

The same principle appears on Windows in the ACL skill: supply the security
descriptor at creation rather than creating and then repairing.

`UnixCreateMode` applies only when a new file is created. `OpenOrCreate` and
`Create` can open an existing object without tightening its permissions;
`Create` also truncates it. Do not use either to adopt an untrusted file.

## Requested mode bits are an upper bound

Measured under `umask 022`:

| Requested | Actual |
| --- | --- |
| `600` | `600` |
| `644` | `644` |
| `666` | `644` |

Without a default ACL, the mode is `requested & ~umask`. A mask can remove
**owner bits too**: requesting `600` with umask `0777` produces `000`, not
`600`. The invariant is no additional ordinary permission bits, not an exact
mode or guaranteed ability to reopen the file.

On Linux, a parent default ACL takes precedence over umask; inherited access is
then limited by the requested mode, including the ACL mask. Do not generalize
Linux POSIX ACL evaluation to macOS extended ACLs. A Unix mode query alone does
not prove effective access on every filesystem.

Verify required access on the target deployment. Fail closed if restrictions
cannot be enforced; do not fall back to an unrestricted create. Do not change
the process-wide umask around an individual operation in a multithreaded program.
Any deliberate permission widening belongs to a separately reviewed policy.

## Directories: the mode reaches the leaf only

`Directory.CreateDirectory(path, mode)` applies the mode to the directory it
creates at the end of the path. Intermediates it has to create along the way get
the process default instead.

```text
CreateDirectory("/home/user/app/a/b/c", owner-only mode), with umask 022:
c:   700
a,b: 755 if newly created as intermediates
```

This is the **opposite** of the .NET Windows ACL overload, which reuses a
supplied security descriptor for every level it creates. Create each level you
care about in its own call:

```csharp
string current = root;
foreach (string segment in segments)
{
    current = Path.Join(current, segment);
    Directory.CreateDirectory(current, OwnerOnlyDirectory);
}
```

Here `root` is the selected fully qualified application root, `segments` are
application-controlled, and `OwnerOnlyDirectory` is
`UserRead | UserWrite | UserExecute`. For a hardened claim, `root` must already
be trusted. This sequence does not validate existing entries or establish trust
through hostile ancestors.

`CreateDirectory` is idempotent, not exclusive creation. On an **existing**
directory it does not change the mode, establish ownership, or prove that the
entry is not a link. Tightening a tree is a deliberate migration after validating
its provenance and contents, not a way to make an attacker-created tree trusted.

## Handles

`File.OpenHandle` has no creation-mode parameter. A new Unix file uses the
default mode (`644` under umask `022`, absent a default ACL). Do not use
open-then-chmod as a confidentiality recipe.

Create through `File.Open(path, options)` as above, then borrow its handle:

```csharp
using FileStream stream = File.Open(path, options);
SafeFileHandle handle = stream.SafeFileHandle;
RandomAccess.Write(handle, payload, fileOffset: 0);
```

Keep the stream alive until handle operations complete; do not dispose the
borrowed handle independently or mix buffered stream I/O with positional handle
I/O without an explicit synchronization policy. A handle binds operations to the
opened object; it does not prove the object's provenance or secure later path
operations such as rename and delete.

## Directory permissions do most of the work

Under Unix mode-based access checks, an owner-only directory blocks other
ordinary accounts from traversing it. The files do **not inherit `600`** from
that directory. Their own modes, ACLs, hard links elsewhere, and already-open
handles still matter. Changing permissions does not revoke existing handles.

Use restrictive file creation modes as defense in depth, and retain the trusted
parent throughout the operation. On Windows, protect the files' DACLs; a directory
that merely hides names is not an equivalent to this Unix traversal rule.

## What the runtime does not expose

- **File ownership.** There is no BCL API for the owning UID or GID on Unix. If a
  trust decision depends on ownership you need a native call or `stat`.
- **ACLs on Unix.** POSIX ACLs and extended attributes are not surfaced.
- **Unix modes on Windows.** There is no translation layer; the concepts do not
  map, and the runtime does not pretend otherwise.

No helper that merely branches between modes and ACLs can establish all of these
trust prerequisites. For an explicit hostile-account access-denial requirement,
validate using a second ordinary account on the target system; a same-identity
test or successful mode query cannot prove denial to another account. Retain
explicit limits for untested ACLs and filesystems without imposing these tests
as the minimum for non-sensitive, ordinary application I/O.
