#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$skillRoot = Split-Path -Parent $PSScriptRoot
$scripts = Join-Path $skillRoot 'scripts'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "user-voice-lifecycle-$([guid]::NewGuid().ToString('N'))"
$pwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })

function Invoke-RequiredSuccess([string] $name, [string[]] $arguments) {
    $output = @(& $pwsh @arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "$name failed unexpectedly:`n$($output -join "`n")"
    }
    return $output
}

function Invoke-RequiredFailure([string] $name, [string[]] $arguments) {
    $output = @(& $pwsh @arguments 2>&1)
    if ($LASTEXITCODE -eq 0) {
        throw "$name passed unexpectedly."
    }
}

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $setupGuideScript = Join-Path $scripts 'New-UserVoiceSetupGuide.ps1'
    $lfSource = [System.IO.File]::ReadAllText($setupGuideScript).
        Replace("`r`n", "`n")
    $tokens = $null
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseInput(
        $lfSource,
        [ref] $tokens,
        [ref] $parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Setup guide script fails LF parsing: $($parseErrors.Message -join '; ')"
    }

    $maintenanceRoot = Join-Path $testRoot 'maintenance'
    $null = Invoke-RequiredSuccess 'Generate maintenance root' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'New-UserVoiceProfile.ps1'),
        '-MaintenanceRoot', $maintenanceRoot)

    $draftCard = @(Invoke-RequiredSuccess 'Draft completion card' @(
            '-NoProfile',
            '-File', (Join-Path $scripts 'New-UserVoiceCompletionCard.ps1'),
            '-MaintenanceRoot', $maintenanceRoot)) -join "`n"
    if (-not $draftCard.Contains('Profile state: draft, not approved', [StringComparison]::Ordinal) -or
        -not $draftCard.Contains('Can it send or post: No', [StringComparison]::Ordinal)) {
        throw 'Draft completion card overstates status or omits the action boundary.'
    }

    $missingContextRoot = Join-Path $testRoot 'missing-context'
    Copy-Item -LiteralPath $maintenanceRoot -Destination $missingContextRoot -Recurse
    $missingContextProfile = Join-Path $missingContextRoot 'voice-profile.md'
    $missingContextText = [regex]::Replace(
        [System.IO.File]::ReadAllText($missingContextProfile),
        '(?ms)^## Context matrix\r?\n.*?(?=^## |\z)',
        '')
    [System.IO.File]::WriteAllText(
        $missingContextProfile,
        $missingContextText,
        [System.Text.UTF8Encoding]::new($false))
    Invoke-RequiredFailure 'Completion card without context matrix' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'New-UserVoiceCompletionCard.ps1'),
        '-MaintenanceRoot', $missingContextRoot)

    $unknownContextRoot = Join-Path $testRoot 'unknown-context'
    Copy-Item -LiteralPath $maintenanceRoot -Destination $unknownContextRoot -Recurse
    $unknownContextProfile = Join-Path $unknownContextRoot 'voice-profile.md'
    $unknownContextText = [System.IO.File]::ReadAllText($unknownContextProfile).
        Replace('| Unreviewed context | unsupported |', '| Unreviewed context | uncertain |')
    [System.IO.File]::WriteAllText(
        $unknownContextProfile,
        $unknownContextText,
        [System.Text.UTF8Encoding]::new($false))
    Invoke-RequiredFailure 'Completion card with unknown context status' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'New-UserVoiceCompletionCard.ps1'),
        '-MaintenanceRoot', $unknownContextRoot)

    $canonicalProfile = Join-Path $maintenanceRoot 'voice-profile.md'
    $runtimeProfile = Join-Path $maintenanceRoot 'user-voice-profile/references/voice-profile.md'
    foreach ($path in @($canonicalProfile, $runtimeProfile)) {
        $content = [System.IO.File]::ReadAllText($path).
            Replace('- profile-status: draft-unapproved', '- profile-status: approved')
        [System.IO.File]::WriteAllText(
            $path,
            $content,
            [System.Text.UTF8Encoding]::new($false))
    }

    $approvedCard = @(Invoke-RequiredSuccess 'Approved completion card' @(
            '-NoProfile',
            '-File', (Join-Path $scripts 'New-UserVoiceCompletionCard.ps1'),
            '-MaintenanceRoot', $maintenanceRoot)) -join "`n"
    if (-not $approvedCard.Contains('Profile state: approved and ready to install', [StringComparison]::Ordinal) -or
        -not $approvedCard.Contains('Installed in: not installed', [StringComparison]::Ordinal)) {
        throw 'Approved candidate completion card incorrectly claims installation.'
    }

    $discoveryRoot = Join-Path $testRoot 'discovery'
    $secondDiscoveryRoot = Join-Path $testRoot 'second-discovery'
    $installed = Join-Path $discoveryRoot 'user-voice-profile'
    New-Item -ItemType Directory -Path $discoveryRoot | Out-Null
    New-Item -ItemType Directory -Path $secondDiscoveryRoot | Out-Null
    Copy-Item -LiteralPath (Join-Path $maintenanceRoot 'user-voice-profile') -Destination $installed -Recurse
    $installArguments = @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'Test-UserVoiceInstallation.ps1'),
        '-SourcePath', (Join-Path $maintenanceRoot 'user-voice-profile'),
        '-InstalledPath', $installed,
        '-DiscoveryRoot', $discoveryRoot,
        '-ForbiddenProfileName', 'legacy-profile',
        '-RequireSingleActiveProfile')
    $null = Invoke-RequiredSuccess 'Installation verification' $installArguments

    Invoke-RequiredFailure 'Installed card without invocation verification' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'New-UserVoiceCompletionCard.ps1'),
        '-MaintenanceRoot', $maintenanceRoot,
        '-InstalledProfilePath', $installed,
        '-DiscoveryRoot', $discoveryRoot,
        '-InstalledClient', 'example-client')

    $installedCard = @(Invoke-RequiredSuccess 'Installed completion card' @(
            '-NoProfile',
            '-File', (Join-Path $scripts 'New-UserVoiceCompletionCard.ps1'),
            '-MaintenanceRoot', $maintenanceRoot,
            '-InstalledProfilePath', $installed,
            '-DiscoveryRoot', $discoveryRoot, $secondDiscoveryRoot,
            '-ForbiddenProfileName', 'legacy-profile',
            '-InstalledClient', 'example-client',
            '-InvocationVerification', 'passed')) -join "`n"
    if (-not $installedCard.Contains('Profile state: installed and checked', [StringComparison]::Ordinal) -or
        -not $installedCard.Contains('Installed in: example-client', [StringComparison]::Ordinal)) {
        throw 'Installed completion card did not use verified installation state.'
    }

    $duplicate = Join-Path $discoveryRoot 'duplicate-profile'
    Copy-Item -LiteralPath $installed -Destination $duplicate -Recurse
    Invoke-RequiredFailure 'Duplicate active profile' $installArguments
    Remove-Item -LiteralPath $duplicate -Recurse -Force

    $legacy = Join-Path $discoveryRoot 'legacy-profile'
    New-Item -ItemType Directory -Path $legacy | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $legacy 'SKILL.md'),
        "---`nname: legacy-profile`n---`n",
        [System.Text.UTF8Encoding]::new($false))
    Invoke-RequiredFailure 'Forbidden legacy profile' $installArguments
    Remove-Item -LiteralPath $legacy -Recurse -Force

    Add-Content -LiteralPath (Join-Path $installed 'INSTALL.md') -Value 'changed'
    Invoke-RequiredFailure 'Installed hash mismatch' $installArguments
    Remove-Item -LiteralPath $installed -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $maintenanceRoot 'user-voice-profile') -Destination $installed -Recurse

    $null = Invoke-RequiredSuccess 'Clean maintenance root' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'Test-UserVoiceTransientCleanup.ps1'),
        '-MaintenanceRoot', $maintenanceRoot)
    $rawDirectory = Join-Path $maintenanceRoot 'options'
    New-Item -ItemType Directory -Path $rawDirectory | Out-Null
    [System.IO.File]::WriteAllText(
        (Join-Path $rawDirectory 'raw.md'),
        "Option A: retained output`n",
        [System.Text.UTF8Encoding]::new($false))
    Invoke-RequiredFailure 'Retained transient output' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'Test-UserVoiceTransientCleanup.ps1'),
        '-MaintenanceRoot', $maintenanceRoot)
    Remove-Item -LiteralPath $rawDirectory -Recurse -Force

    $largeMaintenanceFile = Join-Path $maintenanceRoot 'retained-output.md'
    [System.IO.File]::WriteAllText(
        $largeMaintenanceFile,
        "Option A: retained output`n" + ('x' * (2MB)),
        [System.Text.UTF8Encoding]::new($false))
    Invoke-RequiredFailure 'Unreviewed large maintenance file' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'Test-UserVoiceTransientCleanup.ps1'),
        '-MaintenanceRoot', $maintenanceRoot)
    Remove-Item -LiteralPath $largeMaintenanceFile -Force

    $windowsGuide = Join-Path $testRoot 'windows-guide.md'
    $null = Invoke-RequiredSuccess 'Windows setup guide' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'New-UserVoiceSetupGuide.ps1'),
        '-Platform', 'Windows',
        '-SourceMethod', 'PrivateGitHub',
        '-Client', 'example-client',
        '-SourceRevision', ('a' * 40),
        '-SourceLocation', 'example/private-profile',
        '-DestinationRoot', (Join-Path $testRoot 'private-source'),
        '-InstallerPath', (Join-Path $scripts 'Install-UserSkill.ps1'),
        '-VerifierPath', (Join-Path $scripts 'Test-UserVoiceInstallation.ps1'),
        '-RuntimePath', (Join-Path $maintenanceRoot 'user-voice-profile'),
        '-InstalledPath', $installed,
        '-OutputPath', $windowsGuide)

    $posixGuide = Join-Path $testRoot 'posix-guide.md'
    $null = Invoke-RequiredSuccess 'POSIX setup guide' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'New-UserVoiceSetupGuide.ps1'),
        '-Platform', 'Posix',
        '-SourceMethod', 'LocalTransfer',
        '-Client', 'example-client',
        '-SourceRevision', ('b' * 64),
        '-SourceLocation', '/private/transfer',
        '-DestinationRoot', '/private/source',
        '-InstallerPath', '/private/Install-UserSkill.ps1',
        '-VerifierPath', '/private/Test-UserVoiceInstallation.ps1',
        '-RuntimePath', '/private/source/user-voice-profile',
        '-InstalledPath', '/private/home/user-voice-profile',
        '-OutputPath', $posixGuide)
    foreach ($guide in @($windowsGuide, $posixGuide)) {
        $guideText = [System.IO.File]::ReadAllText($guide)
        if ($guideText -match '\{\{[^}]+\}\}' -or
            -not $guideText.Contains('RequireSingleActiveProfile', [StringComparison]::Ordinal)) {
            throw "Generated guide is incomplete: '$guide'."
        }
    }
    $windowsGuideText = [System.IO.File]::ReadAllText($windowsGuide)
    if (-not $windowsGuideText.Contains('Test-UserVoiceRepository.ps1', [StringComparison]::Ordinal) -or
        -not $windowsGuideText.Contains("-ExpectedOwner 'example'", [StringComparison]::Ordinal)) {
        throw 'The private GitHub guide omits the repository scan or expected owner.'
    }
    $posixGuideText = [System.IO.File]::ReadAllText($posixGuide)
    if (-not $posixGuideText.Contains("-DiscoveryRoot '/private/home'", [StringComparison]::Ordinal) -or
        $posixGuideText.Contains('\private\home', [StringComparison]::Ordinal) -or
        $posixGuideText.Contains('Test-UserVoiceRepository.ps1', [StringComparison]::Ordinal)) {
        throw 'The local-transfer POSIX guide contains an invalid source check or discovery path.'
    }

    Invoke-RequiredFailure 'Short GitHub revision' @(
        '-NoProfile',
        '-File', (Join-Path $scripts 'New-UserVoiceSetupGuide.ps1'),
        '-Platform', 'Windows',
        '-SourceMethod', 'PrivateGitHub',
        '-Client', 'example-client',
        '-SourceRevision', 'abc123',
        '-SourceLocation', 'example/private-profile',
        '-DestinationRoot', (Join-Path $testRoot 'invalid-source'),
        '-InstallerPath', (Join-Path $scripts 'Install-UserSkill.ps1'),
        '-VerifierPath', (Join-Path $scripts 'Test-UserVoiceInstallation.ps1'),
        '-RuntimePath', (Join-Path $maintenanceRoot 'user-voice-profile'),
        '-InstalledPath', $installed,
        '-OutputPath', (Join-Path $testRoot 'invalid-guide.md'))

    $unsafeClients = @(
        "line`nbreak",
        "quote'client",
        'back`tick')
    for ($index = 0; $index -lt $unsafeClients.Count; $index++) {
        Invoke-RequiredFailure "Unsafe setup-guide value $index" @(
            '-NoProfile',
            '-File', (Join-Path $scripts 'New-UserVoiceSetupGuide.ps1'),
            '-Platform', 'Posix',
            '-SourceMethod', 'LocalTransfer',
            '-Client', $unsafeClients[$index],
            '-SourceRevision', ('b' * 64),
            '-SourceLocation', '/private/transfer',
            '-DestinationRoot', '/private/source',
            '-InstallerPath', '/private/Install-UserSkill.ps1',
            '-VerifierPath', '/private/Test-UserVoiceInstallation.ps1',
            '-RuntimePath', '/private/source/user-voice-profile',
            '-InstalledPath', '/private/home/user-voice-profile',
            '-OutputPath', (Join-Path $testRoot "unsafe-guide-$index.md"))
    }
    foreach ($unsafeClient in @("carriage`rreturn", [string] [char] 0)) {
        $rejected = $false
        try {
            & (Join-Path $scripts 'New-UserVoiceSetupGuide.ps1') `
                -Platform Posix `
                -SourceMethod LocalTransfer `
                -Client $unsafeClient `
                -SourceRevision ('b' * 64) `
                -SourceLocation '/private/transfer' `
                -DestinationRoot '/private/source' `
                -InstallerPath '/private/Install-UserSkill.ps1' `
                -VerifierPath '/private/Test-UserVoiceInstallation.ps1' `
                -RuntimePath '/private/source/user-voice-profile' `
                -InstalledPath '/private/home/user-voice-profile' `
                -OutputPath (Join-Path $testRoot 'unsafe-direct-guide.md')
        }
        catch { $rejected = $true }
        if (-not $rejected) {
            throw 'The setup guide accepted a CR or NUL character.'
        }
    }

    Write-Host 'OK lifecycle output acceptance tests'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}