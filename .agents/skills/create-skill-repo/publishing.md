# Publish the repository

Publication is a separate phase after the local scaffold and its selected
validation pass. A local creation request does not authorize this phase.

## Prepare

Run the required writing workflow in pre-publication mode over the exact
repository description, README, governance text, commit message, and remote
checklist. Re-run it when generated content or validation evidence changes.

Present exact proposed actions for review:

1. Initialize and commit locally, if not already selected and completed.
2. Create the private or public GitHub repository with the confirmed owner,
   name, description, visibility, and source directory.
3. Push the confirmed default branch.
4. Apply approved rulesets, security settings, and dependency-update settings.
5. Publish a release, plugin, or marketplace entry only when that surface was
   selected and separately approved.

Wait for an explicit publishing verb before step 2 and do not infer approval
for later settings or distribution from approval to create the repository.

## Visibility checks

- For local-only output, offer publication as a future choice; do not invent an
  owner, URL, or install command.
- For a private repository, verify private visibility after creation before
  pushing private source references or documenting private consumption.
- For a public repository, verify the license, README, contribution and
  security text, source provenance, and absence of private upstream URLs before
  creation or push.

## Report

State which remote actions ran, their observed results, and which remain
pending. Do not equate repository creation with branch protection, release
publication, marketplace availability, or client installation.
