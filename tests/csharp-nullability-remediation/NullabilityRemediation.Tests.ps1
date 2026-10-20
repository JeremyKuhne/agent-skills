#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

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
        $script:Verification | Should -Match 'each nullable or null-forgiving diagnostic observed by the probe'
        $script:Evaluations | Should -Match 'Compiler probe is blocked'
        $script:Evaluations | Should -Match 'restore the reversible probe'
    }

    It 'distinguishes truthful conditional output contracts' {
        $script:Remediation | Should -Match '\[NotNullWhen\(true\)\] out T\?'
        $script:Remediation | Should -Match '\[NotNullWhen\(false\)\] out T\?'
        $script:Remediation | Should -Match '\[MaybeNullWhen\(false\)\] out T'
        $script:Remediation | Should -Match 'every\s+`true` return must still satisfy the ordinary `T` contract'
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

    It 'confirms scope without changing measurement workloads automatically' {
        $script:Skill | Should -Match 'Inventory production, tests,\s+generated code, and benchmarks separately'
        $script:Skill | Should -Match 'Exclusions require repository policy or explicit approval'
        $script:Remediation | Should -Match 'the workload itself is a measurement contract'
        $script:Evaluations | Should -Match 'Approved scope and measurement workloads'
    }

    It 'requires combined probes and containing-type diagnostics' {
        $script:Remediation | Should -Match 'Compile combined edits'
        $script:Remediation | Should -Match 'Include containing-type\s+diagnostics'
        $script:Evaluations | Should -Match 'Combined removal probes'
    }

    It 'makes private AllowNull storage exceptional without forbidding normalization setters' {
        $script:Skill | Should -Match 'Private `\[AllowNull\]` storage is an\s+exceptional remedy'
        $script:Remediation | Should -Match 'Use it only as a justified last resort'
        $script:Remediation | Should -Match 'every read, reset, and cleanup path'
        $script:Remediation | Should -Match 'Public `\[AllowNull\]` is valid'
        $script:Evaluations | Should -Match 'justify private `\[AllowNull\]` as a last resort'
        $script:Evaluations | Should -Match 'compare runtime guard and policy-approved narrow suppression first'
        $script:Evaluations | Should -Match 'storage only as a justified last resort, with audited\s+reads, resets, and cleanup'
    }

    It 'bounds performance work without waiving acceptance criteria' {
        $script:Verification | Should -Match 'defaults below do not waive a required gate'
        $script:Verification | Should -Match 'no mandatory benchmark or IL inspection'
        $script:Verification | Should -Match 'At most one\s+confirmatory repeat is the default'
        $script:Verification | Should -Match 'Statistical\s+significance alone does not establish practical importance'
        $script:Verification | Should -Match 'require separate approval unless already in scope'
        $script:Verification | Should -Match 'When the budget is exhausted, stop'
        $script:Verification | Should -Match 'satisfy explicit performance gates'
        $script:Verification | Should -Match 'compiler-only or annotation-only changes need no\s+timing checks unless an explicit gate requires them'
        $script:Evaluations | Should -Match 'Bounded performance work'
    }

    It 'preserves lifecycle timing and justifies structural rewrites' {
        $script:Skill | Should -Match 'Justify a redesign'
        $script:Remediation | Should -Match 'side-effectful getter evaluation'
        $script:Remediation | Should -Match 'For cyclic deserialization, keep two-phase ownership truthful'
        $script:Remediation | Should -Match 'Do not replace a mode discriminator with payload nullability'
        $script:Evaluations | Should -Match 'Preserved lifecycle semantics'
    }
}