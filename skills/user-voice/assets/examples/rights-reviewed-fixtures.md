# Rights-reviewed user voice evaluation fixtures

- rights-basis: original synthetic text authored for this repository
- license: repository MIT license
- third-party-excerpt: none
- voice-evidence: no

These fixtures demonstrate grounding, condition comparison, impact scoring, and
no-churn mechanics. They do not establish how any user writes and must not enter
a profile or nuance matrix as evidence.

## fixture-001: Supportability decision

- artifact: short technical recommendation
- verified-facts: One option works across the required range. Another can work
  in a narrower range but is unsupported elsewhere. The first is reversible;
  the second is not.
- authority: No ownership, commitment, or publication permission is supplied.
- conditions: Generate general-writing and candidate-profile outputs from the
  identical brief; blind and counterbalance them.
- checks: Preserve possibility versus supportability, reversibility, and the
  absence of authority. Attribute any preference win to a mapped rule.

## fixture-002: Unknown regression

- artifact: technical correction
- verified-facts: Current behavior is observed. No prior-version comparison or
  history is available.
- authority: No owner, fix plan, date, or remote action is supplied.
- conditions: Generate general-writing and candidate-profile outputs from the
  identical brief.
- checks: Neither condition may call the behavior a regression. A hard-gate
  failure excludes the case from voice preference scoring.

## fixture-003: Exact no-churn control

- artifact: compact coordination note
- verified-facts: One required test result remains unknown. No next action is
  authorized.
- authority: Local drafting only.
- conditions: Use an input for which both conditions intentionally return the
  same complete text.
- checks: Compare bytes after the declared newline normalization. Record exact
  identity mechanically and do not ask the user to rate the case.
