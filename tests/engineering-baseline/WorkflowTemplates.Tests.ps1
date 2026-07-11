#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:WorkflowRoot = Join-Path $script:RepoRoot 'skills/engineering-baseline/scripts/template/.github/workflows'
    $script:ScaffoldScript = Get-Content -LiteralPath (
        Join-Path $script:RepoRoot 'skills/engineering-baseline/scripts/New-DotnetRepo.ps1') -Raw
    $script:Ci = Get-Content -LiteralPath (Join-Path $script:WorkflowRoot 'ci.yml.tmpl') -Raw
    $script:FullCi = Get-Content -LiteralPath (Join-Path $script:WorkflowRoot 'full-ci.yml.tmpl') -Raw
    $script:CodeQl = Get-Content -LiteralPath (Join-Path $script:WorkflowRoot 'codeql.yml.tmpl') -Raw
    $script:AgentFiles = Get-Content -LiteralPath (Join-Path $script:WorkflowRoot 'agent-files.yml.tmpl') -Raw
}

Describe 'Cost-aware scaffold workflow contracts' {
    It 'uses one Release merge-candidate gate without a duplicate push run' {
        $script:Ci | Should -Match '(?m)^  pull_request:'
        $script:Ci | Should -Match '(?m)^  merge_group:'
        $script:Ci | Should -Match '(?m)^  workflow_dispatch:'
        $script:Ci | Should -Not -Match '(?m)^  push:'
        $script:Ci | Should -Match 'runs-on: \{\{CI_RUNNER\}\}'
        $script:Ci | Should -Match 'dotnet build --configuration Release'
        $script:Ci | Should -Match 'dotnet test --configuration Release'
        $script:Ci | Should -Not -Match '(?m)^\s+matrix:'
    }

    It 'uses Windows only when the legacy multi-target archetype requires it' {
        $script:ScaffoldScript | Should -Match (
            '\$CiRunner\s*=\s*if \(\$IsMultiTarget\) \{ ''windows-latest'' \} else \{ ''ubuntu-latest'' \}')
        $script:ScaffoldScript | Should -Match 'CI_RUNNER\s*=\s*\$CiRunner'
    }

    It 'keeps Debug and Release breadth in one manually dispatched job' {
        $script:FullCi | Should -Match '(?m)^  workflow_dispatch:'
        $script:FullCi | Should -Not -Match '(?m)^  (?:push|pull_request|merge_group|schedule):'
        $script:FullCi | Should -Match 'Maintainers run this before each release'
        $script:FullCi | Should -Match 'dotnet build --configuration Debug'
        $script:FullCi | Should -Match 'dotnet test --configuration Debug'
        $script:FullCi | Should -Match 'dotnet build --configuration Release'
        $script:FullCi | Should -Match 'dotnet test --configuration Release'
        $script:FullCi | Should -Not -Match '(?m)^\s+matrix:'
    }

    It 'keeps CodeQL on pull requests and a schedule without a post-merge duplicate' {
        $script:CodeQl | Should -Match '(?m)^  pull_request:'
        $script:CodeQl | Should -Match '(?m)^  merge_group:'
        $script:CodeQl | Should -Match '(?m)^  schedule:'
        $script:CodeQl | Should -Match '(?m)^  workflow_dispatch:'
        $script:CodeQl | Should -Match '(?m)^  actions: read\r?$'
        $script:CodeQl | Should -Match '(?m)^  security-events: write\r?$'
        $script:CodeQl | Should -Not -Match '(?m)^  push:'
    }

    It 'requires strict merge and CodeQL rules when post-merge runs are omitted' {
        $script:ScaffoldScript | Should -Match 'enable GitHub Code Security'
        $script:ScaffoldScript | Should -Match 'branches up to date or a'
        $script:ScaffoldScript | Should -Match 'CodeQL code-scanning results'
        $script:ScaffoldScript | Should -Match 'replacement scanner''s status check'
        $script:ScaffoldScript | Should -Match 'agent-files\.yml'
    }

    It 'runs the mirror check only for relevant pull-request paths on Linux Slim' {
        $script:AgentFiles | Should -Match '(?m)^  pull_request:'
        $script:AgentFiles | Should -Match '(?m)^    paths:'
        $script:AgentFiles | Should -Match '(?m)^      - AGENTS\.md\r?$'
        $script:AgentFiles | Should -Match '(?m)^    runs-on: ubuntu-slim\r?$'
        $script:AgentFiles | Should -Not -Match '(?m)^  push:'
    }
}
