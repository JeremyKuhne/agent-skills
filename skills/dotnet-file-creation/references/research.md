# Research: cross-platform file creation on .NET

Evidence base for the `dotnet-file-creation` skill. Keep three levels separate:

- **Documented contract:** an API or OS specification, within its stated scope.
- **Implementation evidence:** inspected versioned runtime source; not a promise
  for another release, storage backend, or configuration.
- **Measurement:** an executed test in a named environment; not proof of access
  denial to another identity, adversarial race resistance, or crash durability.

Primary sources and independent security/storage guidance are indexed in
[documentation.md](documentation.md).

## Review on 2026-09-09

The initial review emphasized hardened recipes; usability review then exposed
that the entry point imposed those prerequisites on ordinary applications too.
The revised default is an unelevated application using normal per-user account
protections, with concrete triggers for stronger guarantees. Direct discardable
writes and replaceable preference saves need not solve adversarial provisioning.
This is an explicit risk policy, not a new API guarantee.

The hardened adversary remains another unprivileged account. Hardened recipes
require an already trusted application parent and stable ancestors; they exclude
hostile code with the same effective authority, fully privileged
administrators/root, and a compromised storage server. Lower-privilege input into
elevated code still needs review. The recipes do not implement a validator for
hostile filesystem trees.

Microsoft's known-folder definitions and object-access documentation distinguish
per-user AppData from common machine locations and actual access policy. A normal
user can edit their own AppData without elevation; a special-folder name does
not make the contents administrator-approved. This distinction is now an entry
point rule and an audit case, not an advanced caveat left to the reader to infer.

| Reviewed claim | Evidence | Resulting boundary |
| --- | --- | --- |
| A profile path proves privacy | Windows object-access and inheritance documentation; CERT secure-directory guidance | Ordinary apps can assume normal account protection; hardened claims require ownership, ancestors, contents, and effective child-access evidence. |
| Requesting `600` guarantees exactly `600` | Linux `umask(2)` and default-ACL rules | Ordinary bits are bounded by the request; owner bits can be removed. Mode queries do not prove every ACL policy. |
| Both platform guards silence CA1416 | Microsoft CA1416 documentation | Both `OperatingSystem` and `RuntimeInformation.IsOSPlatform` are recognized; guard the Unix setter. |
| Directory creation secures an existing tree | .NET 10.0.0 Unix filesystem source | Existing entries are reused; explicit Unix mode applies only to a newly created leaf. |
| Unix `FileShare` equals Windows sharing | .NET 10.0.0 Unix SafeFileHandle source | Coarser, best-effort advisory locking; unsupported locking and configuration can remove exclusion. |
| Delete sharing guarantees Windows replacement | Local Windows tests and a sharing-mode probe | `File.Move` refused an open destination even with all sharing flags; handle refusal without deleting the old version. |
| Flush then rename is a durable commit | `File.Move`, `FileStream.Flush`, Linux `rename(2)`/`fsync(2)`, SQLite commit guidance | Separate visibility from durable directory metadata and coordinated updates. NFS failure can be ambiguous. |
| `DeleteOnClose` survives termination everywhere | .NET 10.0.0 Unix SafeFileHandle source | Unix unlink occurs during managed release and can be bypassed by termination; cleanup is not secure erasure. |
| Linux rules cover macOS and every filesystem | Apple ACL manual, .NET macOS mapping documentation, XDG specification | macOS ACLs/locations and nonlocal or permission-emulating storage need separate evidence. |

### Executed in this review

The focused Pester suite compiled and exercised the bundled
[ordinary preferences example](../assets/OrdinaryPreferences.cs) and
[TrustedFileWrites recipe](../assets/TrustedFileWrites.cs) on Windows
10.0.26200, NTFS, PowerShell 7.6.6, and its hosted .NET 10.0.12 runtime:
**49 passed, 0 failed, 7 Unix-only cases skipped** after the ordinary-path change.

Coverage includes ordinary application-directory creation, new/updated settings,
shorter replacement payloads, reuse of existing ordinary storage, failed-save
cleanup, and invalid roots. Hardened cases cover invalid/rooted keys, missing parents, exclusive-create
collisions, normal scratch cleanup, new/replaced destinations, failed-publish
cleanup, deliberately restricted Windows ACL inheritance, open-reader behavior,
Windows sharing refusal, and lexical escape through a directory junction.
Unix-specific assertions cover creation modes and unchanged permissions on
existing objects, but were not executed locally in this review.

A separate Windows probe tried `File.Move` while a reader used `Read`,
`Read | Delete`, and `ReadWrite | Delete`. All three returned
`UnauthorizedAccessException` with `E_ACCESSDENIED`; the old reader retained its
original content. This is a measured limitation of this environment, not a claim
that every future Windows/filesystem combination must behave identically.

The repository CI runs Pester on Linux and selected filesystem tests on Windows.
That workflow is configured coverage, not an observed successful run of these
changes. Neither local execution nor the current CI provides a macOS run.
WSL was unavailable in this review; no Linux environment was installed.

Not executed: second-account access-denial tests, macOS extended-ACL tests,
process-kill or power-loss injection, independent-process locking validation,
network/overlay/FUSE filesystem tests, and service-identity provisioning tests.
The existing same-process sharing assertion proves only that narrower case.

### Manual decision walkthroughs

These are semantic review cases, not model invocations or measured routing
accuracy:

| Request | Required decision |
| --- | --- |
| Save theme preferences for an ordinary desktop app | Use normal per-user storage and the ordinary recipe; no ACL certification question. Explain the accepted reset/loss limits. |
| Audit direct writes to a non-sensitive cache that validates and rebuilds entries | Accepted tradeoff, not a defect. Do not mandate transactions or disk flushes. |
| Audit a preferences file with unknown simultaneous writers | Conditional risk. Ask whether two instances must retain each other's changes; do not invent that requirement. |
| Audit an elevated helper that trusts an unvalidated command from AppData | Defect: the owning user can change the command without elevation. Recommend service-owned policy or validated authorized requests. |
| Audit ordinary storage because an administrator could read it | Explain the excluded attacker; do not flag the lack of administrator-proof ACLs as a defect. |
| Audit an existing implementation | Remain read-only; report definite defects, conditional risks, and material accepted tradeoffs separately. |
| Make a temporary token file user-only | Establish the parent and effective access first; prefer a credential store for persisted secrets. |
| Resolve `C:logs` under a configured root | Distinguish rooted from fully qualified; an explicit base gives deterministic resolution, not containment. |
| Safely update settings from two processes | Choose last-writer-wins only deliberately; otherwise coordinate the whole update or use a transaction. |
| An attacker may have created the app directory first | Refuse adoption or mode/ACL repair; require trustworthy provisioning or platform-specific validation. |
| Validate a machine-wide Windows security descriptor | Hand off to the Windows ACL workflow, or stop if that capability is unavailable. |

These walkthroughs check the intended decision flow only. No novice-user study
or model-routing evaluation was run; passing code tests does not measure whether
developers understand the questions or agents select the right assurance level.

### Behavioral suite added on 2026-09-10

The initial commons evaluation suite contained 12 opt-in cases for this skill.
It uses natural prompts for ordinary preferences/scratch, public versus sensitive
caches, privileged AppData consumption, mixed audit findings, understandable
writer questions, durable saves, administrator exclusions, hostile existing
directories, empty roots, and a pipe near miss. Four audit cases inspect
synthetic source and deployment facts with writing available but forbidden by
the requested audit scope.

On Windows, **34 focused deterministic checks passed** for the scenario registry,
pattern syntax, coherent and contradictory responses, actual invocation evidence,
unchanged-audit enforcement, isolated fixture staging, and compiled fixture
behavior. These are tests of the suite, not successful model evaluations.

No real model run, generated-answer compilation, full multi-turn interview, or
novice-user study has been performed for this suite. Per-case human rubrics cover
decision quality, useful questions, and runnable implementation output; the
generic scorer does not evaluate those rubrics automatically. Keep any future
model results separate from the API and harness test evidence above.

### Settings decisions extended on 2026-09-11

"Where do I save this?" and "Am I saving this right?" now share the scope,
mobility, and authority rules in [persisted-files.md](../persisted-files.md).
The first designs a storage choice; the second audits the existing read/merge
and save paths without changing them. Windows roaming participates in configured
profile behavior, not automatic cross-device synchronization. Linux and macOS
folder mappings do not provide an equivalent roaming split. The proposed
defaults/user-override ordering is an application design convention, not a
universal .NET persistence or policy contract.

Four new scenarios cover per-user "global" settings, portable versus local
values, shared defaults with user saves/reset behavior, and protected policy
that user preferences must not override. This brings the suite to **16 cases**,
including six source-backed read-only audits and one pipe near miss.

With the CI-pinned native Copilot CLI 1.0.63 selected explicitly, the final
Windows validation reported **95 passed, 0 failed** for the evaluation-harness
test file and **373 passed, 0 failed, 9 skipped** for the full deterministic
suite. All new response checks and compiled fixture checks passed, including
the accepted theme-default precedence, the wrong machine-default save target,
and the user override of an enforced policy value. No real model evaluation,
profile-roaming deployment test, or novice-user study was run.

## Historical measurements

The following environments and observations were recorded before this review.
They are retained as historical evidence, not relabeled as fresh executions:

- **Windows** 11 (10.0.26200), .NET 10.0.11, via PowerShell 7.6.5 and file-based
  apps on the .NET 10 SDK.
- **Linux** Ubuntu 24.04.3 under WSL2, .NET 8.0.21, `umask 0022`, on ext4. Not on
  a `/mnt` drvfs mount, which does not carry real Unix modes and would have
  invalidated every permission measurement.

The Linux figures came from .NET 8. API availability since .NET 7 and shared
syscalls do not prove unchanged behavior on .NET 10. Treat that column only as
the recorded .NET 8 observation; the .NET 10 source review is separate evidence.

---

## 1. Where the runtime puts things

| `Environment.SpecialFolder` | Windows | Linux |
| --- | --- | --- |
| `UserProfile` | `C:\Users\<user>` | `/home/<user>` |
| `ApplicationData` | `%AppData%` | `/home/<user>/.config` |
| `LocalApplicationData` | `%LocalAppData%` | `/home/<user>/.local/share` |
| `CommonApplicationData` | `C:\ProgramData` | `/usr/share` |
| `Path.GetTempPath()` | `%TEMP%` (under the profile) | `/tmp/` |

Both per-user folders resolved under `UserProfile` on both measured systems, and
`CommonApplicationData` resolved outside it on both. The test requests
`SpecialFolderOption.Create`, because the default option returns an empty string
when the directory does not exist. Without that option, the result depends on
the state of the account image rather than only on the platform mapping.

`CommonApplicationData` is otherwise not comparable across platforms:
the measured Windows default allowed standard users to create subdirectories
under `C:\ProgramData`, while `/usr/share` was root-owned. Neither the path nor
those observed defaults is a portable writable-store or trust guarantee.

---

## 2. Default permissions on Linux

| Object | Mode |
| --- | --- |
| `/tmp` | `777` plus the sticky bit |
| `~/.config` | `755` |
| A new subdirectory of `~/.config` via plain `Directory.CreateDirectory` | `755` |
| A file written there via `File.WriteAllText` | `644` |
| `Directory.CreateTempSubdirectory()` | `700` |
| `Path.GetTempFileName()` | `600` |
| A file created by `File.OpenHandle` | `644` |

The composite result was measured directly in this environment: a settings file
written into `~/.config/<app>/` is **reachable and readable by other local
users**, because every component grants other-execute and the file grants
other-read. The `755` parent is not a Linux invariant; desktop tooling can create
`~/.config` more restrictively, while `~/.local/share` is commonly traversable.

The recorded Windows environment had restrictive profile inheritance. That
configuration does not establish privacy for redirected locations, changed ACLs,
or another identity's environment.

`Directory.CreateTempSubdirectory` at `700` matches its documentation, which
states the parent temp directory may be shared while the created directory is
owner-only.

---

## 3. Explicit modes

### The mode must be set at creation to be safe

`File.WriteAllText` then `File.SetUnixFileMode` leaves the file at `644` in
between. `FileStreamOptions.UnixCreateMode` passes the mode to `open`, closing
the window.

### umask subtracts, never adds

Measured under `umask 022`:

| Requested | Actual |
| --- | --- |
| `600` | `600` |
| `644` | `644` |
| `666` | `644` |

These exact outcomes are specific to umask `022`. A mask can remove owner bits
as well; a `600` request under `0777` can produce `000`. For ordinary bits the
testable bound is `(actual & ~requested) == 0`, not equality. Default ACLs require
the separate calculation documented by `umask(2)`.

### Directory modes reach the leaf only

`Directory.CreateDirectory(root + "/a/b/c", 700)` produced:

| Path | Mode |
| --- | --- |
| `c` (the leaf) | `700` |
| `a` (an intermediate) | `755` |

Creating each level in its own call produced `700` at every level.

**This is the opposite of the .NET Windows ACL overload**, where a security
descriptor supplied to `FileSystemAclExtensions.CreateDirectory` is applied to
every level the call creates. This is behavior of that API, not a general rule
for callers of native `CreateDirectoryW`.

---

## 4. Platform gating of the Unix APIs

Reflected attributes and observed Windows behavior:

| Member | Attribute | Windows behavior |
| --- | --- | --- |
| `File.GetUnixFileMode(string)` / `(SafeFileHandle)` | `Unsupported(windows)` | Throws `PlatformNotSupportedException` |
| `File.SetUnixFileMode(...)` | `Unsupported(windows)` | Throws `PlatformNotSupportedException` |
| `Directory.CreateDirectory(string, UnixFileMode)` | `Unsupported(windows)` | Throws `PlatformNotSupportedException` |
| `FileStreamOptions.UnixCreateMode` **setter** | `Unsupported(windows)` | Throws `PlatformNotSupportedException` |
| `FileStreamOptions.UnixCreateMode` property / getter | none | Returns `null` safely |

The attribute on `UnixCreateMode` is on the setter accessor only. Reflecting the
`PropertyInfo` custom attributes reports nothing, which initially looked like a
gap in analyzer coverage; compiling an unguarded assignment proved otherwise:

```text
error CA1416: This call site is reachable on all platforms.
'FileStreamOptions.UnixCreateMode.set' is unsupported on: 'windows'.
```

The message is *"Unix file modes are not supported on this platform."* in all
four cases.

There is no `File.CreateTempFile` in .NET 10. `Path.GetTempFileName` remains the
only built-in temp *file* API, which is why the guidance is built around
`Directory.CreateTempSubdirectory` instead.

---

## 5. Semantics measured on both platforms

| Behavior | Windows | Linux |
| --- | --- | --- |
| `FileMode.CreateNew` over an existing file | `IOException` | `IOException` |
| `FileShare.None`, second open attempt | Blocked | Blocked |
| `File.Delete` while a handle is open with `FileShare.None` | `IOException` | Succeeds, unlinked |
| `File.Move(overwrite: true)` | Replaces | Replaces |
| Path casing | Case-insensitive | Case-sensitive |
| `SetAttributes(Hidden)` on a normal file | Sets it | No throw, **no effect** |
| A dot-prefixed file reports `Hidden` | No | Yes |

The casing row is a property of the **filesystem** measured here (NTFS and ext4),
not of the operating system. The current test probes the actual directory and
accepts either consistent behavior on every OS; it no longer assumes NTFS or
ext4 defaults merely from an OS branch.

The two `Hidden` rows carry the same caveat: they were measured on Linux only.
Whether .NET honors the macOS `UF_HIDDEN` flag was not tested, so the test scopes
those assertions to Linux as well.

The recorded Linux sharing observation was a second .NET open with default
locking. The inspected implementation uses advisory `flock`, with less
granularity than Windows, ignored unsupported-lock errors, and some skipped
filesystem/access combinations. Processes can ignore advisory locks, and
`DOTNET_SYSTEM_IO_DISABLEFILELOCKING=1` disables this runtime behavior.

---

## 6. Path construction and qualification

Path behavior was measured separately on Windows 11 (10.0.26200), .NET 10.0.9,
via PowerShell 7.6.3:

| Input or operation | Result |
| --- | --- |
| `Path.Combine(root, rootedInput)` | Discarded `root` |
| `Path.Join(root, rootedInput)` | Preserved `root` |
| `Path.IsPathRooted("C:relative")` | `true` |
| `Path.IsPathFullyQualified("C:relative")` | `false` |
| `Path.IsPathRooted("\\root-relative")` | `true` |
| `Path.IsPathFullyQualified("\\root-relative")` | `false` |
| `Path.TrimEndingDirectorySeparator("C:\\")` | Preserved the filesystem root separator |

Changing `Environment.CurrentDirectory` between two existing directories changed
the result of `Path.GetFullPath("child.txt")`. The ordinary relative input
`child.txt` resolved under the explicit base both times when passed to
`Path.GetFullPath(path, basePath)`, and a relative `basePath` threw
`ArgumentException`.

The explicit-base overload is deterministic but is not a containment primitive.
With base `N:\trusted\root`, the measured Windows results were:

| Input | Result |
| --- | --- |
| `N:child.txt` | `N:\trusted\root\child.txt` |
| `C:child.txt` | `C:\child.txt` |
| `\child.txt` | `N:\child.txt` |
| `child.txt` | `N:\trusted\root\child.txt` |

The .NET Windows path-format documentation additionally establishes that the
one-argument overload can resolve a drive-relative path from per-drive current
directory state inherited through a hidden environment variable. That ambient
state was not manipulated in the local harness.

---

## 7. Historical verification status

The earlier record reported **18 passed, 3 skipped** on Windows. That count
predates the current suite and is not the result of this review.

That earlier record said the Unix assertions were mirrored as a C# harness under
WSL, rather than executed as Pester, and reported:

```text
19 assertions, all PASS
```

That historical harness result does not execute the current Unix Pester
branches, the new recipe, or its new failure cases. Those need a fresh Linux run.

---

## Open questions

- Whether the Linux figures and new recipes hold on the deployed .NET 10+
  runtime; source inspection is not an executed Linux test.
- macOS execution, including effective access with extended ACLs. Do not infer
  that a matching Unix mode query establishes the same access as on Linux.
- Behavior on non-default filesystems: ReFS, network shares, and container
  overlay filesystems were not exercised.
- Service identities were not measured. `GetTempPath2` can honor a `SystemTemp`
  override for SYSTEM; other identities use a different environment search
  order. Containers can supply a shared, missing, or read-only temp path.
