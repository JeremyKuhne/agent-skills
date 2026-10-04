// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace PowerShellToolchain.Tests;

/// <summary>
///  Tests active CI and full-CI Pester topology, equivalent command forms, and unrelated-workflow controls.
/// </summary>
[TestClass]
public sealed class WorkflowPolicyTests
{
    private static readonly ToolchainManifest Manifest = new(
        SchemaVersion: 1,
        TestMinimumVersion: "7.4",
        PesterCompatibilityMinimumVersion: "6.2.0",
        PesterExecutionVersion: "6.2.0");

    private const string ContinuousIntegration = """
        name: CI
        on:
          pull_request:
        jobs:
          scaffold-linux:
            runs-on: ubuntu-24.04-arm
            steps:
              - name: Install Pester
                shell: pwsh
                run: Install-Module Pester -RequiredVersion 6.2.0 -Force
              - name: Run isolated Pester shards
                shell: pwsh
                run: ./tests/Invoke-PesterShards.ps1 -Path ./tests
          scaffold-windows:
            runs-on: windows-latest
            steps:
              - name: Install Pester
                if: steps.windows-filesystem.outputs.affected == 'true'
                shell: pwsh
                run: Install-Module Pester -RequiredVersion 6.2.0 -Force
              - name: Run isolated Pester shards
                if: steps.windows-filesystem.outputs.affected == 'true'
                shell: pwsh
                run: |
                  $paths = @('tests/windows-acls', 'tests/dotnet-file-creation')
                  ./tests/Invoke-PesterShards.ps1 -Path $paths
        """;

    private const string FullContinuousIntegration = """
        name: Full CI
        on:
          workflow_dispatch:
          schedule:
            - cron: '23 7 * * 1'
        jobs:
          scaffold-windows:
            runs-on: windows-latest
            steps:
              - name: Install Pester
                shell: pwsh
                run: Install-Module Pester -RequiredVersion 6.2.0 -Force
              - name: Run isolated Pester shards
                shell: pwsh
                run: ./tests/Invoke-PesterShards.ps1 -Path ./tests
        """;

    /// <summary>
    ///  Provides equivalent plain, quoted, literal-block, and folded-block YAML command scalars.
    /// </summary>
    /// <value>
    ///  Rows containing a scalar-form name and CI YAML whose Linux Pester bootstrap and shard-runner
    ///  commands use that form.
    /// </value>
    public static IEnumerable<object[]> AcceptedScalarForms
    {
        get
        {
            string continuousIntegration = ContinuousIntegration.ReplaceLineEndings("\n");
            yield return ["plain", continuousIntegration];
            yield return ["single-quoted", WithLinuxRunScalars(
          "'Install-Module Pester -RequiredVersion 6.2.0 -Force'",
          "'./tests/Invoke-PesterShards.ps1 -Path ./tests'")];

            yield return ["double-quoted", WithLinuxRunScalars(
          "\"Install-Module Pester -RequiredVersion 6.2.0 -Force\"",
          "\"./tests/Invoke-PesterShards.ps1 -Path ./tests\"")];

            yield return ["literal", WithLinuxRunScalars(
          "|-\n          Install-Module Pester -RequiredVersion 6.2.0 -Force",
          "|-\n          ./tests/Invoke-PesterShards.ps1 -Path ./tests")];

            yield return ["folded", WithLinuxRunScalars(
          ">-\n          Install-Module Pester -RequiredVersion 6.2.0 -Force",
          ">-\n          ./tests/Invoke-PesterShards.ps1 -Path ./tests")];
        }
    }

    /// <summary>
    ///  Provides malformed YAML and mutations of required CI and full-CI jobs, host matrices, triggers,
    ///  Pester bootstraps, conditions, and shard-runner paths.
    /// </summary>
    /// <value>
    ///  Rows containing a case name and CI YAML, optionally followed by full-CI YAML; omitted full-CI
    ///  inputs use the accepted full-CI fixture.
    /// </value>
    public static IEnumerable<object[]> RejectedWorkflows
    {
        get
        {
            string continuousIntegration = ContinuousIntegration.ReplaceLineEndings("\n");
            string fullContinuousIntegration = FullContinuousIntegration.ReplaceLineEndings("\n");

            yield return ["malformed-yaml", continuousIntegration + "\n  broken: ["];
            yield return ["missing-trigger-mapping", continuousIntegration.Replace(
              "on:\n  pull_request:\n",
              "")];

            yield return ["null-trigger-mapping", continuousIntegration.Replace(
              "on:\n  pull_request:",
              "on: null")];

            yield return ["duplicate-job-key", continuousIntegration.Replace(
                "  scaffold-linux:",
                "  scaffold-linux: {}\n  scaffold-linux:")];

            yield return ["anchor-alias", continuousIntegration.Replace(
                "    runs-on: ubuntu-24.04-arm",
                "    runs-on: &host ubuntu-24.04-arm\n    container: *host")];

            yield return ["merge-key", continuousIntegration.Replace(
                "jobs:",
                "defaults: &defaults\n  timeout-minutes: 15\njobs:\n  <<: *defaults")];

            yield return ["missing-linux-job", continuousIntegration.Replace(
                "  scaffold-linux:",
                "  renamed-linux:")];

            yield return ["null-linux-job", continuousIntegration.Replace(
              "  scaffold-linux:\n    runs-on: ubuntu-24.04-arm",
              "  scaffold-linux: null\n  renamed-linux:\n    runs-on: ubuntu-24.04-arm")];

            yield return ["null-linux-steps", continuousIntegration.Replace(
              "    steps:\n      - name: Install Pester",
              "    steps: null\n    ignored-steps:\n      - name: Install Pester",
              StringComparison.Ordinal)];

            yield return ["wrong-linux-host", continuousIntegration.Replace(
                "runs-on: ubuntu-24.04-arm",
                "runs-on: ubuntu-latest")];

            yield return ["missing-linux-bootstrap", continuousIntegration.Replace(
                "run: Install-Module Pester -RequiredVersion 6.2.0 -Force",
                "run: Write-Host 'Pester is present'",
                StringComparison.Ordinal)];

            string movedBootstrap = ReplaceFirst(
                continuousIntegration,
                "run: Install-Module Pester -RequiredVersion 6.2.0 -Force",
                "run: __runner_placeholder__");

            movedBootstrap = ReplaceFirst(
                movedBootstrap,
                "run: ./tests/Invoke-PesterShards.ps1 -Path ./tests",
                "run: Install-Module Pester -RequiredVersion 6.2.0 -Force");

            yield return ["later-linux-bootstrap", movedBootstrap.Replace(
                "run: __runner_placeholder__",
                "run: ./tests/Invoke-PesterShards.ps1 -Path ./tests",
                StringComparison.Ordinal)];

            yield return ["conditional-linux-bootstrap", continuousIntegration.Replace(
              "run: Install-Module Pester -RequiredVersion 6.2.0 -Force",
              "run: if ($true) { Install-Module Pester -RequiredVersion 6.2.0 -Force }")];

            yield return ["wrong-bootstrap-shell", continuousIntegration.Replace(
                "shell: pwsh\n        run: Install-Module Pester",
                "shell: bash\n        run: Install-Module Pester",
                StringComparison.Ordinal)];

            yield return ["floating-bootstrap", continuousIntegration.Replace(
                "Install-Module Pester -RequiredVersion 6.2.0 -Force",
                "Install-Module Pester -Force")];

            yield return ["mismatched-bootstrap", continuousIntegration.Replace(
                "Install-Module Pester -RequiredVersion 6.2.0 -Force",
                "Install-Module Pester -RequiredVersion 6.1.0 -Force")];

            yield return ["dynamic-bootstrap", continuousIntegration.Replace(
                "Install-Module Pester -RequiredVersion 6.2.0 -Force",
                "Install-Module Pester -RequiredVersion $env:PESTER_VERSION -Force")];

            yield return ["duplicate-bootstrap", continuousIntegration.Replace(
                "run: Install-Module Pester -RequiredVersion 6.2.0 -Force",
                "run: |\n          Install-Module Pester -RequiredVersion 6.2.0 -Force\n          Install-Module Pester -RequiredVersion 6.2.0 -Force",
                StringComparison.Ordinal)];

            yield return ["extra-mismatched-bootstrap", continuousIntegration.Replace(
                "run: Install-Module Pester -RequiredVersion 6.2.0 -Force",
                "run: |\n          Install-Module Pester -RequiredVersion 6.2.0 -Force\n          Install-Module Pester -RequiredVersion 6.1.0 -Force",
                StringComparison.Ordinal)];

            yield return ["extra-mismatched-bootstrap-step", continuousIntegration.Replace(
                "      - name: Install Pester",
                "      - name: Install stale Pester\n        shell: pwsh\n        run: Install-Module Pester -RequiredVersion 6.1.0 -Force\n      - name: Install Pester",
                StringComparison.Ordinal)];

            yield return ["duplicate-required-version", continuousIntegration.Replace(
                "Install-Module Pester -RequiredVersion 6.2.0 -Force",
                "Install-Module Pester -RequiredVersion 6.2.0 -RequiredVersion 6.2.0 -Force")];

            yield return ["mixed-duplicate-required-version", continuousIntegration.Replace(
              "Install-Module Pester -RequiredVersion 6.2.0 -Force",
              "Install-Module Pester -RequiredVersion $version -RequiredVersion 6.2.0 -Force")];

            yield return ["extra-positional-module", continuousIntegration.Replace(
              "Install-Module Pester -RequiredVersion 6.2.0 -Force",
              "Install-Module Pester Other -RequiredVersion 6.2.0 -Force")];

            yield return ["wrong-runner-shell", continuousIntegration.Replace(
                "shell: pwsh\n        run: ./tests/Invoke-PesterShards.ps1",
                "shell: bash\n        run: ./tests/Invoke-PesterShards.ps1",
                StringComparison.Ordinal)];

            yield return ["missing-runner", continuousIntegration.Replace(
              "./tests/Invoke-PesterShards.ps1 -Path ./tests",
              "Write-Host 'Runner omitted'",
              StringComparison.Ordinal)];

            yield return ["wrong-linux-path", continuousIntegration.Replace(
            "./tests/Invoke-PesterShards.ps1 -Path ./tests",
            "./tests/Invoke-PesterShards.ps1 -Path ./skills",
            StringComparison.Ordinal)];

            yield return ["wildcard-linux-path", continuousIntegration.Replace(
            "./tests/Invoke-PesterShards.ps1 -Path ./tests",
            "./tests/Invoke-PesterShards.ps1 -Path ./tests/*",
            StringComparison.Ordinal)];

            yield return ["direct-pester", continuousIntegration.Replace(
            "./tests/Invoke-PesterShards.ps1 -Path ./tests",
            "Invoke-Pester -Path ./tests",
            StringComparison.Ordinal)];

            yield return ["unexpected-runner-job", continuousIntegration.Replace(
            "jobs:",
            "jobs:\n  unexpected:\n    runs-on: ubuntu-latest\n    steps:\n      - shell: pwsh\n        run: ./tests/Invoke-PesterShards.ps1 -Path ./tests")];

            yield return ["alternate-literal-runner", continuousIntegration.Replace(
            "./tests/Invoke-PesterShards.ps1 -Path ./tests",
            "tests/Invoke-PesterShards.ps1 -Path ./tests",
            StringComparison.Ordinal)];

            yield return ["missing-windows-condition", continuousIntegration.Replace(
            "        if: steps.windows-filesystem.outputs.affected == 'true'\n",
            "")];

            yield return ["mismatched-windows-condition", continuousIntegration.Replace(
            "if: steps.windows-filesystem.outputs.affected == 'true'",
            "if: steps.windows-filesystem.outputs.affected == 'false'")];

            yield return ["mismatched-bootstrap-condition", ReplaceFirst(
              continuousIntegration,
              "if: steps.windows-filesystem.outputs.affected == 'true'",
              "if: steps.windows-filesystem.outputs.affected == 'false'")];

            string runnerConditionMismatch = ReplaceFirst(
              continuousIntegration,
              "if: steps.windows-filesystem.outputs.affected == 'true'",
              "if: __bootstrap_condition__");

            runnerConditionMismatch = ReplaceFirst(
              runnerConditionMismatch,
              "if: steps.windows-filesystem.outputs.affected == 'true'",
              "if: steps.windows-filesystem.outputs.affected == 'false'");

            yield return ["mismatched-runner-condition", runnerConditionMismatch.Replace(
              "if: __bootstrap_condition__",
              "if: steps.windows-filesystem.outputs.affected == 'true'",
              StringComparison.Ordinal)];

            yield return ["missing-focused-path", continuousIntegration.Replace(
            "@('tests/windows-acls', 'tests/dotnet-file-creation')",
            "@('tests/windows-acls')")];

            yield return ["extra-focused-path", continuousIntegration.Replace(
            "@('tests/windows-acls', 'tests/dotnet-file-creation')",
            "@('tests/windows-acls', 'tests/dotnet-file-creation', 'tests/repository')")];

            yield return ["conditional-focused-runner", continuousIntegration.Replace(
              "./tests/Invoke-PesterShards.ps1 -Path $paths",
              "if ($true) { ./tests/Invoke-PesterShards.ps1 -Path $paths }")];

            yield return ["full-ci-missing-trigger", continuousIntegration, fullContinuousIntegration.Replace(
                "schedule:",
                "renamed-schedule:")];

            yield return ["full-ci-missing-dispatch", continuousIntegration, fullContinuousIntegration.Replace(
            "workflow_dispatch:",
            "renamed-dispatch:")];

            yield return ["full-ci-empty-schedule", continuousIntegration, fullContinuousIntegration.Replace(
            "  schedule:\n    - cron: '23 7 * * 1'",
            "  schedule:")];

            yield return ["full-ci-wrong-host", continuousIntegration, fullContinuousIntegration.Replace(
            "runs-on: windows-latest",
            "runs-on: ubuntu-latest")];

            yield return ["full-ci-focused-path", continuousIntegration, fullContinuousIntegration.Replace(
            "./tests/Invoke-PesterShards.ps1 -Path ./tests",
            "./tests/Invoke-PesterShards.ps1 -Path ./tests/windows-acls")];
        }
    }

    /// <summary>
    ///  Verifies that Linux ARM64 full-suite shards, conditional focused Windows shards, and
    ///  scheduled and manually dispatched full Windows CI are accepted.
    /// </summary>
    [TestMethod]
    public void ValidateActivePesterWorkflowsAcceptedTopologyPasses()
    {
        PowerShellToolchainPolicy.ValidateActivePesterWorkflows(
            ContinuousIntegration,
            FullContinuousIntegration,
            Manifest);
    }

    /// <summary>
    ///  Verifies that equivalent YAML scalar forms for the Linux bootstrap and shard-runner commands
    ///  preserve an accepted CI and full-CI topology.
    /// </summary>
    /// <param name="name">The descriptive label identifying the YAML scalar form.</param>
    /// <param name="continuousIntegration">The CI YAML using the selected Linux command scalar form.</param>
    [TestMethod]
    [DynamicData(nameof(AcceptedScalarForms))]
    public void ValidateActivePesterWorkflowsEquivalentScalarFormsPass(
        string name,
        string continuousIntegration)
    {
        _ = name;

        PowerShellToolchainPolicy.ValidateActivePesterWorkflows(
            continuousIntegration,
            FullContinuousIntegration,
            Manifest);
    }

    /// <summary>
    ///  Verifies that quoted module, version, and runner-path literals and a lowercase <c>-path</c>
    ///  parameter preserve an accepted workflow topology.
    /// </summary>
    [TestMethod]
    public void ValidateActivePesterWorkflowsEquivalentPowerShellSyntaxPasses()
    {
        string continuousIntegration = ContinuousIntegration
            .ReplaceLineEndings("\n")
            .Replace(
                "Install-Module Pester -RequiredVersion 6.2.0 -Force",
                "Install-Module 'Pester' -RequiredVersion '6.2.0' -Force")
            .Replace(
                "./tests/Invoke-PesterShards.ps1 -Path ./tests\n",
                "./tests/Invoke-PesterShards.ps1 -path './tests'\n",
                StringComparison.Ordinal);

        PowerShellToolchainPolicy.ValidateActivePesterWorkflows(
            continuousIntegration,
            FullContinuousIntegration,
            Manifest);
    }

    /// <summary>
    ///  Verifies that an unrelated reusable-workflow job does not invalidate the accepted CI topology.
    /// </summary>
    [TestMethod]
    public void ValidateActivePesterWorkflowsUnrelatedReusableJobPasses()
    {
        string continuousIntegration = ContinuousIntegration.Replace(
          "jobs:",
          "jobs:\n  delegated:\n    uses: example/repository/.github/workflows/reusable.yml@main");

        PowerShellToolchainPolicy.ValidateActivePesterWorkflows(
          continuousIntegration,
          FullContinuousIntegration,
          Manifest);
    }

    /// <summary>
    ///  Verifies that a YAML anchor and alias used by an unrelated job's environment do not invalidate
    ///  the accepted CI topology.
    /// </summary>
    [TestMethod]
    public void ValidateActivePesterWorkflowsUnrelatedAnchoredJobPasses()
    {
        string continuousIntegration = ContinuousIntegration.Replace(
          "jobs:",
          "env:\n  VALUE: &value accepted\njobs:\n  unrelated:\n    runs-on: ubuntu-latest\n    env:\n      VALUE: *value\n    steps:\n      - run: echo accepted");

        PowerShellToolchainPolicy.ValidateActivePesterWorkflows(
          continuousIntegration,
          FullContinuousIntegration,
          Manifest);
    }

    /// <summary>
    ///  Verifies that an unrelated anchored reusable workflow whose Pester references occur only in
    ///  a comment is accepted alongside the required workflows.
    /// </summary>
    [TestMethod]
    public void ValidateActivePesterWorkflowsUnrelatedAnchoredWorkflowPasses()
    {
        IReadOnlyDictionary<string, string> workflows = new Dictionary<string, string>(
            StringComparer.Ordinal)
        {
            [".github/workflows/ci.yml"] = ContinuousIntegration,
            [".github/workflows/full-ci.yml"] = FullContinuousIntegration,
            [".github/workflows/unrelated.yml"] = """
                name: Unrelated
                # Invoke-PesterShards.ps1 and Invoke-Pester are documentation here.
                on:
                  workflow_dispatch:
                env:
                  VALUE: &value accepted
                jobs:
                  delegated:
                    uses: example/repository/.github/workflows/reusable.yml@main
                    with:
                      value: *value
                """
        };

        PowerShellToolchainPolicy.ValidateActivePesterWorkflows(workflows, Manifest);
    }

    /// <summary>
    ///  Verifies that an additional workflow accepts an unrelated job's YAML anchor when a separate
    ///  Bash step mentions Pester only in output text.
    /// </summary>
    [TestMethod]
    public void ValidateActivePesterWorkflowsAdditionalCandidateWithUnrelatedAnchorPasses()
    {
        IReadOnlyDictionary<string, string> workflows = new Dictionary<string, string>(
            StringComparer.Ordinal)
        {
            [".github/workflows/ci.yml"] = ContinuousIntegration,
            [".github/workflows/full-ci.yml"] = FullContinuousIntegration,
            [".github/workflows/unrelated.yml"] = """
                name: Unrelated
                on:
                  workflow_dispatch:
                jobs:
                  anchored:
                    runs-on: ubuntu-latest
                    env:
                      VALUE: &value accepted
                    steps:
                      - run: echo *value
                  documentation:
                    runs-on: ubuntu-latest
                    steps:
                      - shell: bash
                        run: echo 'Invoke-Pester is documentation'
                """
        };

        PowerShellToolchainPolicy.ValidateActivePesterWorkflows(workflows, Manifest);
    }

    /// <summary>
    ///  Verifies that a PowerShell output string naming <c>Invoke-Pester</c> is not treated as a Pester call.
    /// </summary>
    [TestMethod]
    public void ValidateActivePesterWorkflowsUnrelatedRunStringPasses()
    {
        string continuousIntegration = ContinuousIntegration.Replace(
          "jobs:",
          "jobs:\n  unrelated:\n    runs-on: ubuntu-latest\n    steps:\n      - shell: pwsh\n        run: Write-Host 'Invoke-Pester is not called'");

        PowerShellToolchainPolicy.ValidateActivePesterWorkflows(
          continuousIntegration,
          FullContinuousIntegration,
          Manifest);
    }

    /// <summary>
    ///  Verifies that a Bash loop treating <c>Invoke-Pester</c> as data is not mistaken for a Pester call.
    /// </summary>
    [TestMethod]
    public void ValidateActivePesterWorkflowsUnrelatedBashScriptPasses()
    {
        string continuousIntegration = ContinuousIntegration.Replace(
            "jobs:",
            "jobs:\n  unrelated:\n    runs-on: ubuntu-latest\n    steps:\n      - shell: bash\n        run: |\n          for item in Invoke-Pester; do\n            echo \"$item\"\n          done");

        PowerShellToolchainPolicy.ValidateActivePesterWorkflows(
            continuousIntegration,
            FullContinuousIntegration,
            Manifest);
    }

    /// <summary>
    ///  Verifies that reusable-job input keys and values containing <c>Invoke-Pester</c> and <c>run</c>
    ///  are not treated as execution commands.
    /// </summary>
    [TestMethod]
    public void ValidateActivePesterWorkflowsUnrelatedScalarSequencePasses()
    {
        IReadOnlyDictionary<string, string> workflows = new Dictionary<string, string>(
            StringComparer.Ordinal)
        {
            [".github/workflows/ci.yml"] = ContinuousIntegration,
            [".github/workflows/full-ci.yml"] = FullContinuousIntegration,
            [".github/workflows/unrelated.yml"] = """
                name: Unrelated
                on:
                  workflow_dispatch:
                jobs:
                  delegated:
                    uses: example/repository/.github/workflows/reusable.yml@main
                    with:
                      mode: run
                      Invoke-Pester: documentation
                """
        };

        PowerShellToolchainPolicy.ValidateActivePesterWorkflows(workflows, Manifest);
    }

    /// <summary>
    ///  Verifies that an additional workflow invoking the canonical shard runner is rejected with
    ///  <see cref="ToolchainPolicyException"/>.
    /// </summary>
    [TestMethod]
    public void ValidateActivePesterWorkflowsUnexpectedRunnerWorkflowThrowsPolicyException()
    {
        IReadOnlyDictionary<string, string> workflows = new Dictionary<string, string>(
            StringComparer.Ordinal)
        {
            [".github/workflows/ci.yml"] = ContinuousIntegration,
            [".github/workflows/full-ci.yml"] = FullContinuousIntegration,
            [".github/workflows/unexpected.yml"] = """
                name: Unexpected
                on:
                  workflow_dispatch:
                jobs:
                  runner:
                    runs-on: ubuntu-latest
                    steps:
                      - shell: pwsh
                        run: ./tests/Invoke-PesterShards.ps1 -Path ./tests
                """
        };

        Assert.ThrowsExactly<ToolchainPolicyException>(() =>
            PowerShellToolchainPolicy.ValidateActivePesterWorkflows(workflows, Manifest));
    }

    /// <summary>
    ///  Verifies that inserting a CI job that directly invokes Pester is rejected with
    ///  <see cref="ToolchainPolicyException"/> even when the required jobs remain.
    /// </summary>
    [TestMethod]
    public void ValidateActivePesterWorkflowsDirectPesterInAdditionalOwnedJobThrowsPolicyException()
    {
        string continuousIntegration = ContinuousIntegration.Replace(
            "jobs:",
            "jobs:\n  direct-pester:\n    runs-on: ubuntu-latest\n    steps:\n      - shell: pwsh\n        run: Invoke-Pester -Path ./tests");

        Assert.ThrowsExactly<ToolchainPolicyException>(() =>
            PowerShellToolchainPolicy.ValidateActivePesterWorkflows(
                continuousIntegration,
                FullContinuousIntegration,
                Manifest));
    }

    /// <summary>
    ///  Verifies that each invalid CI or full-CI topology fixture is rejected with
    ///  <see cref="ToolchainPolicyException"/>.
    /// </summary>
    /// <param name="name">The descriptive label identifying the rejected topology fixture.</param>
    /// <param name="continuousIntegration">
    ///  The mutated CI YAML, or the accepted CI YAML when the mutation targets full CI.
    /// </param>
    /// <param name="fullContinuousIntegration">
    ///  The full-CI YAML to validate, or <see langword="null"/> to use the accepted full-CI fixture.
    /// </param>
    [TestMethod]
    [DynamicData(nameof(RejectedWorkflows))]
    public void ValidateActivePesterWorkflowsRejectedTopologyThrowsPolicyException(
        string name,
        string continuousIntegration,
        string? fullContinuousIntegration = null)
    {
        _ = name;

        Assert.ThrowsExactly<ToolchainPolicyException>(() =>
            PowerShellToolchainPolicy.ValidateActivePesterWorkflows(
                continuousIntegration,
                fullContinuousIntegration ?? FullContinuousIntegration,
                Manifest));
    }

    private static string ReplaceFirst(string value, string oldValue, string newValue)
    {
        int index = value.IndexOf(oldValue, StringComparison.Ordinal);
        if (index < 0)
        {
            throw new InvalidOperationException($"Fixture token not found: {oldValue}");
        }

        return value[..index] + newValue + value[(index + oldValue.Length)..];
    }

    private static string WithLinuxRunScalars(string installScalar, string runnerScalar)
    {
        string workflow = ContinuousIntegration.ReplaceLineEndings("\n");
        workflow = ReplaceFirst(
          workflow,
          "run: Install-Module Pester -RequiredVersion 6.2.0 -Force",
          $"run: {installScalar}");

        return ReplaceFirst(
          workflow,
          "run: ./tests/Invoke-PesterShards.ps1 -Path ./tests",
          $"run: {runnerScalar}");
    }
}