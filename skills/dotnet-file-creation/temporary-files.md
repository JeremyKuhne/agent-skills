# Temporary files

## Use a temp subdirectory, not a temp file

`Directory.CreateTempSubdirectory()` is the only built-in API that gives you a
private scratch location on every platform:

```csharp
DirectoryInfo scratch = Directory.CreateTempSubdirectory("myapp_");
try
{
    string payload = Path.Combine(scratch.FullName, "payload.bin");
    // ... work inside scratch ...
}
finally
{
    scratch.Delete(recursive: true);
}
```

- On Unix it is created with owner-only permissions (`700`), which is documented
  and measured. The parent `/tmp` is `777` with the sticky bit, so this is what
  separates your files from every other account on the machine.
- On Windows it lands under `%TEMP%`, which is already inside the user profile.

Files you then create inside it are protected by the directory, so you do not
need to set a mode on each one. That is the main reason to prefer a directory
over individual temp files.

## `Path.GetTempFileName()`

It is not dangerous, but it is limited:

- It creates a zero-byte file with mode `600` on Unix, so permissions are fine.
- The .NET Framework limit of 65535 files was removed in .NET 8 on every OS.
- It returns a **path, not a handle**, so anything you do next re-resolves the
  name. That is a check-then-use window in a directory other users can write to.
- It always creates in `Path.GetTempPath()`, so you cannot place it beside a
  destination for an atomic rename.

Use it for a quick single-file scratch in a trusted context. Prefer a temp
subdirectory when you need more than one file, an atomic publish, or when
untrusted local users share the machine.

## Never build a predictable temp path

```csharp
// Wrong: on Unix this is a world-writable directory and the name is guessable.
string path = Path.Combine(Path.GetTempPath(), "myapp-cache.json");
```

Another user can pre-create that name, or replace it with a symlink pointing
somewhere your process can write. Use a random subdirectory instead, and keep
the predictable name *inside* it.

## Cleaning up

`FileOptions.DeleteOnClose` works on both platforms and removes the file when
the handle closes, including on most abnormal terminations on Windows:

```csharp
using FileStream stream = new(
    path,
    FileMode.CreateNew,
    FileAccess.ReadWrite,
    FileShare.None,
    bufferSize: 4096,
    FileOptions.DeleteOnClose);
```

For a directory, delete it in a `finally`. Accept that a crash can leave one
behind: name it with a recognizable prefix so a later run can sweep old entries
by age, and never recurse into a reparse point while sweeping.

Do not attempt to clean the whole temp root. Other processes and other users
have files there.

## Temp locations differ more than you expect

| | Windows | Unix |
| --- | --- | --- |
| `Path.GetTempPath()` | `%TEMP%`, under the user profile | `$TMPDIR` or `/tmp` |
| Mode of that root | Per-user ACL | `777` plus the sticky bit |
| Shared with other users | No | Yes |

The sticky bit means another user cannot delete or rename *your* entries, but it
does not stop them creating names before you do or reading anything you leave
world-readable.

## Redirected or missing temp

`Path.GetTempPath()` honors `TMPDIR` on Unix and `TMP`/`TEMP` on Windows. In
containers and service accounts these are sometimes unset, pointing at a
read-only location, or shared between users. If your process must work in those
environments, fail with a clear message rather than assuming the path is
writable and private.
