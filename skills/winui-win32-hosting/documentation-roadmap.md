# Documentation roadmap

Use this page to turn investigation results into durable technical documentation.
The current information is fragmented across API reference, deployment articles,
WinUI design notes, samples, and source. The missing artifact is an end-to-end,
versioned .NET Win32 hosting guide that connects those layers and proves its code.

## Documentation principles

Each document must:

- name the Windows App SDK version range and deployment model it covers;
- distinguish supported API, source-observed behavior, measured behavior, and
  future design;
- include a minimal compilable sample or link to a build-tested sample;
- state object, thread, HWND, coordinate-space, and cleanup ownership;
- include common failure signatures and the cheapest discriminating check;
- list automated and manual validation, including architectures not tested;
- link to exact official sources and pin implementation claims to commits;
- avoid absolute guarantees unless the invariant is stated and tested.

## Priority 0: make first hosting successful

### End-to-end .NET Win32 host walkthrough

**Gap:** Existing material provides API pages and a C++ sample, but not one concise
code-only .NET walkthrough for an existing Win32 message loop.

**Content:** Project file, manifest, unpackaged bootstrap, STA entry point,
`DispatcherQueueController`, custom `Application`, metadata/resources,
`WindowsXamlManager`, HWND creation, `DesktopWindowXamlSource`, site-bridge sizing,
pretranslation, focus, disposal, and queue shutdown.

**Acceptance:** The published sample builds from CLI for x64 and ARM64, runs on a
clean machine, accepts keyboard/pointer input, resizes, and exits cleanly.

### Host topology and ownership state machine

**Gap:** API reference does not show parent HWND, wrapper HWND, site-bridge HWND,
`DesktopWindowXamlSource`, `DesktopChildSiteBridge`, `ContentIsland`, `XamlRoot`,
queue, and `Application` ownership together.

**Content:** A diagram plus initialization, normal close, parent destruction,
partial-construction rollback, dispatcher shutdown, and reparenting state machines.

**Acceptance:** Every arrow names ownership, thread, unit/origin, and disposal
responsibility; tests cover every terminal state.

### Message and focus routing cookbook

**Gap:** `ContentPreTranslateMessage`, native dialog navigation, `NavigateFocus`,
`TakeFocusRequested`, correlation IDs, and reverse traversal are documented in
different places.

**Content:** Message-loop ordering; Tab/Shift+Tab algorithm; multiple islands;
WebView2/hosted HWND considerations; inactive top-level windows; focus-loop
prevention.

**Acceptance:** Automated traversal crosses native-before, several XAML stops,
and native-after in both directions without changing activation unexpectedly.

### DPI and coordinate-space cookbook

**Gap:** No single guide maps physical screen pixels, parent-client pixels,
site-bridge coordinates, XAML effective pixels, element-relative points, and
composition offsets.

**Content:** Conversion formulas, origins, `RasterizationScale`, Per-Monitor V2,
negative coordinates, `WM_DPICHANGED`, popup position, OLE points, and diagrams.

**Acceptance:** A matrix covers 100%, 125%, 150%, 200%, and 300% where hardware or
virtual displays allow, in both monitor directions.

## Priority 1: make the host production-ready

### Metadata and resource composition

Document one process `Application`, generated and manual `IXamlMetadataProvider`
registration, `XamlControlsResources`, library dictionaries, collision precedence,
and failure diagnosis. Include two libraries with intentional type and resource
collisions.

### Popup, airspace, and z-order

Document `XamlRoot` assignment, work-area constraints, site-bridge child HWNDs,
native sibling z-order, clipping, negative positions, popup bridges, and why XAML
`ZIndex` cannot order separate HWNDs. Back it with screenshot pixel oracles.

### Accessibility across the island boundary

Document the native/XAML UIA fragment relationship, names, runtime IDs, patterns,
focus, HWND validation, bounded capture, and required manual High Contrast,
Narrator, text-scale, and magnifier checks.

### Deployment and clean-machine operations

Document packaged, external-location, and unpackaged paths; bootstrap error UX;
runtime installer chaining; VCRedist; `.winmd`; architecture matrix; servicing;
repair/uninstall; enterprise provisioning; and diagnostics when Visual Studio hides
missing deployment steps.

### Testing and diagnostics runbook

Document the raw oracle, subprocess scenario protocol, timeout/process-tree cleanup,
structured lifecycle events, artifact retention, WinDbg breakpoints, source lookup,
UIA/screenshot capture, and a failure-signature decision table.

## Priority 2: advanced interop

### Mixed OLE and XAML drag/drop

**Gap:** The supported XAML and OLE contracts are known, but there is no
end-to-end implementation guide validated across native and WinUI text sources
and targets.

Document XAML's routed drag layer versus `DragDropManager`, system/OLE
interoperability, nested-loop behavior, site-bridge target registration, data-object
ownership, source UI limitations, editable-text move transactions, caret rendering,
and reparent/shutdown cleanup. Publish a prescriptive implementation recipe only
after automated and manual behavior is stable across native and WinUI sources and
targets.

### Island-scoped pointer and cursor behavior

Document `InputPointerSource`, `ContentIsland` availability, class-handled routed
events, capture transfer, pointer IDs, cursor lifetime, touch/pen differences, and
Loaded/Unloaded rebinding.

### Windowless island migration watch

Track stable metadata and release notes for `XamlIsland`, `ChildSiteLink`, and
windowless composition. Keep this separate from the shipped
`DesktopWindowXamlSource` guide until the replacement path is stable and has a
complete HWND-host migration story.

## Authoring sequence

1. Freeze a minimal raw sample and integration harness as executable truth.
2. Write the Priority 0 documents from that sample.
3. Add code extraction tests so snippets compile against the declared package.
4. Run the architecture, DPI, focus, deployment, and shutdown matrices.
5. Publish repository-local docs and gather user failure reports.
6. File focused upstream documentation issues for gaps in Microsoft Learn or
   samples, linking reproducible evidence.
7. Propose upstream documentation contributions only with explicit repository and
   publishing approval.
8. Add Priority 1 and Priority 2 pages as their validation gates become real.
9. Review every Windows App SDK upgrade for stale screenshots, properties,
   package names, source paths, and future/stable API boundaries.

## Document template

Use this shape for each page:

```markdown
# Scenario name

## Applies to

- Windows App SDK version/channel
- .NET and Windows minimum
- Packaged/unpackaged
- Architectures tested

## Topology and ownership

## Minimal implementation

## Lifecycle and cleanup

## Input and coordinate spaces

## Failure signatures

## Validation matrix

## Sources

## Known gaps
```

## Tracking table

Keep a repository-local table with these columns:

| Document | Priority | Owner | Evidence sample | Automated gate | Manual matrix | Upstream destination | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |

Do not mark a document complete because prose exists. Mark it complete when its
sample, cited package version, tests, clean-machine path, and declared manual checks
are current.
