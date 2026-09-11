# Integrate a skill into an existing repository

Detail for the [manage-skills](SKILL.md) skill. Use after selecting and reviewing
a candidate, but before writing a project-scope copy into an existing repository.
The goal is to preserve useful local knowledge, avoid competing instructions,
and choose the smallest integration mechanism that makes the portable core work.

This gate is mandatory for project-scope vendoring into an existing repository.
It does not apply to user-scope installation, and an empty greenfield scaffold
uses its scaffold workflow to generate initial bindings. For a bulk install,
build one shared repository inventory, then classify its evidence separately for
each candidate skill.

## 1. Build a candidate lens

Read the reviewed candidate and extract the concepts that can reveal a local
implementation or binding:

- trigger phrases, outcomes, and adjacent workflow boundaries;
- tools, project types, commands, files, and domain terms;
- paths, project names, policies, and prerequisites the portable core leaves
  abstract; and
- required and related skills that may already exist under another name.

Do not search only for the skill name. A differently named local skill or an
instruction-file section may already own the same outcome.

## 2. Choose the integration mechanism

Choose how repository behavior reaches the portable core before writing either form.

Use an **overlay** when local policy specializes the core and must apply whenever the
core is selected. The mandatory loader provides reverse discovery from the shared core
to repository policy and keeps one skill identity. Count both files in initial context
because the workflow unconditionally requires reading the overlay. Keep it to direct
bindings and routing; put repository-only documentation and tools with their owning area
and link to them.

Use a **composing repository skill** when the local workflow has a distinct trigger or
outcome. Verify both directions before choosing it:

1. The repository skill can reliably load the intended shared skill and version in every
   target host and remote environment.
2. Selecting the shared skill directly cannot bypass required repository policy. Use a
   host-supported dependency/extension mechanism or repository instructions that provide
   this reverse route; a local skill that merely names the core is not enough.

If the reverse route or dependency availability cannot be verified, use an overlay or
stop and report the discovery gap.

## 3. Search the repository before writing

Search in this order, stopping when the evidence is sufficient to classify the
candidate without dumping an unrelated repository-wide result set:

1. Inspect every active project skill root, existing `SKILL.md` and `overlay.md`
   file, and local skill catalog for the same name, equivalent outcomes,
   neighboring triggers, and existing bindings.
2. Inspect the canonical `AGENTS.md`, then applicable `*.instructions.md`,
   `*.prompt.md`, and `*.agent.md` files. Treat a generated Copilot instruction
   mirror as the same evidence as its source; do not count or edit it separately.
3. Search the top-level README, contribution guidance, and relevant files under
   `docs/` for the candidate concepts and repository-specific commands, paths,
   policies, examples, and prerequisites.
4. Follow relevant references into configuration, build, source, and test files
   only when they can confirm a concrete binding or show who owns the workflow.

Honor repository search exclusions. Ignore dependency caches, generated output,
build artifacts, and vendored third-party trees unless repository guidance names
one as the canonical source. For each useful hit, retain its path or section, a
short evidence summary, and why it affects this candidate.

If required repository surfaces cannot be inspected, stop and report the gap.
Do not claim that overlap was checked or that integration is complete.

## 4. Classify every useful finding

| Classification | Test | Disposition |
| --- | --- | --- |
| **Repository specialization** | Local policy specializes the core. | Put concise policy in the selected mechanism; link canonical guidance. |
| **Adjacent workflow** | A local workflow owns a distinct outcome. | Keep both; define routing and reverse discovery. |
| **Duplicate guidance** | Two surfaces prescribe materially the same outcome or rule. | Identify the best canonical owner and offer consolidation; do not change either surface yet. |
| **Conflict** | Existing guidance and the candidate prescribe incompatible actions, ownership, permissions, or stop conditions. | Block installation until the user chooses the intended rule and owner. |
| **Portable gap** | The evidence reveals a change every consumer of the core would need. | Keep it out of the overlay and follow the common-change path in [update.md](update.md). |
| **Unrelated** | A keyword matched, but the evidence does not affect invocation, execution, or repository binding. | Exclude it from the overlay and deduplication proposal. |

An existing skill with equivalent outcomes is not made safe by using a different
name. Prefer updating, reconciling, or extending the existing owner over adding a
second implementation.

## 5. Present the integration decision

Before installation, report the material findings and rejected false positives
in a compact table:

| Existing source | Classification | Proposed owner | Proposed action |
| --- | --- | --- | --- |
| `<path>` | specialization/adjacent/duplicate/conflict/portable gap/unrelated | `<owner>` | `<overlay/compose/consolidate/exclude/stop>` |

Label every rejected keyword or concept match explicitly as **Unrelated** and
state why it does not affect invocation, execution, or repository binding. Do
not rely on a "rejected false positives" heading or an explanation alone to
communicate that classification.

Then show the selected integration mechanism, its discovery path, the proposed overlay
entries or composing-skill policy and routing, and any deduplication changes separately.
For an overlay, report the combined core-plus-overlay initial context size. For a
composing skill, report how both invocation directions and dependency availability were
verified.

A request to install or vendor a skill authorizes the new pinned copy and accepted
integration files. It does not authorize editing or deleting existing skills,
documentation, instructions, prompts, or agents. Obtain explicit approval for the
named consolidation edits even when the duplication appears exact.

Whenever duplicate, adjacent, or conflicting guidance could remain after the
current decision, ask a direct question in this response: **"Do you want to
record this overlap or its disposition?"** Offer an overlay boundary, catalog
note, issue, or repository-specific ledger as examples, and state that the
default is no persistent record. Do not defer the question until after the user
chooses a canonical owner or declines consolidation. Do not create a report,
ledger, issue, marker, or note unless the user requests it. The current
interaction still reports the overlap and the resulting residual routing risk.

Stop before writing when:

- a conflict or ambiguous workflow owner remains unresolved;
- the selected integration mechanism has an unresolved dependency or reverse-discovery path;
- a same-name installation conflict remains unresolved under
  [install.md](install.md);
- required repository surfaces could not be inspected; or
- the proposed integration would copy portable rules or duplicate a canonical local rule instead of linking to its owner.

## 6. Install and verify

After the integration decision is resolved:

1. install the unchanged pinned core and its complete requirement closure;
2. write only accepted overlay entries or composing-skill policy and routing;
3. apply consolidation edits only when separately approved, changing the
   canonical source rather than a generated mirror;
4. run the semantic review in [review.md](review.md), including one request on
   each side of every retained routing boundary; and
5. run `agent-files-review` and the repository's local validation.

Report the repository surfaces searched, accepted repository policy and routing,
overlap and conflict dispositions, integration mechanism and reverse-discovery evidence,
separately approved consolidation edits, whether the user requested any persistent
overlap record, validation evidence, and residual risk.
