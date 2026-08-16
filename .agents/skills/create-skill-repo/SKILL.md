---
name: create-skill-repo
description: Create or scaffold a new repository for authoring, vendoring, validating, and distributing Agent Skills. Use when asked to "create a skill repo", "create a skills repository", "set up a team skill commons", or initialize a local, private, or public repository whose primary product is Agent Skills. Guides repository identity, location, role, clients, starter skill sets, upstream sources, infrastructure, distribution, and publication decisions. For creating one skill inside an existing repository, use the skill-lifecycle workflow instead.
license: MIT
compatibility: Local scaffolding requires PowerShell 7.2 and git. Validated tiers use Node.js with npx for pinned Markdown lint and Pester 5 or later. Vendoring uses GitHub CLI 2.90 or later; remote publication requires authenticated gh.
metadata:
  portability: repo-specific
  applicability: repo-local
  binding: none
  risk: remote-write
  maturity: canary
  requires: manage-skills, technical-writing
  related: engineering-baseline
---

# Create a skill repository

Create a repository whose primary product is Agent Skills without copying an
entire commons by default. Separate canonical source under `skills/` from
pinned runtime copies under `.agents/skills/`, select only the infrastructure
and distribution surfaces the repository needs, and stop at the remote boundary
until the user explicitly approves publication.

Assume the user may be new to Agent Skills. Before presenting choices, explain
what skills are, how original skills are shared, why consuming repositories keep
version-pinned copies, and what this workflow will create. Phrase choices by
what the user wants to accomplish; introduce terms such as source, consumer,
hybrid, vendoring, and distribution only with their practical meaning.

## Workflow

1. Run the staged [decision interview](decisions.md), including its process explanation and computed destination recommendation.
2. Present the resolved path, role, audience, clients, visibility, starter
   skills and dependency closure, upstream order, infrastructure, generated
   tree, local commands, and pending remote actions. Obtain confirmation for
   the local scaffold.
3. Follow [scaffold.md](scaffold.md). Invoke the bundled generator with explicit
   parameters; the script is noninteractive and performs no remote writes.
4. Validate the generated repository using only its checked-in tooling. Run the
   required writing workflow over the generated README after technical facts
   stabilize.
5. If private or public GitHub publication was selected, follow
   [publishing.md](publishing.md). Show exact actions and obtain separate
   approval before creating a remote, committing, pushing, applying settings,
   or publishing a release or marketplace entry.

## Boundaries

- This workflow is specific to the `agent-skills` commons. Keep it under the
  repository's `.agents/skills/` root; do not catalog, publish, or install it as
  a shared core.
- “Create a skill” means discover or author one skill in an existing source and
  belongs to the skill-lifecycle workflow. “Create a skill repo” means create
  the repository system and belongs here.
- A .NET tool or library repository belongs to the engineering repository
  scaffold even when it consumes Agent Skills. Use this workflow when skills
  are the repository's primary product.
- Local scaffold approval does not authorize any GitHub or publication action.
- Never edit a vendored core to bind it to the new repository. Generate or
  revise its overlay and preserve immutable provenance.

## Completion

Report the created role and tree, selected and dependency-added skills, local
validation results, omitted capabilities, and every remote action still
pending. Do not claim support for a client or distribution surface that was not
selected and validated.
