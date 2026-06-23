# Agent personas

Portable agent personas (`*.agent.md`) shared across the consuming repositories -
read-only roles that cite the repo's own instructions and skills rather than
restating rules. A persona shared here must be portable: it references owning
skills/instructions by role, not by a specific repo's paths, so each consuming
repo's overlay can point it at the right local files.

| Persona | Role | Pairs with |
| ------- | ---- | ---------- |
| [engineering-baseline-reviewer](./engineering-baseline-reviewer.agent.md) | Read-only reviewer that scores a repository against the engineering baseline and returns a risk-ordered gap report; never edits or runs remote actions. | the `engineering-baseline` skill (its assess verb) |
| [pr-self-reviewer](./pr-self-reviewer.agent.md) | Read-only reviewer that reviews the working diff before a PR for correctness, parser/format, security/CI, and doc-vs-spec issues and returns triaged findings; never edits or runs remote actions. | the `pre-pr-self-review` and `security-review` skills |

More personas are added alongside the skills they pair with.
