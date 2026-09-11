# Running benchmarks

Detail for the [performance-testing](SKILL.md) skill. The perf project's
`Program.Main` typically uses `BenchmarkSwitcher.FromAssembly(...)` so all CLI
arguments are forwarded to BenchmarkDotNet. Run from the repo root.

For before/after discipline and reading the result columns, see
[interpreting-results.md](interpreting-results.md). Drilling a benchmark down to
the hot method or source line is a repo-specific page supplied by the overlay
(the trace-analyzer skill).

## Specifying the target framework is required

Because the perf project is multi-targeted, **`dotnet run` requires `-f <tfm>`** -
the SDK will not pick one for you and the run fails (NETSDK1005 or an ambiguous
target error) if you omit it. Always pass an explicit moniker (e.g. `-f net10.0`
or `-f net481`, or whatever the repo's current modern version resolves to).

```powershell
# Modern .NET
dotnet run -c Release -f net10.0 --project <root>.perf -- --filter *MyBenchmark*

# .NET Framework
dotnet run -c Release -f net481 --project <root>.perf -- --filter *MyBenchmark*
```

`-c Release` is **mandatory**. Debug builds are not representative and
BenchmarkDotNet will warn loudly.

When a change touches code that compiles for both targets, **run both TFMs**. The
results often differ dramatically - the modern runtime has vectorized BCL APIs
that .NET Framework lacks, so a hand-tuned Framework fast path may look identical
to the generic path on the modern runtime.

## Preflight BenchmarkDotNet ETW on Windows

BenchmarkDotNet's ETW profiler requires the separate
`BenchmarkDotNet.Diagnostics.Windows` package. Include its `PackageReference` in
the benchmark project or an imported props file; a version in central package
management does not include the package. Keep the concrete version in the
repository's central package file when it uses one.

Build the benchmark project in Release after adding the reference. Before UAC or
run-ID reservation, use the capture helper supplied by the repository's profiling
overlay when one exists. Otherwise inspect evaluated items directly:

```powershell
dotnet msbuild <root>.perf -nologo `
  -property:Configuration=Release `
  -property:TargetFramework=<tfm> `
  -getItem:PackageReference
```

Confirm the JSON output contains a `BenchmarkDotNet.Diagnostics.Windows` item. Do
not infer inclusion by searching literal project XML: imports and central version
management make that check incomplete.

## Run a single class or method

```powershell
# All benchmarks in a class
dotnet run -c Release -f net10.0 --project <root>.perf -- --filter *MyBenchmark*

# A single method
dotnet run -c Release -f net10.0 --project <root>.perf -- --filter *MyBenchmark.Variant*
```

The trailing `*` matters: `--filter` globs the full benchmark ID
(`Namespace.Type.Method`), so `*MyBenchmark.Variant*` also matches the
parameterized cases (`Variant(x: 1)`, ...) that a bare `*MyBenchmark.Variant`
would miss.

## Interactive picker

```powershell
dotnet run -c Release -f <tfm> --project <root>.perf
```

With no `--filter`, BenchmarkSwitcher prints a numbered menu. Useful when
exploring. `-f <tfm>` is still required on a multi-targeted project.

## Useful extra switches

- `--job short` - very fast, low-confidence run; good for smoke-testing a new
  benchmark before committing to a full run.
- `--memory` - enables the memory diagnoser for this run even if the class is not
  decorated. Prefer the attribute.
- `--exporters github` - emits a GitHub-flavored Markdown report alongside the
  default outputs.

## Serialize shared-output invocations

Do not run builds, tests, captures, or BenchmarkDotNet child builds concurrently
for the same project and configuration unless each invocation has explicitly
isolated intermediate, output, and redirected artifact directories. Shared `obj`,
`bin`, or redirected artifact trees can produce corrupt or mismatched assemblies
and reports even when the commands target different tests or benchmarks. Run
invocations with any shared writable tree sequentially; invocations with all three
trees isolated may run in parallel. Read-only analysis of immutable traces or
results may also run in parallel.
