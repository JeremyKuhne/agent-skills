#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:ComRoot = Join-Path $script:RepoRoot 'skills/cswin32-com'
    $script:InteropRoot = Join-Path $script:RepoRoot 'skills/cswin32-interop'
    $script:ComSkill = Get-Content -LiteralPath (Join-Path $script:ComRoot 'SKILL.md') -Raw
    $script:Audit = Get-Content -LiteralPath (Join-Path $script:ComRoot 'lifecycle-audit.md') -Raw
    $script:Migration = Get-Content -LiteralPath (Join-Path $script:ComRoot 'migration-and-testing.md') -Raw
    $script:InteropSkill = Get-Content -LiteralPath (Join-Path $script:InteropRoot 'SKILL.md') -Raw
    $script:Ownership = Get-Content -LiteralPath (Join-Path $script:InteropRoot 'ownership-and-units.md') -Raw
    $script:EvalScenarios = @((Get-Content -LiteralPath (
                Join-Path $script:RepoRoot 'evals/scenarios/cswin32-com.json') -Raw |
            ConvertFrom-Json).scenarios)
}

Describe 'CsWin32 COM ownership and lifecycle skill contract' {
    It 'ships a portable audit without repository-specific evidence' {
        @(Get-ChildItem -LiteralPath $script:ComRoot -File | Sort-Object Name).Name |
            Should -Be @(
                'ccw-composition.md',
                'comiid-and-cls.md',
                'lifecycle-audit.md',
                'lifetime.md',
                'manual-structs.md',
                'migration-and-testing.md',
                'SKILL.md')

        Test-Path -LiteralPath (Join-Path $script:ComRoot 'overlay.md') |
            Should -BeFalse
        "$script:ComSkill`n$script:Audit`n$script:Migration" |
            Should -Not -Match '(?i)winforms|HtmlShim|AccessibleObject|#15059|#15087|Astra|[A-Z]:\\repos'
    }

    It 'routes lifetime and transfer work through the audit' {
        $script:ComSkill | Should -Match 'lifecycle observers'
        $script:ComSkill | Should -Match 'STGMEDIUM/SetData ownership transfer'
        $script:ComSkill | Should -Match 'Audit ownership and lifecycle before fixing a leak'
        $script:ComSkill | Should -Match '\[lifecycle-audit\.md\]\(lifecycle-audit\.md\)'
        $script:InteropSkill | Should -Match 'ownership-transfer predicates'
        $script:InteropSkill | Should -Match 'what action activates cleanup'
    }

    It 'requires a complete edge ledger and a traced activation path' {
        $script:Audit | Should -Match 'Activation trigger.*Cleanup trigger.*Identity and multiplicity'
        $script:Audit | Should -Match 'A stored observer is not\s+an active observer'
        $script:Audit | Should -Match 'manager must establish that observation independently'
        $script:Audit | Should -Match 'application event handler can accidentally activate'
        $script:Ownership | Should -Match 'whether the callee borrows, retains, or conditionally takes ownership'
        $script:Ownership | Should -Match 'exact success result and flag that transfer ownership'
    }

    It 'distinguishes borrowed, retained, and transferred ownership' {
        $script:Audit | Should -Match '\*\*Borrow:\*\*'
        $script:Audit | Should -Match '\*\*Retain:\*\*'
        $script:Audit | Should -Match '\*\*Transfer:\*\*'
        $script:Audit | Should -Match 'successful call with\s+`fRelease=TRUE` transfers the whole `STGMEDIUM`'
        $script:Audit | Should -Match 'Do not convert the native structure back or\s+release `pUnkForRelease`'
        $script:Audit | Should -Match 'failure or `fRelease=FALSE` leaves the conversion reference'
        $script:Ownership | Should -Match 'callee that releases the transferred value before returning'
    }

    It 'models native registration identity and multiplicity' {
        $script:Audit | Should -Match 'Managed delegate equality is not native registration identity'
        $script:Audit | Should -Match 'Every successful\s+attach can create a distinct proxy, CCW, or cookie'
        $script:Audit | Should -Match 'An unmatched removal is a no-op'
        $script:Audit | Should -Match 'If detach fails, retain or restore ownership metadata'
        $script:Audit | Should -Match 'unless the API contract proves no registration remains'
        $script:Audit | Should -Match 'ordinary connection-point handlers separate from individually attached'
        $script:Audit | Should -Match 'same delegate under different names'
    }

    It 'orders teardown for reentrancy and non-creating removal' {
        $script:Audit | Should -Match 'Establish a\s+terminal state before making them'
        $script:Audit | Should -Match 'mark the owner disposed or unloading'
        $script:Audit | Should -Match 'remove it from manager lookups or clear the lookup collections'
        $script:Audit | Should -Match 'Removal after teardown must be non-creating'
        $script:Audit | Should -Match 'attempt every independent disconnect and release'
        $script:Audit | Should -Match 'callbacks that dispose the owner, throw, remove themselves'
    }

    It 'requires independent tests of the controlling product path' {
        $script:Migration | Should -Match 'cleanup path was never activated'
        $script:Migration | Should -Match 'ordinary public workflow without an\s+optional application event'
        $script:Audit | Should -Match 'Assert that the (?:internal )?native observation or registration was actually\s+established'
        $script:Audit | Should -Match 'Keep the oracle independent of the proposed representation'
        $script:Audit | Should -Match 'Cross-apply a competing fix''s tests'
        $script:Audit | Should -Match 'verify a clean process exit'
        $script:Ownership | Should -Match 'ordinary lifecycle path without optional application behavior'
    }
}

Describe 'CsWin32 COM behavioral evaluation checks' {
    It 'scores a synthetic response with the intended polarity: <CaseName>' -ForEach @(
        @{
            CaseName = 'lifecycle diagnosis accepted'
            ScenarioId = 'cswin32-com-audit-manager-observation-activation'
            Response = 'High: manager-owned observation is missing. Advise is never called on the ordinary customer path. Check that the connection is active. Add a baseline with no application window handler.'
            Expected = $true
        }
        @{
            CaseName = 'lifecycle assumption rejected'
            ScenarioId = 'cswin32-com-audit-manager-observation-activation'
            Response = 'The fix is complete; adding the application handler is sufficient.'
            Expected = $false
        }
        @{
            CaseName = 'transfer diagnosis accepted'
            ScenarioId = 'cswin32-com-audit-stgmedium-transfer'
            Response = 'On successful fRelease=true, ownership of the entire STGMEDIUM transfers. The recipient can ReleaseStgMedium during the call. Do not read or release the medium after it is transferred. On failure or fRelease=false, release the conversion-acquired reference.'
            Expected = $true
        }
        @{
            CaseName = 'unconditional post-call cleanup rejected'
            ScenarioId = 'cswin32-com-audit-stgmedium-transfer'
            Response = 'Always release pUnkForRelease after SetData and copy the medium back after success.'
            Expected = $false
        }
        @{
            CaseName = 'registration diagnosis accepted'
            ScenarioId = 'cswin32-com-audit-registration-multiplicity'
            Response = 'Native registration identity matters. The same delegate needs a separate proxy for each duplicate attach and different event names. Unmatched remove is a no-op. On detach failure, preserve registration metadata. Keep standard connection-point handlers separate from attached dispatch proxies.'
            Expected = $true
        }
        @{
            CaseName = 'delegate dictionary assumption rejected'
            ScenarioId = 'cswin32-com-audit-registration-multiplicity'
            Response = 'Dictionary<EventHandler, Proxy> is sufficient; unmatched remove decrements the count and disconnects.'
            Expected = $false
        }
        @{
            CaseName = 'ordinary RCW answer accepted'
            ScenarioId = 'cswin32-com-routing-ordinary-rcw-near-miss'
            Response = 'Keep the managed automation helper small and expose an interface around the dynamic dependency.'
            Expected = $true
        }
        @{
            CaseName = 'low-level COM machinery rejected for RCW near miss'
            ScenarioId = 'cswin32-com-routing-ordinary-rcw-near-miss'
            Response = 'Replace the RCW with ComScope and IID.Get, then define a delegate* unmanaged vtable over STGMEDIUM.'
            Expected = $false
        }
    ) {
        $scenario = @($script:EvalScenarios | Where-Object id -eq $ScenarioId)[0]
        $missingPatterns = @($scenario.requiredResponsePatterns |
            Where-Object { $Response -notmatch $_ })
        $forbiddenPatterns = @($scenario.forbiddenResponsePatterns |
            Where-Object { $Response -match $_ })
        $passes = $missingPatterns.Count -eq 0 -and $forbiddenPatterns.Count -eq 0

        $passes | Should -Be $Expected -Because $CaseName
    }
}