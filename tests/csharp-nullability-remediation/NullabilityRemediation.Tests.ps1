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

    It 'uses the .NET 10 SDK C# compiler baseline and explicit return targets' {
        $script:Skill | Should -Match 'Requires the \.NET 10 SDK or later'
        $script:Skill | Should -Match 'C# 14 compiler'
        $script:Skill | Should -Match 'nullable context, effective SDK/compiler'
        $script:Remediation | Should -Match '\[return: MaybeNull\].*`T` return'
        $script:Evaluations | Should -Match '\[return: MaybeNull\].*on `T`'
        "$script:Remediation`n$script:Evaluations" | Should -Not -Match 'C# 8|C# 9|CS8627'
    }

    It 'does not treat required members as a framework lifecycle guarantee' {
        $script:Remediation | Should -Match '`required` is a C# 11 construction-site obligation'
        $script:Remediation | Should -Match 'framework activators can bypass object-initializer'
    }

    It 'distinguishes unconditional and Boolean-conditional member postconditions' {
        $script:Remediation | Should -Match '\[MemberNotNull\].*every normal return'
        $script:Remediation | Should -Match '\[MemberNotNullWhen\(value, \.\.\.\)\].*specified Boolean'
    }

    It 'qualifies warning-free probes, generic defaults, and AllowNull storage' {
        $script:Remediation | Should -Match 'nullable warnings are enabled at the site'
        $script:Remediation | Should -Match 'where T : struct.*default represents absence'
        $script:Remediation | Should -Match 'Public `\[AllowNull\]` is valid'
        $script:Evaluations | Should -Match 'expected diagnostic is not suppressed'
    }

    It 'guards public metadata and inherited contracts with consumer builds' {
        $script:Verification | Should -Match 'compile representative consumers'
        $script:Verification | Should -Match 'test overrides and interface implementations for `CS876x`'
        $script:Remediation | Should -Match 'compile\s+the implementation against every shipped reference surface'
    }

    It 'rejects receiver-state postconditions on mutating struct copies' {
        $script:Remediation | Should -Match 'non-readonly mutable struct method'
        $script:Remediation | Should -Match 'mutate a defensive copy while flow\s+analysis\s+narrows the original receiver'
        $script:Evaluations | Should -Match 'verify the hazard with an `in` or readonly-field consumer'
    }

    It 'routes neighboring work to the owning workflow' {
        $script:Skill | Should -Match 'Not for authoring the analyzer itself'
        $script:Skill | Should -Match 'Use `roslyn-analyzers`'
        $script:Skill | Should -Match 'Use `dotnet-polyfills`'
        $script:Skill | Should -Match 'Use `performance-testing`'
        $script:Skill | Should -Match 'Use `security-review`'
        $script:Skill | Should -Match 'Run `pre-pr-self-review`'
        $script:Evaluations | Should -Match 'Write a Roslyn analyzer that bans the null-forgiving operator'
        $script:Evaluations | Should -Match 'Make `MaybeNullWhenAttribute` available on \.NET Framework'
        $script:Evaluations | Should -Match 'Enable nullable reference types in a new repository'
    }

    It 'uses a general diagnostic ledger and conditions analyzer-loading checks' {
        $script:Skill | Should -Match 'compiler or analyzer ID, or none'
        $script:Verification | Should -Match 'when a diagnostic analyzer participates'
        $script:Verification | Should -Match 'compile a representative violation.*expected\s+diagnostic'
        $script:Verification | Should -Not -Match 'acyclic bootstrap|producer source gate'
    }
}