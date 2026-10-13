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

## Preserve JSON roots and values

When a task requires an object root, preserve the parsed root before testing
its type. `ConvertFrom-Json -NoEnumerate` keeps a singleton JSON array from
becoming its element; without it, `[{"records":[]}]` can look like an object
and pass an object-only check.

Do not assume JSON conversion preserves values merely because array-shape
checks pass. Default conversion can turn date-looking strings into
`DateTime`. `PSCustomObject` properties and ordinary PowerShell hashtables
cannot preserve distinct JSON keys such as `a` and `A`. Use a maintained
parser's exact string values and ordinal-key objects when that distinction is
part of the task. Keep parsed objects as dictionaries or JSON elements rather
than casting them back into a case-insensitive object shape.

`ConvertFrom-Json -DateKind String` is available only on PowerShell 7.5 or
later. It is not a fallback for a 7.4 contract. `-AsHashtable` preserves
distinct-case keys, but does not alone disable date conversion. Choose the
smallest maintained parser/API compatible with the declared floor; do not
reimplement JSON syntax to avoid its conversions.

If the contract requires exact JSON string values on PowerShell 7.4, do not
use default `ConvertFrom-Json`, even with `-AsHashtable -NoEnumerate`.
Use a maintained parser that leaves strings unchanged. Do not parse strings
as dates unless the task explicitly requires that conversion.

For an object-root contract, this PowerShell 7.4-compatible example returns
an independently owned `JsonElement`. Cloning preserves the value after the
document is disposed:

```powershell
function ConvertFrom-ExactJsonObject {
    [CmdletBinding()]
    [OutputType([System.Text.Json.JsonElement])]
    param (
        [Parameter(Mandatory)]
        [string] $Json
    )

    $document = [System.Text.Json.JsonDocument]::Parse($Json)
    try {
        if ($document.RootElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) {
            throw 'Expected a JSON object.'
        }

        return $document.RootElement.Clone()
    }
    finally {
        $document.Dispose()
    }
}
```

Read strings with `GetString()` and object members with ordinal
`GetProperty()` lookup; PowerShell dot-property access is not the
`JsonElement` API. When the output contract requires native PowerShell
values, project by JSON kind using exact strings and ordinal dictionaries.
Do not reparse or cast the preserved graph into a case-insensitive shape.

Add independent controls for a singleton array root, a date-looking string,
and distinct-case keys, including nested record values. A valid empty array
and ordinary numeric records do not cover these conversion boundaries.

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
$receipt = ConvertFrom-Json -InputObject $json -AsHashtable -NoEnumerate -ErrorAction Stop
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
