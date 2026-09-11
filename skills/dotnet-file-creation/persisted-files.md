# Persisted settings and per-user files

## Choose settings scope and mobility

Use these decisions for both "where do I save this?" and "am I saving this
right?" Reuse established requirements and the application's settings API before
inventing a new format, folder layout, or merge implementation.

1. **Whose value is it?** "Global" across one user's projects is still per-user.
   All users of one computer is machine-wide; all devices signed into an app
   account is a synchronization feature. Do not infer which meaning from the
   word "global" alone.
2. **Should it follow the person?** Portable preferences such as theme, language,
   and key bindings may be suitable for roaming when that is intended. Absolute
   local paths, device identifiers, and monitor layout are machine-specific;
   caches and logs should not normally roam. Split portable preferences and
   machine-specific state into separate stores rather than roaming everything.
3. **Who may change it?** User preferences, overrideable shared defaults, and
   enforced administrator policy are different authorities. Read scope does not
   grant write permission or make a value trustworthy.

| Need | Windows choice | Writer and limit |
| --- | --- | --- |
| One user's local settings, including global tool preferences | An app subdirectory of `LocalApplicationData` | That user, without elevation; ordinary default when roaming is not required |
| One user's portable preferences intended to roam | An app subdirectory of `ApplicationData` | That user; participates in configured profile roaming, not automatic app-account sync |
| Overrideable defaults for everyone on this computer | Packaged defaults or a provisioned `CommonApplicationData` app directory | Installer/admin/service writes; ordinary users can read and override permitted keys in their own store |
| Enforced machine policy | An administrator/service-controlled configuration store, such as a protected registry key or provisioned directory | Only the policy owner writes; user overrides must not weaken protected keys |

On Windows, the usual directories are AppData Local, AppData Roaming, and
ProgramData respectively. Resolve them through `GetFolderPath`, not literals.
Choosing `ApplicationData` does not enable roaming profiles, guarantee delivery
to another device, resolve conflicting edits, or provide cloud sync. Conversely,
`LocalApplicationData` does not forbid backups or separately configured copying.

The ordinary save example below intentionally chooses non-roaming Windows
storage. When portable preferences should participate in profile roaming, pass
`ApplicationData` to that same example instead. Keep device-specific values in
the local store, and define disjoint keys or an explicit conflict rule; do not
save a merged portable/local object indiscriminately to both stores.

On Linux, `ApplicationData` and `LocalApplicationData` mean configuration and
data conventions, not roaming/non-roaming. On macOS, both map to Application
Support. Neither pair supplies a cross-platform roaming split. Use distinct
application files for distinct roles if needed; real cross-device sync requires
an explicit transport, identity, conflict, and data-protection design.

## Load defaults, save only user overrides

For ordinary overrideable settings, a common load order is **packaged defaults,
then optional machine defaults, then the user's explicit overrides**. Missing
user values inherit defaults; a reset removes the override rather than copying
today's default permanently into the user file. Choose the actual precedence
from the application's requirements, not the order directories happen to appear.

An ordinary preferences save writes only user-owned overrides to the selected
user store. Do not write the resolved settings back to the shared defaults,
request elevation for a theme change, or make the shared directory writable by
everyone. Reuse a settings provider for loading/merging when available, but check
its persistence contract: a configuration reader is not automatically a writer.
The bundled byte-array save examples do not implement layering or policy.

**Enforced policy is not an overrideable default.** Validate policy from its
trusted source and prevent lower-trust user/project/environment/command-line
values from overriding protected keys. Enforce the rule in the authoritative
consumer, not just the settings UI. A last-provider-wins merge does not establish
authority; saving the effective policy into a user file does not preserve it.
Handle missing or invalid mandatory policy according to its failure policy,
without silently treating it as absent and falling back to a weaker user value.

Machine-wide provisioning and trustworthy writers are covered in
[shared-files.md](shared-files.md). The goal is usually read-only shared defaults
plus per-user writes, not a shared mutable JSON file that needs a new lock or
native security subsystem. Changing existing storage or precedence requires
approval and a migration decision; an audit alone does not authorize it.

## Ordinary applications: start here

For an unelevated application saving replaceable preferences, use normal
per-user storage. The user owns and can edit these files; they are not a source
of administrator-approved policy. Rely on normal Windows account protection and
request restrictive Unix creation modes without making every application
implement an ACL or ancestor validator.

Choose by the consequence of an interrupted write:

| Consequence | Adequate default |
| --- | --- |
| Output can be discarded and recreated | Direct write plus validation/rebuild on the next read |
| Keep the previous preferences if a write fails | Write a sibling temporary file, close it, then replace; recipe below |
| This is the only copy of valuable data | Use the application's established document-save/recovery protocol; ask before accepting loss |
| Several writers must not lose each other's changes | Use an existing transaction or coordinator, not last-writer-wins by accident |
| Data contains credentials | Reuse a platform credential-store integration |

Recoverability does not establish privacy. Non-sensitive output can take the
direct path; personal data and secrets need protection even when rebuildable.
Use the escalation triggers in [SKILL.md](SKILL.md) if ordinary assumptions do
not fit. Do not turn a hypothetical hostile deployment into a prerequisite for
every preferences file.

## Choose the location by purpose

| Purpose | Windows | Linux/XDG |
| --- | --- | --- |
| Per-user configuration | `ApplicationData` when roaming is intended | `ApplicationData`: `$XDG_CONFIG_HOME` or `~/.config` |
| Persistent application data | `LocalApplicationData` when roaming is not intended | `LocalApplicationData`: `$XDG_DATA_HOME` or `~/.local/share` |
| Rebuildable caches | An app subdirectory of `LocalApplicationData` | `$XDG_CACHE_HOME` or `~/.cache` |
| Logs and restart state | An app subdirectory of `LocalApplicationData` | `$XDG_STATE_HOME` or `~/.local/state` |

The XDG cache/state locations are not what `LocalApplicationData` returns; use
an explicit platform-aware location policy. XDG environment paths must be
absolute; ignore relative overrides. On macOS, .NET 8+ maps both
`ApplicationData` and `LocalApplicationData` to the platform Application Support
directory. Neither is a cache or log selector. Use macOS Library and sandbox
conventions for Caches and Logs, not the Linux XDG mapping.

These are location conventions, not promises of privacy, ownership, roaming,
backup, or local storage. Redirection and environment overrides can select a
different volume or a network share. Elevated services must not trust a
less-privileged caller's environment as their storage policy.

`GetFolderPath` with its default option can return an empty string when the
folder is unavailable or absent. Reject empty and non-fully-qualified results
before joining anything to them. `SpecialFolderOption.Create` may create the
directory, but does not validate its ownership, ACL, or prior contents.

## Complete ordinary preferences example

Reuse the application's settings API when one exists. Otherwise
[assets/OrdinaryPreferences.cs](assets/OrdinaryPreferences.cs) supplies the small
creation-and-save example: it creates an `ExampleApp` directory and writes
`settings.json`. Replace that fixed application name once for the product; no
key scheme, installer, native calls, or permission audit is required for this
ordinary path.

For a preferences object already held by the application:

```csharp
Environment.SpecialFolder folder = OperatingSystem.IsWindows()
   ? Environment.SpecialFolder.LocalApplicationData
   : Environment.SpecialFolder.ApplicationData;
string dataRoot = Environment.GetFolderPath(folder, Environment.SpecialFolderOption.Create);
byte[] payload = JsonSerializer.SerializeToUtf8Bytes(preferences);
string settingsPath = OrdinaryPreferences.Save(dataRoot, payload);
```

This selects non-roaming app data on Windows, configuration on Linux, and
Application Support on macOS. The helper rejects an empty or relative root,
creates the application directory, writes a uniquely named sibling file, closes
it, and requests replacement. It inherits the Windows ACL and requests `700`
for a new Unix application directory and `600` for the new file. Existing
directories are reused, not certified or recursively repaired.

**Accepted risk:** normal account protections are assumed, one writer owns each
update, and the latest replaceable preference may be lost after an unexpected
shutdown. The helper deliberately does not request `Flush(true)` or claim
power-loss durability. It does not claim verified exclusion of hostile accounts,
preservation of old metadata, or resistance to tampered directory trees. It is
for bounded preferences, not documents, credentials, or privileged policy.

A failed save propagates an exception; show/log a save failure rather than
claiming success. The example cleans its own staging file when possible and
preserves both operation and cleanup failures if both occur. It never deletes
the old destination to make replacement succeed. Close preference readers after
loading; a held destination handle can cause replacement failure on Windows.

On read, missing preferences can use application defaults. For malformed or
truncated replaceable preferences, use the documented reset/default policy and
report the reset; do not silently convert every access or I/O error into "no
settings". Validate deserialized values. Treat paths, commands, or policy read
from the file as user-editable input, especially before privileged operations.

## When a direct write is enough

For non-sensitive output that can be rebuilt, direct writes are simpler:

```csharp
Directory.CreateDirectory(cacheDirectory);
File.WriteAllText(Path.Join(cacheDirectory, "index.json"), json);
```

Here `cacheDirectory` is the application's selected, fully qualified cache
directory from the location table, and `json` is generated output. The agent
should supply that location using existing project utilities or the platform
convention, not ask the developer to choose filesystem internals. No permission
audit, sibling staging, or disk flush is needed for this non-sensitive case.

The old file can be truncated and an interrupted write can leave invalid data.
Validate it when reading and rebuild on absence or corruption; do not expose
partially written entries to readers that require a complete value. When writes
and reads overlap, serialize them or stage complete entries. If ordinary
preferences can also reset to defaults after a partial write, this direct-write
tradeoff is acceptable there too; the staged example preserves the earlier copy
during a handled write failure.

## User-selected exports

Use the path the user actually authorized. `CreateNew` is the simple default
when an existing file must not be overwritten:

```csharp
using FileStream output = File.Open(selectedPath, FileMode.CreateNew, FileAccess.Write);
output.Write(payload);
```

This creates a visible file immediately and a failed export can leave partial
output. Report failure and remove only the newly created output when the
application's cleanup policy permits. Ask before replacing an existing file;
use the established save API or sibling staging when retaining the old copy
matters. Do not replace a valuable document by deleting it first. A user-selected
destination may be shared: do not call the export private merely because the
application created it. An elevated export influenced by a lower-privilege
caller needs authorization and the hardened review, not this ordinary recipe.

## Hardened writes: establish the parent first

Use this path only when the ordinary account-protection assumption is inadequate,
such as defending against another unprivileged account or protecting service
state that a lower-privilege caller can influence. Prefer a private location or
provisioned service-owned storage before building native security code. Follow
the [hardened prerequisites](permissions.md); a profile path alone is not proof.

The complete recipe below begins **after** the application root is provisioned
and trusted. It intentionally does not create or adopt that root. Do not treat
`CreateDirectory(root, ownerOnlyMode)` as the missing trust check: existing
objects are unchanged, and intermediate Unix directories get default modes.
Refuse an untrusted existing tree instead of recursively repairing it.

## Optional trusted-parent recipe

[assets/TrustedFileWrites.cs](assets/TrustedFileWrites.cs) is self-contained C#
using the BCL. Its methods use the same constrained key contract described in
[paths.md](paths.md): `settings` maps to `item-settings.bin`, regardless of the
payload format. It neither accepts arbitrary leaf paths nor creates parents.
It is an optional hardened building block, not the default settings interface.

| Method | Contract |
| --- | --- |
| `GetPath` | Validate key syntax and root qualification; return a path, not proof of trust. |
| `CreateNew` | Exclusively create a new file with creation-time restrictions; return an owned write-only stream. Existing entries fail. The caller owns disposal and incomplete-file cleanup. |
| `CreateScratch` | Return an owned, randomly named read-write stream requesting deletion on normal disposal; see [temporary-files.md](temporary-files.md) for limits. |
| `PublishLastWriterWins` | Write a private sibling staging file, flush and close it, then request replacement. No compare-and-swap, multi-file transaction, or crash-durability promise. |

For protected state already serialized to a byte array:

```csharp
TrustedFileWrites.PublishLastWriterWins(trustedRoot, "state", payload);
```

`trustedRoot` must meet the prerequisites throughout the operation. On Windows
the file inherits the verified file-inheritable ACL. On Unix the code requests
`600` at creation; the filesystem may reduce bits, and effective ACL policy still
belongs to the parent-trust decision. The byte-array recipe suits bounded
configuration, not arbitrarily large uploads.

The publisher has no delete-old or copy-over fallback. It deletes a staging path
on failure only after its own exclusive open succeeded. If cleanup also fails,
an `AggregateException` preserves both failures; do not suppress it or claim
cleanup succeeded. A process crash can still leave staging files behind.

## Reference: what publication guarantees

Read this table when a specific guarantee matters, not as a questionnaire for
every ordinary application. The ordinary example accepts the limits above;
the hardened example adds a file-data flush but not a durable commit protocol.

| Property | Guarantee and limit |
| --- | --- |
| Partial-write isolation | The destination is untouched during serialization, staging writes, flush, and close. Readers must ignore staging names. |
| Atomic visibility | On a filesystem providing atomic same-directory replacement, an open of the destination sees the old or new version, not partially copied content. POSIX `rename` documents this; .NET `File.Move` is not a universal atomicity contract for every storage backend. |
| Same-volume operation | Sibling staging avoids ordinary cross-volume copy fallback while the trusted directory remains stable. Two paths on the same drive letter are a weaker condition. |
| Open readers | Where replacement is permitted, existing readers can retain the old object. Windows delete sharing may be necessary but is not sufficient for `File.Move`; it can fail even with all sharing flags. Reopening for each read can mix versions. |
| Metadata | Replacement publishes the staging object's metadata. Do not assume the old destination's ACL, mode, owner, timestamps, streams, hard-link relationships, or other metadata is retained. |
| Concurrent writers | The last successful replacement wins; a writer may overwrite an update it never read. There is no ordering or lost-update protection. |
| Durable commit | Not provided by either example. A successful file flush and move do not establish that the renamed directory entry survives power loss. |

Use `File.Replace` only after deciding its existing-destination, optional-backup,
and platform-specific metadata behavior fits the application. It is available
on Unix too, but it is not a portable transaction or durability shortcut.

If readers must remain open during replacement, verify the exact primitive and
sharing flags on the deployment. Do not turn a failed `Move` into a delete-old,
copy-over, or automatic `Replace` fallback with different metadata semantics.

## Durability and recovery

Distinguish a process exception from abrupt termination, an OS crash, and power
loss. `Flush(flushToDisk: true)` requests file-data persistence and surfaces
some writeback failures; `FlushAsync` is not a replacement for that durability
request. File flush does not make the later rename durable.

On Linux, a durability protocol normally also synchronizes the parent directory
after rename; newly created ancestors introduce further metadata to synchronize.
Portable .NET has no single file-and-parent commit primitive. Windows and macOS
need their own documented flush/storage protocol. Device caches, mount options,
and remote servers can weaken the result even when calls return success.

If loss of the last committed value is unacceptable, stop and use a proven
transactional store, such as SQLite with appropriate durability settings and a
supported local filesystem, or a separately verified native protocol. Neither a
backup filename nor a passing unit test establishes crash recovery.

Before the replacement attempt, a handled write/flush failure leaves the old
destination untouched. During or after replacement, determine recovery from the
storage contract and validated content/version identifiers. In particular, NFS
can report rename failure after the server performed it. Do not blindly retry a
read-modify-write or promise the old copy survived an ambiguous failure.

## Concurrency between cooperating processes

For a read-modify-write, coordination must cover **read, validate, modify, stage,
and publish**, not just the rename. Prefer a transaction when correctness depends
on excluding lost updates.

A file-lock protocol is acceptable only after verifying it on the deployment:

1. Provision a dedicated lock file inside the trusted parent with the intended
   creation-time permissions. Its identity and contents must already be trusted.
2. Every participant opens that same file with `FileMode.Open`,
   `FileAccess.ReadWrite`, and `FileShare.None`. Keep the handle for the complete
   update. Use bounded retries for known contention, not every `IOException`.
3. Never delete, replace, or request `DeleteOnClose` on the lock file. Otherwise
   processes can lock different objects behind the same name.
4. Verify contention in independent processes. On Unix, locking is coarser,
   advisory, best-effort, and disableable with
   `DOTNET_SYSTEM_IO_DISABLEFILELOCKING=1`; a successful open does not prove a
   lock was acquired on unsupported filesystems. See
   [platform-differences.md](platform-differences.md).

This protocol is not a security boundary against nonparticipants or hostile
same-identity code. Stop and choose a stronger store or coordinator if the
locking prerequisite cannot be verified.

## Secrets require another decision

Modes and ACLs are access controls, not encryption or secure erasure. They do
not protect against hostile same-identity code, privileged access, offline disk
access, backups, or copies synced elsewhere. Prefer a platform credential store
for tokens and keys: DPAPI on Windows or an appropriate keychain/secret service.
Those stores have their own identity and key-management boundaries; they are not
blanket protection from an administrator or a compromised application.
