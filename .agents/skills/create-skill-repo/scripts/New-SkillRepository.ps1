<#
.SYNOPSIS
    Creates a local repository whose primary product is Agent Skills.

.DESCRIPTION
    Renders composable template tiers for a source, consumer, or hybrid skill
    repository. The command is noninteractive and performs no remote writes.
    Static file bodies live under scripts/template and use {{TOKEN}}
    substitution.
#>

#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Root,
    [Parameter(Mandatory)] [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9._-]*$')] [string] $Name,
    [Parameter(Mandatory)] [string] $Description,
    [Parameter(Mandatory)] [ValidateSet('source', 'consumer', 'hybrid')] [string] $Role,
    [ValidateSet('minimal', 'validated', 'team-ci', 'distribution')] [string] $Infrastructure = 'validated',
    [ValidateSet('local', 'private', 'public')] [string] $Visibility = 'local',
    [ValidateSet('person', 'team', 'organization', 'public')] [string] $Audience = 'team',
    [string] $Owner,
    [ValidateSet('MIT', 'none')] [string] $License = 'MIT',
    [ValidatePattern('^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$')] [string] $Version = '0.1.0',
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._/-]*$')] [string] $DefaultBranch = 'main',
    [ValidateSet('github-copilot', 'claude-code', 'codex', 'gemini-cli', 'cursor')]
    [string[]] $Clients = @('github-copilot'),
    [string[]] $SelectedSkills = @(),
    [string[]] $ResolvedSkills = @(),
    [string] $SkillsRepo = 'JeremyKuhne/agent-skills',
    [string] $SkillsRef,
    [string[]] $UpstreamSources = @(),
    [string[]] $PrivateUpstreamSources = @(),
    [ValidateSet('direct', 'plugin', 'marketplace', 'agents', 'mcp')]
    [string[]] $DistributionSurfaces = @('direct'),
    [switch] $IncludeEvaluations,
    [switch] $AllowNestedRepository,
    [switch] $SkipGit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Root = [System.IO.Path]::GetFullPath($Root)

function New-Directory ([string] $Path) {
    if ($Path -and -not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Expand-TemplateText {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [hashtable] $Tokens
    )

    $text = Get-Content -LiteralPath $Path -Raw
    $evaluator = [System.Text.RegularExpressions.MatchEvaluator] {
        param($match)
        $name = $match.Groups['name'].Value
        if (-not $Tokens.ContainsKey($name)) {
            throw "Template '$Path' contains unknown token '{{$name}}'."
        }
        return [string] $Tokens[$name]
    }
    $text = [regex]::Replace(
        $text,
        '\{\{(?<name>[A-Z][A-Z0-9_]*)\}\}',
        $evaluator)
    return $text.TrimEnd("`r", "`n") + "`n"
}

function Expand-TemplateSet {
    param(
        [Parameter(Mandatory)] [string] $TemplateRoot,
        [Parameter(Mandatory)] [string] $Destination,
        [Parameter(Mandatory)] [hashtable] $Tokens
    )

    Get-ChildItem -LiteralPath $TemplateRoot -Recurse -File -Force | ForEach-Object {
        $relative = $_.FullName.Substring($TemplateRoot.Length).TrimStart([char]'\', [char]'/')
        if ($relative.EndsWith('.tmpl')) {
            $relative = $relative.Substring(0, $relative.Length - 5)
        }

        $text = Expand-TemplateText -Path $_.FullName -Tokens $Tokens

        $target = Join-Path $Destination $relative
        New-Directory (Split-Path $target -Parent)
        [System.IO.File]::WriteAllText(
            $target,
            $text,
            [System.Text.UTF8Encoding]::new($false))
    }
}

function Get-InfrastructureRank ([string] $Value) {
    switch ($Value) {
        'minimal' { 0 }
        'validated' { 1 }
        'team-ci' { 2 }
        'distribution' { 3 }
    }
}

function Get-ClientRoot ([string] $Client) {
    switch ($Client) {
        'github-copilot' { '.agents/skills/' }
        'claude-code' { '.claude/skills/' }
        'codex' { '.agents/skills/' }
        'gemini-cli' { '.agents/skills/' }
        'cursor' { '.agents/skills/' }
    }
}

function ConvertTo-PowerShellLiteral ([string] $Value) {
    return "'$($Value.Replace("'", "''"))'"
}

function ConvertTo-JsonScalar ([string] $Value) {
    return ConvertTo-Json -InputObject $Value -Compress
}

function Test-ImmutableSkillRef ([string] $Value) {
    return $Value -match '^(?:[0-9a-fA-F]{40}|v?\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)$'
}

function ConvertTo-PowerShellArrayLiteral ([string[]] $Values) {
    if ($Values.Count -eq 0) { return '@()' }
    $items = @($Values | ForEach-Object { ConvertTo-PowerShellLiteral $_ }) -join ', '
    return "@($items)"
}
function Get-ExistingAncestor ([string] $Path) {
    $candidate = [System.IO.Path]::GetFullPath($Path)
    while (-not (Test-Path -LiteralPath $candidate)) {
        $parent = Split-Path $candidate -Parent
        if (-not $parent -or $parent -eq $candidate) { return $null }
        $candidate = $parent
    }
    return $candidate
}

$templateRoot = Join-Path $PSScriptRoot 'template'
if (-not (Test-Path -LiteralPath $templateRoot -PathType Container)) {
    throw "Template directory not found: $templateRoot"
}

if ([string]::IsNullOrWhiteSpace($Description) -or $Description -match '[\r\n]') {
    throw '-Description must be one non-empty line.'
}
if ($Visibility -ne 'local' -and [string]::IsNullOrWhiteSpace($Owner)) {
    throw "Visibility '$Visibility' requires -Owner."
}
if ($Owner -and $Owner -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$') {
    throw "Owner '$Owner' is not a valid GitHub owner or organization name."
}
if ($Clients.Count -eq 0) {
    throw 'Select at least one client.'
}
foreach ($skill in @($SelectedSkills) + @($ResolvedSkills)) {
    if ($skill -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
        throw "Skill name '$skill' is invalid."
    }
}
foreach ($source in @($UpstreamSources) + @($PrivateUpstreamSources)) {
    if ([string]::IsNullOrWhiteSpace($source) -or $source -match '[\r\n]') {
        throw 'Every upstream source must be one non-empty line.'
    }
}
if ($Visibility -eq 'public' -and $License -eq 'none') {
    throw 'A public scaffold requires a license.'
}
if ($Infrastructure -eq 'distribution' -and $License -eq 'none') {
    throw 'Distribution infrastructure requires a license.'
}
if ($Role -eq 'source' -and ($SelectedSkills.Count -gt 0 -or $ResolvedSkills.Count -gt 0)) {
    throw 'A source-only repository has no runtime skill root. Choose hybrid to vendor operational skills.'
}
if ($SelectedSkills.Count -gt 0 -and $ResolvedSkills.Count -eq 0) {
    throw '-ResolvedSkills must explicitly contain the selected skills and their complete transitive requirement closure.'
}
if ($SelectedSkills.Count -eq 0 -and $ResolvedSkills.Count -gt 0) {
    throw '-ResolvedSkills cannot be supplied without directly selected skills.'
}
foreach ($skill in $SelectedSkills) {
    if ($ResolvedSkills -notcontains $skill) {
        throw "ResolvedSkills must contain directly selected skill '$skill'."
    }
}
if ($ResolvedSkills.Count -gt 0 -and [string]::IsNullOrWhiteSpace($SkillsRef)) {
    throw '-SkillsRef must be an immutable tag or full commit SHA when skills are selected.'
}
if ($SkillsRef -and -not (Test-ImmutableSkillRef $SkillsRef)) {
    throw "SkillsRef '$SkillsRef' must be a semantic-version tag or full 40-character commit SHA."
}
if ($Infrastructure -ne 'distribution' -and
    @($DistributionSurfaces | Where-Object { $_ -ne 'direct' }).Count -gt 0) {
    throw 'Plugin, marketplace, agent, and MCP surfaces require -Infrastructure distribution.'
}
if ($Infrastructure -eq 'distribution' -and $Role -eq 'consumer') {
    throw 'Distribution infrastructure requires a source or hybrid repository.'
}
if ($IncludeEvaluations -and (Get-InfrastructureRank $Infrastructure) -lt 2) {
    throw 'Behavioral evaluations require Team CI or Distribution infrastructure.'
}
if ($DistributionSurfaces -contains 'marketplace' -and
    $DistributionSurfaces -notcontains 'plugin') {
    throw 'The marketplace surface requires the plugin surface.'
}
if ($DistributionSurfaces -contains 'plugin' -and
    ($Visibility -eq 'local' -or $Name -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$')) {
    throw 'Plugin distribution requires GitHub visibility and a lowercase hyphenated repository name.'
}
if ($Visibility -eq 'public' -and $PrivateUpstreamSources.Count -gt 0) {
    throw 'Private upstream sources cannot be written into a public scaffold. Keep them in a private user or organization binding.'
}

$upstreams = if ($PSBoundParameters.ContainsKey('UpstreamSources')) {
    @($UpstreamSources)
} else {
    $defaults = [System.Collections.Generic.List[string]]::new()
    $defaults.Add('local installations')
    if ($Role -in @('source', 'hybrid')) { $defaults.Add('repository source') }
    $defaults.Add('JeremyKuhne/agent-skills')
    $defaults.Add('public catalogs (untrusted)')
    @($defaults)
}
foreach ($privateSource in $PrivateUpstreamSources) {
    if ($upstreams -notcontains $privateSource) {
        throw "Private upstream '$privateSource' must also appear in UpstreamSources to preserve its search order."
    }
}

if (-not $AllowNestedRepository) {
    $ancestor = Get-ExistingAncestor $Root
    if ($ancestor) {
        $gitRoot = (& git -C $ancestor rev-parse --show-toplevel 2>$null)
        if ($LASTEXITCODE -eq 0 -and $gitRoot) {
            $resolvedRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
            $resolvedGitRoot = [System.IO.Path]::GetFullPath(
                ([string] $gitRoot).Trim()).TrimEnd('\', '/')
            if ($resolvedRoot -eq $resolvedGitRoot -or
                $resolvedRoot.StartsWith(
                    "$resolvedGitRoot$([System.IO.Path]::DirectorySeparatorChar)",
                    [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Root '$Root' is inside existing repository '$resolvedGitRoot'. Pass -AllowNestedRepository only when this is intentional."
            }
        }
    }
}

$rootExisted = Test-Path -LiteralPath $Root
if ($rootExisted) {
    $existing = @(Get-ChildItem -LiteralPath $Root -Force -ErrorAction SilentlyContinue)
    if ($existing.Count -gt 0) {
        throw "Root '$Root' is not empty ($($existing.Count) items)."
    }
} else {
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
}

$rank = Get-InfrastructureRank $Infrastructure
$sharedRuntime = $Role -in @('consumer', 'hybrid') -and
    @($Clients | Where-Object { $_ -ne 'claude-code' }).Count -gt 0
$claudeRuntime = $Role -in @('consumer', 'hybrid') -and $Clients -contains 'claude-code'
$runtimeTargets = [System.Collections.Generic.List[object]]::new()
if ($sharedRuntime) {
    $runtimeTargets.Add([pscustomobject]@{
            RelativePath = '.agents/skills'
        })
}
if ($claudeRuntime) {
    $runtimeTargets.Add([pscustomobject]@{
            RelativePath = '.claude/skills'
        })
}
$repositoryUrl = if ($Visibility -eq 'local') { '' } else { "https://github.com/$Owner/$Name" }
$ownerUrl = if ($Owner) { "https://github.com/$Owner" } else { '' }
$copyrightHolder = if ($Owner) { "$Owner and contributors" } else { "$Name contributors" }
$remoteCreateCommand = if ($Visibility -eq 'local') { '' } else {
    $descriptionLiteral = ConvertTo-PowerShellLiteral $Description
    $rootLiteral = ConvertTo-PowerShellLiteral $Root
    "gh repo create $Owner/$Name --$Visibility --description $descriptionLiteral --source $rootLiteral --remote origin"
}
$licenseLabel = if ($License -eq 'none') { 'No license selected' } else { $License }
$sourceRoot = if ($Role -in @('source', 'hybrid')) {
    '- Canonical skill source: `skills/`'
} else { '' }
$runtimeRoot = if ($Role -in @('consumer', 'hybrid')) {
    @($runtimeTargets | ForEach-Object { "- Vendored runtime skills: ``$($_.RelativePath)/``" }) -join "`n"
} else { '' }
$layoutRows = @($sourceRoot, $runtimeRoot) | Where-Object { $_ }
$remoteIdentity = if ($Visibility -eq 'local') {
    'This repository is local-only. No remote URL or remote installation command is configured.'
} else {
    "Repository: [$Owner/$Name]($repositoryUrl) ($Visibility). Remote actions remain pending in [REMOTE-SETUP.md](REMOTE-SETUP.md)."
}
$consumption = if ($Visibility -eq 'local' -or $Role -eq 'consumer') {
    'No remote source installation command is published for this repository.'
} elseif ($Visibility -eq 'private') {
    @(
        'Authenticated readers with repository access can install a released skill:'
        ''
        '```pwsh'
        'gh auth status'
        "gh skill install $Owner/$Name <skill> --pin <tag-or-full-sha>"
        '```'
    ) -join "`n"
} else {
    @(
        'Install a released skill at an immutable revision:'
        ''
        '```pwsh'
        "gh skill install $Owner/$Name <skill> --pin <tag-or-full-sha>"
        '```'
    ) -join "`n"
}
$clientRows = @($Clients | Sort-Object -Unique | ForEach-Object {
    "| ``$_`` | ``$(Get-ClientRoot $_)`` |"
}) -join "`n"
$upstreamRows = @($upstreams | ForEach-Object -Begin { $index = 0 } -Process {
    $index++
    $privacy = if ($PrivateUpstreamSources -contains $_) { ' (private source)' } else { '' }
    "$index. $_$privacy"
}) -join "`n"
$skillRows = if ($ResolvedSkills.Count -eq 0) {
    'No starter runtime skills were selected.'
} else {
    $rows = @('| Skill | Selection | Pin |', '| --- | --- | --- |')
    $rows += $ResolvedSkills | Sort-Object -Unique | ForEach-Object {
        $selection = if ($SelectedSkills -contains $_) { 'direct' } else { 'dependency' }
        "| ``$_`` | $selection | ``$SkillsRef`` |"
    }
    $rows -join "`n"
}
$validationSection = if ($rank -ge 1) {
    @'
## Validate

```pwsh
./tools/Validate-Repository.ps1
Invoke-Pester ./tests
```
'@
} else {
    ''
}
$ciSection = if ($rank -ge 2) {
    @'
## Continuous integration

GitHub Actions runs deterministic skill validation and report-only provenance
drift checks.
'@
} else {
    ''
}
$distributionSection = if ($rank -eq 3) {
    $lines = @(
        '## Distribution'
        ''
        "Selected distribution surfaces: $(@($DistributionSurfaces | Sort-Object -Unique) -join ', ')."
    )
    if ($DistributionSurfaces -contains 'marketplace') {
        $lines += @(
            ''
            'After deterministic validation, test the local plugin package in an isolated Copilot home:'
            ''
            '```pwsh'
            './tests/Invoke-PluginSmoke.ps1'
            '```')
    }
    $lines -join "`n"
} else {
    ''
}
$limitations = [System.Collections.Generic.List[string]]::new()
if ($rank -lt 1) { $limitations.Add('No deterministic validation tooling was selected.') }
if ($rank -lt 2) { $limitations.Add('No continuous integration workflow was selected.') }
if ($rank -lt 3) {
    $limitations.Add('No release, plugin, marketplace, custom-agent, or MCP distribution was selected.')
}
if ($rank -eq 3 -and $DistributionSurfaces -contains 'plugin' -and
    $DistributionSurfaces -notcontains 'marketplace') {
    $limitations.Add('Direct plugin installation can be smoke-tested only after the GitHub repository is published; no marketplace was selected for an isolated local install.')
}
$limitationsSection = if ($limitations.Count -gt 0) {
    "## Deliberate omissions`n`n$(@($limitations | ForEach-Object { "- $_" }) -join "`n")"
} else { '' }
$optionalSections = @(
    $validationSection.TrimEnd()
    $ciSection.TrimEnd()
    $distributionSection.TrimEnd()
    $limitationsSection.TrimEnd()
) | Where-Object { $_ }
$pluginAgents = if ($DistributionSurfaces -contains 'agents') {
    ",`n  `"agents`": `"agents/`""
} else { '' }
$pluginMcp = if ($DistributionSurfaces -contains 'mcp') {
    ",`n  `"mcpServers`": `".mcp.json`""
} else { '' }
$pluginSmokeSteps = if ($DistributionSurfaces -contains 'marketplace') {
        @'
            - name: Install Copilot CLI
                run: npm install --global @github/copilot@1.0.63
            - name: Smoke-test plugin installation
                shell: pwsh
                run: ./tests/Invoke-PluginSmoke.ps1
'@
} else { '' }
$validateRuntimeCommands = @($runtimeTargets | ForEach-Object {
    "& `$validator (Join-Path `$root '$($_.RelativePath)')"
}) -join "`n"
$manageOverlayTargets = @($runtimeTargets | ForEach-Object {
    "- ``$($_.RelativePath)/manage-skills/overlay.md``"
}) -join "`n"
$marketplaceName = if ([string]::IsNullOrWhiteSpace($Owner)) {
    ''
} else {
    "$($Owner.ToLowerInvariant())-$Name"
}

$tokens = @{
    NAME = $Name
    DESCRIPTION = $Description
    ROLE = $Role
    AUDIENCE = $Audience
    VISIBILITY = $Visibility
    LICENSE = $licenseLabel
    LAYOUT_ROWS = $layoutRows -join "`n"
    REMOTE_IDENTITY = $remoteIdentity
    CONSUMPTION = $consumption
    CLIENT_ROWS = $clientRows
    UPSTREAM_ROWS = $upstreamRows
    SKILL_ROWS = $skillRows
    OPTIONAL_SECTIONS = $optionalSections -join "`n`n"
    OWNER = $Owner
    COPYRIGHT_HOLDER = $copyrightHolder
    SKILLS_REPO = $SkillsRepo
    SKILLS_REF = $SkillsRef
    EXPECT_SHARED_RUNTIME = if ($sharedRuntime) { '$true' } else { '$false' }
    EXPECT_CLAUDE_RUNTIME = if ($claudeRuntime) { '$true' } else { '$false' }
    NAME_JSON = ConvertTo-JsonScalar $Name
    VERSION_JSON = ConvertTo-JsonScalar $Version
    DESCRIPTION_JSON = ConvertTo-JsonScalar $Description
    LICENSE_JSON = ConvertTo-JsonScalar $License
    OWNER_JSON = ConvertTo-JsonScalar $Owner
    OWNER_URL_JSON = ConvertTo-JsonScalar $ownerUrl
    REPOSITORY_URL_JSON = ConvertTo-JsonScalar $repositoryUrl
    MARKETPLACE_NAME_JSON = ConvertTo-JsonScalar $marketplaceName
    PLUGIN_AGENTS = $pluginAgents
    PLUGIN_MCP = $pluginMcp
    PLUGIN_SMOKE_STEPS = $pluginSmokeSteps.TrimEnd()
    REMOTE_CREATE_COMMAND = $remoteCreateCommand
    DEFAULT_BRANCH = $DefaultBranch
    RUNTIME_ROOTS_PS = ConvertTo-PowerShellArrayLiteral @(
        $runtimeTargets | ForEach-Object { $_.RelativePath })
    RESOLVED_SKILLS_PS = ConvertTo-PowerShellArrayLiteral @(
        $ResolvedSkills | Sort-Object -Unique)
    MANAGE_OVERLAY_TARGETS = $manageOverlayTargets
    VALIDATE_SOURCE = if ($Role -in @('source', 'hybrid')) {
        '& $validator (Join-Path $root ''skills'') -RequirePortfolioMetadata'
    } else { '' }
    VALIDATE_RUNTIME = $validateRuntimeCommands
}

try {
    Expand-TemplateSet (Join-Path $templateRoot 'base') $Root $tokens

    if ($Visibility -ne 'local') {
        Expand-TemplateSet (Join-Path $templateRoot 'remote') $Root $tokens
    }

    if ($License -eq 'none') {
        Remove-Item -LiteralPath (Join-Path $Root 'LICENSE') -Force
    }
    if ($Role -in @('source', 'hybrid')) {
        New-Directory (Join-Path $Root 'skills')
        Expand-TemplateSet (Join-Path $templateRoot 'role-source') $Root $tokens
    }
    if ($sharedRuntime) {
        Expand-TemplateSet (Join-Path $templateRoot 'role-consumer-shared') $Root $tokens
    }
    if ($claudeRuntime) {
        Expand-TemplateSet (Join-Path $templateRoot 'role-consumer-claude') $Root $tokens
    }

    if ($rank -ge 1) {
        Expand-TemplateSet (Join-Path $templateRoot 'validation') $Root $tokens
        $validatorSource = Join-Path $PSScriptRoot '../../../../skills/manage-skills/scripts/Validate-Skills.ps1'
        if (-not (Test-Path -LiteralPath $validatorSource -PathType Leaf)) {
            throw "Required commons validator not found: $validatorSource"
        }
        Copy-Item -LiteralPath $validatorSource -Destination (
            Join-Path $Root 'tools/Validate-Skills.ps1')
    }
    if ($rank -ge 2) {
        Expand-TemplateSet (Join-Path $templateRoot 'ci') $Root $tokens
    }
    if ($rank -eq 3) {
        Expand-TemplateSet (Join-Path $templateRoot 'distribution/base') $Root $tokens
        foreach ($surface in @($DistributionSurfaces |
                Where-Object { $_ -ne 'direct' } | Sort-Object -Unique)) {
            Expand-TemplateSet (Join-Path $templateRoot "distribution/$surface") $Root $tokens
        }
    }
    if ($IncludeEvaluations) {
        Expand-TemplateSet (Join-Path $templateRoot 'evaluations') $Root $tokens
    }

    if ($rank -ge 1 -and $Role -in @('source', 'hybrid')) {
        & (Join-Path $Root 'tools/Update-SkillCatalog.ps1') -Apply
    }

    if ($ResolvedSkills.Count -gt 0) {
        $gh = Get-Command gh -ErrorAction SilentlyContinue
        $canInstall = $false
        if ($gh) {
            & gh skill --help *> $null
            $canInstall = $?
        }

        $pending = [System.Collections.Generic.List[string]]::new()
        $manageOverlayPending = $false
        foreach ($target in $runtimeTargets) {
            $destination = Join-Path $Root $target.RelativePath
            foreach ($skill in @($ResolvedSkills | Sort-Object -Unique)) {
                $installed = $false
                if ($canInstall) {
                    & gh skill install $SkillsRepo $skill --pin $SkillsRef --dir $destination `
                        --force *> $null
                    $installed = $?
                }
                if (-not $installed) {
                    $pending.Add(
                        "gh skill install $SkillsRepo $skill --pin $SkillsRef --dir $($target.RelativePath) --force")
                }
                if ($skill -eq 'manage-skills') {
                    $manageDirectory = Join-Path $destination 'manage-skills'
                    if ($installed -and (Test-Path (Join-Path $manageDirectory 'SKILL.md'))) {
                        $overlay = Expand-TemplateText `
                            -Path (Join-Path $templateRoot 'fragments/manage-skills-overlay.md.tmpl') `
                            -Tokens $tokens
                        [System.IO.File]::WriteAllText(
                            (Join-Path $manageDirectory 'overlay.md'),
                            $overlay,
                            [System.Text.UTF8Encoding]::new($false))
                    } else {
                        $manageOverlayPending = $true
                    }
                }
            }
        }
        if ($pending.Count -gt 0) {
            $pendingText = @(
                '# Pending skill installs'
                ''
                'These commands were not completed during scaffolding:'
                'The dependency closure cannot be verified until every command succeeds.'
                ''
                '```pwsh'
                $pending
                '```'
                ''
            ) -join "`n"
            [System.IO.File]::WriteAllText(
                (Join-Path $Root 'PENDING-SKILL-INSTALLS.md'),
                $pendingText,
                [System.Text.UTF8Encoding]::new($false))
        }
        if ($manageOverlayPending) {
            $overlay = Expand-TemplateText `
                -Path (Join-Path $templateRoot 'fragments/manage-skills-overlay.md.tmpl') `
                -Tokens $tokens
            $pendingGuide = Expand-TemplateText `
                -Path (Join-Path $templateRoot 'fragments/pending-manage-skills-overlay.md.tmpl') `
                -Tokens ($tokens + @{ MANAGE_OVERLAY_CONTENT = $overlay.TrimEnd() })
            [System.IO.File]::WriteAllText(
                (Join-Path $Root 'PENDING-MANAGE-SKILLS-OVERLAY.md'),
                $pendingGuide,
                [System.Text.UTF8Encoding]::new($false))
        }
    }

    if (-not $SkipGit) {
        & git -C $Root init --initial-branch=$DefaultBranch *> $null
        if ($LASTEXITCODE -ne 0) { throw 'git init failed.' }
    }

    Write-Host "Local skill repository scaffold complete: $Root"
    if ($Visibility -ne 'local') {
        Write-Host 'Remote creation remains pending explicit approval:'
        Write-Host "  $remoteCreateCommand"
    }
} catch {
    if (-not $rootExisted -and (Test-Path -LiteralPath $Root)) {
        Remove-Item -LiteralPath $Root -Recurse -Force
    } elseif (Test-Path -LiteralPath $Root) {
        [System.IO.File]::WriteAllText(
            (Join-Path $Root 'SCAFFOLD-FAILED.txt'),
            "$($_.Exception.Message)`n",
            [System.Text.UTF8Encoding]::new($false))
    }
    throw
}