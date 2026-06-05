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
