#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Tests for skills/manage-skills/scripts/Validate-Skills.ps1.
#
# Black-box tests: each case builds a throwaway skill directory under TestDrive
# with crafted SKILL.md frontmatter, invokes the validator in-process, and
# asserts on its exit code and its OK/FAIL output. The call operator (&) contains
# the script's `exit`, so the run survives it; the validator writes with
# Write-Host, so output is captured by redirecting the information stream (6>&1).

BeforeAll {
    $script:ValidatorPath = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'skills' 'manage-skills' 'scripts' 'Validate-Skills.ps1')).Path
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path

    # Write a SKILL.md fixture and return its directory.
    function New-SkillFixture {
        param(
            [Parameter(Mandatory)] [string] $Name,
            [Parameter(Mandatory)] [string] $Frontmatter,
            [string] $Body = "# $Name`n`nBody.",
            [string] $Root = $TestDrive
        )
        $dir = Join-Path $Root $Name
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $content = "---`n$Frontmatter`n---`n`n$Body`n"
        Set-Content -LiteralPath (Join-Path $dir 'SKILL.md') -Value $content -NoNewline
        return $dir
    }

    # Invoke the validator and capture its output (info stream) plus exit code.
    # Arguments are the positional path(s) plus an optional '-Quiet'; they are
    # rebound through hashtable splatting so the switch binds as a switch.
    function Invoke-Validator {
        param([Parameter(Mandatory)] [string[]] $Arguments)
        $paths = @()
        $quiet = $false
        foreach ($a in $Arguments) {
            if ($a -eq '-Quiet') { $quiet = $true } else { $paths += $a }
        }
        $splat = @{ Path = $paths }
        if ($quiet) { $splat['Quiet'] = $true }
        $records = & $script:ValidatorPath @splat 6>&1
        $code = $LASTEXITCODE
        $text = ($records | ForEach-Object { $_.ToString() }) -join "`n"
        return [pscustomobject]@{ Output = $text; ExitCode = $code }
    }
}

Describe 'Validate-Skills.ps1' {

    Context 'valid skills' {
        It 'passes a well-formed skill and exits 0' {
            $dir = New-SkillFixture -Name 'good-skill' -Frontmatter (@(
                    'name: good-skill'
                    'description: A valid skill.'
                ) -join "`n")
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 0
            $r.Output | Should -Match 'OK'
            $r.Output | Should -Match 'All 1 skill'
        }

        It 'accepts optional license, compatibility, and a metadata block' {
            $dir = New-SkillFixture -Name 'meta-skill' -Frontmatter (@(
                    'name: meta-skill'
                    'description: Has optional fields.'
                    'license: MIT'
                    'compatibility: Works anywhere.'
                    'metadata:'
                    '  category: testing'
                ) -join "`n")
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 0
            $r.Output | Should -Match 'All 1 skill'
        }

        It 'validates the bundled manage-skills skill (real-world parity)' {
            $dir = Join-Path $script:RepoRoot 'skills/manage-skills'
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 0
            $r.Output | Should -Match 'All 1 skill'
        }
    }

    Context 'name rules' {
        It 'rejects a non-lowercase name' {
            $dir = New-SkillFixture -Name 'Good-Skill' -Frontmatter (@(
                    'name: Good-Skill'
                    'description: x.'
                ) -join "`n")
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'must be lowercase'
        }

        It 'rejects a name that does not match the directory' {
            $dir = New-SkillFixture -Name 'dir-name' -Frontmatter (@(
                    'name: other-name'
                    'description: x.'
                ) -join "`n")
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'must match skill name'
        }

        It 'rejects consecutive hyphens' {
            $dir = New-SkillFixture -Name 'bad--name' -Frontmatter (@(
                    'name: bad--name'
                    'description: x.'
                ) -join "`n")
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'consecutive hyphens'
        }

        It 'rejects a leading or trailing hyphen' {
            $dir = New-SkillFixture -Name '-bad' -Frontmatter (@(
                    'name: -bad'
                    'description: x.'
                ) -join "`n")
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'start or end with a hyphen'
        }

        It 'rejects invalid characters' {
            $dir = New-SkillFixture -Name 'bad_name' -Frontmatter (@(
                    'name: bad_name'
                    'description: x.'
                ) -join "`n")
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'invalid characters'
        }

        It 'rejects a name over 64 characters' {
            $long = 'a' * 65
            $dir = New-SkillFixture -Name $long -Frontmatter (@(
                    "name: $long"
                    'description: x.'
                ) -join "`n")
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'exceeds 64 character limit'
        }
    }

    Context 'description rules' {
        It 'rejects a missing description' {
            $dir = New-SkillFixture -Name 'no-desc' -Frontmatter 'name: no-desc'
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'Missing required field in frontmatter: description'
        }

        It 'rejects an empty description' {
            $dir = New-SkillFixture -Name 'empty-desc' -Frontmatter (@(
                    'name: empty-desc'
                    'description: ""'
                ) -join "`n")
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'must be a non-empty string'
        }

        It 'rejects a description over 1024 characters' {
            $long = 'a' * 1025
            $dir = New-SkillFixture -Name 'long-desc' -Frontmatter (@(
                    'name: long-desc'
                    "description: $long"
                ) -join "`n")
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'exceeds 1024 character limit'
        }
    }

    Context 'frontmatter fields' {
        It 'rejects an unexpected field' {
            $dir = New-SkillFixture -Name 'extra-field' -Frontmatter (@(
                    'name: extra-field'
                    'description: x.'
                    'bogus: nope'
                ) -join "`n")
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'Unexpected fields in frontmatter: bogus'
        }

        It 'rejects an over-long compatibility string' {
            $long = 'a' * 501
            $dir = New-SkillFixture -Name 'long-compat' -Frontmatter (@(
                    'name: long-compat'
                    'description: x.'
                    "compatibility: $long"
                ) -join "`n")
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'exceeds 500 character limit'
        }
    }

    Context 'driver behavior' {
        It 'aggregates results across a parent directory and fails if any fail' {
            $root = Join-Path $TestDrive 'multi'
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            New-SkillFixture -Root $root -Name 'pass-one' -Frontmatter (@(
                    'name: pass-one'
                    'description: x.'
                ) -join "`n") | Out-Null
            New-SkillFixture -Root $root -Name 'fail-one' -Frontmatter (@(
                    'name: NotLower'
                    'description: x.'
                ) -join "`n") | Out-Null
            $r = Invoke-Validator -Arguments @($root)
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match '1 of 2 skill'
        }

        It 'reports when no skills are found' {
            $empty = Join-Path $TestDrive 'empty'
            New-Item -ItemType Directory -Path $empty -Force | Out-Null
            $r = Invoke-Validator -Arguments @($empty)
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'No skills found'
        }
    }

    Context '-Quiet switch' {
        It 'suppresses OK lines but still prints the summary' {
            $dir = New-SkillFixture -Name 'quiet-pass' -Frontmatter (@(
                    'name: quiet-pass'
                    'description: x.'
                ) -join "`n")
            $r = Invoke-Validator -Arguments @($dir, '-Quiet')
            $r.ExitCode | Should -Be 0
            $r.Output | Should -Not -Match 'OK'
            $r.Output | Should -Match 'All 1 skill'
        }

        It 'still reports failures' {
            $dir = New-SkillFixture -Name 'quiet-fail' -Frontmatter (@(
                    'name: NotLower'
                    'description: x.'
                ) -join "`n")
            $r = Invoke-Validator -Arguments @($dir, '-Quiet')
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'FAIL'
        }
    }

    Context 'SKILL.md length' {
        It 'rejects a SKILL.md longer than 500 lines' {
            $body = (1..520 | ForEach-Object { "Filler line $_." }) -join "`n"
            $dir = New-SkillFixture -Name 'too-long' -Body $body -Frontmatter (@(
                    'name: too-long'
                    'description: x.'
                ) -join "`n")
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'under the recommended 500-line limit'
        }

        It 'accepts a SKILL.md within the 500-line limit' {
            $body = (1..480 | ForEach-Object { "Filler line $_." }) -join "`n"
            $dir = New-SkillFixture -Name 'within-limit' -Body $body -Frontmatter (@(
                    'name: within-limit'
                    'description: x.'
                ) -join "`n")
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 0
            $r.Output | Should -Match 'All 1 skill'
        }
    }

    Context 'YAML colon safety' {
        It 'rejects an unquoted value containing a colon' {
            $dir = New-SkillFixture -Name 'colon-bad' -Frontmatter (@(
                    'name: colon-bad'
                    'description: Use this skill when: the user asks about PDFs.'
                ) -join "`n")
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match "unquoted ':'"
        }

        It 'accepts a colon inside a quoted value' {
            $dir = New-SkillFixture -Name 'colon-ok' -Frontmatter (@(
                    'name: colon-ok'
                    'description: "Use this skill when: the user asks about PDFs."'
                ) -join "`n")
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 0
            $r.Output | Should -Match 'All 1 skill'
        }

        It 'accepts a colon with no following space (a URL)' {
            $dir = New-SkillFixture -Name 'colon-url' -Frontmatter (@(
                    'name: colon-url'
                    'description: See https://example.com for details.'
                ) -join "`n")
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 0
            $r.Output | Should -Match 'All 1 skill'
        }
    }

    Context 'XML tags in description' {
        It 'rejects an XML-style tag in the description' {
            $dir = New-SkillFixture -Name 'xml-bad' -Frontmatter (@(
                    'name: xml-bad'
                    'description: Handles Span<T> buffers in hot paths.'
                ) -join "`n")
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'XML-style tags'
        }

        It 'accepts a less-than sign used as a comparison' {
            $dir = New-SkillFixture -Name 'xml-ok' -Frontmatter (@(
                    'name: xml-ok'
                    'description: Apply when the buffer size is < 256 bytes on a hot path.'
                ) -join "`n")
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 0
            $r.Output | Should -Match 'All 1 skill'
        }
    }
}
