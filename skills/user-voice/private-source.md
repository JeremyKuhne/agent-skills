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
5. Obtain a new push approval naming destination, branch, staged file manifest
   and hashes, commit message and author, and push command.
6. Before every push, run the repository scanner directly and verify the
   reviewed pre-push hook is enabled, present, executable, and self-tested.
7. Re-query visibility before every later push, install, update, export, or
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
