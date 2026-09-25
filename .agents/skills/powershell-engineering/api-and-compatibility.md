# Design stable PowerShell APIs

Read this before changing a parameterized script, exported function, supported
runtime, output shape, stream behavior, or exit code. Compatibility is an
observable consumer contract, not an implementation-detail judgment.

## Name the contract

Identify the entry point and its consumers before editing. Public boundaries
include scripts called by people or automation, exported module commands,
generated wrappers, and child-process protocols.

| Surface | Contract to record | Independent evidence |
| --- | --- | --- |
| Invocation | Command name, parameters, aliases, types, parameter sets, mandatory status, position, pipeline binding, validation, and defaults | PowerShell AST plus command metadata on a supported host |
| Results | Output types, properties, cardinality, ordering when promised, and success-stream content | Public invocation with contract assertions |
| Failure | Terminating versus non-terminating errors, error identity, non-success streams, and process exit codes | Fresh-process receipts for process-visible behavior |
| Host | Minimum PowerShell and module versions plus intentional platform limits | Minimum-host execution and explicit unsupported-host controls |
| Callers | Source calls, generated consumers, examples, and operator documentation | Caller inventory plus named invocation checks |

Do not snapshot incidental formatting, timing, unordered output, or internal
helpers and call it compatibility evidence. Include a detail only when a
consumer can rely on it or the repository has explicitly promised it.

## Design new entry points

- For new named-only parameterized scripts and advanced functions, use
  `[CmdletBinding(PositionalBinding = $false)]` and omit explicit
  `[Parameter(Position = ...)]` values. Invoke them with named parameters in source
  and examples.
- Validate mandatory paths, enums, numeric bounds, mutually exclusive states, and
  unsupported combinations at the boundary.
- Define pipeline input, wildcard behavior, parameter aliases, and parameter sets
  deliberately. Each becomes compatibility surface once consumers rely on it.
- Define output objects and failure behavior before implementation. Keep human
  display separate from machine-readable output.
- Do not convert a simple private helper into an advanced function solely to apply
  public-command rules. Once a function is advanced, apply the named-only settings
  above explicitly rather than relying on `[CmdletBinding()]` defaults.

## Classify changes before editing

An implementation refactor is compatibility-preserving only when the recorded
invocation, result, failure, and host contracts remain unchanged. Treat these as
breaking or compatibility-sensitive until a contract proves otherwise:

- disabling positional binding on an entry point with positional callers;
- removing or renaming a parameter or alias;
- changing a type, mandatory status, default, position, parameter set, pipeline
  binding, validation rule, or wildcard behavior;
- adding a parameter that makes an abbreviation or parameter set ambiguous;
- changing output type, property names, cardinality, ordering, or stream placement;
- changing terminating behavior, error identity, or process exit codes; or
- raising a PowerShell, module, operating-system, or external-tool floor.

Choose one disposition: preserve the contract, provide and test a transition, or
name an intentional break. Do not describe a behavioral break as cleanup.

## Distinguish floors from locks

A compatibility floor states the oldest supported version. An execution lock
selects one exact version for reproducible repository or CI execution. A portable
core may recommend a floor; the consuming repository owns its exact lock.

- Raising a floor is an explicit compatibility decision.
- An exact test-host lock does not prove compatibility across every permitted host.
- A `ModuleVersion` requirement permits that version or later; a
  `RequiredVersion` requirement selects exactly one version.
- Test the minimum supported host separately from the repository's locked host when
  those versions differ.

## Migration workflow

1. Inventory entry points, callers, generated consumers, examples, and supported
   hosts.
2. Record accepted, rejected, and deferred forms for invocation, results, failure,
   and host behavior.
3. Capture the current contract with AST or command metadata and fresh-process
   receipts where streams or exit codes matter.
4. Add the smallest failing control for the proposed change. Include a negative
   control that would catch a silent default, schema, or exit-code change.
5. Decide whether to preserve, transition, or break. State the decision before
   changing implementation or callers.
6. Implement the smallest change and update every affected named invocation,
   generated consumer, example, and migration note.
7. Run focused contract tests, the minimum-host lane, and the repository's broader
   gate. Report which supported hosts actually ran.

Stop when the current contract or caller inventory is unknown. Resolve that gap
instead of guessing from implementation shape or accepting a green current-host
test as compatibility proof.
