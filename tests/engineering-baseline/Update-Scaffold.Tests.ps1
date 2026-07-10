#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:ScriptsRoot = Join-Path $PSScriptRoot '..' '..' 'skills' 'engineering-baseline' 'scripts'
    $script:VersionsScript = Join-Path $script:ScriptsRoot 'Update-ScaffoldVersions.ps1'
    $script:ActionsScript = Join-Path $script:ScriptsRoot 'Update-ScaffoldActions.ps1'
}

Describe 'Update-ScaffoldVersions policy helpers' {
    BeforeAll {
        . $script:VersionsScript -SkipMain
    }

    It 'accepts each allowlisted SPDX identifier in a compound expression' {
        Test-LicenseAllowed '(MIT OR Apache-2.0) AND BSD-3-Clause' @('MIT', 'Apache-2.0', 'BSD-3-Clause') |
            Should -BeTrue
    }

    It 'rejects an identifier outside the allowlist' {
        Test-LicenseAllowed 'MIT OR GPL-3.0-only' @('MIT', 'Apache-2.0') |
            Should -BeFalse
    }

    It 'rejects custom and missing license expressions' {
        Test-LicenseAllowed 'LicenseRef-Proprietary' @('MIT') | Should -BeFalse
        Test-LicenseAllowed '' @('MIT') | Should -BeFalse
    }
}

Describe 'Update-ScaffoldActions policy helpers' {
    BeforeAll {
        . $script:ActionsScript -SkipMain
    }

    It 'extracts the owning repository from an action subpath' {
        Get-ActionRepo 'github/codeql-action/init' | Should -Be 'github/codeql-action'
        Get-ActionRepo 'actions/checkout' | Should -Be 'actions/checkout'
    }

    It 'orders semantic tags numerically after padding missing components' {
        ConvertTo-SortableVersion 'v5' | Should -Be ([version]'5.0.0')
        ConvertTo-SortableVersion 'v5.10.2' | Should -BeGreaterThan (ConvertTo-SortableVersion 'v5.9.9')
    }

    It 'uses a jq backslash-t escape so release date rows contain a real tab' {
        $source = Get-Content -LiteralPath $script:ActionsScript -Raw
        $source | Should -Match ([regex]::Escape('"\(.tag_name)\t\(.published_at)"'))
        $source | Should -Not -Match ([regex]::Escape('"\(.tag_name)`t\(.published_at)"'))
    }
}