# Platform differences

This page combines documented contracts, .NET 10 source inspection, and limited
runtime measurements. The evidence and untested deployments are separated in
[references/research.md](references/research.md); not every row has been tested
on every platform or filesystem.

## Common behavior on supported filesystems

| Behavior | Result |
| --- | --- |
| `FileMode.CreateNew` over an existing file | Throws `IOException` |
| Successful `File.Move(source, destination, overwrite: true)` | Replaces the destination and removes the source; sharing or filesystem constraints can reject the request |
| `FileShare.None` blocking a second .NET open | Observed with default locking on the tested local filesystems, not universal |
| Special-folder APIs | Select locations; do not prove ownership, privacy, availability, or local storage |

Exclusive create is the one to lean on. `FileMode.CreateNew` maps to `O_EXCL` on
Unix and `CREATE_NEW` on Windows. This is the create-if-absent primitive where
the filesystem supports those semantics. Prefer it to `File.Exists` followed
by `File.Create`, which is a race. It reserves the leaf only; it does not protect
ancestors or atomically publish all future writes to the new file.

## Different

### Deleting an open file

| Windows | Unix |
| --- | --- |
| Sharing can block deletion unless existing handles allow `FileShare.Delete` | An open file can be unlinked when directory permissions and the filesystem allow it |

Windows can delete open files when sharing permits; final removal may wait for
handle closure depending on the deletion mechanism. On Unix, open descriptors
and other hard links keep the data alive after unlink. Neither case revokes
existing access or securely erases data.

Rename is **not** a workaround for a destination handle that denies delete
sharing on Windows. Readers participating in snapshot replacement should allow
`FileShare.Delete`, but that alone does not make every replacement primitive
work: the tested Windows `File.Move` refused replacement even with all sharing
flags. A refusal can surface as `UnauthorizedAccessException`, not only
`IOException`. Retry only identified transient failures with a bounded policy;
diagnose the actual operation and error rather than inferring an ACL problem
from the exception type alone.

### `FileShare`

| Windows | Unix |
| --- | --- |
| Sharing checks enforced by the kernel for normal file opens | Coarser, best-effort advisory locks, not Windows-equivalent sharing |

In the inspected .NET 10 Unix implementation, `FileShare.None` requests an
exclusive `flock`; other share combinations use shared locks where supported.
This does not enforce individual read/write/delete share flags. For example,
`FileShare.Read` must not be assumed to exclude a writer as it does on Windows.

The runtime can ignore unsupported-lock errors and skip locking on some
filesystem/access combinations. `DOTNET_SYSTEM_IO_DISABLEFILELOCKING=1` disables
it. A native process can ignore an advisory lock, and network filesystems can
translate locking differently. Successful open is not proof of mutual exclusion.
Use only a verified cooperative protocol, such as the bounded one in
[persisted-files.md](persisted-files.md), never a confidentiality boundary.

### Path casing

Case sensitivity is a property of the **filesystem**, not the operating system.
The common shorthand "Windows is case-insensitive, Unix is case-sensitive" is
wrong: a default macOS volume behaves like Windows here.

| Filesystem | Default |
| --- | --- |
| NTFS (Windows) | Case-insensitive, case-preserving |
| ext4, XFS (Linux) | Case-sensitive |
| APFS, HFS+ (macOS) | Case-**in**sensitive, case-preserving |

APFS and HFS+ can be formatted case-sensitive, ext4 supports casefolding, and
Windows can enable case sensitivity per directory. Do not extrapolate one
mount or directory's behavior to every path on the machine.

Consequences worth checking for:

- Two config entries differing only in case collide on Windows and on a default
  macOS volume, and coexist on Linux.
- A lookup keyed by path cannot pick its comparer from the OS. Use
  `StringComparer.Ordinal` for exact string keys, not as proof of file identity.
  Case, Unicode normalization, aliases, and hard links can defeat that inference.
  `StringComparer.OrdinalIgnoreCase` everywhere silently merges distinct files on
  a case-sensitive volume.
- Case-only rename behavior depends on the API and filesystem. Test the actual
  operation before adding a two-step rename, which introduces an intermediate
  state and additional failure cases.

If the behavior matters, probe it rather than branching on
`OperatingSystem.IsWindows()`: create a file, ask whether the uppercase name
resolves, and cache the answer per directory root.

### Hidden files

| Windows | Linux |
| --- | --- |
| `FileAttributes.Hidden` is real and settable | Derived from a leading dot in the name |

`File.SetAttributes(path, FileAttributes.Hidden)` on Linux **does not throw and
does not work**: reading the attributes back afterwards shows the file is not
hidden. A file named `.config` reports `Hidden` on Linux without anyone setting
it.

macOS has a native `UF_HIDDEN` flag and must not be inferred from Linux behavior;
the bundled suite has not measured it. To hide a file portably, name it with a
leading dot and set the attribute on Windows.

### Directory creation and permissions

| Windows | Unix |
| --- | --- |
| `FileSystemAclExtensions.CreateDirectory` supplies its descriptor for each newly created level | The Unix mode overload supplies the explicit mode for the new leaf only |

Neither overload establishes the provenance or protection of existing
directories. See [permissions.md](permissions.md).

## Paths

- Follow [paths.md](paths.md) for construction, qualification, deterministic
  resolution, and containment. In particular, build with `Path.Join`, use
  `Path.IsPathFullyQualified` rather than `Path.IsPathRooted` to detect ambient
  dependence, and resolve relative paths with the `Path.GetFullPath` overload
  that takes a known fully qualified base.
- `Path.DirectorySeparatorChar` differs, but Windows accepts forward slashes, so
  forward slashes in literals are usually portable. Backslashes are not.
- `Path.GetFullPath` performs lexical normalization, whose rules depend on the
  platform and path namespace. Ordinary Windows paths can collapse trailing
  dots and spaces; extended namespaces bypass some normalization. Never use
  normalization as a substitute for an accepted-name policy.
- Windows reserves `< > : " | ? *` and the device names `CON`, `NUL`, `LPT1`,
  and related variants. Windows 10-era systems, including Server 2022, can still
  reinterpret device names in fully qualified paths; reject them when those
  versions are supported.
- For fully qualified paths, modern .NET file APIs support paths beyond
  `MAX_PATH` without an application manifest by adding extended syntax
  internally. The manifest and long-path policy still matter to .NET Framework,
  direct Win32 calls, the process working directory, and paths passed to native
  components. Supplying `\\?\` yourself bypasses normalization and should not be
  done with untrusted input.

## Line endings and encoding

`File.WriteAllText` writes UTF-8 without a BOM on all platforms and does not
translate line endings. If a file is consumed by platform-native tooling, choose
the terminator explicitly rather than relying on `Environment.NewLine`, which
differs and will make your output non-deterministic across platforms.

## Symbolic links

`File.CreateSymbolicLink` and `Directory.CreateSymbolicLink` are cross-platform,
but the privilege is not: Windows requires `SeCreateSymbolicLinkPrivilege` or
Developer Mode, while Unix allows any user to create one. Directory *junctions*
on Windows need no privilege at all.

`File.ResolveLinkTarget(path, returnFinalTarget: true)` reports a supported link's
target at that instant. It neither checks every ancestor and reparse-point type
nor pins a later open to that object. Follow [paths.md](paths.md) for the
distinction between lexical containment, physical containment, and object trust.
