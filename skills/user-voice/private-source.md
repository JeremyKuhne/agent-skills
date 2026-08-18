# Private source and installation

## Local-only source

Default to an OS-local private maintenance root outside Git worktrees,
synchronized folders, network shares, reparse points, project or plugin skill
roots, and unapproved backup or indexing surfaces. Keep the consent ledger,
de-identified cards, audits, and evaluations there. Put the generated runtime
package in a dedicated child directory so installation copies only that package.
Run `New-UserVoiceProfile.ps1` without `-PrivateGitHubSource` for this path.

## Verified private GitHub

A dedicated private GitHub repository is permitted after the user accepts its
collaborators, administrators, integrations, backups, and residual visibility
risk. `PRIVATE` is a condition verified at each operation, not a permanent
guarantee. Local-only source remains lower exposure.
Pass `-PrivateGitHubSource` only after that decision; the scaffold then verifies
every reachable object and current GitHub visibility before writing.

Prepare and audit locally. Hand repository creation and push to `manage-skills`:

1. Scan the proposed tree and every reachable object in existing history.
2. Obtain creation approval naming owner, repository, collaborators, source
   root, and an explicit `--private` command. Creation authorizes no push.
3. Create without `--push`; query GitHub and require exactly `PRIVATE`.
4. Inspect owner, remotes, collaborators, applications, Actions, Pages,
   releases, packages, and forking policy. Disable unused surfaces where the
   account permits.
5. Before asking to commit, explain in plain language what behavior changes,
   which kinds of writing become ready or remain off, what evidence supports
   the change, any material loss or unresolved gap, and what the commit does
   not authorize. Then link the exact staged manifest and hashes, name the
   author, message, and command, and obtain approval for that local commit only.
   A file list, hash table, version label, or command is audit detail; none is a
   useful substitute for the change explanation.
6. After the commit, obtain a separate push approval naming the private
   destination, branch, exact commit, and push command. Explain that pushing
   copies the reviewed private history to that destination and identify any
   exposure boundary that changes. Commit approval never authorizes a push.
7. Before every push, run the repository scanner directly and verify the
   reviewed pre-push hook is enabled, present, executable, and self-tested.
8. Re-query visibility before every later push, install, update, export, or
   migration. Cached private state is not evidence.

The workflow must refuse public, internal, wrong-owner, or unverifiable
destinations. A repository hook is defense in depth; it cannot constrain a user
or tool that bypasses the workflow.

Generated private-source defenses should ignore raw exports, transcripts,
prompts, scratch, model output, evaluation artifacts, credentials, and backups;
scan ignored files during local audit; run privacy checks in private CI; and
publish no releases, packages, Pages, issue attachments, or Actions artifacts
containing the profile.

## Exposure response

If visibility becomes public, internal, or unverifiable, stop reads, installs,
updates, pushes, and profile use. Tell the user exposure may already have
occurred. With fresh approval, make the repository private or delete it, inspect
forks and every secondary surface, rotate any credential, rebuild from a
scrubbed export when history was affected, and obtain a user decision before
restoring use. Returning to private does not retract prior disclosure.

## Install and retire

Use the private complete-directory copy in `manage-skills` for a documented
personal root. Do not use project scope, a neutral shared root without explicit
multi-host approval, a source-directory registration, symlink, or
`gh skill --from-local` provenance that exposes a local path.

Retirement inventories canonical source, registered roots, copied installs,
aliases, backups, and every host first. Remove only approved targets, verify
absence through each host, and apply the user's retention decision to the
private maintenance root.

## Move to another machine

Generate a private, reviewed guide from
[assets/setup-windows.md.tmpl](assets/setup-windows.md.tmpl) or
[assets/setup-posix.md.tmpl](assets/setup-posix.md.tmpl). Resolve every token;
do not store a generated guide in the public core. Name the client, source
method, exact checked source version, sign-in boundary, installer with privacy
and rollback checks, actual install folder, check command, and reload step.

Use `scripts/New-UserVoiceSetupGuide.ps1` to resolve the selected template. The
generator accepts only a full commit for private GitHub or a reviewed manifest
SHA-256 for local transfer, emits commands for review, and performs no clone,
copy, authentication, installation, or remote action.

Support only:

- cloning a currently verified private GitHub source at the exact checked version; or
- a user-approved secure local transfer with a reviewed manifest and hashes.

The destination machine repeats source visibility, repository scan, installer,
manifest, hash, and host-discovery checks. Authentication occurs in the
provider's own interface; never place credentials in the guide. A local install
does not reach cloud agents, code review, or another remote session.

## Record the finished version

Record the draft, reviewed main copy, installed copy, and rollback versions plus
the exact source and installed file lists. Replace the active copy only after
the exact draft is approved and installation is separately authorized.
Verify one active profile after replacement. A rollback restores the last
verified package; it never activates legacy and current profiles together.

After an approved install or rollback, run
`scripts/Test-UserVoiceInstallation.ps1` against the reviewed source and
installed directories with every applicable discovery root and
`-RequireSingleActiveProfile`. Manifest, hash, runtime validation, or duplicate
discovery failure blocks completion.

Report the user-facing profile version and next review trigger. Keep schema IDs,
commit hashes, and filesystem detail in advanced audit output unless they change
the user's decision.
