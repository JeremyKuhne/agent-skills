# Repository agent guidance

`.github/copilot-instructions.md` is a generated mirror of this file. Edit this
file and regenerate the mirror rather than changing both.

## Shipping

Validate release candidates with `./tools/Test-Shipping.ps1`. Publishing is a
separate approval boundary and uses `./tools/Publish-Widget.ps1` only after the
shipping checklist passes.
