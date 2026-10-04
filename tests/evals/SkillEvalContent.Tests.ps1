#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.2.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:ScenarioPath = Join-Path $script:RepoRoot 'evals\scenarios\technical-writing.json'
    $script:PwshPath = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
    Import-Module (Join-Path $script:RepoRoot 'evals\SkillEval.psm1') -Force
    Import-Module (Join-Path $script:RepoRoot 'evals\SkillEvalContent.psm1') -Force
    $script:CliPath = Get-SkillEvalContentCliPath
    $script:ProcessFixturePath = Join-Path $script:RepoRoot 'tests\skill-evaluation\process-fixture\bin\Release\net10.0\SkillEvaluation.ProcessFixture.dll'

    function Invoke-ContentReplay([string] $source, [string] $destination, [string] $scenarioPath) {
        Invoke-SkillEvalContentCli -Arguments @(
            'rescore',
            '--repo-root', $script:RepoRoot,
            '--scenario', $scenarioPath,
            '--input-directory', $source,
            '--output-directory', $destination,
            '--report-only', 'true'
        )
    }

    function New-FileScenario([string] $root) {
        $scenarioDirectory = Join-Path $root 'scenarios'
        New-Item -ItemType Directory -Path $scenarioDirectory, (Join-Path $root 'fixtures') | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'evals\SkillEvalScorer.ps1') -Destination $root
        $scenario = Get-SkillEvalScenarios -Path $script:ScenarioPath |
            Where-Object id -eq 'technical-writing-artifact-pull-request'
        $scenario = $scenario | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        $scenario.contentEvaluation.artifactTargets = @(
            [pscustomobject]@{ id = 'body'; source = 'file'; path = 'body with spaces.md' })
        $scenario.requiredResponsePatterns = @('^Done\.$')
        $scenario.forbiddenResponsePatterns = @()
        $scenario.requireUnchangedWorktree = $false
        $path = Join-Path $scenarioDirectory 'file.json'
        @{ schemaVersion = 1; scenarios = @($scenario) } |
            ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $path
        return $path
    }
}

Describe 'Skill content evaluator process boundary' {
    It 'rejects a preparation that omits a declared profile before scheduling any attempt' {
        Mock Invoke-SkillEvalContentCli -ModuleName SkillEval -MockWith {
            [pscustomobject]@{ ExitCode = 0; StandardOutput = '[]'; StandardError = '' }
        }
        {
            Invoke-SkillEvalSuite -RepoRoot $script:RepoRoot `
                -ScenarioPath $script:ScenarioPath -ScenarioId technical-writing-artifact-review-comment `
                -OutputDirectory (Join-Path $TestDrive 'omitted-profile') -Model fake-model `
                -RunCount 1 -Executor { throw 'No attempt should be scheduled.' }
        } | Should -Throw '*Content preparation omitted profiled scenario*'
    }

    It 'keeps a parseable child result with nonzero exit as failure' {
        $receipt = Invoke-SkillEvalContentCli -Arguments @('exit-with-json') -CliPath $script:ProcessFixturePath
        $receipt.ExitCode | Should -Be 7
        ($receipt.StandardOutput | ConvertFrom-Json).schemaVersion | Should -Be 1
        $receipt.StandardError | Should -Match 'Controlled child failure'
    }

    It 'terminates its owned process after a timeout' {
        $watch = [Diagnostics.Stopwatch]::StartNew()
        { Invoke-SkillEvalContentCli -Arguments @('sleep') -CliPath $script:ProcessFixturePath -TimeoutSeconds 1 } |
            Should -Throw '*timed out after 1 seconds*'
        $watch.Stop()
        $watch.Elapsed.TotalSeconds | Should -BeLessThan 10
    }

    It 'preserves exact argument values and restores no ambient environment state' {
        $before = $env:PATH
        $receipt = Invoke-SkillEvalContentCli -Arguments @(
            'arguments', 'a path with spaces', 'quoted"value', '', 'end\') -CliPath $script:ProcessFixturePath
        $receipt.ExitCode | Should -Be 0
        $values = ConvertFrom-Json -InputObject $receipt.StandardOutput -NoEnumerate
        $values | Should -Be @('a path with spaces', 'quoted"value', '', 'end\')
        $env:PATH | Should -BeExactly $before
    }

    It 'rejects a missing built evaluator without silently skipping profiles' {
        { Get-SkillEvalContentCliPath -CliPath (Join-Path $TestDrive 'missing.dll') } |
            Should -Throw '*Content evaluator is not built*'
    }

    It 'passes path values containing spaces through the real CLI' {
        $bodyPath = Join-Path $TestDrive 'body with spaces.md'
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'evals\fixtures\output-quality\pr-description.md') `
            -Destination $bodyPath
        $receipt = Invoke-SkillEvalContentCli -Arguments @(
            'lint-artifact',
            '--repo-root', $script:RepoRoot,
            '--scenario', $script:ScenarioPath,
            '--scenario-id', 'technical-writing-artifact-pull-request',
            '--target-id', 'body',
            '--input', $bodyPath
        )
        $receipt.ExitCode | Should -Be 0
        $receipt.StandardError | Should -BeNullOrEmpty
        $record = $receipt.StandardOutput | ConvertFrom-Json
        $record.literalStatus | Should -BeExactly 'passed'
        $record.usefulOutcome | Should -BeExactly 'pending'
    }
}

Describe 'Current model roster receipt integrity' {
    It 'checks requested and served identity and token reconciliation: <Model>' -ForEach @(
        @{ Model = 'gpt-6.1-sol' }
        @{ Model = 'gpt-6-luna' }
    ) {
        $usagePath = Join-Path $TestDrive "$Model-usage.json"
        $telemetryPath = Join-Path $TestDrive "$Model-telemetry.jsonl"
        $metrics = @{}
        $metrics[$Model] = @{
            requests = @{ count = 1 }
            usage = @{ inputTokens = 12; outputTokens = 4 }
        }
        @{ totalUserRequests = 1; modelMetrics = $metrics } |
            ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $usagePath
        $span = @{
            type = 'span'
            status = @{ code = 0 }
            attributes = @{
                'gen_ai.operation.name' = 'chat'
                'gen_ai.request.model' = $Model
                'gen_ai.response.model' = $Model
                'gen_ai.request.reasoning.level' = 'medium'
                'gen_ai.usage.input_tokens' = 12
                'gen_ai.usage.output_tokens' = 4
            }
        }
        $span | ConvertTo-Json -Depth 6 -Compress | Set-Content -LiteralPath $telemetryPath
        $module = Get-Module SkillEval
        $check = {
            & $module {
                param($usage, $telemetry, $expected)
                Assert-SkillEvalUsageReceipt -Path $usage -TelemetryPath $telemetry -ExpectedModel $expected
            } $usagePath $telemetryPath $Model
        }
        $check | Should -Not -Throw
        $span.attributes['gen_ai.response.model'] = 'gpt-6-sol'
        $span | ConvertTo-Json -Depth 6 -Compress | Set-Content -LiteralPath $telemetryPath
        $check | Should -Throw '*requested model and medium effort*'
        $span.attributes['gen_ai.response.model'] = $Model
        $span.attributes['gen_ai.usage.input_tokens'] = 13
        $span | ConvertTo-Json -Depth 6 -Compress | Set-Content -LiteralPath $telemetryPath
        $check | Should -Throw '*does not reconcile*'
    }
}

Describe 'Skill content immutable capture and replay' {
    It 'rejects a prompt edited after preparation before accepting capture' {
        $scenarioPath = New-FileScenario -root (Join-Path $TestDrive 'prompt-drift-evals')
        $executor = {
            param($invocation)
            $document = Get-Content -LiteralPath $scenarioPath -Raw | ConvertFrom-Json
            $document.scenarios[0].prompt += ' Add a Known gaps section.'
            $document | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $scenarioPath
            [IO.File]::WriteAllText((Join-Path $invocation.WorkingDirectory 'body with spaces.md'),
                "## Summary`n`nPreserve headings and list boundaries.`n`n## Validation`n`nWindows: 14 tests passed.`n`nLinux validation has not run.`n")
            return [pscustomobject]@{
                ExitCode = 0
                StandardOutput = '{"type":"assistant.message","data":{"content":"Done.","toolRequests":[{"name":"skill","arguments":{"skill":"technical-writing"}}]}}'
                StandardError = ''
            }
        }.GetNewClosure()
        $summary = Invoke-SkillEvalSuite -RepoRoot $script:RepoRoot `
            -ScenarioPath $scenarioPath -OutputDirectory (Join-Path $TestDrive 'prompt-drift-source') `
            -Model fake-model -RunCount 1 -Executor $executor
        $summary.InfrastructureFailureCount | Should -Be 1
        $summary.SafetyFailureCount | Should -Be 0
        $summary.Runs[0].Error | Should -Match 'Content inputs or source output changed'
    }

    It 'preserves routing and safety while leaving useful outcomes pending: <ScenarioId>' -ForEach @(
        @{ ScenarioId = 'technical-writing-artifact-pull-request'; Artifact = 'pr-description.md'; Target = 'body' }
        @{ ScenarioId = 'technical-writing-artifact-review-comment'; Artifact = 'review-comment.md'; Target = 'comment' }
    ) {
        $source = Join-Path $TestDrive "$ScenarioId-source"
        $body = Get-Content -LiteralPath (Join-Path $script:RepoRoot "evals\fixtures\output-quality\$Artifact") -Raw
        $executor = {
            param($invocation)
            $promptIndex = [Array]::IndexOf($invocation.Arguments, '-p')
            $invocation.Arguments[$promptIndex + 1] | Should -Not -Match '\{\{suppliedFacts\}\}'
            $invocation.ContentProfileRevision | Should -Match '^[0-9A-F]{64}$'
            return [pscustomobject]@{
                ExitCode = 0
                StandardOutput = @{
                    type = 'assistant.message'
                    data = @{
                        content = $body
                        toolRequests = @(@{ name = 'skill'; arguments = @{ skill = 'technical-writing' } })
                    }
                } | ConvertTo-Json -Depth 6 -Compress
                StandardError = ''
            }
        }.GetNewClosure()
        $summary = Invoke-SkillEvalSuite -RepoRoot $script:RepoRoot `
            -ScenarioPath $script:ScenarioPath -ScenarioId $ScenarioId `
            -OutputDirectory $source -Model fake-model -RunCount 1 -Executor $executor
        $summary.PassedCount | Should -Be 1
        $summary.SafetyFailureCount | Should -Be 0
        $summary.InfrastructureFailureCount | Should -Be 0
        $summary.Runs[0].ArtifactManifestRevision | Should -Match '^[0-9A-F]{64}$'
        $manifestPath = Join-Path $summary.Runs[0].RunDirectory 'artifacts.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.modelOutputRevision | Should -BeExactly $summary.Runs[0].ModelOutputRevision
        $manifest.profileRevision | Should -BeExactly $summary.Runs[0].ContentProfileRevision
        $manifest.inputRevision | Should -BeExactly $summary.Runs[0].ContentInputRevision
        $before = (Get-FileHash -LiteralPath (Join-Path $source 'summary.json') -Algorithm SHA256).Hash
        $destination = Join-Path $TestDrive "$ScenarioId-derived"
        $receipt = Invoke-ContentReplay -source $source -destination $destination -scenarioPath $script:ScenarioPath
        $receipt.ExitCode | Should -Be 0 -Because $receipt.StandardError
        $derived = $receipt.StandardOutput | ConvertFrom-Json
        $derived.runCount | Should -Be 1
        $derived.usefulPassedCount | Should -Be 0
        $derived.pendingCount | Should -Be 1
        $derived.runs[0].sourceResult.Passed | Should -BeTrue
        $derived.runs[0].sourceResult.SafetyPassed | Should -BeTrue
        $derived.runs[0].content.literalStatus | Should -BeExactly 'passed'
        $derived.runs[0].content.semanticStatus | Should -BeExactly 'pending'
        (Get-FileHash -LiteralPath (Join-Path $source 'summary.json') -Algorithm SHA256).Hash |
            Should -BeExactly $before
        Test-Path -LiteralPath (Join-Path $destination "$ScenarioId\run-1\semantic.json") |
            Should -BeTrue
        $patternRescore = Invoke-SkillEvalRescore -RepoRoot $script:RepoRoot `
            -ScenarioPath $script:ScenarioPath -InputDirectory $source `
            -OutputDirectory (Join-Path $TestDrive "$ScenarioId-pattern-rescore")
        $patternRescore.Runs[0].ArtifactManifestRevision | Should -BeExactly $summary.Runs[0].ArtifactManifestRevision
        $patternRescore.Runs[0].ContentProfileRevision | Should -BeExactly $summary.Runs[0].ContentProfileRevision
        $patternRescore.Runs[0].ContentInputRevision | Should -BeExactly $summary.Runs[0].ContentInputRevision

        Set-Content -LiteralPath (Join-Path $summary.Runs[0].RunDirectory "artifacts\$Target.utf8") -Value 'Tampered.'
        $tampered = Invoke-ContentReplay -source $source `
            -destination (Join-Path $TestDrive "$ScenarioId-tampered") -scenarioPath $script:ScenarioPath
        $tampered.ExitCode | Should -Be 3
        ($tampered.StandardOutput | ConvertFrom-Json).infrastructureFailureCount | Should -Be 1
    }

    It 'snapshots a declared file rather than evaluating the closing Done message' {
        $scenarioPath = New-FileScenario -root (Join-Path $TestDrive 'file-evals')
        $executor = {
            param($invocation)
            [IO.File]::WriteAllText((Join-Path $invocation.WorkingDirectory 'body with spaces.md'),
                "## Summary`n`nPreserve headings and list boundaries.`n`n## Validation`n`nWindows: 14 tests passed.`n`nLinux validation has not run.`n")
            return [pscustomobject]@{
                ExitCode = 0
                StandardOutput = '{"type":"assistant.message","data":{"content":"Done.","toolRequests":[{"name":"skill","arguments":{"skill":"technical-writing"}}]}}'
                StandardError = ''
            }
        }
        $source = Join-Path $TestDrive 'file-source'
        $summary = Invoke-SkillEvalSuite -RepoRoot $script:RepoRoot `
            -ScenarioPath $scenarioPath -OutputDirectory $source -Model fake-model `
            -RunCount 1 -Executor $executor
        $summary.InfrastructureFailureCount | Should -Be 0
        $snapshot = Join-Path $summary.Runs[0].RunDirectory 'artifacts\body.utf8'
        (Get-Content -LiteralPath $snapshot -Raw) | Should -Match '14 tests passed'
        (Get-Content -LiteralPath $snapshot -Raw) | Should -Not -Match '^Done\.'
        $receipt = Invoke-ContentReplay -source $source `
            -destination (Join-Path $TestDrive 'file-derived') -scenarioPath $scenarioPath
        $receipt.ExitCode | Should -Be 0
        ($receipt.StandardOutput | ConvertFrom-Json).pendingCount | Should -Be 1
    }

    It 'records missing artifact capture as infrastructure failure without changing observed safety' {
        $scenarioPath = New-FileScenario -root (Join-Path $TestDrive 'missing-file-evals')
        $executor = {
            param($invocation)
            return [pscustomobject]@{
                ExitCode = 0
                StandardOutput = '{"type":"assistant.message","data":{"content":"Done.","toolRequests":[{"name":"skill","arguments":{"skill":"technical-writing"}}]}}'
                StandardError = ''
            }
        }
        $summary = Invoke-SkillEvalSuite -RepoRoot $script:RepoRoot `
            -ScenarioPath $scenarioPath -OutputDirectory (Join-Path $TestDrive 'missing-file-source') `
            -Model fake-model -RunCount 1 -Executor $executor
        $summary.InfrastructureFailureCount | Should -Be 1
        $summary.SafetyFailureCount | Should -Be 0
        $summary.Runs[0].Error | Should -Match 'Declared file is missing'
        Get-SkillEvalExitCode -Summary $summary -ReportOnly | Should -Be 3
    }

    It 'runs the public semantic entry point in a fresh PowerShell process' {
        $source = Join-Path $TestDrive 'entry-source'
        $executor = {
            param($invocation)
            return [pscustomobject]@{
                ExitCode = 0
                StandardOutput = '{"type":"assistant.message","data":{"content":"Required: Complete operation A before operation B. The outbound request can begin after cancellation. Correct the ordering.","toolRequests":[{"name":"skill","arguments":{"skill":"technical-writing"}}]}}'
                StandardError = ''
            }
        }
        $summary = Invoke-SkillEvalSuite -RepoRoot $script:RepoRoot `
            -ScenarioPath $script:ScenarioPath -ScenarioId technical-writing-artifact-review-comment `
            -OutputDirectory $source -Model fake-model -RunCount 1 -Executor $executor
        $summary.InfrastructureFailureCount | Should -Be 0
        $destination = Join-Path $TestDrive 'entry-derived'
        $output = & $script:PwshPath -NoProfile -File (Join-Path $script:RepoRoot 'evals\Invoke-SkillEvalSemantic.ps1') `
            -InputDirectory $source -OutputDirectory $destination -ReportOnly 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
        ($output -join "`n") | Should -Match 'useful passes: 0; pending: 1'
        (Get-Content -LiteralPath (Join-Path $destination 'summary.json') -Raw | ConvertFrom-Json).usefulPassedCount |
            Should -Be 0
    }

    It 'rejects a Windows junction artifact source' -Skip:(-not $IsWindows) {
        $root = Join-Path $TestDrive 'junction-root'
        $outside = Join-Path $TestDrive 'outside'
        New-Item -ItemType Directory -Path $root, $outside | Out-Null
        Set-Content -LiteralPath (Join-Path $outside 'body.md') -Value 'Outside.'
        New-Item -ItemType Junction -Path (Join-Path $root 'linked') -Target $outside | Out-Null
        $receipt = Invoke-SkillEvalContentCli -Arguments @(
            'capture',
            '--repo-root', $script:RepoRoot,
            '--scenario', (New-FileScenario -root (Join-Path $TestDrive 'junction-evals')),
            '--scenario-id', 'technical-writing-artifact-pull-request',
            '--workspace', (Join-Path $root 'linked'),
            '--run-directory', $root,
            '--run-number', '1',
            '--scenario-revision', ('A' * 64)
        )
        $receipt.ExitCode | Should -Be 3
        $receipt.StandardError | Should -Match 'Links and reparse points'
    }
}
