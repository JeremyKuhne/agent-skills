#Requires -Version 7.2
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:ScaffoldPath = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'skills' 'engineering-baseline' 'scripts' 'New-DotnetRepo.ps1')).Path
    $tokens = $null
    $errors = $null
    $script:ScaffoldAst = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:ScaffoldPath,
        [ref]$tokens,
        [ref]$errors)
    if ($errors.Count -gt 0) {
        throw "New-DotnetRepo.ps1 has parse errors: $($errors.Message -join '; ')"
    }
}

Describe 'New-DotnetRepo defaults' {
    It 'vendors the complete universal starting skill tier' {
        $skillsParameter = $script:ScaffoldAst.ParamBlock.Parameters |
            Where-Object { $_.Name.VariablePath.UserPath -eq 'Skills' }
        $defaultSkills = @($skillsParameter.DefaultValue.FindAll(
                { param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] },
                $true) |
            ForEach-Object Value)

        $defaultSkills | Should -Be @(
            'manage-skills',
            'agent-files-review',
            'create-pr',
            'address-pr-feedback',
            'technical-writing',
            'security-review')
    }
}
