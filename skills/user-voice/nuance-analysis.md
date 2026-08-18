# Analyze source nuance

Run this workflow only on confirmed, de-identified evidence from
[discovery.md](discovery.md) or a validated [handoff.md](handoff.md) report.
Source evidence creates the draft; later interviews refine and validate it.

For a targeted source refresh performed by a source agent, validate the
de-identified return with `scripts/Test-UserVoiceTargetedAnalysis.ps1` before
using any finding. Reject and regenerate a report with identifiers, quotations,
invalid count bands, incomplete retrieval, missing passes, or rule mismatches;
never ask the user to repair it.

## Separate signal from context

Analyze multiple independent sources before naming a durable rule. Vary topic,
artifact, audience, relationship, intent, stakes, length, formality, and era
where the proposed scope requires it. Treat organizational templates,
collaborator edits, translation, AI assistance, source-domain terminology, and
artifact conventions as possible confounds.

For every proposed decision, ask what nearby evidence could disconfirm it. A
stable user choice should survive a change in topic or artifact convention. A
contextual choice should recur within its claimed context and disappear or
change where the matrix predicts.

## Run all seven passes

Every profile and every proposed context receives all seven passes. Record
`not-observed` when evidence is insufficient; never skip a pass or infer a
neutral default.

### 1. Rhetorical and epistemic structure

Record information order, causal explanation, evidence placement, uncertainty,
qualification, disagreement, ownership boundaries, and stopping behavior.
Separate sound argument structure from recurring subject-matter structure.

### 2. Register and relationship

Record changes by audience, relationship, hierarchy, familiarity, formality,
and stakes. Distinguish deliberate warmth, directness, deference, or terseness
from platform etiquette and organizational convention.

### 3. Mechanics

Record distributions and tolerances for sentence and paragraph length,
contractions, punctuation, headings, lists, parentheticals, fragments, and
transitions. Preserve ranges and context shifts rather than a caricatured
signature.

### 4. Interpersonal stance

Record how the writing acknowledges contributions, assigns action, challenges
claims, maintains accountability, and handles uncertainty or conflict. Exclude
blame, competence judgments, motive attribution, sarcasm, and rhetorical
pressure even when observed.

### 5. Lexical behavior

Record stable choices such as concrete versus abstract nouns, verbs of
causality, modal force, technical terminology, intensifiers, and habitual
ceremony. Do not retain distinctive phrases, names, quotations, or topic-bound
vocabulary as voice evidence.

### 6. Artifact patterns

Record conditional structures for reviews, design notes, investigations,
status updates, corrections, and other supported artifacts. Separate personal
choices from fields or layouts imposed by the artifact.

### 7. Conflicts and counterevidence

Record contrary sources, time drift, collaboration effects, unresolved
interpretations, tone hazards, and contexts with insufficient evidence. A
conflict changes scope or confidence unless a discriminating batch resolves it.

## Build the matrix

Create one block per proposed context using
[assets/nuance-matrix.md.tmpl](assets/nuance-matrix.md.tmpl). Use stable opaque
context IDs. Record category-level diversity, count bands, the attained evidence
floor, all seven pass results, gaps, rule mappings, validation mappings, and
approval state.

Use these states:

- `unsupported`: insufficient or rejected; runtime uses general writing;
- `provisional`: source pattern exists but independent validation or approval is
  incomplete; runtime uses general writing; and
- `supported`: evidence, user approval, independent validation, hard gates, and
  genericity control all pass.

Confidence cannot exceed the context state. `Low` and `provisional` remain
fallback-only. `Moderate` requires the moderate evidence floor and independent
preference and impact validation. `Strong` additionally requires the strong
floor, saturation, stable validation, and plateaued edit effort.

## Compile the source-derived draft

Compile only abstract, observable writing decisions. Every draft rule cites at
least one context ID. Preserve distributions, tolerances, conditional behavior,
counterevidence, and unsupported contexts. Keep source identities, excerpts,
exact provenance, topics, current facts, beliefs, relationships, and authority
out of the profile.

The first draft precedes elicitation. Mark uncertainty directly instead of
asking the user to invent a preference. Later cases may test only a pre-existing
draft rule and context; a newly stated preference remains inactive until source
evidence and separate validation support it.

## Check before review

Run the matrix validator, then verify that the draft:

- maps every approved rule to at least one context;
- compiles provisional and unsupported contexts to general-writing fallback;
- retains context-specific rhetorical, mechanical, interpersonal, lexical, and
  artifact variation;
- carries counterevidence and unresolved gaps forward; and
- contains no raw source, identifying provenance, or source-derived authority.

Only then begin section review or controlled elicitation.
