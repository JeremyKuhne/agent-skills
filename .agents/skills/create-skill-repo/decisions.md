# Decide the repository shape

Resolve decisions in small conditional batches. Do not ask the whole interview
at once. Reuse facts already supplied by the user, explain material defaults,
and summarize each batch before advancing.

## 1. Explain the process

Assume the user has not worked with Agent Skills before. Before asking about
repository shape, explain these points in plain language:

- A skill is a directory of instructions and optional scripts or templates that
  an AI coding agent can load for a particular task.
- A source repository keeps the original, editable skill directories. Those
  skills can later be shared directly from GitHub or packaged through a selected
  distribution surface.
- A repository that uses someone else's skills normally stores pinned copies in
  a client discovery directory. A pinned copy records a specific version so an
  upstream change does not silently alter the repository's agent behavior. This
  process is called vendoring.
- One repository can both publish its own skills and vendor operational skills
  used to maintain them. The workflow creates the selected folders, guidance,
  validation, and optional automation; it does not publish anything remotely
  without a later approval.

Use technical terms such as **source**, **consumer**, **hybrid**, **vendored**,
and **pin** only after explaining their practical meaning. Do not assume the
user knows Agent Skills discovery paths, plugins, marketplaces, or releases.

## 2. Name and intended use

Collect the repository name and one-line purpose before asking for its location.
Ask how the repository will be used with choices phrased by outcome:

- **Author and share skills (source)** - keep the original editable skills here
  so they can be maintained and optionally published for other repositories.
- **Use existing skills (consumer)** - keep version-pinned copies of skills from
  other sources so agents working in this repository can discover them.
- **Do both (hybrid, recommended for most skill teams)** - author original skills
  and also keep pinned operational skills used to review, test, and publish them.

Recommend hybrid when maintainers will author shared skills and use skills to
maintain the repository. Explain why the recommendation fits before asking the
user to choose; do not ask only "What role should the repository have?"

## 3. Destination

After the name is known, derive a destination from the current repository rather
than asking the user to type a path. Use the current repository's parent
directory joined with the new repository name. For example, from
`N:\repos\agent-skills` and the name `team-skills`, offer:

- **Use `N:\repos\team-skills` (recommended)** - create the new repository next
  to the current one.
- **Choose another folder** - ask for a path only after this choice is selected.

Preselect or clearly mark the computed sibling path as recommended. Resolve and
show its absolute path before writing, require an empty destination, and reject
nesting inside the current repository unless the user explicitly selects it.
Do not lead with "Enter an absolute path."

## 4. Audience, clients, and visibility

Explain that the audience controls documentation and collaboration defaults,
while clients are the AI coding tools expected to discover the installed skill
copies. Collect the audience: one person, team, organization, or public
ecosystem. Collect each required client: GitHub Copilot, Claude Code, Codex,
Gemini CLI, Cursor, or an explicit combination. State that the scaffold creates
only the discovery directories used by the selected clients; selecting a client
does not install that application. Select only documented discovery roots and
record any client that cannot be runtime-verified.

Explain visibility choices before asking:

- **Local only** - create files on this machine with no GitHub repository or
  remote installation instructions.
- **Private GitHub** - prepare for authenticated access by selected people or an
  organization; the later publication step creates the remote only after
  approval.
- **Public GitHub** - prepare documentation, licensing, and installation for
  anyone who can access GitHub; publication still requires later approval.

For a remote repository, collect owner, license, default branch, and desired
governance files. This choice plans publication; it does not approve a remote
action.

## 5. Starter skill sets

Explain that starter skills are optional, version-pinned tools the new
repository will use for its own maintenance. They are installed copies, not the
new skills the repository will author. Some selected skills require supporting
skills; show those additions before writing. Present purpose-based
recommendations. Sets are not indivisible bundles.

| Set | When it applies | Skills |
| --- | --- | --- |
| **Skill repository operations** | Authoring, vendoring, validating, or documenting skills. Recommend for source and hybrid repositories; offer a reduced selection to consumers. | `manage-skills`, `agent-files-review`, `technical-writing` |
| **Change quality** | Reviewing code, scripts, templates, and documentation. Recommend for executable helpers or contributed changes. | `security-review`, `code-comprehension`, `pre-pr-self-review` |
| **GitHub collaboration** | Maintaining changes through GitHub pull requests. Recommend for GitHub-hosted team, organization, and public repositories. | `create-pr`, `address-pr-feedback` |
| **CI stewardship** | Measuring and improving selected GitHub Actions infrastructure beyond generated validation. | `github-actions-cost-optimization` |

Allow complete sets, individual skills, or none. Distinguish direct selections
from skills added through `metadata.requires`, and resolve the complete closure
at one immutable pin. Do not add domain skills silently. Selecting CI does not
implicitly select CI stewardship.

## 6. Upstream source policy

Explain that this choice does not search for or install anything during
scaffolding. It creates a durable policy in the new repository. Later, when a
maintainer asks an agent to find, add, or update a skill, the agent will:

1. Check copies already available to the project or user.
2. Search each configured repository or catalog in the saved order.
3. Identify the source of each relevant candidate and compare applicability,
   trust, and version information before recommending one.
4. Review the selected candidate and pin an exact version before installation.

The order decides where discovery looks first and which source is preferred
when equivalent candidates exist. It does not make an earlier source trusted,
automatically choose the first name match, install anything, or override the
security review and explicit installation decision.

Present the concrete policy rather than asking only "Use the default upstream
search order?" Offer these choices:

- **Use the recommended search order** - prefer skills already available
  locally, then skills authored in the new repository, then approved private or
  organization catalogs, then `JeremyKuhne/agent-skills`, and finally search
  untrusted public catalogs when no suitable reviewed candidate has been found.
- **Customize where skills are found** - add, remove, or reorder repositories
  and catalogs, marking any private sources so they cannot leak into public
  output.

Use this recommended order unless the user customizes it:

1. Active local project and user installations.
2. The new repository's source skills, for source or hybrid roles.
3. User-selected organization or private catalogs.
4. `JeremyKuhne/agent-skills` as the default commons.
5. Public catalogs as an untrusted fallback.

Allow reordering, additions, or explicit removal of the default commons. Apply
the skill-lifecycle security gate and immutable pinning to public candidates.
Record the selected order and trust policy in the generated README and the
`manage-skills` overlay. Do not expose a private source URL in public output.

## 7. Infrastructure and distribution

Explain that infrastructure levels control how much maintenance automation is
generated. Higher levels include everything in the levels above them. Offer
cumulative presets, then permit individual changes:

| Level | Included infrastructure |
| --- | --- |
| **Minimal** | Git repository, selected role roots, format guidance, selected license, ignore rules, and tailored README. |
| **Validated** | Minimal plus skill validator, generated catalog, Markdown lint, offline link checks, and repository contract tests. |
| **Team CI** | Validated plus validation and drift workflows, dependency updates, contribution guidance, and selected governance files. |
| **Distribution** | Team CI plus a release workflow and explicitly selected plugin, marketplace, agent, or MCP manifests and smoke tests. |

Behavioral model evaluations are a separate opt-in because they require
credentials, incur cost, and establish different evidence from deterministic
validation.

For source and hybrid roles, explain that a distribution surface is how another
user or tool obtains repository content:

- **Direct pinned install (default)** - install a named skill straight from a
  specific repository tag or commit. This is the simplest publishing model.
- **Copilot plugin** - bundle skills and optional related components for Copilot
  CLI plugin installation.
- **Plugin marketplace entry** - advertise that plugin through a marketplace
  manifest; this is additional metadata, not automatic publication.
- **Custom agents** - distribute selected agent definitions with the plugin.
- **MCP configuration** - distribute selected external tool-server definitions
  with the plugin.

Add only selected surfaces; each adds corresponding manifest validation and
smoke tests. Do not imply that creating a GitHub repository also publishes a
plugin, marketplace entry, release, agent, or MCP server.

## 8. Governance and confirmation

Explain that these choices determine how collaborators contribute, how versions
are named, and how updates are reported. Resolve license, contribution model,
release tags, consumed-skill pinning, drift reporting versus pull requests,
public-source discovery, branch protection expectations, and generated-catalog
enforcement. Default pins to an immutable tag or full commit SHA so installed
behavior cannot move silently, and default drift to a report rather than an
automatically opened pull request.

Before writing, present one compact confirmation containing all resolved
decisions, selected and dependency-added skills, generated files, local
commands, and pending remote actions. Confirmation authorizes only local
scaffolding.
