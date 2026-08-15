#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot 'SkillArtifactTestHelpers.ps1')
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:SkillsRoot = Join-Path $script:RepoRoot 'skills'
    $script:AgentsRoot = Join-Path $script:RepoRoot 'agents'

    function Get-SkillRecord ([string] $skillDirectory) {
        $skillPath = Join-Path $skillDirectory 'SKILL.md'
        $content = Get-Content -LiteralPath $skillPath -Raw
        $nameMatch = [regex]::Match($content, '(?m)^name:\s*(?<value>[^\r\n]+)\r?$')
        if (-not $nameMatch.Success) { throw "Could not parse name from $skillPath" }

        $metadata = @{}
        $insideMetadata = $false
        foreach ($line in ($content -split "\r?\n")) {
            if ($line -ceq 'metadata:') {
                $insideMetadata = $true
                continue
            }
            if (-not $insideMetadata) { continue }
            if ($line -match '^\s+(?<key>[a-z][a-z-]*):\s*(?<value>.*)$') {
                $metadata[$Matches.key] = $Matches.value.Trim()
                continue
            }
            if ($line -match '^\S') { break }
        }

        [pscustomobject]@{
            Name = $nameMatch.Groups['value'].Value.Trim()
            Directory = $skillDirectory
            Path = $skillPath
            Metadata = $metadata
        }
    }

    function Get-RelationshipNames ([string] $value) {
        if ([string]::IsNullOrWhiteSpace($value) -or $value -eq 'none') { return @() }
        return @($value -split ',' | ForEach-Object { $_.Trim() })
    }

    $script:SkillRecords = @(Get-ChildItem -LiteralPath $script:SkillsRoot -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') } |
        Sort-Object Name |
        ForEach-Object { Get-SkillRecord $_.FullName })
    $script:SkillNames = @($script:SkillRecords.Name)
}

Describe 'Skill catalog contracts' {
    It 'ships the shared installed-artifact test helper' {
        Test-Path -LiteralPath (
            Join-Path $PSScriptRoot 'SkillArtifactTestHelpers.ps1') -PathType Leaf |
            Should -BeTrue
    }

    It 'contains exactly one catalog link for every source skill' {
        $catalog = Get-Content -LiteralPath (Join-Path $script:SkillsRoot 'README.md') -Raw
        $inventory = ($catalog -split [regex]::Escape('<!-- portfolio-matrix:start -->'), 2)[0]
        $catalogNames = @([regex]::Matches($inventory, '\]\(\./(?<name>[a-z0-9-]+)/SKILL\.md\)') |
            ForEach-Object { $_.Groups['name'].Value })

        @($catalogNames | Group-Object | Where-Object Count -ne 1).Count | Should -Be 0
        @(Compare-Object ($script:SkillNames | Sort-Object) ($catalogNames | Sort-Object)).Count | Should -Be 0
    }

    It 'keeps the generated portfolio matrix current' {
        $generator = Join-Path $script:RepoRoot 'tools/Update-SkillCatalog.ps1'
        $output = & pwsh -NoProfile -File $generator 2>&1
        $LASTEXITCODE | Should -Be 0 -Because "$output"
    }

    It 'generates the portfolio matrix byte-for-byte idempotently' {
        $generator = Join-Path $script:RepoRoot 'tools/Update-SkillCatalog.ps1'
        $temporarySkills = Join-Path $TestDrive 'catalog-idempotency'
        Copy-Item -LiteralPath $script:SkillsRoot -Destination $temporarySkills -Recurse

        & pwsh -NoProfile -File $generator -SkillsRoot $temporarySkills -Apply *> $null
        $LASTEXITCODE | Should -Be 0
        $firstHash = (Get-FileHash (Join-Path $temporarySkills 'README.md') -Algorithm SHA256).Hash

        & pwsh -NoProfile -File $generator -SkillsRoot $temporarySkills -Apply *> $null
        $LASTEXITCODE | Should -Be 0
        $secondHash = (Get-FileHash (Join-Path $temporarySkills 'README.md') -Algorithm SHA256).Hash

        $secondHash | Should -Be $firstHash
    }

    It 'ignores an end marker that appears before the portfolio start marker' {
        $generator = Join-Path $script:RepoRoot 'tools/Update-SkillCatalog.ps1'
        $temporarySkills = Join-Path $TestDrive 'catalog-marker-order'
        Copy-Item -LiteralPath $script:SkillsRoot -Destination $temporarySkills -Recurse
        $catalogPath = Join-Path $temporarySkills 'README.md'
        $catalog = Get-Content -LiteralPath $catalogPath -Raw
        Set-Content -LiteralPath $catalogPath -NoNewline -Value "<!-- portfolio-matrix:end -->`n$catalog"

        $output = & pwsh -NoProfile -File $generator -SkillsRoot $temporarySkills 2>&1
        $LASTEXITCODE | Should -Be 0 -Because "$output"
    }

    It 'resolves every required and related skill to a source core' {
        foreach ($record in $script:SkillRecords) {
            foreach ($relationshipField in @('requires', 'related')) {
                foreach ($relationshipName in (Get-RelationshipNames $record.Metadata[$relationshipField])) {
                    $relationshipName | Should -Not -Be $record.Name -Because "$($record.Name) cannot reference itself"
                    $script:SkillNames | Should -Contain $relationshipName -Because "$($record.Name) metadata.$relationshipField must resolve"
                }
            }
        }
    }

    It 'requires technical-writing for every remote-write workflow' {
        $remoteWriteRecords = @($script:SkillRecords | Where-Object { $_.Metadata.risk -eq 'remote-write' })

        @($remoteWriteRecords.Name | Sort-Object) | Should -Be @(
            'address-pr-feedback',
            'create-pr',
            'engineering-baseline',
            'manage-skills')
        foreach ($record in $remoteWriteRecords) {
            Get-RelationshipNames $record.Metadata.requires |
                Should -Contain 'technical-writing' -Because "$($record.Name) publishes human-facing text"
        }
    }

    It 'permits public-source provenance while keeping personalized content private' {
        $userVoice = @($script:SkillRecords | Where-Object Name -eq 'user-voice')
        $userVoice.Count | Should -Be 1
        $userVoice[0].Metadata.risk | Should -Be 'local-write'
        Get-RelationshipNames $userVoice[0].Metadata.requires |
            Should -Contain 'manage-skills'

        Test-Path -LiteralPath (Join-Path $script:SkillsRoot 'user-voice-profile') |
            Should -BeFalse
        $technicalWriting = @($script:SkillRecords | Where-Object Name -eq 'technical-writing')[0]
        Get-RelationshipNames $technicalWriting.Metadata.requires |
            Should -Not -Contain 'user-voice-profile'
        Get-RelationshipNames $technicalWriting.Metadata.related |
            Should -Contain 'user-voice'

        Get-SkillArtifactPrivacyContent $userVoice[0].Directory |
            Should -Not -Match '(?i)jeremy[- ]kuhne|JeremyKuhne'

        $installedFixture = Join-Path $TestDrive '[provenance-bearing-user-voice]'
        New-Item -ItemType Directory -Path $installedFixture | Out-Null
        $fixtureSkillPath = Join-Path $installedFixture 'SKILL.md'
                $fixtureContent = @(
                        '---'
                        'name: user-voice'
                        'description: Generic lifecycle fixture.'
                        'metadata:'
                        '  github-path: skills/user-voice'
                        '  github-pinned: 0123456789012345678901234567890123456789'
                        '  github-ref: 0123456789012345678901234567890123456789'
                        '  github-repo: https://github.com/JeremyKuhne/agent-skills'
                        '  github-tree-sha: 0123456789012345678901234567890123456789'
                        '---'
                        ''
                        '# User voice'
                        ''
                        'Generic lifecycle content.'
                ) -join "`n"
        [System.IO.File]::WriteAllText($fixtureSkillPath, $fixtureContent)
        (Get-SkillArtifactDocument $fixtureSkillPath).Frontmatter |
            Should -Match 'JeremyKuhne'
        Get-SkillArtifactPrivacyContent $installedFixture |
            Should -Not -Match 'JeremyKuhne'

        Add-Content -LiteralPath $fixtureSkillPath `
            -Value "`nPrivate profile subject: JeremyKuhne"
        Get-SkillArtifactPrivacyContent $installedFixture |
            Should -Match 'JeremyKuhne'

        [System.IO.File]::WriteAllText($fixtureSkillPath, $fixtureContent)
        [System.IO.File]::WriteAllText(
            (Join-Path $installedFixture 'private-resource.md'),
            'Private profile subject: JeremyKuhne')
        Get-SkillArtifactPrivacyContent $installedFixture |
            Should -Match 'JeremyKuhne'
    }

    It 'has an acyclic required-skill graph' {
        $recordsByName = @{}
        foreach ($record in $script:SkillRecords) { $recordsByName[$record.Name] = $record }
        $states = @{}
        $visitRequirement = $null
        $visitRequirement = {
            param([string] $skillName)

            if ($states[$skillName] -eq 'visited') { return }
            if ($states[$skillName] -eq 'visiting') { throw "Required-skill cycle includes '$skillName'." }

            $states[$skillName] = 'visiting'
            foreach ($requiredName in (Get-RelationshipNames $recordsByName[$skillName].Metadata.requires)) {
                & $visitRequirement $requiredName
            }
            $states[$skillName] = 'visited'
        }
        foreach ($skillName in $script:SkillNames) {
            { & $visitRequirement $skillName } | Should -Not -Throw
        }
    }
}


Describe 'Agent contracts' {
    It 'catalogs every agent exactly once' {
        $agentFiles = @(Get-ChildItem -LiteralPath $script:AgentsRoot -Filter '*.agent.md' -File | Sort-Object Name)
        $catalog = Get-Content -LiteralPath (Join-Path $script:AgentsRoot 'README.md') -Raw
        $catalogFiles = @([regex]::Matches($catalog, '\]\(\./(?<file>[a-z0-9-]+\.agent\.md)\)') |
            ForEach-Object { $_.Groups['file'].Value })

        @($catalogFiles | Group-Object | Where-Object Count -ne 1).Count | Should -Be 0
        @(Compare-Object $agentFiles.Name ($catalogFiles | Sort-Object)).Count | Should -Be 0
    }

    It 'gives every agent a description and recognized tool identifiers' {
        $allowedTools = @('search', 'read', 'edit', 'web', 'execute', 'web/fetch', 'search/usages', 'search/changes', 'read/problems')
        foreach ($agentFile in (Get-ChildItem -LiteralPath $script:AgentsRoot -Filter '*.agent.md' -File)) {
            $content = Get-Content -LiteralPath $agentFile.FullName -Raw
            $frontmatterMatch = [regex]::Match($content, '\A---\r?\n(?<body>.*?)\r?\n---', 'Singleline')
            $frontmatterMatch.Success | Should -BeTrue -Because "$($agentFile.Name) needs YAML frontmatter"
            $frontmatter = $frontmatterMatch.Groups['body'].Value
            $frontmatter | Should -Match '(?m)^description:\s*\S'

            $toolsMatch = [regex]::Match($frontmatter, '(?m)^tools:\s*\[(?<tools>[^\]]*)\]\s*$')
            $toolsMatch.Success | Should -BeTrue -Because "$($agentFile.Name) tools must use the supported inline-list form"
            $tools = @($toolsMatch.Groups['tools'].Value -split ',' |
                ForEach-Object { $_.Trim().Trim("'", '"') } |
                Where-Object { $_ })
            foreach ($tool in $tools) { $allowedTools | Should -Contain $tool }
        }
    }
}

Describe 'Distribution manifest contracts' {
    BeforeAll {
        $script:Plugin = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'plugin.json') -Raw | ConvertFrom-Json
        $script:Marketplace = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/plugin/marketplace.json') -Raw | ConvertFrom-Json
        $script:Mcp = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.mcp.json') -Raw | ConvertFrom-Json
    }

    It 'uses a valid plugin identity and semantic version' {
        $script:Plugin.name | Should -Match '^[a-z0-9]+(?:-[a-z0-9]+)*$'
        $script:Plugin.version | Should -Match '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$'
        $script:Plugin.license | Should -Be 'MIT'
        $script:Plugin.author.name | Should -Not -BeNullOrEmpty
        $script:Plugin.author.url | Should -Match '^https://'
        $script:Plugin.repository | Should -Match '^https://'
        @($script:Plugin.keywords).Count | Should -BeGreaterThan 0
    }

    It 'points every plugin component at an existing artifact' {
        foreach ($componentPath in @($script:Plugin.skills) + @($script:Plugin.agents) + @($script:Plugin.mcpServers)) {
            Test-Path -LiteralPath (Join-Path $script:RepoRoot $componentPath) | Should -BeTrue
        }
        $script:SkillRecords.Count | Should -BeGreaterThan 0
        @(Get-ChildItem -LiteralPath $script:AgentsRoot -Filter '*.agent.md' -File).Count | Should -BeGreaterThan 0
    }

    It 'keeps the marketplace entry aligned with plugin.json' {
        $entry = @($script:Marketplace.plugins) | Where-Object name -eq $script:Plugin.name
        @($entry).Count | Should -Be 1
        $entry.version | Should -Be $script:Plugin.version
        $entry.source | Should -Be './'
        $script:Marketplace.metadata.version | Should -Be $script:Plugin.version
    }

    It 'uses typed and pinned MCP server definitions' {
        foreach ($serverProperty in $script:Mcp.mcpServers.PSObject.Properties) {
            $server = $serverProperty.Value
            @('http', 'stdio') | Should -Contain $server.type
            if ($server.type -eq 'http') {
                $server.url | Should -Match '^https://'
            }
            else {
                $server.command | Should -Not -BeNullOrEmpty
                @($server.args | Where-Object { $_ -match '@\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$' }).Count |
                    Should -BeGreaterThan 0 -Because "$($serverProperty.Name) must pin an executable package version"
            }
        }
    }

    It 'matches an exact release tag when HEAD is tagged' {
        $tagsAtHead = @(& git -C $script:RepoRoot tag --points-at HEAD |
            Where-Object { $_ -match '^v\d+\.\d+\.\d+$' })
        $LASTEXITCODE | Should -Be 0
        foreach ($tag in $tagsAtHead) {
            $tag.TrimStart('v') | Should -Be $script:Plugin.version
        }
    }
}

Describe 'Workflow pin contracts' {
    It 'pins repository CI actions to immutable SHAs with readable version comments' {
        foreach ($workflow in (Get-ChildItem (Join-Path $script:RepoRoot '.github/workflows') -Filter '*.yml' -File)) {
            foreach ($line in (Get-Content -LiteralPath $workflow.FullName | Where-Object { $_ -match '\buses:' })) {
                $line | Should -Match '@[0-9a-f]{40}\s+#\s+v\d'
            }
        }
    }

    It 'keeps scaffold action placeholders paired with concrete version comments' {
        $templateRoot = Join-Path $script:RepoRoot 'skills/engineering-baseline/scripts/template/.github/workflows'
        foreach ($workflow in (Get-ChildItem $templateRoot -Filter '*.tmpl' -File)) {
            foreach ($line in (Get-Content -LiteralPath $workflow.FullName | Where-Object { $_ -match '\buses:' })) {
                $line | Should -Match '@<SHA>\s+#\s+v\d'
            }
        }
    }
}

Describe 'Workflow execution contracts' {
    BeforeAll {
        $script:CiWorkflow = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/ci.yml') -Raw
        $script:FullCiWorkflow = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/full-ci.yml') -Raw
        $script:AllWorkflowText = @(Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot '.github/workflows') -Filter '*.yml' -File |
            Sort-Object Name |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"

        function Get-WorkflowJobBody ([string] $workflow, [string] $jobName) {
            $escapedJobName = [regex]::Escape($jobName)
            $match = [regex]::Match(
                $workflow,
                "(?ms)^  ${escapedJobName}:\r?\n(?<body>.*?)(?=^  [a-z0-9-]+:\r?$|\z)")
            if (-not $match.Success) { throw "Workflow job '$jobName' was not found." }
            return $match.Groups['body'].Value
        }
    }

    It 'limits ordinary CI to main, release tags, and main pull requests' {
        $script:CiWorkflow | Should -Match "(?ms)^on:\r?\n  push:\r?\n    branches: \[main\]\r?\n    tags: \['v\*'\]\r?\n  pull_request:\r?\n    branches: \[main\]"
    }

    It 'runs release-critical artifact gates for tag pushes' {
        foreach ($jobName in @('validate', 'scaffold-linux', 'scaffold-windows')) {
            Get-WorkflowJobBody $script:CiWorkflow $jobName |
                Should -Not -Match "startsWith\(github\.ref, 'refs/tags/'\)" -Because "$jobName must run against the tagged commit"
        }
    }

    It 'runs the full stable Linux scaffold matrix on the weekly schedule' {
        $script:FullCiWorkflow | Should -Match '(?m)^  schedule:\s*$'
        foreach ($jobName in @('scaffold-linux', 'scaffold-linux-x64')) {
            Get-WorkflowJobBody $script:FullCiWorkflow $jobName |
                Should -Not -Match "github\.event_name == 'workflow_dispatch'" -Because "$jobName is part of scheduled Full CI"
        }
    }

    It 'exercises a pinned synthetic consumer on tag pushes' {
        $validateJob = Get-WorkflowJobBody $script:CiWorkflow 'validate'

        $validateJob | Should -Match 'Invoke-SyntheticConsumer\.ps1'
        $validateJob | Should -Match '-SourceRepository \$env:SOURCE_REPOSITORY'
        $validateJob | Should -Match '-Pin \$env:SOURCE_PIN'
    }

    It 'keeps real model evaluations out of GitHub Actions' {
        $script:AllWorkflowText | Should -Not -Match 'Invoke-SkillEvals\.ps1'
        $script:AllWorkflowText | Should -Not -Match 'COPILOT_GITHUB_TOKEN'
        $script:AllWorkflowText | Should -Not -Match '(?m)^\s+copilot\s+(?:-p|--prompt)\b'
    }
}
