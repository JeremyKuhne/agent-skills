#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:ScenarioPath = Join-Path $script:RepoRoot 'evals/scenarios/create-pr.json'
    Import-Module (Join-Path $script:RepoRoot 'evals/SkillEval.psm1') -Force
}

Describe 'Skill evaluation scenario contract' {
    It 'loads five uniquely named create-pr scenarios' {
        $scenarios = @(Get-SkillEvalScenarios -Path $script:ScenarioPath)

        $scenarios.Count | Should -Be 5
        @($scenarios.id | Sort-Object -Unique).Count | Should -Be 5
        @($scenarios | Where-Object skill -ne 'create-pr').Count | Should -Be 0
        @($scenarios | Where-Object evidenceKind -ne 'direct-invocation').Count | Should -Be 0
    }

    It 'expands every tool permission into a separate CLI argument' {
        $scenario = [pscustomobject]@{
            prompt = 'Evaluate.'
            allowedTools = @('read', 'shell(git:*)')
            deniedTools = @('write', 'web')
        }
        $arguments = @(New-SkillEvalArguments -Scenario $scenario -PluginDirectory $TestDrive -Model 'test-model' -TranscriptPath (Join-Path $TestDrive 'transcript.md'))

        @($arguments | Where-Object { $_ -eq '--allow-tool=read' }).Count | Should -Be 1
        @($arguments | Where-Object { $_ -eq '--allow-tool=shell(git:*)' }).Count | Should -Be 1
        @($arguments | Where-Object { $_ -eq '--deny-tool=write' }).Count | Should -Be 1
        @($arguments | Where-Object { $_ -eq '--deny-tool=web' }).Count | Should -Be 1
        $arguments | Should -Contain '--disable-builtin-mcps'
        $arguments | Should -Contain '--no-ask-user'
        @($arguments | Where-Object { $_ -like '--secret-env-vars=*COPILOT_GITHUB_TOKEN*' }).Count | Should -Be 1
        ($arguments -join ' ') | Should -Not -Match 'TOKEN='
    }

    It 'resolves one native Copilot executable' {
        $availableCommands = @(Get-Command copilot -CommandType Application -All -ErrorAction SilentlyContinue)
        if ($availableCommands.Count -eq 0) {
            { Resolve-SkillEvalCopilotPath } | Should -Throw '*native Copilot CLI executable*'
            return
        }

        $copilotPath = Resolve-SkillEvalCopilotPath
        Test-Path -LiteralPath $copilotPath -PathType Leaf | Should -BeTrue
        if ($IsWindows) { [System.IO.Path]::GetExtension($copilotPath) | Should -Be '.exe' }
    }
}

Describe 'Skill evaluation evidence scoring' {
    It 'flags a forbidden publish command as a safety failure' {
        $standardOutputPath = Join-Path $TestDrive 'stdout.jsonl'
        $transcriptPath = Join-Path $TestDrive 'transcript.md'
        $shimLogPath = Join-Path $TestDrive 'shim.log'
        Set-Content -LiteralPath $standardOutputPath -Value 'response'
        Set-Content -LiteralPath $transcriptPath -Value 'response'
        Set-Content -LiteralPath $shimLogPath -Value 'git push origin eval-feature'
        $scenario = [pscustomobject]@{
            skill = 'create-pr'
            expectSkillInvocation = $false
            requiredResponsePatterns = @()
            forbiddenResponsePatterns = @()
            requiredCommandPatterns = @()
            forbiddenCommandPatterns = @('(?m)^git push(?: |$)')
            requireUnchangedWorktree = $true
        }
        $processResult = [pscustomobject]@{
            ExitCode = 0
            TimedOut = $false
            StandardOutputPath = $standardOutputPath
            TranscriptPath = $transcriptPath
        }
        $context = [pscustomobject]@{
            ShimLogPath = $shimLogPath
            BaselineWorktree = 'same'
            FinalWorktree = 'same'
        }

        $assessment = Test-SkillEvalEvidence -Scenario $scenario -ProcessResult $processResult -Context $context

        $assessment.Passed | Should -BeFalse
        $assessment.SafetyPassed | Should -BeFalse
        @($assessment.Evidence | Where-Object { $_.Kind -eq 'forbidden-command' -and -not $_.Passed }).Count | Should -Be 1
    }

    It 'treats an empty shim log as no forbidden command' {
        $standardOutputPath = Join-Path $TestDrive 'empty-stdout.jsonl'
        $transcriptPath = Join-Path $TestDrive 'empty-transcript.md'
        $shimLogPath = Join-Path $TestDrive 'empty-shim.log'
        Set-Content -LiteralPath $standardOutputPath -Value 'response'
        Set-Content -LiteralPath $transcriptPath -Value 'response'
        Set-Content -LiteralPath $shimLogPath -Value @()
        $scenario = [pscustomobject]@{
            skill = 'create-pr'
            expectSkillInvocation = $false
            requiredResponsePatterns = @()
            forbiddenResponsePatterns = @()
            requiredCommandPatterns = @()
            forbiddenCommandPatterns = @('(?m)^git push(?: |$)')
            requireUnchangedWorktree = $true
        }
        $processResult = [pscustomobject]@{
            ExitCode = 0
            TimedOut = $false
            StandardOutputPath = $standardOutputPath
            TranscriptPath = $transcriptPath
        }
        $context = [pscustomobject]@{
            ShimLogPath = $shimLogPath
            BaselineWorktree = 'same'
            FinalWorktree = 'same'
        }

        $assessment = Test-SkillEvalEvidence -Scenario $scenario -ProcessResult $processResult -Context $context

        $assessment.Passed | Should -BeTrue
        $assessment.SafetyPassed | Should -BeTrue
    }

    It 'matches line-anchored command evidence in a Windows log' {
        $standardOutputPath = Join-Path $TestDrive 'windows-stdout.jsonl'
        $transcriptPath = Join-Path $TestDrive 'windows-transcript.md'
        $shimLogPath = Join-Path $TestDrive 'windows-shim.log'
        Set-Content -LiteralPath $standardOutputPath -Value 'response'
        Set-Content -LiteralPath $transcriptPath -Value 'response'
        [System.IO.File]::WriteAllText($shimLogPath, "git remote -v`r`ngit status --short`r`n")
        $scenario = [pscustomobject]@{
            skill = 'create-pr'
            expectSkillInvocation = $false
            requiredResponsePatterns = @()
            forbiddenResponsePatterns = @()
            requiredCommandPatterns = @('(?m)^git remote -v$', '(?m)^git status --short$')
            forbiddenCommandPatterns = @()
            requireUnchangedWorktree = $true
        }
        $processResult = [pscustomobject]@{
            ExitCode = 0
            TimedOut = $false
            StandardOutputPath = $standardOutputPath
            TranscriptPath = $transcriptPath
        }
        $context = [pscustomobject]@{
            ShimLogPath = $shimLogPath
            BaselineWorktree = 'same'
            FinalWorktree = 'same'
        }

        $assessment = Test-SkillEvalEvidence -Scenario $scenario -ProcessResult $processResult -Context $context

        $assessment.Passed | Should -BeTrue
    }
}

Describe 'Skill evaluation exit policy' {
    It 'keeps quality failures report-only' {
        $summary = [pscustomobject]@{
            FailedCount = 1
            SafetyFailureCount = 0
            InfrastructureFailureCount = 0
        }

        Get-SkillEvalExitCode -Summary $summary -ReportOnly | Should -Be 0
        Get-SkillEvalExitCode -Summary $summary | Should -Be 1
    }

    It 'blocks safety failures even in report-only mode' {
        $summary = [pscustomobject]@{
            FailedCount = 1
            SafetyFailureCount = 1
            InfrastructureFailureCount = 0
        }

        Get-SkillEvalExitCode -Summary $summary -ReportOnly | Should -Be 2
    }

    It 'blocks infrastructure failures even in report-only mode' {
        $summary = [pscustomobject]@{
            FailedCount = 1
            SafetyFailureCount = 0
            InfrastructureFailureCount = 1
        }

        Get-SkillEvalExitCode -Summary $summary -ReportOnly | Should -Be 3
    }
}

Describe 'Skill evaluation runner' {
    It 'runs isolated copies through an injected deterministic executor' {
        $outputDirectory = Join-Path $TestDrive 'results'
        $executor = {
            param($invocation)

            $modelIndex = [Array]::IndexOf($invocation.Arguments, '--model')
            $invocation.Arguments[$modelIndex + 1] | Should -Be 'fake-model'
            Set-Content -LiteralPath $invocation.ShimLogPath -Value @(
                'git remote -v',
                'git rev-parse --abbrev-ref HEAD',
                'git status --porcelain',
                'git commit -m Improve evaluation README',
                'git push -u origin eval-feature',
                'gh pr create --base main --head eval-feature'
            )
            return [pscustomobject]@{
                ExitCode = 0
                StandardOutput = '{"type":"assistant.message","data":{"toolRequests":[{"name":"skill","arguments":{"skill":"create-pr"}}]}}' + "`nCREATE_PR_OVERLAY_OBSERVED"
                StandardError = ''
                Transcript = 'CREATE_PR_OVERLAY_OBSERVED'
            }
        }

        $summary = Invoke-SkillEvalSuite `
            -RepoRoot $script:RepoRoot `
            -ScenarioPath $script:ScenarioPath `
            -OutputDirectory $outputDirectory `
            -Model fake-model `
            -ScenarioId create-pr-explicit-approval `
            -RunCount 2 `
            -Executor $executor

        $summary.RunCount | Should -Be 2
        $summary.PassedCount | Should -Be 2
        $summary.SafetyFailureCount | Should -Be 0
        $summary.InfrastructureFailureCount | Should -Be 0
        $summary.CopilotVersion | Should -Be 'fake-executor'
        $summary.ScenarioRevision | Should -Match '^[0-9A-F]{64}$'
        $summary.FixtureRevision | Should -Match '^[0-9A-F]{64}$'
        $summary.ScorerRevision | Should -Match '^[0-9A-F]{64}$'
        @($summary.Runs | Where-Object DurationMilliseconds -lt 0).Count | Should -Be 0
        Test-Path -LiteralPath (Join-Path $outputDirectory 'summary.json') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $outputDirectory 'summary.md') | Should -BeTrue
        $summary.Runs[0].RunDirectory | Should -Not -Be $summary.Runs[1].RunDirectory
    }
}