# Constructing and resolving paths

Path construction, qualification, canonicalization, and containment answer
different questions. Do not treat success at one stage as proof of another.

## Choose construction semantics deliberately

For a fixed application root, prefer `Path.Join` over manual concatenation or
`Path.Combine`. `Combine` is appropriate when a later trusted absolute path is
intended to replace the earlier base; that is a different contract.

If any argument after the first is rooted, `Path.Combine` discards every
preceding component. A caller-controlled later argument can therefore replace a
trusted root. `Path.Join` concatenates the components instead and preserves the
earlier root.

`Path.Join` is only construction. It does not normalize, validate, or establish
containment. A later component can still contain separators, `..`, volume
syntax, or a symbolic link reached during filesystem traversal.

## Test qualification, not rooting

Use `Path.IsPathFullyQualified` to ask whether a path is independent of the
current drive and current directory. `Path.IsPathRooted` asks only whether the
string contains root syntax. It is useful when a contract forbids any root, but
it does not establish that a path is stable.

Windows has rooted paths that are still relative:

| Path shape | Rooted | Fully qualified | Ambient dependency |
| --- | --- | --- | --- |
| `logs\app.txt` | No | No | Current drive and directory |
| `C:logs\app.txt` | Yes | No | Current directory for drive `C:` |
| `\logs\app.txt` | Yes | No | Current drive |
| `C:\logs\app.txt` | Yes | Yes | None |
| `\\server\share\app.txt` | Yes | Yes | None |

On Unix, a leading `/` is both rooted and fully qualified; a path without it is
neither. The distinction is therefore most visible on Windows.

Qualification is not canonicalization or validation. A fully qualified path
can still contain `.` or `..`, name a missing object, escape an intended root,
or traverse a symbolic link.

## Resolve relative paths against an explicit base

Do not call `Path.GetFullPath(path)` when `path` is not fully qualified. That
overload uses the process current directory, which any thread can change. On
Windows, drive-relative paths can also depend on per-drive current-directory
state inherited through hidden environment variables such as `=C:`.

Resolve against a known fully qualified base instead:

```csharp
if (!Path.IsPathFullyQualified(basePath))
{
    throw new ArgumentException("The base path must be fully qualified.", nameof(basePath));
}

string fullPath = Path.GetFullPath(path, basePath);
```

The two-argument overload rejects a base that is not fully qualified and makes
resolution independent of later current-directory changes. Do not derive
`basePath` from another relative value with the one-argument overload.

An explicit base makes resolution deterministic; it does not force the result
under that base. Given `N:\trusted\root` on Windows:

| Input | Result |
| --- | --- |
| `child.txt` | `N:\trusted\root\child.txt` |
| `N:child.txt` | `N:\trusted\root\child.txt` |
| `\child.txt` | `N:\child.txt` |
| `C:child.txt` | `C:\child.txt` when `C:` is a different drive |
| `C:\child.txt` | `C:\child.txt`; a fully qualified input ignores the base |

## Prefer keys over caller-supplied paths

For a fixed application file such as `settings.json`, use that literal leaf;
no custom key scheme is necessary. When the feature accepts external identifiers
instead of a full destination, a logical key can keep the filename policy small.
[assets/TrustedFileWrites.cs](assets/TrustedFileWrites.cs) accepts 1-64 lowercase
ASCII letters, digits, hyphens, or underscores, then produces `item-<key>.bin`.
The fixed prefix avoids Windows device names even for a key such as `con`.
The alphabet excludes separators, `..`, alternate data streams, trailing dots
and spaces, device namespaces, and case-only key collisions.

This is an intentional application key contract, not a general filename parser.
Do not silently strip invalid characters into a colliding name. Reject invalid
input, and keep the trusted root in application configuration rather than in the
request. The helper requires a fully qualified root but **does not certify it**.
The application must separately authorize access to each key; accepted syntax
is not authorization to read or overwrite the corresponding object.

## Lexical containment is a separate, weaker check

When a feature genuinely accepts relative paths, define lexical containment:

1. Require the root to pass `Path.IsPathFullyQualified`; canonicalize it once.
2. Define the accepted input shape. Reject root syntax when the contract is
   relative-only. For one filename, also reject directory separators, the
   volume separator, `.` and `..`.
3. Construct with `Path.Join`; this is not the validation step.
4. Canonicalize the joined result with
   `Path.GetFullPath(joinedPath, canonicalRoot)`.
5. Build the containment prefix by retaining an existing ending separator or
   appending `Path.DirectorySeparatorChar`. A filesystem root such as `C:\`
   already ends in one; appending another produces the wrong prefix. Verify that
   the result equals the root or starts with that prefix. Never compare only with
   the bare root: `C:\root2` shares the prefix `C:\root`. Choose comparison casing
   from known filesystem behavior; `Ordinal` is a conservative lexical default,
   which can reject equivalent spellings. It is not a file-identity comparison.
6. Reject unwanted filename syntax explicitly. `GetInvalidFileNameChars` follows
   the host platform and is not a cross-platform filename policy. Windows device
   names, alternate streams, trailing dots/spaces, and extended path namespaces
   need a policy even if the string passes a prefix check.

Test ordinary relative input, rooted and fully qualified input, both Windows
rooted-relative forms, `..`, alternate separators, a sibling whose name shares
the root prefix, and relevant link or reparse-point behavior.

## Physical containment and object trust

Canonicalize the configured root **before** establishing its trust, and use that
same path throughout. A prefix check does not resolve symbolic links, junctions,
mounts, or all reparse-point types. Hard links can name the same file outside the
tree without being symbolic links at all.

`ResolveLinkTarget`, `GetAttributes`, and `Exists` followed by open are separate
operations. An attacker able to replace a component can change it between the
check and use. `CreateNew` protects the new leaf from an existing entry; it does
not prevent redirection through ancestors. An open handle identifies the opened
object, not whether that object was trustworthy to begin with.

Use the [trusted-parent prerequisites](permissions.md) when hardened protection
is required, not for every ordinary app path. If an attacker can replace or
redirect a relevant component, prefer moving the operation to private storage
or trusted provisioning. If the hostile path cannot be avoided, stop and require a platform-specific
handle-relative/no-follow design with ownership and object-type checks. Merely
rejecting a symlink once, or setting a no-follow flag for only the final leaf,
is not a complete hostile-tree traversal protocol. This skill does not supply
that stronger recipe.
