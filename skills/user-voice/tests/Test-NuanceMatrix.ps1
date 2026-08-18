#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$skillRoot = Split-Path -Parent $PSScriptRoot
$scripts = Join-Path $skillRoot 'scripts'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "user-voice-nuance-$([guid]::NewGuid().ToString('N'))"
$pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })

function Invoke-RequiredSuccess([string] $name, [string[]] $arguments) {
    $output = @(& $pwsh @arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "$name failed unexpectedly:`n$($output -join "`n")"
    }
}

function Invoke-RequiredFailure([string] $name, [string[]] $arguments) {
    $output = @(& $pwsh @arguments 2>&1)
    if ($LASTEXITCODE -eq 0) {
        throw "$name passed unexpectedly."
    }
}

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null

    foreach ($target in @(
            'Test-UserVoiceNuanceMatrix.ps1',
            'Test-UserVoiceProfile.ps1',
            'New-UserVoiceProfile.ps1',
            'Build-UserVoiceProfile.ps1')) {
        $tokens = $null
        $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $scripts $target),
            [ref] $tokens,
            [ref] $parseErrors)
        if ($parseErrors.Count -gt 0) {
            throw "$target has parser errors: $($parseErrors.Message -join '; ')"
        }
    }

    $maintenanceRoot = Join-Path $testRoot 'maintenance'
    Invoke-RequiredSuccess 'Generation' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'New-UserVoiceProfile.ps1'),
        '-MaintenanceRoot', $maintenanceRoot)

    $runtime = Join-Path $maintenanceRoot 'user-voice-profile'
    $canonicalProfile = Join-Path $maintenanceRoot 'voice-profile.md'
    $matrix = Join-Path $maintenanceRoot 'nuance-matrix.md'
    Invoke-RequiredSuccess 'Draft runtime' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'Test-UserVoiceProfile.ps1'),
        '-ProfilePath', $runtime,
        '-AllowDraft')
    $volatileRuntime = Join-Path $testRoot 'volatile-runtime'
    Copy-Item -LiteralPath $runtime -Destination $volatileRuntime -Recurse
    Add-Content -LiteralPath (Join-Path $volatileRuntime 'references/voice-profile.md') `
        -Value '- active-runtime: stale-version'
    Invoke-RequiredFailure 'Volatile lifecycle field' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'Test-UserVoiceProfile.ps1'),
        '-ProfilePath', $volatileRuntime,
        '-AllowDraft')
    $dispositionRuntime = Join-Path $testRoot 'disposition-runtime'
    Copy-Item -LiteralPath $runtime -Destination $dispositionRuntime -Recurse
    Add-Content -LiteralPath (Join-Path $dispositionRuntime 'references/voice-profile.md') `
        -Value '- profile-disposition: approved-pending-build'
    Invoke-RequiredFailure 'Volatile profile disposition' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'Test-UserVoiceProfile.ps1'),
        '-ProfilePath', $dispositionRuntime,
        '-AllowDraft')
    $lifecycleProseRuntime = Join-Path $testRoot 'lifecycle-prose-runtime'
    Copy-Item -LiteralPath $runtime -Destination $lifecycleProseRuntime -Recurse
    Add-Content -LiteralPath (Join-Path $lifecycleProseRuntime 'references/voice-profile.md') `
        -Value "`n## Current state`n`nApproved, but not built, installed, or active:`n"
    Invoke-RequiredFailure 'Volatile lifecycle prose' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'Test-UserVoiceProfile.ps1'),
        '-ProfilePath', $lifecycleProseRuntime,
        '-AllowDraft')
    Invoke-RequiredSuccess 'Default matrix' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'Test-UserVoiceNuanceMatrix.ps1'),
        '-Path', $matrix,
        '-ProfilePath', $canonicalProfile)

    $legacyMaintenance = Join-Path $testRoot 'legacy-maintenance'
    Copy-Item -LiteralPath $maintenanceRoot -Destination $legacyMaintenance -Recurse
    $legacyCanonical = Join-Path $legacyMaintenance 'voice-profile.md'
    $legacyRuntime = Join-Path $legacyMaintenance 'user-voice-profile'
    $legacyVoice = [System.IO.File]::ReadAllText($legacyCanonical).
        Replace('- profile-schema-version: 2', '- profile-schema-version: 1').
        Replace('- profile-status: draft-unapproved', '- profile-status: approved')
    $legacyVoice = $legacyVoice -replace '(?m)^- profile-version:.*\r?\n', ''
    $legacyVoice = $legacyVoice -replace '(?m)^- runtime-status:.*\r?\n', ''
    [System.IO.File]::WriteAllText(
        $legacyCanonical,
        $legacyVoice,
        [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText(
        (Join-Path $legacyRuntime 'references/voice-profile.md'),
        $legacyVoice,
        [System.Text.UTF8Encoding]::new($false))
    $legacySkillPath = Join-Path $legacyRuntime 'SKILL.md'
    [System.IO.File]::WriteAllText(
        $legacySkillPath,
        ([System.IO.File]::ReadAllText($legacySkillPath).Replace(
                'profile-schema-version: 2',
                'profile-schema-version: 1')),
        [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText(
        (Join-Path $legacyMaintenance '.user-voice-maintenance.json'),
        "{`n  `"schemaVersion`": 1,`n  `"runtimeDirectory`": `"user-voice-profile`",`n  `"profileStatus`": `"approved`"`n}`n",
        [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText(
        (Join-Path $legacyMaintenance 'consent-ledger.md'),
        "# Consent ledger`n`n- consent-schema: 1`n- consent-id: consent-001`n- status: approved`n- analysis-provider: approved-provider`n- analysis-host: approved-host`n- retention: minimum`n- expiry: future-review`n- installed-hosts: test-host`n",
        [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText(
        (Join-Path $legacyMaintenance 'audit-results.md'),
        "# Audit results`n`n- deterministic-package-check: passed`n- semantic-privacy-review: passed`n- user-read-back: approved`n",
        [System.Text.UTF8Encoding]::new($false))
    Invoke-RequiredSuccess 'Schema 1 build' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'Build-UserVoiceProfile.ps1'),
        '-MaintenanceRoot', $legacyMaintenance)
    Invoke-RequiredSuccess 'Schema 1 runtime' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'Test-UserVoiceProfile.ps1'),
        '-ProfilePath', $legacyRuntime)

    $fixtureRoot = Join-Path $testRoot 'fixtures'
    New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
    $profileText = [System.IO.File]::ReadAllText($canonicalProfile).
        Replace('- user-approved: no', '- user-approved: yes').
        Replace('- runtime-status: inactive', '- runtime-status: active').
        Replace('- profile-status: draft-unapproved', '- profile-status: approved')
    $matrixText = [System.IO.File]::ReadAllText($matrix).
        Replace('- runtime-status: unsupported', '- runtime-status: supported').
        Replace('- channel-and-artifact: not-observed', '- channel-and-artifact: observed: review comment').
        Replace('- audience-and-relationship: not-observed', '- audience-and-relationship: observed: technical peer').
        Replace('- intent-and-stakes: not-observed', '- intent-and-stakes: observed: correction at moderate stakes').
        Replace('- length-and-formality: not-observed', '- length-and-formality: observed: short formal response').
        Replace('- direct-evidence-count-band: none', '- direct-evidence-count-band: 6-10').
        Replace('- source-diversity: none', '- source-diversity: audience=3+, artifact=2+').
        Replace('- evidence-floor: insufficient', '- evidence-floor: moderate').
        Replace('- rhetorical-and-epistemic: not-observed', '- rhetorical-and-epistemic: observed: leads with the controlling constraint').
        Replace('- register-and-relationship: not-observed', '- register-and-relationship: observed: uses a direct peer register').
        Replace('- mechanics: not-observed', '- mechanics: observed: uses compact paragraphs').
        Replace('- interpersonal-stance: not-observed', '- interpersonal-stance: observed: separates the claim from the person').
        Replace('- lexical-behavior: not-observed', '- lexical-behavior: observed: favors concrete causal verbs').
        Replace('- artifact-patterns: not-observed', '- artifact-patterns: observed: states the result before the mechanism').
        Replace('- unresolved-gaps: No confirmed evidence has been analyzed.', '- unresolved-gaps: none').
        Replace('- candidate-rule-ids: none', '- candidate-rule-ids: rule-001').
        Replace('- validation-case-ids: none', '- validation-case-ids: case-001, case-002, case-003, case-004, case-005').
        Replace('- genericity-control: not-run', '- genericity-control: passed').
        Replace('- confidence: low', '- confidence: moderate').
        Replace('- user-status: unreviewed', '- user-status: approved')

    $validProfile = Join-Path $fixtureRoot 'valid-profile.md'
    $validMatrix = Join-Path $fixtureRoot 'valid-matrix.md'
    [System.IO.File]::WriteAllText($validProfile, $profileText, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($validMatrix, $matrixText, [System.Text.UTF8Encoding]::new($false))
    Invoke-RequiredSuccess 'Supported matrix' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'Test-UserVoiceNuanceMatrix.ps1'),
        '-Path', $validMatrix,
        '-ProfilePath', $validProfile)

    $missingMechanics = Join-Path $fixtureRoot 'missing-mechanics.md'
    [System.IO.File]::WriteAllText(
        $missingMechanics,
        ($matrixText -replace '(?m)^- mechanics:.*\r?\n', ''),
        [System.Text.UTF8Encoding]::new($false))
    Invoke-RequiredFailure 'Missing mechanics' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'Test-UserVoiceNuanceMatrix.ps1'),
        '-Path', $missingMechanics,
        '-ProfilePath', $validProfile)

    $genericityNotRun = Join-Path $fixtureRoot 'genericity-not-run.md'
    [System.IO.File]::WriteAllText(
        $genericityNotRun,
        $matrixText.Replace('- genericity-control: passed', '- genericity-control: not-run'),
        [System.Text.UTF8Encoding]::new($false))
    Invoke-RequiredFailure 'Genericity not run' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'Test-UserVoiceNuanceMatrix.ps1'),
        '-Path', $genericityNotRun,
        '-ProfilePath', $validProfile)

    Invoke-RequiredFailure 'Active rule unmapped' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'Test-UserVoiceNuanceMatrix.ps1'),
        '-Path', $matrix,
        '-ProfilePath', $validProfile)

    [System.IO.File]::WriteAllText(
        $canonicalProfile,
        $profileText,
        [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText(
        $matrix,
        $matrixText,
        [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText(
        (Join-Path $maintenanceRoot 'consent-ledger.md'),
        "# Consent ledger`n`n- consent-schema: 1`n- consent-id: consent-001`n- status: approved`n- analysis-provider: approved-provider`n- analysis-host: approved-host`n- retention: minimum`n- expiry: future-review`n- installed-hosts: test-host`n",
        [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText(
        (Join-Path $maintenanceRoot 'audit-results.md'),
        "# Audit results`n`n- deterministic-package-check: pending candidate build`n- source-confirmation-check: passed`n- nuance-matrix-check: passed`n- elicitation-high-impact-results: unresolved`n- transient-cleanup-check: passed`n- section-review: approved`n- release-review: passed`n- semantic-privacy-review: passed`n- user-read-back: approved`n",
        [System.Text.UTF8Encoding]::new($false))
    Invoke-RequiredFailure 'Unresolved build gate' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'Build-UserVoiceProfile.ps1'),
        '-MaintenanceRoot', $maintenanceRoot)
    [System.IO.File]::WriteAllText(
        (Join-Path $maintenanceRoot 'audit-results.md'),
        "# Audit results`n`n- deterministic-package-check: pending candidate build`n- source-confirmation-check: passed`n- nuance-matrix-check: passed`n- elicitation-high-impact-results: resolved`n- transient-cleanup-check: passed`n- section-review: approved`n- release-review: passed`n- semantic-privacy-review: passed`n- user-read-back: approved`n",
        [System.Text.UTF8Encoding]::new($false))
    $runtimeProfileBeforePreflight = [System.IO.File]::ReadAllText(
        (Join-Path $runtime 'references/voice-profile.md'))
    Invoke-RequiredSuccess 'Schema 2 preflight' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'Build-UserVoiceProfile.ps1'),
        '-MaintenanceRoot', $maintenanceRoot,
        '-WhatIf')
    $buildScriptText = [System.IO.File]::ReadAllText(
        (Join-Path $scripts 'Build-UserVoiceProfile.ps1'))
    if ($buildScriptText.Contains('-WhatIf:$false', [System.StringComparison]::Ordinal)) {
        throw 'The build script bypasses WhatIf for a file operation.'
    }
    $runtimeProfileAfterPreflight = [System.IO.File]::ReadAllText(
        (Join-Path $runtime 'references/voice-profile.md'))
    if ($runtimeProfileAfterPreflight -cne $runtimeProfileBeforePreflight) {
        throw 'The preflight changed the runtime source.'
    }
    $preflightAudit = [System.IO.File]::ReadAllText(
        (Join-Path $maintenanceRoot 'audit-results.md'))
    if ($preflightAudit -notmatch '(?m)^- deterministic-package-check:\s*pending candidate build\s*$') {
        throw 'The preflight changed the deterministic package status.'
    }
    if (@(Get-ChildItem -LiteralPath $maintenanceRoot -Force |
            Where-Object { $_.Name -like '.user-voice-profile.build-*' }).Count -gt 0) {
        throw 'The preflight retained a staging directory.'
    }
    [System.IO.File]::WriteAllText(
        $canonicalProfile,
        $profileText + "`nhttps://example.invalid/private-source`n",
        [System.Text.UTF8Encoding]::new($false))
    Invoke-RequiredFailure 'Schema 2 prospective profile validation' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'Build-UserVoiceProfile.ps1'),
        '-MaintenanceRoot', $maintenanceRoot,
        '-WhatIf')
    [System.IO.File]::WriteAllText(
        $canonicalProfile,
        $profileText,
        [System.Text.UTF8Encoding]::new($false))
    $approvedAudit = [System.IO.File]::ReadAllText(
        (Join-Path $maintenanceRoot 'audit-results.md'))
    Add-Content -LiteralPath (Join-Path $maintenanceRoot 'audit-results.md') `
        -Value '- deterministic-package-check: duplicate'
    Invoke-RequiredFailure 'Duplicate package-check field' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'Build-UserVoiceProfile.ps1'),
        '-MaintenanceRoot', $maintenanceRoot,
        '-WhatIf')
    [System.IO.File]::WriteAllText(
        (Join-Path $maintenanceRoot 'audit-results.md'),
        $approvedAudit,
        [System.Text.UTF8Encoding]::new($false))
    Invoke-RequiredSuccess 'Schema 2 build' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'Build-UserVoiceProfile.ps1'),
        '-MaintenanceRoot', $maintenanceRoot)
    Invoke-RequiredSuccess 'Built runtime' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'Test-UserVoiceProfile.ps1'),
        '-ProfilePath', $runtime)
    $builtAudit = [System.IO.File]::ReadAllText((Join-Path $maintenanceRoot 'audit-results.md'))
    if ($builtAudit -notmatch '(?m)^- deterministic-package-check:\s*passed\s*$') {
        throw 'The successful build did not record the deterministic package check.'
    }

    $privateRoot = Join-Path $testRoot 'private-maintenance'
    Invoke-RequiredSuccess 'Private repository scaffold' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'New-UserVoiceProfile.ps1'),
        '-MaintenanceRoot', $privateRoot,
        '-PreparePrivateRepository')
    $copiedMatrixValidator = Join-Path $privateRoot '.private-voice/Test-UserVoiceNuanceMatrix.ps1'
    $copiedCleanupValidator = Join-Path $privateRoot '.private-voice/Test-UserVoiceTransientCleanup.ps1'
    $privateWorkflow = Join-Path $privateRoot '.github/workflows/private-voice-audit.yml'
    if (-not (Test-Path -LiteralPath $copiedMatrixValidator -PathType Leaf) -or
        -not (Test-Path -LiteralPath $copiedCleanupValidator -PathType Leaf) -or
        -not (Test-Path -LiteralPath $privateWorkflow -PathType Leaf) -or
        -not ([System.IO.File]::ReadAllText($privateWorkflow).Contains(
            'Test-UserVoiceNuanceMatrix.ps1',
            [System.StringComparison]::Ordinal)) -or
        -not ([System.IO.File]::ReadAllText($privateWorkflow).Contains(
            'Test-UserVoiceTransientCleanup.ps1',
            [System.StringComparison]::Ordinal))) {
        throw 'The private repository scaffold does not carry and invoke required validators.'
    }
    Invoke-RequiredSuccess 'Copied matrix validator' @(
        '-NoProfile',
        '-File', $copiedMatrixValidator,
        '-Path', (Join-Path $privateRoot 'nuance-matrix.md'),
        '-ProfilePath', (Join-Path $privateRoot 'voice-profile.md'))
    Invoke-RequiredSuccess 'Copied cleanup validator' @(
        '-NoProfile',
        '-File', $copiedCleanupValidator,
        '-MaintenanceRoot', $privateRoot)

    Write-Host 'OK nuance matrix acceptance tests'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
