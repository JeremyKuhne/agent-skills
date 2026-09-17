using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace PowerShellToolchain.Tests;

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

    [TestMethod]
    public void ValidateGeneratedRunner_IdenticalBytes_Passes()
    {
        byte[] runner = [0x23, 0x20, 0x50, 0x65, 0x73, 0x74, 0x65, 0x72];

        PowerShellToolchainPolicy.ValidateGeneratedRunner(runner, runner.ToArray());
    }

    [TestMethod]
    public void ValidateGeneratedRunner_DivergentBytes_ThrowsPolicyException()
    {
        Assert.ThrowsExactly<ToolchainPolicyException>(() =>
            PowerShellToolchainPolicy.ValidateGeneratedRunner(
                [0x23, 0x20, 0x50, 0x65, 0x73, 0x74, 0x65, 0x72],
                [0x23, 0x20, 0x50, 0x65, 0x73, 0x74, 0x65, 0x64]));
    }

    [TestMethod]
    public void ValidateGeneratedTeamContinuousIntegration_AcceptedOutput_Passes()
    {
        PowerShellToolchainPolicy.ValidateGeneratedTeamContinuousIntegration(
            TeamWorkflows(),
            Manifest);
    }

    [TestMethod]
    public void ValidateGeneratedTeamContinuousIntegration_UnrelatedShapes_Pass()
    {
        Dictionary<string, string> workflows = TeamWorkflows();
        workflows[".github/workflows/skill-drift.yml"] = DriftWorkflow.Replace(
            "jobs:\n  report:\n    runs-on: ubuntu-latest".ReplaceLineEndings(),
            "jobs:\n  defaults: &defaults\n    runs-on: ubuntu-latest\n  empty:\n  report:\n    <<: *defaults".ReplaceLineEndings());

        PowerShellToolchainPolicy.ValidateGeneratedTeamContinuousIntegration(
            workflows,
            Manifest);
    }

    [TestMethod]
    public void ValidateGeneratedTeamContinuousIntegration_RenamedJobAndHost_Passes()
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

    [TestMethod]
    public void ValidateGeneratedTeamContinuousIntegration_RawTemplate_ThrowsPolicyException()
    {
        Dictionary<string, string> workflows = TeamWorkflows();
        workflows[".github/workflows/skills.yml.tmpl"] = workflows[".github/workflows/skills.yml"];
        workflows.Remove(".github/workflows/skills.yml");

        Assert.ThrowsExactly<ToolchainPolicyException>(() =>
            PowerShellToolchainPolicy.ValidateGeneratedTeamContinuousIntegration(
                workflows,
                Manifest));
    }

    [TestMethod]
    [DynamicData(nameof(RejectedTeamWorkflows))]
    public void ValidateGeneratedTeamContinuousIntegration_RejectedOutput_ThrowsPolicyException(
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

    [TestMethod]
    public void ValidateGeneratedTeamContinuousIntegration_AdditionalRunner_ThrowsPolicyException()
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

    [TestMethod]
    public void ValidateGeneratedDistributionWorkflows_AcceptedOutput_Passes()
    {
        Dictionary<string, string> workflows = TeamWorkflows();
        workflows[".github/workflows/release.yml"] = ReleaseWorkflow;

        PowerShellToolchainPolicy.ValidateGeneratedDistributionWorkflows(workflows, Manifest);
    }

    [TestMethod]
    public void ValidateGeneratedDistributionWorkflows_MissingRelease_ThrowsPolicyException()
    {
        Assert.ThrowsExactly<ToolchainPolicyException>(() =>
            PowerShellToolchainPolicy.ValidateGeneratedDistributionWorkflows(
                TeamWorkflows(),
                Manifest));
    }

    [TestMethod]
    public void ValidateGeneratedDistributionWorkflows_DirectPesterInRelease_ThrowsPolicyException()
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