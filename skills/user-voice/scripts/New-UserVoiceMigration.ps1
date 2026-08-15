#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string] $ExistingSkillPath,

    [Parameter(Mandatory)]
    [string] $StagingRoot,

    [switch] $PreparePrivateRepository,
    [switch] $ExistingSkillPrivateGitHubSource,
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-SourceManifest([string] $root) {
    return @(Get-ChildItem -LiteralPath $root -File -Recurse -Force |
        Sort-Object FullName |
        ForEach-Object {
            [pscustomobject]@{
                Path = [System.IO.Path]::GetRelativePath($root, $_.FullName).
                    Replace('\', '/')
                Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
        })
}

function Get-Disposition([string] $relativePath) {
    $name = [System.IO.Path]::GetFileName($relativePath)
    if ($relativePath -match '(?i)\.(?:eml|mbox|msg|ost|pst|zip)$') { return 'drop' }
    if ($name -ceq 'SKILL.md') { return 'transform' }
    if ($name -match '(?i)voice-profile|profile') { return 'transform' }
    if ($name -match '(?i)evaluation|test') { return 'transform' }
    if ($name -match '(?i)evidence|source|calibration') { return 'maintenance-only' }
    if ($name -match '(?i)install') { return 'transform' }
    return 'needs-user-decision'
}

$sourceInput = $ExecutionContext.SessionState.Path.
    GetUnresolvedProviderPathFromPSPath($ExistingSkillPath)
if (-not (Test-Path -LiteralPath $sourceInput -PathType Container)) {
    throw "The existing skill directory does not exist: '$ExistingSkillPath'."
}
$source = (Resolve-Path -LiteralPath $sourceInput).Path
$skillPath = Join-Path $source 'SKILL.md'
if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) {
    throw "The existing skill has no SKILL.md: '$source'."
}

$skillContent = [System.IO.File]::ReadAllText($skillPath)
$nameMatch = [regex]::Match($skillContent, '(?m)^name:\s*(?<value>[^\r\n]+)\r?$')
$descriptionMatch = [regex]::Match($skillContent, '(?m)^description:\s*(?<value>[^\r\n]+)\r?$')
if (-not $nameMatch.Success -or -not $descriptionMatch.Success) {
    throw 'The existing skill frontmatter does not expose a scalar name and description.'
}
$skillName = $nameMatch.Groups['value'].Value.Trim().Trim("'", '"')
$description = $descriptionMatch.Groups['value'].Value.Trim().Trim("'", '"')
$git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($null -ne $git) {
    $sourceRepository = @(& $git.Source -C $source rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -eq 0 -and $sourceRepository.Count -gt 0) {
        if (-not $ExistingSkillPrivateGitHubSource) {
            throw 'The existing skill is inside a Git repository. Pass -ExistingSkillPrivateGitHubSource only after accepting and verifying the private GitHub source boundary.'
        }
        $repositoryValidator = Join-Path $PSScriptRoot 'Test-UserVoiceRepository.ps1'
        $pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
        & $pwsh -NoProfile -File $repositoryValidator `
            -RepositoryPath $sourceRepository[0] `
            -ContentPath $source `
            -RequirePrivateGitHub `
            -ScanHistory
        if ($LASTEXITCODE -ne 0) {
            throw 'The existing skill source could not be verified as private.'
        }
    }
    elseif ($ExistingSkillPrivateGitHubSource) {
        throw '-ExistingSkillPrivateGitHubSource requires the existing skill to be inside a verifiable private GitHub repository.'
    }
}
elseif ($ExistingSkillPrivateGitHubSource) {
    throw 'Git is required to verify a private GitHub source.'
}
$manifestBefore = Get-SourceManifest $source

$pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
$profileScript = Join-Path $PSScriptRoot 'New-UserVoiceProfile.ps1'
$arguments = @(
    '-NoProfile',
    '-File', $profileScript,
    '-MaintenanceRoot', $StagingRoot)
if ($PreparePrivateRepository) { $arguments += '-PreparePrivateRepository' }
if ($Force) { $arguments += '-Force' }
if (-not $PSCmdlet.ShouldProcess($StagingRoot, "Create migration candidate for '$skillName'")) {
    return
}
& $pwsh @arguments | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not create the standard migration candidate.' }

$staging = (Resolve-Path -LiteralPath $StagingRoot).Path
$maintenance = Join-Path $staging 'migration'
New-Item -ItemType Directory -Path $maintenance -Force | Out-Null
$manifestBefore | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath (Join-Path $maintenance 'source-manifest.json')
[ordered]@{
    schemaVersion = 1
    sourceSkillName = $skillName
    sourceDescription = $description
    sourceFileCount = $manifestBefore.Count
    candidateRuntimeName = 'user-voice-profile'
    status = 'needs-private-semantic-conversion'
} | ConvertTo-Json |
    Set-Content -LiteralPath (Join-Path $maintenance 'source-metadata.json')

$mapLines = [System.Collections.Generic.List[string]]::new()
$mapLines.Add('# Migration map')
$mapLines.Add('')
$mapLines.Add('| Source path | Disposition | Reviewed destination |')
$mapLines.Add('| --- | --- | --- |')
foreach ($item in $manifestBefore) {
    $disposition = Get-Disposition $item.Path
    $mapLines.Add("| ``$($item.Path)`` | ``$disposition`` | needs private review |")
}
$mapLines.Add('')
$mapLines.Add('No source prose was copied into the standard candidate.')
$mapLines | Set-Content -LiteralPath (Join-Path $maintenance 'migration-map.md')

$knownRoots = @(
    (Join-Path $HOME '.copilot/skills')
    (Join-Path $HOME '.agents/skills')
    (Join-Path $HOME '.claude/skills')
    (Join-Path $HOME '.gemini/skills')
    (Join-Path $HOME '.cursor/skills'))
$installs = @($knownRoots | ForEach-Object {
        $candidate = Join-Path $_ $skillName
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            [pscustomobject]@{
                Root = $_
                Path = (Resolve-Path -LiteralPath $candidate).Path
                FileCount = @(Get-ChildItem -LiteralPath $candidate -File -Recurse -Force).Count
            }
        }
    })
$installsJson = if ($installs.Count -eq 0) {
    '[]'
}
else { $installs | ConvertTo-Json -Depth 5 }
$installsJson | Set-Content -LiteralPath (
    Join-Path $maintenance 'installed-copies.json')

$manifestAfter = Get-SourceManifest $source
if ((ConvertTo-Json $manifestBefore -Depth 5 -Compress) -cne
    (ConvertTo-Json $manifestAfter -Depth 5 -Compress)) {
    throw 'The source skill changed while creating the migration candidate.'
}

[pscustomobject]@{
    SourceSkill = $skillName
    SourcePath = $source
    StagingRoot = $staging
    RuntimeCandidate = Join-Path $staging 'user-voice-profile'
    MigrationMap = Join-Path $maintenance 'migration-map.md'
    InstalledCopyCount = $installs.Count
    Status = 'needs-private-semantic-conversion'
}