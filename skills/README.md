# Skills (the commons catalog)

The shared, portable skill cores live here, one directory per skill, each with a
`SKILL.md` plus optional siblings / `references/` / `assets/`. See
[FORMAT.md](../FORMAT.md) for the format and the portable-core rules.

This is the layout the `gh skill` publisher discovers (`skills/<name>/SKILL.md`).
A consuming repository vendors a copy into its own `.agents/skills/` (the
host-read location) with `gh skill install`.

| Skill | Trigger phrasing | Notes |
| ----- | ---------------- | ----- |
| [security-review](./security-review/SKILL.md) | "assess for security vulnerabilities", "do a security review", "check for ReDoS / DoS", "audit untrusted input handling"; any member taking caller-supplied data; any `unsafe` / `Unsafe.*` / `MemoryMarshal.*` / `Marshal.*` use | Portable core with an optional overlay for local cross-references and examples. |
| [scratch-buffer-strategy](./scratch-buffer-strategy/SKILL.md) | choosing a scratch-buffer strategy (zeroed `stackalloc` vs `[SkipLocalsInit]` vs `BufferScope<T>` vs `ArrayPool` rental), "should I rent or stackalloc?", net481/net10 size crossovers | Portable core with an optional overlay. Bundles `references/arraypool-performance.md` (the measured net481/net10 backing data). |
| [manage-skills](./manage-skills/SKILL.md) | "find a skill for X", "build a skill" / "create a skill", "review this skill" / "is this skill effective", "update the skill", "retire this skill" / "remove this skill", reconcile a local skill change against the commons vs a repo overlay | Portable core with an optional overlay. Sibling pages cover find, build, semantic review, update, and dependency-first retirement; bundles the strict validator and overlay template, and delegates file correctness to `agent-files-review`. |
| [dotnet-polyfills](./dotnet-polyfills/SKILL.md) | "use a modern .NET API on .NET Framework", setting up PolySharp or the official downlevel packages (`System.Memory`, `Microsoft.Bcl.*`), "which package supplies this type downlevel", "is this already polyfilled" | Portable core with an optional overlay. Bundles `references/packages.md`; names `KlutzyNinja.Touki` as an additive source. |
| [cswin32-interop](./cswin32-interop/SKILL.md) | "replace `[DllImport]` with CsWin32", generated `PInvoke.*` / Win32 types, native ownership and size units, platform / TFM guards, or public owner/extender composition | Portable core with an optional overlay. General P/Invoke layer; required by `cswin32-com`. |
| [cswin32-com](./cswin32-com/SKILL.md) | struct-based COM with `ComScope`, `IID.Get`, raw vtables, activation, `IComIID`, caller-owned CCW references, `Advise` / `Unadvise`, or cross-assembly CCWs | Portable core with an optional overlay. Requires `cswin32-interop` for the shared blittable-signature and P/Invoke rules. |
| [il-copy-inspection](./il-copy-inspection/SKILL.md) | "find struct copies", "is this a defensive copy", "check for boxing in IL", "did the compiler emit a copy here", "audit a `[NonCopyable]` type after build" | Portable core with an optional overlay. Bundles `references/copy-opcodes.md`; post-build counterpart to a source analyzer. |
| [roslyn-analyzers](./roslyn-analyzers/SKILL.md) | "write an analyzer", "create a Roslyn/diagnostic analyzer", "add an analyzer rule", "add a code fix", "enforce a convention at build time", "flag a pattern in code" | Portable core with an optional overlay. Checks existing analyzer suites before authoring and includes design, validation, and performance pages. |
| [fuzz-testing](./fuzz-testing/SKILL.md) | "add a fuzz target", "run the fuzzer", "install the fuzzing prerequisites", "promote a crashing input into a regression test" | Portable core with an optional overlay. Bundles `references/running.md`; requires an existing fuzz harness. |
| [create-pr](./create-pr/SKILL.md) | "make a PR", "prepare a PR", "open a pull request", "push and PR", publish in-progress work for review | Portable core with an optional overlay. Enforces the publish gate and defers exact client tools to `host-adapters.md`. |
| [address-pr-feedback](./address-pr-feedback/SKILL.md) | "address the review", "fix the comments", "address Copilot's feedback", "fix the CI failure", post-PR follow-up | Portable core with an optional overlay. Post-PR counterpart to `create-pr` with the same publish gate. |
| [pre-pr-self-review](./pre-pr-self-review/SKILL.md) | self-review before opening a PR, "review my code change / PR candidate", after a reviewer flags issues that should have been caught | Portable core with an optional overlay. Checklist of recurring multi-targeted-polyfill mistakes. |
| [agent-files-review](./agent-files-review/SKILL.md) | review or validate changes to agent customization files (`AGENTS.md`, `*.instructions.md`, `*.prompt.md`, `*.agent.md`, `SKILL.md`), "fix the agent-files CI failure" | Portable core with an optional overlay. Sibling `frontmatter.md`; pairs with `manage-skills`. |
| [performance-testing](./performance-testing/SKILL.md) | "how long does this take", "how much memory", "where is time spent", "make this faster", add / run BenchmarkDotNet benchmarks, evaluate allocations, profile a hot method | Portable core with an optional overlay. BenchmarkDotNet authoring, bounded optimization investigations, running, and drill-down; requires an existing perf project. |
| [framework-jit-optimization](./framework-jit-optimization/SKILL.md) | optimize a `net481` / .NET Framework hot path, specialize a generic for primitives, diagnose a Framework micro-benchmark regression; the `net10` vectorization / intrinsics counterpart too | Portable core with an optional overlay. Cross-TFM codegen fundamentals; use `performance-testing` for harness mechanics. |
| [engineering-baseline](./engineering-baseline/SKILL.md) | "create a new repository" / "scaffold a CLI tool or library" with CI, packaging, and governance, or "ensure this repo follows modern engineering best practices" / "audit this repository" / "bring this repo up to standard" | Portable core with an optional overlay. Nine-domain assessment plus tested greenfield scaffolding; remote actions require confirmation. |
| [github-actions-cost-optimization](./github-actions-cost-optimization/SKILL.md) | "reduce CI cost / spend / minutes", optimize GitHub Actions triggers, matrices, runners, caches, artifacts, or automatic versus scheduled/manual checks | Portable core with an optional overlay. Models actual and normalized Actions cost without weakening validation; application runtime performance remains `performance-testing`. |
| [code-comprehension](./code-comprehension/SKILL.md) | "review this for readability", "is this too complex", "reduce nesting / cognitive load", "what is a reasonable method length / parameter count / nesting depth", judging whether code will be hard to understand | Portable core with an optional overlay. Bundles research and binds local style in the overlay. |
| [technical-writing](./technical-writing/SKILL.md) | "draft this issue", "rewrite this email", "tighten this explanation", "review this note before publishing"; creating durable human-facing prose; the final text check before a publishing workflow | Portable core with an optional overlay. Draft, revise, review, and pre-publication modes; grounding and authority remain hard gates, and the skill never publishes. |
| [user-voice](./user-voice/SKILL.md) | "capture how I write", "build my voice profile", "hand voice research to another agent", "audit / migrate / install my private voice skill", connect a personal voice profile to technical-writing | Portable lifecycle and privacy workflow. Creates only local private candidates, audits verified private source and user-scope installation, and keeps every personalized profile out of the commons. |
| [winui-win32-hosting](./winui-win32-hosting/SKILL.md) | "host WinUI in Win32", "embed a WinUI control in an HWND", set up or debug `DesktopWindowXamlSource`, XAML Islands, dispatcher/message/focus/DPI/airspace/accessibility/packaging/lifetime integration | Portable core with an optional overlay. Includes a build-tested raw host, four Priority 0 guides, deeper boundary guidance, an official source map, and the remaining documentation roadmap. |

## Routing boundaries

`technical-writing` owns prose whose wording is part of a human-facing
deliverable and the final content check before publication. Use
`code-comprehension` for source-code readability, `agent-files-review` for
customization behavior and file correctness, and `pre-pr-self-review` for code,
test, and diff-to-PR factual checks. When more than one applies, settle the
domain facts and behavior first, then run the prose review. The workflow that
publishes the artifact keeps its own approval gate and remote action.

`user-voice` owns the lifecycle of a private personal profile: consented source
capture, manual data-gathering handoff, de-identification, audit, migration,
private source controls, personal installation, and retirement. It does not
draft ordinary prose. `technical-writing` owns the shared fact, authority,
comprehension, and tone gates and conditionally invokes an installed personal
`user-voice-profile` for attributed first-person realization. The personalized
runtime skill is never a commons core or public dependency.

## Portfolio contract

<!-- portfolio-matrix:start -->
<!-- Generated by tools/Update-SkillCatalog.ps1. Do not edit this block by hand. -->
| Skill | Applicability | Binding | Risk | Maturity | Requires | Related |
| ----- | ------------- | ------- | ---- | -------- | -------- | ------- |
| [address-pr-feedback](./address-pr-feedback/SKILL.md) | `git-github` | `optional-overlay` | `remote-write` | `canary` | `technical-writing` | `create-pr`, `pre-pr-self-review`, `agent-files-review` |
| [agent-files-review](./agent-files-review/SKILL.md) | `agent-customization` | `optional-overlay` | `local-write` | `canary` | - | `manage-skills`, `technical-writing` |
| [code-comprehension](./code-comprehension/SKILL.md) | `universal` | `optional-overlay` | `advisory` | `canary` | - | `pre-pr-self-review` |
| [create-pr](./create-pr/SKILL.md) | `git-github` | `optional-overlay` | `remote-write` | `canary` | `technical-writing` | `pre-pr-self-review`, `address-pr-feedback` |
| [cswin32-com](./cswin32-com/SKILL.md) | `dotnet` | `optional-overlay` | `local-write` | `canary` | `cswin32-interop` | `security-review`, `il-copy-inspection` |
| [cswin32-interop](./cswin32-interop/SKILL.md) | `dotnet` | `optional-overlay` | `local-write` | `canary` | - | `cswin32-com`, `dotnet-polyfills`, `scratch-buffer-strategy`, `security-review` |
| [dotnet-polyfills](./dotnet-polyfills/SKILL.md) | `dotnet-framework` | `optional-overlay` | `local-write` | `canary` | - | `pre-pr-self-review`, `framework-jit-optimization` |
| [engineering-baseline](./engineering-baseline/SKILL.md) | `dotnet` | `optional-overlay` | `remote-write` | `canary` | `technical-writing` | `manage-skills`, `security-review`, `create-pr`, `github-actions-cost-optimization` |
| [framework-jit-optimization](./framework-jit-optimization/SKILL.md) | `dotnet-framework` | `optional-overlay` | `local-write` | `canary` | - | `performance-testing`, `scratch-buffer-strategy`, `pre-pr-self-review` |
| [fuzz-testing](./fuzz-testing/SKILL.md) | `dotnet-project-gated` | `optional-overlay` | `local-write` | `canary` | - | `security-review`, `pre-pr-self-review` |
| [github-actions-cost-optimization](./github-actions-cost-optimization/SKILL.md) | `git-github` | `optional-overlay` | `local-write` | `canary` | - | `engineering-baseline`, `security-review` |
| [il-copy-inspection](./il-copy-inspection/SKILL.md) | `dotnet` | `optional-overlay` | `advisory` | `canary` | - | `roslyn-analyzers`, `framework-jit-optimization`, `performance-testing`, `scratch-buffer-strategy` |
| [manage-skills](./manage-skills/SKILL.md) | `universal` | `optional-overlay` | `remote-write` | `canary` | `agent-files-review`, `technical-writing` | - |
| [performance-testing](./performance-testing/SKILL.md) | `dotnet-project-gated` | `optional-overlay` | `local-write` | `canary` | - | `framework-jit-optimization`, `scratch-buffer-strategy`, `pre-pr-self-review` |
| [pre-pr-self-review](./pre-pr-self-review/SKILL.md) | `universal` | `optional-overlay` | `local-write` | `canary` | - | `create-pr`, `address-pr-feedback`, `security-review`, `performance-testing`, `technical-writing` |
| [roslyn-analyzers](./roslyn-analyzers/SKILL.md) | `dotnet-project-gated` | `optional-overlay` | `local-write` | `canary` | - | `performance-testing`, `security-review`, `pre-pr-self-review`, `il-copy-inspection` |
| [scratch-buffer-strategy](./scratch-buffer-strategy/SKILL.md) | `dotnet-framework` | `optional-overlay` | `advisory` | `canary` | - | `performance-testing`, `framework-jit-optimization` |
| [security-review](./security-review/SKILL.md) | `universal` | `optional-overlay` | `local-write` | `canary` | - | `pre-pr-self-review`, `performance-testing`, `fuzz-testing` |
| [technical-writing](./technical-writing/SKILL.md) | `universal` | `optional-overlay` | `local-write` | `canary` | - | `agent-files-review`, `code-comprehension`, `pre-pr-self-review`, `user-voice` |
| [user-voice](./user-voice/SKILL.md) | `universal` | `none` | `local-write` | `experimental` | `manage-skills` | - |
| [winui-win32-hosting](./winui-win32-hosting/SKILL.md) | `dotnet` | `optional-overlay` | `local-write` | `canary` | - | `cswin32-com`, `cswin32-interop`, `security-review` |
<!-- portfolio-matrix:end -->
