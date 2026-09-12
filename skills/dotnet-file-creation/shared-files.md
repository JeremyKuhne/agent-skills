# Shared machine-wide files

## Confirm that the setting is machine-wide

For both "where do I save this?" and "am I saving this right?", start with the
[settings scope and layering rules](persisted-files.md). "Global" across one
person's projects is per-user; it does not belong in ProgramData just because
it is called global. Continue here when the store serves multiple users on a
computer or supplies privileged policy.

Shared defaults can be read-only to ordinary applications while each person
saves overrides in their own store. That does not require a machine-wide writable
file. Enforced policy is a different case: the authoritative consumer must
prevent user overrides of protected keys, not merely choose a protected folder.

## There is no portable machine-writable location

`Environment.SpecialFolder.CommonApplicationData` selects a conventional
location, not a portable writable or trusted store. Typical mappings differ:

| | Windows | Linux |
| --- | --- | --- |
| Path | `C:\ProgramData` | `/usr/share` |
| Writable by an ordinary process | Default policy can permit creating subdirectories; inspect actual ACLs | Normally administrator-managed, not user-writable |
| Safe to trust a lazy first-run create | **No** | **No**; existing objects and access policy still need validation |

First-run name squatting is possible wherever untrusted accounts can create the
application directory. `Directory.CreateDirectory` can return an existing
directory without proving who created it, what it contains, or where its links
lead. A successful call is never the trust decision.

## Decide whether you need shared *storage* or shared *trust*

Most designs that reach for a machine-wide directory want one of these instead:

- **Common starting preferences with personal customization.** Load packaged or
  provisioned read-only defaults and save only explicit per-user overrides.
  Do not copy the merged defaults into every user's settings, where future
  default changes would be hidden, or let a preferences save rewrite the shared
  source. Independent rebuildable caches can still use per-user copies.
- **Read-only content that ships with the product.** Use the installation's
  protected content location. An arbitrary executable directory, portable
  unpacked app, or user-writable install is not automatically trusted.
- **Small machine-wide configuration.** Use a store the platform already
  protects: the Windows registry under `HKEY_LOCAL_MACHINE`, or a path your
  package provisions on Linux.

If unprivileged users can write data later consumed by an elevated service,
treat that data as untrusted even when the directory was provisioned correctly.
For privileged state, prefer a dedicated service identity that owns writes and
validates requests through an authenticated interface. Shared write access is
not shared trust.

## Provision it at install time

| Platform | Mechanism |
| --- | --- |
| Windows | Windows Installer `MsiLockPermissionsEx` on a created folder, or a registry key under `HKLM\SOFTWARE\<Vendor>\<Product>` |
| Linux | A package-provisioned `/var/lib/<app>` for mutable state; `/etc/<app>` for configuration, with explicit ownership, mode, and ACL policy |
| macOS | A path under `/Library/Application Support/<app>` created by the installer |

Provisioning must itself handle preexisting or name-squatted entries. Create
with the final policy beneath a trusted ancestor, or validate an already trusted
object and its contents. Do not merely reset its ACL/mode and adopt it. Correct
provisioning establishes a boundary for later runs; running at install time
does not by itself remove a race or certify an existing tree.

Once a private application/service parent meets
[permissions.md](permissions.md), the bundled
[assets/TrustedFileWrites.cs](assets/TrustedFileWrites.cs) recipe can create or
publish files there. A directory intentionally writable by mutually untrusted
users does not meet that recipe's prerequisites.

## If you must create it at run time

Then you own the whole problem, and it is a security problem rather than a file
API problem:

- The privileged process must create the root with its final ownership and
  permissions **at creation**, not create then repair.
- If the root already exists, validate it and **fail closed**. Repairing a
  directory somebody else created leaves their data in place under a descriptor
  that now looks trustworthy.
- Validate both the owner and effective access, including ancestors and existing
  contents. A trusted owner alone is insufficient if untrusted accounts have
  write, delete-child, or policy-changing rights. Restrictive-looking modes or
  a DACL alone do not establish provenance.
- Never recursively delete a machine-wide path assembled from untrusted
  components.

On Windows, the Windows ACL skill owns descriptor creation and root-anchored
trust validation. If that workflow is unavailable, stop and require trusted
provisioning rather than inventing a reduced ACL check. On Unix, BCL mode APIs
do not expose the owning UID or the full ACL policy. A `stat` query followed by
an open is still a race when ancestors can change. macOS extended ACLs and
network-server permission models require their own validation.

## Sharing between processes, not between users

If the requirement is coordination rather than storage, prefer a mechanism that
does not leave a file behind:

- An appropriately scoped and protected OS coordination primitive, after
  checking platform support and name-squatting rules.
- A lock file opened with `FileShare.None`, kept **inside per-user storage**, for
  cooperating instances of the same user.
- A socket or pipe for actual communication.

A file in a shared directory used as a flag is the pattern most likely to be
hijacked, because its name is predictable and its location is writable by
everyone.

Named primitives are not automatically secure substitutes: identities,
namespaces, access control, and supported operations differ by platform.
The complete cooperative lock protocol and its limits are in
[persisted-files.md](persisted-files.md).

## Reading machine-wide data written by someone else

Even read-only consumption is a trust decision. Anything under a location that
unprivileged users can write is untrusted input:

- Do not let its content select a path your process then writes to or deletes.
- Do not deserialize it into types with side effects.
- Validate it as you would a network payload.

That applies to configuration files, cache manifests, and version markers alike.
