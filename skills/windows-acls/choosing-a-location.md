# Choosing a location for Windows application state

The location decision determines how much security work you have to do. Choose
per-user unless a requirement forces machine scope, then let the installer own
the machine-scope object.

## Per-user state

The user profile is already private. On a default installation `%LocalAppData%`
and `%AppData%` grant full control to the owning user, `SYSTEM`, and
`Administrators`, and nothing to other standard users. That is the isolation you
want, and you get it by doing nothing.

| Use | .NET | Notes |
| --- | --- | --- |
| Settings that should follow the user across machines | `Environment.SpecialFolder.ApplicationData` | Roams. Keep it small; roaming profiles copy it at logon and logoff. |
| Caches, logs, indexes, downloaded payloads | `Environment.SpecialFolder.LocalApplicationData` | Does not roam. This is the default choice for anything recreatable. |
| Scratch that survives only the operation | `Path.GetTempPath()` | Assume another process as the same user can see and modify it. |

Do not write custom ACLs here. Adding an explicit DACL sets `SE_DACL_PROTECTED`
on the object, which severs it from profile-wide inheritance; a later profile
migration, redirection change, or permission repair then skips your directory.
The failure mode is a directory the user can no longer read after a profile move.

Two things per-user placement does **not** give you:

- **Protection from the same user.** Another process running as that user can
  read and modify the data. If elevated code later consumes it, treat it as
  untrusted input no matter how it is ACLed.
- **Confidentiality from administrators.** An administrator can take ownership.
  For secrets use DPAPI (`ProtectedData`) or the Windows Credential Manager
  rather than a file you try to lock down.

## Machine-wide state

This is where the mistakes live. `%ProgramData%` looks like the machine-wide
counterpart to `%AppData%`, and it is - for *sharing*, not for *trust*. Its
default descriptor grants `BUILTIN\Users` create-file and create-subdirectory
rights, so any standard user can create a top-level directory there and own it.

The consequence: **if your application creates `%ProgramData%\YourApp` lazily on
first use, whoever runs first owns it.** A standard user who wins that race gets
a directory that your elevated code will later read, write, or delete inside.

Prefer, in order:

### 1. HKLM registry, created by the installer

For configuration, feature state, version records, reference counts, install
markers, and anything else small and structured, a registry key under
`HKEY_LOCAL_MACHINE\SOFTWARE\<Vendor>\<Product>` is the safest machine-wide
store, and often the right answer to "where should this file go" is **not a
file**.

Registry keys avoid the entire class of filesystem problems:

- No reparse points, so no junction redirection of a privileged read or delete.
- No path traversal, no trailing-dot or trailing-space aliasing, no 8.3 aliases.
- `HKLM\SOFTWARE` is already administrator-write, standard-user-read by default,
  so the correct ACL is the one you inherit.
- A value write is a single operation, so there is no partially written file to
  detect and no completion-marker protocol to design.
- Registry views are explicit: choose `RegistryView.Registry64` deliberately
  rather than being silently redirected by WOW64.

Size is the practical limit. Values over a few kilobytes belong in a file; the
registry is not a document store.

### 2. A directory the installer provisions with a locked descriptor

When the state genuinely is file-shaped - payloads, caches, large logs - have the
**installer** create the directory and set its ACL, so it exists with the right
descriptor before any application code runs and before any user can race it.

Windows Installer does this with the `MsiLockPermissionsEx` table, which sets a
security descriptor on a created folder. The older `LockPermissions` table exists
but cannot express deny ACEs or inheritance control; prefer `MsiLockPermissionsEx`.

This removes the first-run race entirely: the directory is never absent while the
machine is reachable by a standard user.

### 3. Under `Program Files`

Immutable payload that ships with the product belongs beside the product. Writes
require elevation, which is exactly the property you want for content that
elevated code executes or loads.

Do not use it for mutable state. Applications that write to their own install
directory break under per-user installs, roaming, and file virtualization.

### 4. Runtime creation with an explicit protected descriptor

Acceptable when installer provisioning is not available, but you take on the
first-run race and must fail closed. Create the root with the descriptor supplied
at creation and, if it already exists, **validate and reject** rather than
repair. See [validating-trust.md](validating-trust.md).

Understand what you are signing up for: a standard user who pre-creates your root
converts a privilege-escalation bug into a denial of service. Failing closed with
a clear recovery message is the correct trade for security, but it is a real
availability cost, and it is the reason installer provisioning is preferred.

## Shared caches are a trust boundary

A machine-wide cache shared by all users looks like a disk-space and
bandwidth optimization. It is also:

- An information disclosure channel, when one user's downloaded content becomes
  readable by every other account on the machine.
- A lifetime problem, because no single user owns eviction.
- A trust boundary that privileged code must defend on every read.

Per-user caches cost duplicate downloads and buy isolation for free. Choose a
shared cache only when the duplication is genuinely unacceptable, and then treat
every read as untrusted input.

## Quick anti-patterns

- Creating `%ProgramData%\<Product>` on first run and trusting it afterwards.
- Calling a "create secure directory" helper that returns early when the
  directory already exists. That is the whole bug: the ACL is never applied to a
  directory somebody else created.
- Writing an explicit DACL under the user profile "to be safe".
- Storing secrets in a file and relying on ACLs instead of DPAPI or the
  Credential Manager.
- Using `%ProgramData%` because `%AppData%` was per-user and you wanted "the
  machine version", without asking whether the state must be *trusted* or merely
  *shared*.
