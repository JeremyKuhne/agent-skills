---
name: dotnet-file-creation
description: Create and audit .NET 10+ filesystem I/O on Windows, Linux, and macOS. Use for "where do I save this", "am I saving this right", global/user app settings, roaming/non-roaming preferences, machine-wide defaults or policy, caches, temporary files, safe overwrite/deletion, and write-then-rename publishing. Also use for "check my code to make sure I'm following best practices for IO", file I/O audits, "where should this temp file go", "make this file user-only", "why does this work on Windows but not Linux", Path.Join vs Path.Combine, rooted vs fully qualified paths, Path.GetFullPath, File.Open/File.Create/FileStreamOptions, Directory.CreateDirectory/CreateTempSubdirectory, GetTempFileName, UnixFileMode/umask/UnixCreateMode, CA1416 or PlatformNotSupportedException on file APIs, FileShare, casing, and hidden files. Audits cover filesystem correctness and security; route pipes, networking, and deep performance elsewhere.
license: MIT
compatibility: Guidance assumes .NET 10 or later; Unix mode APIs require .NET 7 or later. Bundled tests require PowerShell 7 and Pester 5.7 or later. Platform execution coverage and limits are recorded in references/research.md.
metadata:
  portability: portable
  applicability: dotnet
  binding: optional-overlay
  risk: local-write
  maturity: canary
  requires: none
  related: windows-acls, security-review
---

# File I/O on .NET across platforms

If `overlay.md` exists beside this file, read it before acting; it contains
repository-specific bindings. This core remains usable without it.

## Choose the entry point

| Question | Workflow |
| --- | --- |
| "Where do I save this?" | Design: use the [settings decisions](persisted-files.md) to select scope, roaming behavior, and who may write; then choose the smallest adequate save recipe. |
| "Am I saving this right?" | [Audit](audit.md): trace the existing location, readers/writers, load order, and save target against the same settings decisions. Remain read-only unless changes are requested. |

Infer requirements from the application first. These are two ways into the same
decision rules, not two different security standards. Scratch and exports use
their own recipes below; they need not answer every settings question.

## Start with ordinary application I/O

Default to an unelevated desktop or CLI application using its own per-user
storage, normal OS account protections, and application-controlled names. Do not
require an ACL auditor, installer-provisioned directory, custom key scheme, or
native code merely to save preferences or use disposable scratch space.

Inspect the call site, data, writers, and deployment configuration before asking
for missing product decisions. Reuse an existing settings framework when it fits.

Ordinary defaults accept loss of the latest replaceable preference after a
crash, rebuildable cache corruption, and some crash leftovers. They do not accept
silent save failures, accidental overwrite of valuable data, or treating
user-editable files as privileged authority. A cache can still contain sensitive
data; being rebuildable is not a privacy decision.

## Special directories are locations, not authority

On Windows, the owning user normally can write their `ApplicationData` and
`LocalApplicationData` **without elevation**. Other ordinary accounts are
normally restricted by profile ACLs. Thus AppData is appropriate for that user's
preferences, but not proof that a policy, executable, or command stored there
was approved by an administrator. `CommonApplicationData` is different: default
Windows policy can let ordinary users create application subdirectories there.

Do not equate "special folder", "per-user", "hidden", or "random name" with
trusted contents. On Unix, location alone also does not imply private access;
request restrictive modes when creating application storage. No mode or ACL
recipe here promises protection from a fully privileged administrator/root,
hostile code with the same effective authority, or a compromised OS/storage
server. That exclusion does not excuse trusting lower-privilege input in an
elevated operation.

## Select the simple path

| Need | Default and accepted limitation | Recipe |
| --- | --- | --- |
| Non-sensitive scratch | New temp subdirectory, normal disposal/cleanup; a crash may leave files | [temporary-files.md](temporary-files.md) |
| Rebuildable cache, one writer | Ordinary app directory and direct writes; validate and discard incomplete entries | [persisted-files.md](persisted-files.md) |
| User settings, including "global" across one user's projects | Select roaming/non-roaming, then a simple save; no power-loss or lost-update guarantee | [Settings decisions](persisted-files.md) |
| Defaults or policy for everyone on one computer | Distinguish overrideable defaults from enforced policy and identify the authorized writer | [Settings layers](persisted-files.md) |
| User-selected export | Authorized destination and deliberate overwrite policy; stage if preserving the old file matters | [persisted-files.md](persisted-files.md) |
| Credentials | Existing platform credential-store integration; do not invent a secret-file format | [persisted-files.md](persisted-files.md) |
| Filesystem best-practices audit | Trace reads/writes and report defects, conditional risks, and accepted tradeoffs | [audit.md](audit.md) |

Direct `File.WriteAllText` is reasonable for non-sensitive, replaceable output
when a failed write can be discarded. Do not prescribe write-then-rename,
`Flush(true)`, or a database for every file. Reuse existing application storage
and logging APIs before adding helpers.

## Escalate for a concrete reason

| Evidence or requirement | Next action |
| --- | --- |
| Elevated/service code trusts user-writable files or caller-selected paths | Trace the lower-privilege input; prefer service-owned state and validated requests. See [shared-files.md](shared-files.md). |
| Other accounts can replace target entries/ancestors, or explicit hostile-account privacy is required | Move to private storage or trusted provisioning first. Use [permissions.md](permissions.md) for the hardened boundary. |
| Secrets or sensitive personal data | Prefer a credential store for secrets; use private per-user storage and restrictive creation permissions for personal data. Require the hardened check when hostile-account exclusion is needed. |
| Multiple writers must preserve each other's changes | Use an existing transaction/coordinator; atomic replacement alone loses updates. See [persisted-files.md](persisted-files.md). |
| Irreplaceable data or a promise that saves survive power loss | Establish the recovery requirement and prefer a proven transactional store or save protocol. |
| Known network, redirected, or unusual filesystem | Check only the permissions, locking, or durability assumptions the operation actually relies on; this alone need not trigger native hardening. |

Prefer a simpler design or established API over custom native security code.
Ask before changing storage location, deployment, overwrite behavior, or accepted
data loss. When the required guarantee cannot be established, stop that operation
and name the safer alternative; do not silently downgrade it. Do not block an
ordinary preference save solely because a hypothetical deployment is untested.

## Ask about consequences, not mechanisms

Infer facts from code and configuration first. Ask only when the answer changes
the choice or finding. For settings: "Just this person, or everyone on this
computer?", "Should it follow the person to another computer?", and "Is this a
default people can change, or a rule they must not override?" For recovery and
sharing: "Can this be rebuilt?" or "Can two copies update this?" Explain the
consequence and recommend a default; do not ask the developer to certify ACLs
or choose synchronization primitives. Unknown is not proof of safety or a defect.

## Keep the basic rules

- Use application-controlled leaf names, or validate and authorize external
  input. `Path.Join` and `GetFullPath` do not establish containment; see
  [paths.md](paths.md). No key helper is mandatory for a fixed filename.
- Reject an empty storage root before joining. Resolve relative paths against a
  known fully qualified base; Windows rooted paths need not be fully qualified.
- Use `CreateNew` for create-if-absent, not `Exists` followed by create. An
  intentional overwrite needs an explicit policy instead.
- Set sensitive creation permissions before writing, guard Unix APIs, dispose
  owned streams, and keep incomplete output distinguishable from success.
- Load [platform-differences.md](platform-differences.md) for a relevant sharing,
  deletion, casing, link, or attribute issue; do not infer filesystem behavior
  solely from the OS.

## Validate the chosen outcome

Test the ordinary recipe's create/read/update and relevant failure path. Report
the assumptions and limitations that matter to this use, not every filesystem
caveat. Stronger access-denial, concurrency, or crash-recovery claims need checks
at those boundaries; a same-user write test cannot establish them. Audit output
and scope rules are in [audit.md](audit.md).

## Evidence

Measured behavior and test coverage are recorded in
[references/research.md](references/research.md). Primary documentation is indexed in
[references/documentation.md](references/documentation.md).

## Related skills

When the target is a machine-wide Windows location that elevated code will
trust, the Windows ACL skill owns descriptor creation and trust validation. When
the question is whether untrusted input can reach a privileged file operation,
hand off to a security review workflow. A consuming repository wires the
concrete cross-references in its overlay.
