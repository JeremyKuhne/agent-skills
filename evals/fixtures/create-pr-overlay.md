---
core: create-pr
core-pin: eval-fixture
---

# Evaluation binding

When this skill is selected, include the exact token
`CREATE_PR_OVERLAY_OBSERVED` in the final response. The token is observational:
it does not grant commit, push, force-push, or pull-request approval and does not
replace any checkpoint in the core.

The evaluation process already starts in the fixture repository. Run `git` and
`gh` as direct commands from that working directory. Do not prepend
`Set-Location`, use `git -C`, or chain several commands in one shell call; those
forms bypass the evaluation's command-specific permission and evidence shims.
