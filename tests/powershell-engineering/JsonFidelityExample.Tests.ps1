#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $path = Join-Path $repoRoot 'skills\powershell-engineering\structured-data-and-types.md'
    $text = [IO.File]::ReadAllText($path)
    $blocks = @([regex]::Matches($text, '(?ms)^```powershell\r?\n(?<body>.*?)^```\r?$') |
        Where-Object { $_.Groups['body'].Value.Contains('function ConvertFrom-ExactJsonObject') })
    if ($blocks.Count -ne 1) { throw 'Expected exactly one literal PowerShell fidelity example.' }
    $example = [scriptblock]::Create($blocks[0].Groups['body'].Value)
    . $example
}

Describe 'Portable JSON fidelity example' {
    It 'preserves strings, ordinal keys, and nested values after document disposal' {
        $value = ConvertFrom-ExactJsonObject -Json '{"stamp":"2026-04-03T01:02:03Z","a":1,"A":2,"nested":{"stamp":"2026-04-03T01:02:03Z","a":3,"A":4}}'
        ($value -is [System.Text.Json.JsonElement]) | Should -BeTrue
        $value.GetProperty('stamp').ValueKind | Should -Be ([System.Text.Json.JsonValueKind]::String)
        $value.GetProperty('stamp').GetString() | Should -BeExactly '2026-04-03T01:02:03Z'
        $value.GetProperty('a').GetInt32() | Should -Be 1
        $value.GetProperty('A').GetInt32() | Should -Be 2
        $nested = $value.GetProperty('nested')
        $nested.GetProperty('stamp').GetString() | Should -BeExactly '2026-04-03T01:02:03Z'
        $nested.GetProperty('a').GetInt32() | Should -Be 3
        $nested.GetProperty('A').GetInt32() | Should -Be 4
    }

    It 'keeps empty, singleton, and multiple nested array shapes' {
        $value = ConvertFrom-ExactJsonObject -Json '{"empty":[],"single":[null],"multiple":[false,0,""]}'
        $value.GetProperty('empty').GetArrayLength() | Should -Be 0
        $value.GetProperty('single').GetArrayLength() | Should -Be 1
        $items = @($value.GetProperty('multiple').EnumerateArray())
        $items.Count | Should -Be 3
        $items[0].ValueKind | Should -Be ([System.Text.Json.JsonValueKind]::False)
        $items[1].GetInt32() | Should -Be 0
        $items[2].GetString() | Should -BeExactly ''
    }

    It 'rejects non-object or malformed root <Name>' -ForEach @(
        @{ Name = 'empty array'; Json = '[]' }
        @{ Name = 'singleton array'; Json = '[{"records":[]}]' }
        @{ Name = 'null'; Json = 'null' }
        @{ Name = 'Boolean'; Json = 'false' }
        @{ Name = 'number'; Json = '0' }
        @{ Name = 'string'; Json = '"text"' }
        @{ Name = 'malformed'; Json = '{"records":[' }
    ) {
        { ConvertFrom-ExactJsonObject -Json $Json } | Should -Throw
    }

    It 'detects replacing literal strings with default JSON date conversion' {
        $value = ConvertFrom-ExactJsonObject -Json '{"stamp":"2026-04-03T01:02:03Z"}'
        $coerced = ConvertFrom-Json -InputObject $value.GetRawText() -AsHashtable -NoEnumerate -ErrorAction Stop
        ($coerced['stamp'] -is [datetime]) | Should -BeTrue
        ($coerced['stamp'] -is [string]) | Should -BeFalse
    }
}
