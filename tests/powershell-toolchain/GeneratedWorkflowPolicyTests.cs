// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace PowerShellToolchain.Tests;

/// <summary>
///  Tests byte-for-byte shard-runner parity and generated team-CI and release-workflow policies.
/// </summary>
[TestClass]
public sealed class GeneratedWorkflowPolicyTests
{
    private static readonly ToolchainManifest Manifest = new(
        SchemaVersion: 1,
        TestMinimumVersion: "7.4",
        PesterCompatibilityMinimumVersion: "6.2.0",
        PesterExecutionVersion: "6.2.0");

    private const string SkillsWorkflow = """
        name: Skills validation
        on:
          pull_request:
        jobs:
          validate:
            runs-on: ubuntu-latest
            steps:
              - name: Install Pester
                shell: pwsh
                run: Install-Module Pester -RequiredVersion 6.2.0 -Force -Scope CurrentUser
              - name: Test repository contracts
                shell: pwsh
                run: ./tests/Invoke-PesterShards.ps1 -Path ./tests
        """;

    private const string ReleaseWorkflow = """
        name: Release validation
        on:
          workflow_dispatch:
        jobs:
          validate:
            runs-on: ubuntu-latest
            steps:
              - name: Install Pester
                shell: pwsh
                run: Install-Module Pester -RequiredVersion 6.2.0 -Force -Scope CurrentUser
              - name: Test release contracts
                shell: pwsh
                run: ./tests/Invoke-PesterShards.ps1 -Path ./tests
        """;

    private const string DriftWorkflow = """
        name: Skill provenance drift
        on:
          workflow_dispatch:
        jobs:
          report:
            runs-on: ubuntu-latest
            steps:
              - name: Report available skill updates
                shell: pwsh
                run: gh skill update --all --dry-run
                env:
                  GH_TOKEN: ${{ github.token }}
        """;

    /// <summary>
    ///  Provides skills-workflow mutations that must fail generated team-CI validation.
    /// </summary>
    /// <value>
    ///  Rows containing a mutation name and skills-workflow YAML with an unresolved token, an invalid
    ///  Pester bootstrap, a direct Pester call, or an incorrect shard-runner path or shell.
    /// </value>
    public static IEnumerable<object[]> RejectedTeamWorkflows
    {
        get
        {
            string skillsWorkflow = SkillsWorkflow.ReplaceLineEndings("\n");
            yield return ["unresolved-token", skillsWorkflow.Replace(
                "name: Skills validation",
                "name: '{{UNRESOLVED_NAME}}'")];

            yield return ["floating-bootstrap", skillsWorkflow.Replace(
                "Install-Module Pester -RequiredVersion 6.2.0 -Force",
                "Install-Module Pester -Force")];

            string laterBootstrap = skillsWorkflow.Replace(
                "run: Install-Module Pester -RequiredVersion 6.2.0 -Force -Scope CurrentUser",
                "run: __runner_placeholder__",
                StringComparison.Ordinal).Replace(
                "run: ./tests/Invoke-PesterShards.ps1 -Path ./tests",
                "run: Install-Module Pester -RequiredVersion 6.2.0 -Force -Scope CurrentUser",
                StringComparison.Ordinal).Replace(
                "run: __runner_placeholder__",
                "run: ./tests/Invoke-PesterShards.ps1 -Path ./tests",
                StringComparison.Ordinal);

            yield return ["later-bootstrap", laterBootstrap];
            yield return ["direct-pester", skillsWorkflow.Replace(
                "./tests/Invoke-PesterShards.ps1 -Path ./tests",
                "Invoke-Pester -Path ./tests")];

            yield return ["wrong-runner-path", skillsWorkflow.Replace(
                "./tests/Invoke-PesterShards.ps1 -Path ./tests",
                "./tests/Invoke-PesterShards.ps1 -Path ./skills")];

            yield return ["wrong-runner-shell", skillsWorkflow.Replace(
                "shell: pwsh\n        run: ./tests/Invoke-PesterShards.ps1",
                "shell: bash\n        run: ./tests/Invoke-PesterShards.ps1")];
        }
    }

    /// <summary>
    ///  Verifies that a generated runner with bytes identical to the canonical runner is accepted.
    /// </summary>
    [TestMethod]
    public void ValidateGeneratedRunnerIdenticalBytesPasses()
    {
        byte[] runner = [0x23, 0x20, 0x50, 0x65, 0x73, 0x74, 0x65, 0x72];

        PowerShellToolchainPolicy.ValidateGeneratedRunner(runner, runner.ToArray());
    }

    /// <summary>
    ///  Verifies that changing one generated-runner byte is rejected with
    ///  <see cref="ToolchainPolicyException"/>.
    /// </summary>
    [TestMethod]
    public void ValidateGeneratedRunnerDivergentBytesThrowsPolicyException()
    {
        Assert.ThrowsExactly<ToolchainPolicyException>(() =>
            PowerShellToolchainPolicy.ValidateGeneratedRunner(
                [0x23, 0x20, 0x50, 0x65, 0x73, 0x74, 0x65, 0x72],
                [0x23, 0x20, 0x50, 0x65, 0x73, 0x74, 0x65, 0x64]));
    }

    /// <summary>
    ///  Verifies that skills validation with the pinned Pester bootstrap and shard runner is accepted
    ///  alongside the skill-drift reporting workflow.
    /// </summary>
    [TestMethod]
    public void ValidateGeneratedTeamContinuousIntegrationAcceptedOutputPasses()
    {
        PowerShellToolchainPolicy.ValidateGeneratedTeamContinuousIntegration(
            TeamWorkflows(),
            Manifest);
    }

    /// <summary>
    ///  Verifies that an anchor, merge key, and null job in the unrelated drift workflow are accepted.
    /// </summary>
    [TestMethod]
    public void ValidateGeneratedTeamContinuousIntegrationUnrelatedShapesPass()
    {
        Dictionary<string, string> workflows = TeamWorkflows();
        workflows[".github/workflows/skill-drift.yml"] = DriftWorkflow.Replace(
            "jobs:\n  report:\n    runs-on: ubuntu-latest".ReplaceLineEndings(),
            "jobs:\n  defaults: &defaults\n    runs-on: ubuntu-latest\n  empty:\n  report:\n    <<: *defaults".ReplaceLineEndings());

        PowerShellToolchainPolicy.ValidateGeneratedTeamContinuousIntegration(
            workflows,
            Manifest);
    }

    /// <summary>
    ///  Verifies that the generated skills-validation job may be renamed and use a Windows host.
    /// </summary>
    [TestMethod]
    public void ValidateGeneratedTeamContinuousIntegrationRenamedJobAndHostPasses()
    {
        Dictionary<string, string> workflows = TeamWorkflows();
        workflows[".github/workflows/skills.yml"] = SkillsWorkflow.Replace(
            "  validate:",
            "  contracts:").Replace(
            "runs-on: ubuntu-latest",
            "runs-on: windows-latest");

        PowerShellToolchainPolicy.ValidateGeneratedTeamContinuousIntegration(
            workflows,
            Manifest);
    }

    /// <summary>
    ///  Verifies that supplying a template-suffixed path instead of the generated skills-workflow path
    ///  is rejected with <see cref="ToolchainPolicyException"/>.
    /// </summary>
    [TestMethod]
    public void ValidateGeneratedTeamContinuousIntegrationRawTemplateThrowsPolicyException()
    {
        Dictionary<string, string> workflows = TeamWorkflows();
        workflows[".github/workflows/skills.yml.tmpl"] = workflows[".github/workflows/skills.yml"];
        workflows.Remove(".github/workflows/skills.yml");

        Assert.ThrowsExactly<ToolchainPolicyException>(() =>
            PowerShellToolchainPolicy.ValidateGeneratedTeamContinuousIntegration(
                workflows,
                Manifest));
    }

    /// <summary>
    ///  Verifies that each rejected skills-workflow mutation changes the fixture and fails team-CI
    ///  validation with <see cref="ToolchainPolicyException"/>.
    /// </summary>
    /// <param name="name">The mutation name used in the fixture-change and rejection assertions.</param>
    /// <param name="skillsWorkflow">The mutated skills-workflow YAML paired with the drift fixture.</param>
    [TestMethod]
    [DynamicData(nameof(RejectedTeamWorkflows))]
    public void ValidateGeneratedTeamContinuousIntegrationRejectedOutputThrowsPolicyException(
        string name,
        string skillsWorkflow)
    {
        Dictionary<string, string> workflows = TeamWorkflows();
        workflows[".github/workflows/skills.yml"] = skillsWorkflow;

        Assert.AreNotEqual(
            SkillsWorkflow.ReplaceLineEndings("\n"),
            skillsWorkflow,
            $"Mutation '{name}' must change the fixture.");

        Assert.ThrowsExactly<ToolchainPolicyException>(() =>
            PowerShellToolchainPolicy.ValidateGeneratedTeamContinuousIntegration(
                workflows,
                Manifest),
            name);
    }

    /// <summary>
    ///  Verifies that adding a shard-runner invocation changes the drift fixture and is rejected with
    ///  <see cref="ToolchainPolicyException"/>.
    /// </summary>
    [TestMethod]
    public void ValidateGeneratedTeamContinuousIntegrationAdditionalRunnerThrowsPolicyException()
    {
        Dictionary<string, string> workflows = TeamWorkflows();
        string mutatedDrift = DriftWorkflow.Replace(
            "gh skill update --all --dry-run",
            "./tests/Invoke-PesterShards.ps1 -Path ./tests");

        Assert.AreNotEqual(DriftWorkflow, mutatedDrift);
        workflows[".github/workflows/skill-drift.yml"] = mutatedDrift;

        Assert.ThrowsExactly<ToolchainPolicyException>(() =>
            PowerShellToolchainPolicy.ValidateGeneratedTeamContinuousIntegration(
                workflows,
                Manifest));
    }

    /// <summary>
    ///  Verifies that the team workflows plus a release workflow with the pinned Pester bootstrap
    ///  and isolated shard runner satisfy generated distribution policy.
    /// </summary>
    [TestMethod]
    public void ValidateGeneratedDistributionWorkflowsAcceptedOutputPasses()
    {
        Dictionary<string, string> workflows = TeamWorkflows();
        workflows[".github/workflows/release.yml"] = ReleaseWorkflow;

        PowerShellToolchainPolicy.ValidateGeneratedDistributionWorkflows(workflows, Manifest);
    }

    /// <summary>
    ///  Verifies that team workflows without the required release workflow are rejected with
    ///  <see cref="ToolchainPolicyException"/>.
    /// </summary>
    [TestMethod]
    public void ValidateGeneratedDistributionWorkflowsMissingReleaseThrowsPolicyException()
    {
        Assert.ThrowsExactly<ToolchainPolicyException>(() =>
            PowerShellToolchainPolicy.ValidateGeneratedDistributionWorkflows(
                TeamWorkflows(),
                Manifest));
    }

    /// <summary>
    ///  Verifies that replacing the release shard runner with a direct Pester call changes the fixture
    ///  and is rejected with <see cref="ToolchainPolicyException"/>.
    /// </summary>
    [TestMethod]
    public void ValidateGeneratedDistributionWorkflowsDirectPesterInReleaseThrowsPolicyException()
    {
        Dictionary<string, string> workflows = TeamWorkflows();
        string mutatedRelease = ReleaseWorkflow.Replace(
            "./tests/Invoke-PesterShards.ps1 -Path ./tests",
            "Invoke-Pester -Path ./tests");

        Assert.AreNotEqual(ReleaseWorkflow, mutatedRelease);
        workflows[".github/workflows/release.yml"] = mutatedRelease;

        Assert.ThrowsExactly<ToolchainPolicyException>(() =>
            PowerShellToolchainPolicy.ValidateGeneratedDistributionWorkflows(
                workflows,
                Manifest));
    }

    private static Dictionary<string, string> TeamWorkflows()
    {
        return new Dictionary<string, string>(StringComparer.Ordinal)
        {
            [".github/workflows/skills.yml"] = SkillsWorkflow,
            [".github/workflows/skill-drift.yml"] = DriftWorkflow
        };
    }
}