#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:SkillRoot = Join-Path $script:RepoRoot 'skills/csharp-nullability-remediation'
    $script:Skill = Get-Content -LiteralPath (Join-Path $script:SkillRoot 'SKILL.md') -Raw
    $script:Remediation = Get-Content -LiteralPath (Join-Path $script:SkillRoot 'remediation.md') -Raw
    $script:Verification = Get-Content -LiteralPath (Join-Path $script:SkillRoot 'verification.md') -Raw
    $script:Evaluations = Get-Content -LiteralPath (Join-Path $script:SkillRoot 'evaluations.md') -Raw
}

Describe 'C# nullability remediation skill contract' {
    It 'ships a complete portable core without a repository overlay' {
        @(Get-ChildItem -LiteralPath $script:SkillRoot -File | Sort-Object Name).Name |
            Should -Be @('evaluations.md', 'remediation.md', 'SKILL.md', 'verification.md')

        Test-Path -LiteralPath (Join-Path $script:SkillRoot 'overlay.md') |
            Should -BeFalse
        "$script:Skill`n$script:Remediation`n$script:Verification`n$script:Evaluations" |
            Should -Not -Match '(?i)\bTouki\b|TOUKI\d|c:\\repos|\.agents/skills'
    }

    It 'requires a compiler probe before selecting a nontrivial remedy' {
        $script:Skill | Should -Match 'Remove one representative `!` first and compile'
        $script:Skill | Should -Match 'Capture the warning id, message, natural\s+type, converted type'
        $script:Evaluations | Should -Match 'Compiler probe is blocked'
        $script:Evaluations | Should -Match 'restore the reversible probe'
    }

    It 'distinguishes truthful conditional output contracts' {
        $script:Remediation | Should -Match '\[NotNullWhen\(true\)\] out T\?'
        $script:Remediation | Should -Match '\[NotNullWhen\(false\)\] out T\?'
        $script:Remediation | Should -Match '\[MaybeNullWhen\(false\)\] out T'
        $script:Remediation | Should -Match 'successful lookup of a stored null'
        $script:Evaluations | Should -Match 'empty `Nullable<U>`'
    }

    It 'guards public metadata and inherited contracts with consumer builds' {
        $script:Verification | Should -Match 'compile representative consumers'
        $script:Verification | Should -Match 'test overrides and interface implementations for `CS876x`'
        $script:Remediation | Should -Match 'compile\s+the implementation against every shipped reference surface'
    }

    It 'rejects receiver-state postconditions on mutating struct copies' {
        $script:Remediation | Should -Match 'non-readonly mutable struct method'
        $script:Remediation | Should -Match 'mutate a defensive copy while flow\s+analysis narrows the original receiver'
        $script:Evaluations | Should -Match 'verify the hazard with an `in` or readonly-field consumer'
    }

    It 'routes neighboring work to the owning workflow' {
        $script:Skill | Should -Match 'Not for authoring the analyzer itself'
        $script:Evaluations | Should -Match 'Write a Roslyn analyzer that bans the null-forgiving operator'
        $script:Evaluations | Should -Match 'Make `MaybeNullWhenAttribute` available on \.NET Framework'
        $script:Evaluations | Should -Match 'Enable nullable reference types in a new repository'
    }
}