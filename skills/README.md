# Skills (the commons catalog)

The shared, portable skill cores live here, one directory per skill, each with a
`SKILL.md` plus optional siblings / `references/` / `assets/`. See
[FORMAT.md](../FORMAT.md) for the format and the portable-core rules.

This is the layout the `gh skill` publisher discovers (`skills/<name>/SKILL.md`).
A consuming repository vendors a copy into its own `.agents/skills/` (the
host-read location) with `gh skill install`.

| Skill | Trigger phrasing | Notes |
| ----- | ---------------- | ----- |
| [security-review](./security-review/SKILL.md) | "assess for security vulnerabilities", "do a security review", "check for ReDoS / DoS", "audit untrusted input handling"; any member taking caller-supplied data; any `unsafe` / `Unsafe.*` / `MemoryMarshal.*` / `Marshal.*` use | Portable. Consuming repos add their own cross-references and example links in an overlay. |
| [scratch-buffer-strategy](./scratch-buffer-strategy/SKILL.md) | choosing a scratch-buffer strategy (zeroed `stackalloc` vs `[SkipLocalsInit]` vs `BufferScope<T>` vs `ArrayPool` rental), "should I rent or stackalloc?", net481/net10 size crossovers | Semi-portable. Bundles `references/arraypool-performance.md` (the measured net481/net10 backing data). Consuming repos add cross-references in an overlay. |
| [manage-skills](./manage-skills/SKILL.md) | "find a skill for X", "build a skill" / "create a skill", "update the skill", reconcile a local skill change against the commons vs a repo overlay | Portable. Sibling pages `find.md` / `build.md` / `update.md`. The skill-lifecycle meta-skill; pairs with `agent-files-review`. |
| [dotnet-polyfills](./dotnet-polyfills/SKILL.md) | "use a modern .NET API on .NET Framework", setting up PolySharp or the official downlevel packages (`System.Memory`, `Microsoft.Bcl.*`), "which package supplies this type downlevel", "is this already polyfilled" | Semi-portable. Bundles `references/packages.md` (the official package catalog). Names the `KlutzyNinja.Touki` package as an additive source. For *authoring* a hand-rolled polyfill, that is the repo-local `polyfill-dotnet-api`. |
| [il-copy-inspection](./il-copy-inspection/SKILL.md) | "find struct copies", "is this a defensive copy", "check for boxing in IL", "did the compiler emit a copy here", "audit a `[NonCopyable]` type after build" | Semi-portable. Bundles `references/copy-opcodes.md` (the IL copy-opcode catalog). The post-build, ground-truth counterpart to a source-level defensive-copy analyzer. |
