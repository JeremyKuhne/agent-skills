#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$skillRoot = Split-Path -Parent $PSScriptRoot

function Assert-Contains(
    [string] $relativePath,
    [string[]] $requiredText) {
    $path = Join-Path $skillRoot $relativePath
    $content = ([System.IO.File]::ReadAllText($path) -replace '\s+', ' ')
    foreach ($required in $requiredText) {
        if (-not $content.Contains($required, [System.StringComparison]::Ordinal)) {
            throw "$relativePath is missing required contract text: $required"
        }
    }
}

Assert-Contains 'SKILL.md' @(
    '[discovery.md](discovery.md)',
    '[nuance-analysis.md](nuance-analysis.md)',
    '[elicitation.md](elicitation.md)',
    '[interaction.md](interaction.md)',
    '[completion.md](completion.md)')
Assert-Contains 'discovery.md' @(
    'channel and kind of writing',
    'audience and relationship',
    'intent and stakes',
    'length and formality',
    'topic',
    'era or recency',
    'Stop when there is no approved evidence',
    'another agent that can access those sources')
Assert-Contains 'capture.md' @(
    'any source-derived draft needs five independent',
    'a kind of writing that is not yet ready needs three independent samples',
    'moderate confidence needs five independent',
    'strong confidence needs ten or more')
Assert-Contains 'nuance-analysis.md' @(
    '### 1. Rhetorical and epistemic structure',
    '### 2. Register and relationship',
    '### 3. Mechanics',
    '### 4. Interpersonal stance',
    '### 5. Lexical behavior',
    '### 6. Artifact patterns',
    '### 7. Conflicts and counterevidence',
    'not-observed')
Assert-Contains 'elicitation.md' @(
    'manually written option C',
    'both condition hashes must match',
    'the user does not assess that case',
    'at least three cases',
    'loses no more than one case',
    'Explain this result in more detail',
    'High-impact pending results block promotion')
Assert-Contains 'interaction.md' @(
    'Use the simplest accurate words',
    'Every question must stand on its own',
    'a shared message on another question does not count',
    'How much editing would A need?',
    'Where should this profile be allowed to shape your writing?',
    'Explain the initial decision before offering choices',
    'Explain this result in more detail',
    'Which version would you rather edit?',
    'Explain this comparison in more detail',
    'repeat the practical task, the complete option the user selected',
    'The preference already identifies the starting point',
    'change no file, score, confidence, approval, or runtime state')
Assert-Contains 'completion.md' @(
    'Profile state: <draft, not approved | approved and ready to install | installed and checked>',
    'Can it send or post: No',
    'Moving to another machine:',
    'Where should this profile be allowed to shape your writing?',
    'Explain what each category means',
    'New-UserVoiceCompletionCard.ps1',
    '-InvocationVerification passed',
    'Do not ask the user to repeat facts the workflow can verify',
    'Present the verified state')
Assert-Contains 'interaction.md' @(
    'Do not ask the user to repeat state that tools or files already establish',
    'Ask only for a choice, missing information, or a clarification')
Assert-Contains 'audit.md' @(
    'source-confirmation-check: passed',
    'elicitation-high-impact-results: resolved',
    'transient-cleanup-check: passed',
    'release-review: passed')
Assert-Contains 'private-source.md' @(
    'New-UserVoiceSetupGuide.ps1',
    'Test-UserVoiceInstallation.ps1',
    '-RequireSingleActiveProfile',
    'Before asking to commit, explain in plain language what behavior changes',
    'A file list, hash table, version label, or command is audit detail',
    'obtain a separate push approval',
    'Commit approval never authorizes a push')
Assert-Contains 'interaction.md' @(
    'Explain an action before asking for approval',
    'what behavior or user-visible state changes',
    'A technically exact prompt is still inadequate',
    'Ask for those approvals separately')
Assert-Contains 'profile-schema.md' @(
    'Do not put current installation status',
    'generated completion card')
Assert-Contains 'migration.md' @(
    'Test-UserVoiceThreeWayComparison.ps1',
    'Which version would you rather edit?',
    'Every rating question repeats the practical task',
    'beats the old profile in at least three cases',
    'old profile beats the draft in no more than one')
Assert-Contains 'handoff.md' @(
    'USER-VOICE-REPORT-BEGIN',
    'USER-VOICE-REPORT-END',
    'schema version 2',
    'Never ask the user to repair machine fields manually')
Assert-Contains 'assets/setup-windows.md.tmpl' @(
    '{{CLIENT}}',
    '{{SOURCE_METHOD}}',
    '{{SOURCE_REVISION}}',
    '{{INSTALLER_PATH}}',
    '{{VERIFY_STEPS}}',
    'does not make the profile available to cloud agents')
Assert-Contains 'assets/setup-posix.md.tmpl' @(
    '{{CLIENT}}',
    '{{SOURCE_METHOD}}',
    '{{SOURCE_REVISION}}',
    '{{INSTALLER_PATH}}',
    '{{VERIFY_STEPS}}',
    'does not make the profile available to cloud agents')
Assert-Contains 'assets/examples/rights-reviewed-fixtures.md' @(
    'rights-basis: original synthetic text authored for this repository',
    'third-party-excerpt: none',
    'voice-evidence: no',
    'do not ask the user to rate the case')

Write-Host 'OK workflow contract tests'
