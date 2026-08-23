# Platform differences

Behavior measured on Windows 11 with .NET 10 and Ubuntu 24.04 with .NET 8. Each
row is pinned by a bundled test.

## Same on both platforms

| Behavior | Result |
| --- | --- |
| `FileMode.CreateNew` over an existing file | Throws `IOException` |
| `File.Move(source, destination, overwrite: true)` | Replaces the destination, removes the source |
| `FileShare.None` blocking a second open | Blocked |
| Per-user special folders | Under `SpecialFolder.UserProfile` |
| Machine-wide special folder | Outside the user profile |

Exclusive create is the one to lean on. `FileMode.CreateNew` maps to `O_EXCL` on
Unix and `CREATE_NEW` on Windows, so it is a genuine atomic
"create-if-absent-or-fail" on both. Prefer it to `File.Exists` followed by
`File.Create`, which is a race on every platform.

## Different

### Deleting an open file

| Windows | Unix |
| --- | --- |
| Throws `IOException` while a handle is open without `FileShare.Delete` | Succeeds; the name is unlinked and the data lives until the last handle closes |

Code that deletes and immediately recreates a file works on Unix and
intermittently fails on Windows, usually under a scanner or an indexer holding a
transient handle. Retry with backoff on Windows, or write to a new name and
rename over the old one.

### `FileShare`

| Windows | Unix |
| --- | --- |
| Enforced by the kernel against every process | Emulated by .NET; enforced between .NET processes, invisible to anything else |

So a lock file works for coordinating instances of your own application on both
platforms, and is not a security boundary on Unix. A native tool, a shell script,
or a different runtime will open the file regardless.

### Path casing

| Windows | Unix |
| --- | --- |
| Case-insensitive; `CASETEST.TXT` finds `casetest.txt` | Case-sensitive; they are different files |

Consequences worth checking for:

- Two config entries differing only in case collide on Windows and coexist on
  Linux.
- A lookup keyed by path needs `StringComparer.OrdinalIgnoreCase` on Windows and
  `StringComparer.Ordinal` on Unix. `StringComparer.OrdinalIgnoreCase`
  everywhere silently merges distinct Linux files.
- Case-only renames need a two-step rename through a temporary name on Windows.

### Hidden files

| Windows | Unix |
| --- | --- |
| `FileAttributes.Hidden` is real and settable | Derived from a leading dot in the name |

`File.SetAttributes(path, FileAttributes.Hidden)` on Unix **does not throw and
does not work**: reading the attributes back afterwards shows the file is not
hidden. A file named `.config` reports `Hidden` on Unix without anyone setting
it.

To hide a file portably, name it with a leading dot and set the attribute on
Windows.

### Directory creation and permissions

| Windows | Unix |
| --- | --- |
| A supplied security descriptor applies to every level the call creates, and sets `SE_DACL_PROTECTED` | An explicit `UnixFileMode` applies to the leaf only |

This asymmetry catches people who verified their code on one platform. See
[permissions.md](permissions.md).

## Paths

- Build paths with `Path.Combine` or `Path.Join`, never string concatenation.
  `Path.Combine` discards earlier segments when a later one is rooted, which is a
  useful traversal guard and a surprise if you did not expect it; `Path.Join`
  simply concatenates with a separator.
- `Path.DirectorySeparatorChar` differs, but Windows accepts forward slashes, so
  forward slashes in literals are usually portable. Backslashes are not.
- `Path.GetFullPath` normalizes, and normalization differs. Windows strips
  trailing dots and spaces, so `name.` and `name` can be the same file there and
  different files on Unix.
- Windows reserves `< > : " | ? *` and historically the device names `CON`,
  `NUL`, `LPT1`. Modern Windows no longer reinterprets those in a fully qualified
  path, but they remain poor filename choices.
- Long paths beyond `MAX_PATH` need opt-in on Windows through the application
  manifest and the long-paths policy. `\\?\` prefixing bypasses normalization
  entirely, which also disables the safety of that normalization.

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

Use `File.ResolveLinkTarget(path, returnFinalTarget: true)` when you need to know
what a link points at, and treat any link in a path you did not construct as
untrusted.
