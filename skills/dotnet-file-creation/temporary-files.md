# Temporary files

## Ordinary disposable scratch

For non-sensitive scratch used by an unelevated application, take the built-in
path. Normal OS-managed temp behavior is a reasonable assumption unless code or
deployment evidence contradicts it. Do not require an installer or a native
permission audit for disposable work:

```csharp
DirectoryInfo scratch = Directory.CreateTempSubdirectory("exampleapp_");
try
{
    string path = Path.Join(scratch.FullName, "work.txt");
    File.WriteAllText(path, "intermediate data");
    string result = File.ReadAllText(path);
}
finally
{
    try
    {
        scratch.Delete(recursive: true);
    }
    catch (Exception cleanupError) when (cleanupError is IOException or UnauthorizedAccessException)
    {
        System.Diagnostics.Trace.TraceWarning("Scratch cleanup failed: {0}", cleanupError.Message);
    }
}
```

Use the application's logger in place of `Trace` when available. A cleanup
failure is a warning for this disposable, non-sensitive case; it must not hide
an earlier operation failure. Close any streams before deleting the directory.
A crash can leave files behind, and deletion is not secure erasure. Those are
accepted limits, not reasons to replace this recipe with native code.

The directory contains only this operation's files, so the fixed inner name is
fine. Do not use that predictable name directly in the shared temp root.
Do not pass this disposable recipe off as protection for credentials, sensitive
personal data, privileged work, or a temp root known to be attacker-controlled.
Route those cases through the specific protection they need below.

## Hardened single-file scratch

When explicit hostile-account protection or a privileged operation requires it,
start with the already trusted application parent described in
[permissions.md](permissions.md). The complete
[assets/TrustedFileWrites.cs](assets/TrustedFileWrites.cs) recipe creates a random
leaf exclusively, requests restrictive permissions at creation, and keeps the
handle open:

```csharp
using FileStream stream = TrustedFileWrites.CreateScratch(trustedRoot);
stream.Write(payload);
stream.Position = 0;
```

Here `payload` is a byte array and `trustedRoot` is provisioned configuration,
not a path supplied by an untrusted request. Use the returned stream rather than
closing it and reopening its name. Normal disposal requests deletion; see the
cleanup limits below. For publishing, use sibling staging in the destination
directory instead of this delete-on-close stream.

## When to use `Directory.CreateTempSubdirectory`

For a group of temporary files, this API creates a new, uniquely named directory
under `Path.GetTempPath()`. It does not accept a custom parent. On Unix it
requests owner-only mode (`700`); on Windows it inherits the temp root's ACL.
The .NET documentation describes the Unix directory as owner-only, but effective
ACL policy and ancestor integrity still matter to a hardened protection claim.
For the ordinary non-sensitive recipe, these are normal environment assumptions,
not a mandatory preflight investigation.

A correctly configured, administrator-owned sticky `/tmp` prevents other
ordinary accounts from deleting or renaming entries you own. That is useful,
but not proof that an arbitrary `TMPDIR`, its ancestors, or inherited ACLs are
safe. Before relying on a temp subdirectory for sensitive data, establish those
conditions. If they are unknown, use the provisioned private root instead;
do not silently fall back to a shared root.

Inside a verified private temp directory, use the same creation-time file
restrictions as elsewhere. Unix files do **not** inherit `600` from a `700`
directory. Directory traversal protection does not cover preexisting handles,
hard links elsewhere, same-identity processes, or administrators.

## `Path.GetTempFileName()`

This API reserves a name by creating a zero-byte file, then returns its path:

- Current Unix runtime implementations request `600`; that does not validate
  the selected parent or its effective ACL policy.
- On Windows, .NET 7 and earlier failed after 65,535 generated names remained in
  the temp directory. .NET 8 removed that Windows-specific limit.
- It returns a **path, not a handle**, so reopening re-resolves the name. If an
  attacker can replace that entry or an ancestor, the next operation can reach
  another object. A properly configured sticky directory restricts replacement
  by other users, but not by the same identity or the directory's owner.
- It always creates in `Path.GetTempPath()`, so you cannot place it beside a
  destination for an atomic rename.

Use it only when that path-only lifetime fits a trusted context. A subsequent
`CreateNew` on its returned path will fail because the file already exists.
`GetRandomFileName` does the opposite: it creates nothing. Pair a generated name
with exclusive creation and retain the resulting handle, as the bundled recipe
does.

## Never build a predictable temp path

Do not open a fixed name such as `myapp-cache.json` in an untrusted shared root
with `Create` or `OpenOrCreate`. Another account can pre-create the entry, even
when the directory has the sticky bit. Randomness reduces collisions and name
prediction; **exclusive creation**, not randomness, reserves the new entry.
Neither makes hostile ancestors safe.

## Cleaning up

| Mechanism | Limit |
| --- | --- |
| `DeleteOnClose` on Windows | Kernel handle-close semantics normally survive process termination, but this is not a power-loss or secure-erasure guarantee. |
| `DeleteOnClose` on Unix | .NET implements unlink during managed handle release. Abrupt termination can bypass that code; unlink errors can be ignored by the runtime. |
| `finally` cleanup | Runs during normal unwinding, not all process termination, OS crashes, or power loss. |
| Deleting a name | Does not revoke other handles, remove other hard links, erase backups, or securely erase storage. |

If verified absence is required, verify and report cleanup under the trusted parent.
Keep an operation failure and any cleanup failure distinguishable. For a
temporary directory, close all handles before attempting recursive deletion and
retain the chosen protection assumptions throughout. Best-effort cleanup with a
warning is acceptable for the ordinary recipe; silent success is not an adequate
response when the user specifically required removal.

Do not sweep the whole temp root or authorize deletion by a prefix and age
alone. Only reclaim objects whose ownership, location, and inactive lifetime
are established by the application's cleanup protocol. A one-time reparse-point
check does not make recursive deletion safe in an attacker-mutable tree. Leave
and report uncertain leftovers instead of deleting them speculatively.

## Temp locations differ more than you expect

| Platform | `Path.GetTempPath()` selection |
| --- | --- |
| Windows, non-SYSTEM | `TMP`, then `TEMP`, then `USERPROFILE`, then the Windows directory |
| Windows, SYSTEM with `GetTempPath2` | `SystemTemp` override or the protected system temp default |
| Linux | `TMPDIR` when set, otherwise `/tmp/` |
| macOS | `TMPDIR`, normally set to a per-user location at login; otherwise `/tmp/` |

These APIs select a path; they do not prove existence, writability, or trust.
The conventional `/tmp` mode is `1777`, not a guarantee for an arbitrary mount.
The sticky bit restricts entry deletion/replacement, not reading world-readable
files or squatting on a name before creation.

## Windows services

Current .NET uses `GetTempPath2` when the OS exposes it, otherwise `GetTempPath`.
Availability includes some older Windows versions with servicing updates; do
not infer it from a marketing version alone. `GetTempPath2` normally gives
`SYSTEM` the protected system temp directory, but `SystemTemp` can override it.
The API does not secure the override and preserves symbolic links in the path.

Other service identities use the non-SYSTEM search order and can resolve to a
shared location. Provision a dedicated private root when the service's trust
requirements exceed what that environment establishes.

Test `Path.GetTempPath()` under the service's real identity. Do not infer that it
is private or even writable from behavior in an interactive session.

## Redirected or missing temp

Reject empty or non-fully-qualified configured roots, and handle missing,
read-only, full, or quota-limited storage as failures. Do not create a new trust
boundary by repairing an arbitrary environment-selected path. Network,
container, and permission-emulating filesystems require their own access and
cleanup checks.
