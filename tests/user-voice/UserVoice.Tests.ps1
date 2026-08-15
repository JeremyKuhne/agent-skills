#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
    $script:SkillRoot = Join-Path $script:RepoRoot 'skills/user-voice'
    $script:Pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })

    function Invoke-UserVoiceScript {
        param(
            [Parameter(Mandatory)] [string] $Script,
            [string[]] $Arguments
        )

        $output = @(& $script:Pwsh -NoProfile -File $Script @Arguments 2>&1)
        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = $output -join "`n"
        }
    }

    function Write-Utf8File([string] $Path, [string] $Content) {
        $directory = Split-Path -Parent $Path
        if ($directory) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
        [System.IO.File]::WriteAllText(
            $Path,
            $Content.TrimEnd("`r", "`n") + "`n",
            [System.Text.UTF8Encoding]::new($false))
    }

    function New-EvidenceReport([string] $Path) {
        $template = Get-Content -LiteralPath (
            Join-Path $script:SkillRoot 'assets/evidence-report.md.tmpl') -Raw
        $tokens = @{
            REPORT_ID = 'report_12345678'
            CONSENT_ID = 'consent_12345678'
            CONSENT_SCHEMA = '1'
            ANALYSIS_PROVIDER = 'approved-provider'
            ANALYSIS_HOST = 'approved-client'
            CONSENT_EXPIRY = 'profile-release'
            SOURCE_CLASSES = 'published writing and sent correspondence'
            CHANNELS = 'technical discussion and professional correspondence'
            AUDIENCES = 'expert peer and broad technical audience'
            ERA_BANDS = 'earlier baseline and recent human-only'
            AUTHORSHIP_MIX = 'human-only and labeled assisted'
            ABSTRACT_WRITING_DECISION = 'Lead with the controlling constraint.'
            BROAD_CONTEXT = 'technical disagreement with an expert peer'
            OBSERVABLE_CHECK = 'The controlling constraint appears first.'
            DE_IDENTIFIED_CONFLICT = 'The opening varies in unsupported contexts.'
            DISTRIBUTION_OR_TOLERANCE = 'Paragraphs normally contain one idea.'
            BROAD_UNSUPPORTED_CONTEXT = 'Relationship-sensitive personal writing'
            GENERAL_HAZARD_CLASS_WITH_NO_SOURCE_PHRASE = 'Rhetorical pressure was excluded.'
            USER_CONFIRMATION_OR_MISSING_CONTEXT = 'Confirm the candidate rule and scope.'
        }
        foreach ($token in $tokens.Keys) {
            $template = $template.Replace("{{$token}}", $tokens[$token])
        }
        Write-Utf8File $Path $template
    }

    function New-FakeGh {
        param(
            [Parameter(Mandatory)] [string] $Directory,
            [Parameter(Mandatory)] [string] $Visibility,
            [string] $Owner = 'example'
        )

        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
        $json = "{`"visibility`":`"$Visibility`",`"owner`":{`"login`":`"$Owner`"},`"name`":`"private-voice`"}"
        if ($IsWindows) {
            Write-Utf8File (Join-Path $Directory 'gh.cmd') "@echo off`necho $json"
        }
        else {
            $path = Join-Path $Directory 'gh'
            Write-Utf8File $path "#!/usr/bin/env sh`nprintf '%s\n' '$json'"
            & chmod +x $path
            if ($LASTEXITCODE -ne 0) { throw 'Could not make the fake gh executable.' }
        }
    }

    function New-TestGitRepository([string] $Root) {
        New-Item -ItemType Directory -Path $Root -Force | Out-Null
        & git -C $Root init --quiet
        & git -C $Root config user.name 'Voice Test'
        & git -C $Root config user.email 'voice-test@example.invalid'
        Write-Utf8File (Join-Path $Root 'README.md') '# Private source'
        & git -C $Root add README.md
        & git -C $Root commit --quiet -m 'Initialize'
    }
}

Describe 'User voice package assets' {
    It 'ships the complete synthetic template and script set' {
        $expected = @(
            'SKILL.md',
            'audit.md',
            'capture.md',
            'handoff.md',
            'integration.md',
            'migration.md',
            'private-source.md',
            'profile-schema.md',
            'assets/data-gathering-handoff.md.tmpl',
            'assets/evidence-report.md.tmpl',
            'assets/private-source-repository/gitignore.tmpl',
            'assets/private-source-repository/pre-push.tmpl',
            'assets/private-source-repository/private-voice-audit.yml.tmpl',
            'assets/user-voice-profile/INSTALL.md.tmpl',
            'assets/user-voice-profile/SKILL.md.tmpl',
            'assets/user-voice-profile/evaluations.md.tmpl',
            'assets/user-voice-profile/voice-profile.md.tmpl',
            'scripts/New-UserVoiceMigration.ps1',
            'scripts/New-UserVoiceProfile.ps1',
            'scripts/Build-UserVoiceProfile.ps1',
            'scripts/Test-UserVoiceEvidenceReport.ps1',
            'scripts/Test-UserVoiceProfile.ps1',
            'scripts/Test-UserVoiceRepository.ps1')
        $actual = @(Get-ChildItem -LiteralPath $script:SkillRoot -File -Recurse |
            ForEach-Object {
                [System.IO.Path]::GetRelativePath($script:SkillRoot, $_.FullName).
                    Replace('\', '/')
            } |
            Sort-Object)

        $actual | Should -Be ($expected | Sort-Object)
        foreach ($file in (Get-ChildItem -LiteralPath $script:SkillRoot -File -Recurse)) {
            Get-Content -LiteralPath $file.FullName -Raw |
                Should -Not -Match '(?m)^\*\*\* (?:Add|Update|Delete) File:'
        }
        $privateWorkflow = Get-Content -LiteralPath (
            Join-Path $script:SkillRoot 'assets/private-source-repository/private-voice-audit.yml.tmpl') -Raw
        $privateWorkflow | Should -Match 'GH_TOKEN:\s*\$\{\{ github\.token \}\}'
        $privateWorkflow | Should -Match 'Test-UserVoiceRepository\.ps1[\s\S]*-RequirePrivateGitHub[\s\S]*-ScanHistory'
        $privateWorkflow | Should -Match 'Test-UserVoiceProfile\.ps1[\s\S]*-ProfilePath ./user-voice-profile'
    }
}

Describe 'Evidence report validation' {
    BeforeEach {
        $script:ReportPath = Join-Path $TestDrive 'report.md'
        New-EvidenceReport $script:ReportPath
        $script:ReportScript = Join-Path $script:SkillRoot 'scripts/Test-UserVoiceEvidenceReport.ps1'
        $script:ReportArguments = @(
            '-Path', $script:ReportPath,
            '-ConsentId', 'consent_12345678',
            '-ConsentSchema', '1',
            '-AnalysisProvider', 'approved-provider',
            '-AnalysisHost', 'approved-client',
            '-ConsentExpiry', 'profile-release')
    }

    It 'accepts the exact de-identified Markdown schema' {
        $result = Invoke-UserVoiceScript -Script $script:ReportScript -Arguments $script:ReportArguments

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $result.Output | Should -Match '^OK evidence report:'
    }

    It 'rejects a <Category> adversarial imported report' -ForEach @(
        @{ Category = 'unexpected-field'; Transform = { param($text) $text + "`n## Sources`n" } }
        @{ Category = 'external-reference'; Transform = { param($text) $text.Replace('Confirm the candidate rule and scope.', 'Visit https://example.invalid/source.') } }
        @{ Category = 'private-identifier'; Transform = { param($text) $text.Replace('expert peer', 'person@example.invalid') } }
        @{ Category = 'external-reference'; Transform = { param($text) $text.Replace('Paragraphs normally contain one idea.', 'Open C:\Users\person\source.txt.') } }
        @{ Category = 'false-approval'; Transform = { param($text) $text.Replace('agent-derived, user-unconfirmed', 'user-approved') } }
        @{ Category = 'copied-source'; Transform = { param($text) $text.Replace('Paragraphs normally contain one idea.', '> This is copied source text.') } }
        @{ Category = 'raw-retention'; Transform = { param($text) $text.Replace('raw_source_retained: no', 'raw_source_retained: yes') } }
        @{ Category = 'consent-mismatch'; Transform = { param($text) $text.Replace('approved-provider', 'different-provider') } }
    ) {
        $content = Get-Content -LiteralPath $script:ReportPath -Raw
        Write-Utf8File $script:ReportPath (& $Transform $content)

        $result = Invoke-UserVoiceScript -Script $script:ReportScript -Arguments $script:ReportArguments

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match ([regex]::Escape("[$Category]"))
    }
}

Describe 'Private profile scaffolding' {
    It 'creates an exact draft runtime package with no unresolved token' {
        $root = Join-Path $TestDrive 'profile'
        $scriptPath = Join-Path $script:SkillRoot 'scripts/New-UserVoiceProfile.ps1'
        $result = Invoke-UserVoiceScript -Script $scriptPath -Arguments @('-MaintenanceRoot', $root)

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $runtime = Join-Path $root 'user-voice-profile'
        $manifest = @(Get-ChildItem -LiteralPath $runtime -File -Recurse |
            ForEach-Object {
                [System.IO.Path]::GetRelativePath($runtime, $_.FullName).
                    Replace('\', '/')
            } |
            Sort-Object)
        $manifest | Should -Be @(
            'INSTALL.md',
            'references/evaluations.md',
            'references/voice-profile.md',
            'SKILL.md')
        @(Get-ChildItem -LiteralPath $root -File -Recurse |
            Select-String -Pattern '(?<!\$)\{\{[^}]+\}\}').Count | Should -Be 0

        $validator = Join-Path $script:SkillRoot 'scripts/Test-UserVoiceProfile.ps1'
        (Invoke-UserVoiceScript -Script $validator -Arguments @(
                '-ProfilePath', $runtime,
                '-AllowDraft')).ExitCode | Should -Be 0
        (Invoke-UserVoiceScript -Script $validator -Arguments @(
                '-ProfilePath', $runtime)).ExitCode | Should -Be 1
    }

    It 'adds dedicated private-repository defenses only when requested' {
        $root = Join-Path $TestDrive 'prepared'
        $scriptPath = Join-Path $script:SkillRoot 'scripts/New-UserVoiceProfile.ps1'
        $result = Invoke-UserVoiceScript -Script $scriptPath -Arguments @(
            '-MaintenanceRoot', $root,
            '-PreparePrivateRepository')

        $result.ExitCode | Should -Be 0 -Because $result.Output
        foreach ($relativePath in @(
                '.gitignore',
                '.githooks/pre-push',
                '.github/workflows/private-voice-audit.yml',
                '.private-voice/Test-UserVoiceProfile.ps1',
                '.private-voice/Test-UserVoiceRepository.ps1')) {
            Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf |
                Should -BeTrue
        }
    }

    It 'requires explicit private-Git selection inside a Git worktree' {
        $repository = Join-Path $TestDrive 'source-repository'
        New-TestGitRepository $repository
        $target = Join-Path $repository 'private-profile'
        $scriptPath = Join-Path $script:SkillRoot 'scripts/New-UserVoiceProfile.ps1'

        $result = Invoke-UserVoiceScript -Script $scriptPath -Arguments @(
            '-MaintenanceRoot', $target)

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match 'inside a Git repository'
        $result.Output | Should -Match 'PrivateGitHubSource'
        Test-Path -LiteralPath $target | Should -BeFalse
    }

    It 'builds the runtime copy only after consent and audit approval' {
        $root = Join-Path $TestDrive 'approved-profile'
        $scaffold = Join-Path $script:SkillRoot 'scripts/New-UserVoiceProfile.ps1'
        (Invoke-UserVoiceScript -Script $scaffold -Arguments @(
                '-MaintenanceRoot', $root)).ExitCode | Should -Be 0
        $build = Join-Path $script:SkillRoot 'scripts/Build-UserVoiceProfile.ps1'

        (Invoke-UserVoiceScript -Script $build -Arguments @(
                '-MaintenanceRoot', $root)).ExitCode | Should -Be 1

        $consentPath = Join-Path $root 'consent-ledger.md'
        $consent = Get-Content -LiteralPath $consentPath -Raw
        $consent = $consent.
            Replace('- consent-id: not-approved', '- consent-id: consent_12345678').
            Replace('- status: incomplete', '- status: approved').
            Replace('- analysis-provider: not-approved', '- analysis-provider: approved-provider').
            Replace('- analysis-host: not-approved', '- analysis-host: approved-client').
            Replace('- retention: not-approved', '- retention: profile-lifetime').
            Replace('- expiry: not-approved', '- expiry: profile-release').
            Replace('- installed-hosts: none', '- installed-hosts: github-copilot')
        Write-Utf8File $consentPath $consent

        $auditPath = Join-Path $root 'audit-results.md'
        $audit = Get-Content -LiteralPath $auditPath -Raw
        $audit = $audit.
            Replace('deterministic-package-check: not-run', 'deterministic-package-check: passed').
            Replace('semantic-privacy-review: not-run', 'semantic-privacy-review: passed').
            Replace('user-read-back: not-approved', 'user-read-back: approved')
        Write-Utf8File $auditPath $audit

        $canonicalPath = Join-Path $root 'voice-profile.md'
        $canonical = Get-Content -LiteralPath $canonicalPath -Raw
        $canonical = $canonical.Replace('profile-status: draft-unapproved', 'profile-status: approved')
        Write-Utf8File $canonicalPath $canonical

        $result = Invoke-UserVoiceScript -Script $build -Arguments @(
            '-MaintenanceRoot', $root)

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $runtimePath = Join-Path $root 'user-voice-profile/references/voice-profile.md'
        (Get-FileHash $runtimePath).Hash | Should -Be (Get-FileHash $canonicalPath).Hash
        $validator = Join-Path $script:SkillRoot 'scripts/Test-UserVoiceProfile.ps1'
        (Invoke-UserVoiceScript -Script $validator -Arguments @(
                '-ProfilePath', (Join-Path $root 'user-voice-profile'))).ExitCode |
            Should -Be 0
    }
}

Describe 'Private repository scanning' {
    It 'scans ignored working-tree files instead of trusting ignore rules' {
        $root = Join-Path $TestDrive 'ignored-raw-source'
        New-Item -ItemType Directory -Path (Join-Path $root 'raw') -Force | Out-Null
        Write-Utf8File (Join-Path $root '.gitignore') "raw/`n"
        Write-Utf8File (Join-Path $root 'raw/message.eml') 'raw source'
        $scanner = Join-Path $script:SkillRoot 'scripts/Test-UserVoiceRepository.ps1'

        $result = Invoke-UserVoiceScript -Script $scanner -Arguments @('-RepositoryPath', $root)

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match '\[raw-source\]'
    }

    It 'finds a prohibited raw path that was deleted from the current tree' {
        $root = Join-Path $TestDrive 'history'
        New-TestGitRepository $root
        Write-Utf8File (Join-Path $root 'message.eml') 'raw source'
        & git -C $root add message.eml
        & git -C $root commit --quiet -m 'Add raw source'
        Remove-Item (Join-Path $root 'message.eml')
        & git -C $root add -u
        & git -C $root commit --quiet -m 'Remove raw source'
        $scanner = Join-Path $script:SkillRoot 'scripts/Test-UserVoiceRepository.ps1'

        $result = Invoke-UserVoiceScript -Script $scanner -Arguments @(
            '-RepositoryPath', $root,
            '-ScanHistory')

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match '\[raw-source\]'
    }

    It 'scopes content auditing inside a mixed private repository' {
        $root = Join-Path $TestDrive 'mixed-repository'
        New-TestGitRepository $root
        $profile = Join-Path $root 'private-profile'
        Write-Utf8File (Join-Path $profile 'SKILL.md') '# Private profile source'
        Write-Utf8File (Join-Path $root 'unrelated-plan.md') 'C:\Users\person\unrelated.txt'
        & git -C $root add private-profile/SKILL.md unrelated-plan.md
        & git -C $root commit --quiet -m 'Add mixed private content'
        $scanner = Join-Path $script:SkillRoot 'scripts/Test-UserVoiceRepository.ps1'

        $scoped = Invoke-UserVoiceScript -Script $scanner -Arguments @(
            '-RepositoryPath', $root,
            '-ContentPath', $profile,
            '-ScanHistory')
        $scoped.ExitCode | Should -Be 0 -Because $scoped.Output

        $wholeRepository = Invoke-UserVoiceScript -Script $scanner -Arguments @(
            '-RepositoryPath', $root,
            '-ScanHistory')
        $wholeRepository.ExitCode | Should -Be 1
        $wholeRepository.Output | Should -Match '\[absolute-path\]'
    }

    It 'requires every GitHub remote to report PRIVATE visibility' {
        $root = Join-Path $TestDrive 'private-remote'
        New-TestGitRepository $root
        & git -C $root remote add origin https://github.com/example/private-voice.git
        $fakeBin = Join-Path $TestDrive 'private-gh'
        New-FakeGh -Directory $fakeBin -Visibility PRIVATE
        $originalPath = $env:PATH
        $env:PATH = "$fakeBin$([System.IO.Path]::PathSeparator)$originalPath"
        try {
            $scanner = Join-Path $script:SkillRoot 'scripts/Test-UserVoiceRepository.ps1'
            $result = Invoke-UserVoiceScript -Script $scanner -Arguments @(
                '-RepositoryPath', $root,
                '-RequirePrivateGitHub',
                '-ExpectedOwner', 'example')
        }
        finally { $env:PATH = $originalPath }

        $result.ExitCode | Should -Be 0 -Because $result.Output
    }

    It 'rejects a GitHub remote whose visibility is not PRIVATE' {
        $root = Join-Path $TestDrive 'public-remote'
        New-TestGitRepository $root
        & git -C $root remote add origin https://github.com/example/private-voice.git
        $fakeBin = Join-Path $TestDrive 'public-gh'
        New-FakeGh -Directory $fakeBin -Visibility PUBLIC
        $originalPath = $env:PATH
        $env:PATH = "$fakeBin$([System.IO.Path]::PathSeparator)$originalPath"
        try {
            $scanner = Join-Path $script:SkillRoot 'scripts/Test-UserVoiceRepository.ps1'
            $result = Invoke-UserVoiceScript -Script $scanner -Arguments @(
                '-RepositoryPath', $root,
                '-RequirePrivateGitHub')
        }
        finally { $env:PATH = $originalPath }

        $result.ExitCode | Should -Be 1
        $result.Output | Should -Match '\[visibility\]'
    }

    It 'requires the configured reviewed pre-push hook' {
        $root = Join-Path $TestDrive 'hook'
        New-TestGitRepository $root
        $hooks = Join-Path $root '.githooks'
        $hook = Join-Path $hooks 'pre-push'
        Write-Utf8File $hook "#!/usr/bin/env sh`n# Test-UserVoiceRepository.ps1"
        if (-not $IsWindows) {
            & chmod +x $hook
            $LASTEXITCODE | Should -Be 0
        }
        & git -C $root config core.hooksPath .githooks
        $scanner = Join-Path $script:SkillRoot 'scripts/Test-UserVoiceRepository.ps1'

        $valid = Invoke-UserVoiceScript -Script $scanner -Arguments @(
            '-RepositoryPath', $root,
            '-RequirePrePushHook')
        $valid.ExitCode | Should -Be 0 -Because $valid.Output

        Remove-Item -LiteralPath $hook
        $missing = Invoke-UserVoiceScript -Script $scanner -Arguments @(
            '-RepositoryPath', $root,
            '-RequirePrePushHook')
        $missing.ExitCode | Should -Be 1
        $missing.Output | Should -Match '\[hook\]'
    }
}

Describe 'Existing skill migration' {
    It 'stages an empty standard candidate without changing or copying source prose' {
        $source = Join-Path $TestDrive 'sample-private-voice'
        Write-Utf8File (Join-Path $source 'SKILL.md') @'
---
name: sample-private-voice
description: Draft the current user's private prose.
---

# Legacy

LEGACY_SOURCE_SENTINEL
'@
        Write-Utf8File (Join-Path $source 'references/voice-profile.md') "# Profile`n`nLEGACY_SOURCE_SENTINEL"
        Write-Utf8File (Join-Path $source 'references/evidence.md') "# Evidence`n`nLEGACY_SOURCE_SENTINEL"
        Write-Utf8File (Join-Path $source 'references/evaluations.md') '# Evaluations'
        Write-Utf8File (Join-Path $source 'INSTALL.md') '# Install'
        $before = @(Get-ChildItem -LiteralPath $source -File -Recurse |
            ForEach-Object {
                "$([System.IO.Path]::GetRelativePath($source, $_.FullName)):$((Get-FileHash $_.FullName).Hash)"
            })
        $staging = Join-Path $TestDrive 'migration-candidate'
        $migration = Join-Path $script:SkillRoot 'scripts/New-UserVoiceMigration.ps1'

        $result = Invoke-UserVoiceScript -Script $migration -Arguments @(
            '-ExistingSkillPath', $source,
            '-StagingRoot', $staging)

        $result.ExitCode | Should -Be 0 -Because $result.Output
        $after = @(Get-ChildItem -LiteralPath $source -File -Recurse |
            ForEach-Object {
                "$([System.IO.Path]::GetRelativePath($source, $_.FullName)):$((Get-FileHash $_.FullName).Hash)"
            })
        @(Compare-Object $before $after).Count | Should -Be 0
        foreach ($relativePath in @(
                'migration/installed-copies.json',
                'migration/migration-map.md',
                'migration/source-manifest.json',
                'migration/source-metadata.json')) {
            Test-Path -LiteralPath (Join-Path $staging $relativePath) -PathType Leaf |
                Should -BeTrue
        }
        @(Get-ChildItem -LiteralPath (Join-Path $staging 'user-voice-profile') -File -Recurse |
            Select-String -Pattern 'LEGACY_SOURCE_SENTINEL').Count | Should -Be 0
        Get-Content -LiteralPath (Join-Path $staging 'migration/migration-map.md') -Raw |
            Should -Match 'No source prose was copied'
    }
}