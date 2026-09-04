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

    function New-PortfolioFrontmatter {
        param(
            [Parameter(Mandatory)] [string] $Name,
            [string] $Portability = 'portable',
            [string] $Binding = 'optional-overlay',
            [string] $Related = 'none'
        )
        return @(
            "name: $Name"
            'description: A portfolio skill.'
            'metadata:'
            "  portability: $Portability"
            '  applicability: universal'
            "  binding: $Binding"
            '  risk: advisory'
            '  maturity: canary'
            '  requires: none'
            "  related: $Related"
        ) -join "`n"
    }

    # Invoke the validator and capture its output (info stream) plus exit code.
    # Arguments are the positional path(s) plus an optional '-Quiet'; they are
    # rebound through hashtable splatting so the switch binds as a switch.
    function Invoke-Validator {
        param([Parameter(Mandatory)] [string[]] $Arguments)
        $paths = @()
        $quiet = $false
        $requirePortfolioMetadata = $false
        foreach ($argument in $Arguments) {
            if ($argument -eq '-Quiet') { $quiet = $true }
            elseif ($argument -eq '-RequirePortfolioMetadata') { $requirePortfolioMetadata = $true }
            else { $paths += $argument }
        }
        $splat = @{ Path = $paths }
        if ($quiet) { $splat['Quiet'] = $true }
        if ($requirePortfolioMetadata) { $splat['RequirePortfolioMetadata'] = $true }
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

        It 'validates the complete source portfolio under the strict policy' {
            $dir = Join-Path $script:RepoRoot 'skills'
            $r = Invoke-Validator -Arguments @($dir, '-RequirePortfolioMetadata')
            $r.ExitCode | Should -Be 0
            $r.Output | Should -Match 'All 24 skill'
        }
    }

    Context 'Markdown list continuation indentation' {
        It 'accepts consistent paragraphs, nested lists, and fenced examples' {
            $dir = New-SkillFixture -Name 'good-list-indentation' -Frontmatter (@(
                    'name: good-list-indentation'
                    'description: A skill with lists.'
                ) -join "`n") -Body @'
# Good list indentation

1. The first paragraph starts here
   and keeps its indentation.

   A later paragraph starts here
   and also keeps its indentation.

   - A nested item starts here
     and keeps its own indentation.

   ```text
  Indentation inside a fence is literal.
   ```

A top-level paragraph after the list remains valid.
'@
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 0 -Because $r.Output
            $r.Output | Should -Match 'All 1 skill'
        }

        It 'accepts a top-level HTML block after a list' {
            $dir = New-SkillFixture -Name 'html-after-list' -Frontmatter (@(
                    'name: html-after-list'
                    'description: A skill with an HTML block after a list.'
                ) -join "`n") -Body @'
# HTML after a list

1. The list item ends here.
<div>
Top-level HTML remains outside the list.
</div>
'@
            $result = Invoke-Validator -Arguments @($dir)

            $result.ExitCode | Should -Be 0 -Because $result.Output
            $result.Output | Should -Match 'All 1 skill'
        }

        It 'rejects an under-indented <Kind> autolink continuation' -ForEach @(
            @{ Kind = 'URL'; Autolink = '<https://example.com>' }
            @{ Kind = 'email'; Autolink = '<user@example.com>' }
        ) {
            $dir = New-SkillFixture -Name 'under-indented-autolink' -Frontmatter (@(
                    'name: under-indented-autolink'
                    'description: A skill with an under-indented autolink.'
                ) -join "`n") -Body (@(
                    '# Under-indented autolink'
                    ''
                    '1. Read the reference at'
                    "  $Autolink"
                ) -join "`n")
            $result = Invoke-Validator -Arguments @($dir)

            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match 'list continuation is indented 2 spaces; align it with the paragraph''s 3-space indentation'
        }

        It 'adjusts the content column when ordered items cross from 9 to 10' {
            [string] $threeSpaces = ' ' * 3
            [string] $fourSpaces = ' ' * 4
            $body = @(
                '# Two-digit ordered list'
                ''
                '9. The ninth item starts here'
                "${threeSpaces}and continues at three spaces."
                '10. The tenth item starts here'
                "${fourSpaces}and continues at four spaces."
                ''
                "${fourSpaces}A later paragraph also starts at four spaces"
                "${fourSpaces}and keeps that indentation."
            ) -join "`n"
            $skillDirectory = New-SkillFixture -Name 'two-digit-list' -Frontmatter (@(
                    'name: two-digit-list'
                    'description: A skill with a two-digit ordered list.'
                ) -join "`n") -Body $body

            $result = Invoke-Validator -Arguments @($skillDirectory)

            $result.ExitCode | Should -Be 0 -Because $result.Output
            $result.Output | Should -Match 'All 1 skill'
        }

        It 'rejects a two-digit item continuation indented for a one-digit marker' {
            [string] $threeSpaces = ' ' * 3
            $body = @(
                '# Under-indented two-digit item'
                ''
                '10. The tenth item starts here'
                "${threeSpaces}but continues at only three spaces."
            ) -join "`n"
            $skillDirectory = New-SkillFixture -Name 'under-indented-two-digit-list' -Frontmatter (@(
                    'name: under-indented-two-digit-list'
                    'description: A skill with an under-indented two-digit item.'
                ) -join "`n") -Body $body

            $result = Invoke-Validator -Arguments @($skillDirectory)

            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match 'list continuation is indented 3 spaces; align it with the paragraph''s 4-space indentation'
        }

        It 'rejects a later two-digit list paragraph one space right of its content column' {
            [string] $fiveSpaces = ' ' * 5
            $body = @(
                '# Over-indented two-digit paragraph'
                ''
                '10. The tenth item starts here'
                ''
                "${fiveSpaces}This paragraph starts at five spaces instead of four."
            ) -join "`n"
            $skillDirectory = New-SkillFixture -Name 'over-indented-two-digit-paragraph' -Frontmatter (@(
                    'name: over-indented-two-digit-paragraph'
                    'description: A skill with an over-indented two-digit paragraph.'
                ) -join "`n") -Body $body

            $result = Invoke-Validator -Arguments @($skillDirectory)

            $result.ExitCode | Should -Be 1
            $result.Output | Should -Match 'list paragraph starts at 5 spaces; align prose with the list item''s 4-space content column'
        }

        It 'rejects an under-indented continuation in a later list paragraph' {
            $dir = New-SkillFixture -Name 'bad-list-indentation' -Frontmatter (@(
                    'name: bad-list-indentation'
                    'description: A skill with a malformed list.'
                ) -join "`n")
            Set-Content -LiteralPath (Join-Path $dir 'detail.md') -NoNewline -Value @'
# Bad list indentation

1. Install the selected revision.

   Without the helper, copy the complete
  directory and preserve its metadata.
'@
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'detail.md:\d+ list continuation is indented 2 spaces; align it with the paragraph''s 3-space indentation'
        }

        It 'rejects an over-indented continuation in a list paragraph' {
            $dir = New-SkillFixture -Name 'over-indented-list' -Frontmatter (@(
                    'name: over-indented-list'
                    'description: A skill with a shifted continuation.'
                ) -join "`n") -Body @'
# Over-indented list

1. This paragraph starts at the content column
    but its continuation moves one space right.
'@
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'list continuation is indented 4 spaces; align it with the paragraph''s 3-space indentation'
        }

        It 'rejects a later list paragraph that starts left of the content column' {
            $dir = New-SkillFixture -Name 'bad-list-paragraph-start' -Frontmatter (@(
                    'name: bad-list-paragraph-start'
                    'description: A skill with a shifted list paragraph.'
                ) -join "`n") -Body @'
# Bad list paragraph start

1. Install the selected revision.

  This paragraph starts one space too far left.
'@
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'list paragraph starts at 2 spaces; indent it to the list item''s 3-space content column or move it to column 0'
        }

        It 'rejects a later list prose paragraph that starts right of the content column' {
            $dir = New-SkillFixture -Name 'over-indented-list-paragraph' -Frontmatter (@(
                    'name: over-indented-list-paragraph'
                    'description: A skill with an over-indented list paragraph.'
                ) -join "`n") -Body @'
# Over-indented list paragraph

1. Install the selected revision.

     This prose starts at five spaces instead of three.
'@
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'list paragraph starts at 5 spaces; align prose with the list item''s 3-space content column'
        }

        It 'rejects an accidental list marker followed by a lazy continuation' {
            $dir = New-SkillFixture -Name 'lazy-list-continuation' -Frontmatter (@(
                    'name: lazy-list-continuation'
                    'description: A skill with an accidental list.'
                ) -join "`n") -Body @'
# Lazy list continuation

This sentence wraps before its dash
- and accidentally starts a list.
The next line is a lazy continuation.
'@
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'list continuation is indented 0 spaces; align it with the paragraph''s 2-space indentation'
        }
    }

    Context 'portfolio metadata and overlays' {
        It 'rejects missing portfolio metadata in strict mode' {
            $dir = New-SkillFixture -Name 'missing-policy' -Frontmatter (@(
                    'name: missing-policy'
                    'description: A skill.'
                ) -join "`n")
            $r = Invoke-Validator -Arguments @($dir, '-RequirePortfolioMetadata')
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'Missing required field in frontmatter: metadata'
        }

        It 'rejects an invalid metadata vocabulary value' {
            $frontmatter = New-PortfolioFrontmatter -Name 'bad-risk'
            $frontmatter = $frontmatter.Replace('  risk: advisory', '  risk: destructive')
            $dir = New-SkillFixture -Name 'bad-risk' -Frontmatter $frontmatter -Body @'
# Bad risk

If `overlay.md` exists beside this file, read it before acting.
'@
            $r = Invoke-Validator -Arguments @($dir, '-RequirePortfolioMetadata')
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match "metadata.risk 'destructive' is invalid"
        }

        It 'rejects a mixed-case metadata vocabulary value' {
            $frontmatter = New-PortfolioFrontmatter -Name 'upper-risk'
            $frontmatter = $frontmatter.Replace('  risk: advisory', '  risk: ADVISORY')
            $dir = New-SkillFixture -Name 'upper-risk' -Frontmatter $frontmatter -Body @'
# Upper risk

If `overlay.md` exists beside this file, read it before acting.
'@
            $r = Invoke-Validator -Arguments @($dir, '-RequirePortfolioMetadata')
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match "metadata.risk 'ADVISORY' is invalid"
        }

        It 'rejects mixed-case portability in strict mode' {
            $frontmatter = New-PortfolioFrontmatter -Name 'upper-portability' -Portability 'Portable'
            $dir = New-SkillFixture -Name 'upper-portability' -Frontmatter $frontmatter -Body @'
# Upper portability

If `overlay.md` exists beside this file, read it before acting.
'@
            $r = Invoke-Validator -Arguments @($dir, '-RequirePortfolioMetadata')
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match "metadata.portability 'Portable' is invalid"
            $r.Output | Should -Match "must set metadata.portability to 'portable'"
        }

        It 'rejects invalid relationship syntax' {
            $frontmatter = New-PortfolioFrontmatter -Name 'bad-related' -Related 'good-skill, Bad_Skill'
            $dir = New-SkillFixture -Name 'bad-related' -Frontmatter $frontmatter -Body @'
# Bad related

If `overlay.md` exists beside this file, read it before acting.
'@
            $r = Invoke-Validator -Arguments @($dir, '-RequirePortfolioMetadata')
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match "metadata.related contains invalid skill name 'Bad_Skill'"
        }

        It 'rejects a mixed-case none sentinel' {
            $frontmatter = New-PortfolioFrontmatter -Name 'upper-none'
            $frontmatter = $frontmatter.Replace('  requires: none', '  requires: None')
            $dir = New-SkillFixture -Name 'upper-none' -Frontmatter $frontmatter -Body @'
# Upper none

If `overlay.md` exists beside this file, read it before acting.
'@
            $r = Invoke-Validator -Arguments @($dir, '-RequirePortfolioMetadata')
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match "metadata.requires contains invalid skill name 'None'"
        }

        It 'rejects a mixed-case relationship name' {
            $frontmatter = New-PortfolioFrontmatter -Name 'upper-related' -Related 'Bad-Skill'
            $dir = New-SkillFixture -Name 'upper-related' -Frontmatter $frontmatter -Body @'
# Upper related

If `overlay.md` exists beside this file, read it before acting.
'@
            $r = Invoke-Validator -Arguments @($dir, '-RequirePortfolioMetadata')
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match "metadata.related contains invalid skill name 'Bad-Skill'"
        }

        It 'trims canonical portfolio values before validation' {
            $frontmatter = New-PortfolioFrontmatter -Name 'trimmed-values'
            $frontmatter = $frontmatter.Replace('  portability: portable', '  portability: " portable "')
            $frontmatter = $frontmatter.Replace('  requires: none', '  requires: " none "')
            $dir = New-SkillFixture -Name 'trimmed-values' -Frontmatter $frontmatter -Body @'
# Trimmed values

If `overlay.md` exists beside this file, read it before acting.
'@
            $r = Invoke-Validator -Arguments @($dir, '-RequirePortfolioMetadata')
            $r.ExitCode | Should -Be 0
            $r.Output | Should -Match 'All 1 skill'
        }

        It 'requires the loader cue for an overlay-aware core' {
            $dir = New-SkillFixture -Name 'missing-cue' -Frontmatter (New-PortfolioFrontmatter -Name 'missing-cue')
            $r = Invoke-Validator -Arguments @($dir, '-RequirePortfolioMetadata')
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'requires this loader cue'
        }

        It 'requires overlay.md for a required binding' {
            $frontmatter = New-PortfolioFrontmatter -Name 'needs-overlay' -Binding 'required-overlay'
            $dir = New-SkillFixture -Name 'needs-overlay' -Frontmatter $frontmatter -Body @'
# Needs overlay

If `overlay.md` exists beside this file, read it before acting.
'@
            $r = Invoke-Validator -Arguments @($dir, '-RequirePortfolioMetadata')
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match "requires overlay.md beside SKILL.md"
        }

        It 'accepts a required overlay whose core and pin match' {
            $frontmatter = New-PortfolioFrontmatter -Name 'bound-skill' -Binding 'required-overlay'
            $dir = New-SkillFixture -Name 'bound-skill' -Frontmatter $frontmatter -Body @'
# Bound skill

If `overlay.md` exists beside this file, read it before acting.
'@
            Set-Content -LiteralPath (Join-Path $dir 'overlay.md') -NoNewline -Value @'
---
core: bound-skill
core-pin: v1.2.3
---

# Bound skill overlay
'@
            $r = Invoke-Validator -Arguments @($dir, '-RequirePortfolioMetadata')
            $r.ExitCode | Should -Be 0
            $r.Output | Should -Match 'All 1 skill'
        }

        It 'rejects an overlay bound to a different core' {
            $dir = New-SkillFixture -Name 'wrong-core' -Frontmatter (New-PortfolioFrontmatter -Name 'wrong-core') -Body @'
# Wrong core

If `overlay.md` exists beside this file, read it before acting.
'@
            Set-Content -LiteralPath (Join-Path $dir 'overlay.md') -NoNewline -Value @'
---
core: another-skill
core-pin: v1.2.3
---

# Wrong overlay
'@
            $r = Invoke-Validator -Arguments @($dir, '-RequirePortfolioMetadata')
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match "must match skill directory 'wrong-core'"
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
        It 'accepts an unknown (custom) field' {
            $dir = New-SkillFixture -Name 'extra-field' -Frontmatter (@(
                    'name: extra-field'
                    'description: x.'
                    'argument-hint: a hint'
                    'bogus: nope'
                ) -join "`n")
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 0
            $r.Output | Should -Match 'All 1 skill'
        }

        It 'unwraps a single-quoted value and un-doubles escaped quotes' {
            $dir = New-SkillFixture -Name 'sq-escape' -Frontmatter (@(
                    'name: sq-escape'
                    "description: 'It''s a valid skill.'"
                ) -join "`n")
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 0
            $r.Output | Should -Match 'All 1 skill'
        }

        It 'accepts an inline flow mapping on an unknown field' {
            $dir = New-SkillFixture -Name 'flow-map' -Frontmatter (@(
                    'name: flow-map'
                    'description: A skill.'
                    'custom-data: { a: 1, b: 2 }'
                ) -join "`n")
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 0
            $r.Output | Should -Match 'All 1 skill'
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

    Context 'Markdown readability' {
        It 'rejects named and numeric HTML entities in skill Markdown' {
            $dir = New-SkillFixture -Name 'entity-bad' -Frontmatter (@(
                    'name: entity-bad'
                    'description: A skill.'
                ) -join "`n") -Body "# Entity bad`n`nSee &sect;1."
            Set-Content -LiteralPath (Join-Path $dir 'detail.md') -NoNewline -Value "Decimal &#167; and hexadecimal &#xA7;."
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match "HTML entity '&sect;'"
            $r.Output | Should -Match "HTML entity '&#167;'"
            $r.Output | Should -Match "HTML entity '&#xA7;'"
        }

        It 'accepts directly readable Unicode text' {
            $dir = New-SkillFixture -Name 'unicode-good' -Frontmatter (@(
                    'name: unicode-good'
                    'description: A skill.'
                ) -join "`n") -Body "# Unicode good`n`nUse §, ≤, →, and …."
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

        It 'does not let a leading > bypass the colon guard' {
            $dir = Join-Path $TestDrive 'gt-prefix'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $content = "---`nname: gt-prefix`ndescription: > use this when: the user asks`n---`n`n# gt-prefix`n"
            Set-Content -LiteralPath (Join-Path $dir 'SKILL.md') -Value $content -NoNewline
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match "unquoted ':'"
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

    Context 'YAML block shapes' {
        It 'folds a block-scalar (>) description and validates the folded text' {
            $dir = Join-Path $TestDrive 'block-good'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $content = "---`nname: block-good`ndescription: >`n  Analyze CSV files and clean messy data.`n  Use when the user has a CSV or tabular file.`n---`n`n# block-good`n"
            Set-Content -LiteralPath (Join-Path $dir 'SKILL.md') -Value $content -NoNewline
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 0
            $r.Output | Should -Match 'All 1 skill'
        }

        It 'checks the folded block-scalar content, not the indicator' {
            $dir = Join-Path $TestDrive 'block-xml'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $content = "---`nname: block-xml`ndescription: >`n  Handles Span<T> buffers in hot paths.`n---`n`n# block-xml`n"
            Set-Content -LiteralPath (Join-Path $dir 'SKILL.md') -Value $content -NoNewline
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'XML-style tags'
        }

        It 'rejects a block sequence for a known field (allowed-tools)' {
            $dir = Join-Path $TestDrive 'block-seq'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $content = "---`nname: block-seq`ndescription: A skill.`nallowed-tools:`n  - search`n  - edit`n---`n`n# block-seq`n"
            Set-Content -LiteralPath (Join-Path $dir 'SKILL.md') -Value $content -NoNewline
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'must be a scalar value'
        }

        It 'rejects a block mapping for a known field (license)' {
            $dir = Join-Path $TestDrive 'block-map-known'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $content = "---`nname: block-map-known`ndescription: A skill.`nlicense:`n  spdx: MIT`n---`n`n# block-map-known`n"
            Set-Content -LiteralPath (Join-Path $dir 'SKILL.md') -Value $content -NoNewline
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 1
            $r.Output | Should -Match 'must be a scalar value'
        }

        It 'accepts a block mapping under an unknown field' {
            $dir = Join-Path $TestDrive 'block-map-custom'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $content = "---`nname: block-map-custom`ndescription: A skill.`ncustom-data:`n  a: 1`n  b: 2`n---`n`n# block-map-custom`n"
            Set-Content -LiteralPath (Join-Path $dir 'SKILL.md') -Value $content -NoNewline
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 0
            $r.Output | Should -Match 'All 1 skill'
        }

        It 'does not let --- inside a value terminate the frontmatter' {
            $dir = Join-Path $TestDrive 'dash-value'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $content = "---`ndescription: see the --- marker below`nname: dash-value`n---`n`n# dash-value`n"
            Set-Content -LiteralPath (Join-Path $dir 'SKILL.md') -Value $content -NoNewline
            $r = Invoke-Validator -Arguments @($dir)
            $r.ExitCode | Should -Be 0
            $r.Output | Should -Match 'All 1 skill'
        }
    }
}
