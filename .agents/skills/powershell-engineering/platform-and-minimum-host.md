# Validate supported hosts and platforms

Read this when PowerShell behavior depends on a declared minimum runtime,
operating system, architecture, filesystem, native dependency, or host API.
An exact CI execution lock and one green host are not evidence for every
supported environment.

## Name the supported boundary

Record the minimum PowerShell and test-framework versions separately from
the repository's exact execution locks. Identify which features are portable
and which belong to a particular operating system or architecture. For each
claim, name an observable check and the host that can decide it.

| Claim | Required evidence |
| --- | --- |
| Minimum PowerShell version | Run the public entry point on the minimum supported host, not only a newer locked host or a syntax parser. |
| Test-framework compatibility | Exercise tests under the declared compatible version; an exact CI pin proves only that pin. |
| Filesystem or native behavior | Exercise ACLs, modes, symlinks, path casing, or native loading on each operating system that owns the claimed behavior. |
| Cross-platform result | Compare the same behavior contract and expected results on the named supported hosts, recording skips and unsupported features. |

Treat a missing minimum-host lane as unknown, not as an implicit pass. If the
implementation requires a newer API, replace it, narrow the supported
contract, or explicitly name a compatibility break; do not silently raise
the floor after tests pass on a newer local host.

## Build the smallest host matrix

1. Inventory supported runtime versions, operating systems, architectures,
   native dependencies, and the contract classes they own. Put exact local
   paths, locks, and job names in the consuming repository's overlay.
2. Keep pure logic tests in their owning harness. Use the minimum supported
   host for runtime behavior and each owning platform for filesystem or native
   contracts. A cross-platform test should assert the same public behavior,
   not just that an unrelated platform's test process exits successfully.
3. Test supported and unsupported forms: valid behavior, an absent capability,
   a deliberate guard or error on unsupported hosts, and any documented
   fallback. Use literal paths where path semantics are in scope.
4. Run the cheapest failing control first: a newer-only API under the minimum
   host, or an owning-platform test that fails when its guard is removed.
   Restore the implementation and rerun the focused test before broadening.
5. Report the actual PowerShell version, OS, architecture, discovered and
   executed tests, skips, and failures per lane. An intentional skip is visible
   but does not prove behavior on that host.

When the required host is unavailable, mark the claim unverified and defer its
acceptance. Do not substitute a parser check, a different OS, or a coverage
percentage for the missing behavior lane. Keep platform-only ownership and
coverage exceptions explicit rather than hiding them in an aggregate result.
