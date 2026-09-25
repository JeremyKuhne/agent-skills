# Validate structured data and PowerShell values

Read this when a script consumes structured data or turns parsed values into
PowerShell conditions, pipeline output, or a report. Decide what the producer
promises before choosing a parser or an accepted type.

## Keep syntax with its owner

| Input | Owning mechanism | PowerShell's role |
| --- | --- | --- |
| JSON | `ConvertFrom-Json` for its supported contract, or a maintained JSON parser when token, duplicate-key, or number semantics require more | Parse, validate the root and field types, then orchestrate |
| YAML, XML, Markdown, or PowerShell source | A maintained format parser, schema tool, XML API, or PowerShell AST | Consume parsed nodes; do not reconstruct grammar with lines or regex |
| Versions and external command output | A parser matching the declared complete token or the tool's structured output | Validate the parsed value and supported range before acting |

Do not extend a regex or indentation scanner to handle new syntax classes.
If the chosen parser discards distinctions the contract needs, use one that
preserves them or narrow the accepted input. Do not turn a format check into
a claim that arbitrary input or scripts are safe to execute.

## Preserve the value states

Check key presence *before* reading the value. Reading a missing field and an
explicit null can both yield `$null` in PowerShell, while a Boolean cast can
make distinct values look alike.

| Parsed state | Distinction to retain |
| --- | --- |
| Missing field | The key does not exist; apply the documented default or reject it. |
| Explicit null | The key exists with a null value; accept it only if the schema permits null. |
| Boolean false | A valid Boolean value, not absence or failure to parse. |
| Numeric zero | A number, not a substitute for Boolean false. Validate its permitted range. |
| Empty string or array | A present value with its own type and shape; apply its documented cardinality rule. |
| Malformed or unsupported input | Parser failure, incompatible schema, or rejected type; do not silently default it. |

For a required JSON Boolean in a PowerShell 7.4-or-later host, validate the
root, presence, and type separately:

```powershell
$receipt = ConvertFrom-Json -InputObject $json -AsHashtable -ErrorAction Stop
if ($receipt -isnot [System.Collections.IDictionary]) {
    throw 'Expected a JSON object.'
}
if (-not $receipt.Contains('passed')) {
    throw 'Missing passed.'
}
if ($receipt['passed'] -isnot [bool]) {
    throw 'passed must be a JSON Boolean.'
}
```

This accepts `false` but rejects null, `0`, `"false"`, and missing evidence.
Use the parser's actual primitive types and the contract's allowed ranges;
do not use PowerShell truthiness, string matching, or coercive comparisons
as substitutes for a type check.

## Keep array shape across PowerShell boundaries

PowerShell enumerates values emitted through the pipeline. A directly assigned
parsed `[]` is an empty array, but emitting it from an `if` expression can
produce no output and assign `$null`; a single-element array can become a
scalar. Keep a direct reference to the parsed array before pipeline or branch
output, and explicitly preserve shape when passing it between commands.
Test zero, one, and multiple elements through the actual public entry point.

## Test against the contract

Build a synthetic table for missing, null, false, true, zero, empty text and
array, malformed input, unsupported types, and unknown schema versions where
applicable. Make the accepted and rejected states explicit, then use the same
corpus for a core, wrapper, and rendered generated copy when they share a
contract. Mutate type, presence, and shape checks to prove the tests can fail.
Use a real host or process lane for stream and exit behavior; a parser test
alone does not establish that behavior.
