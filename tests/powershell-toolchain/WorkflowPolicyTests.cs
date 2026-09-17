using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace PowerShellToolchain.Tests;

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

    public static IEnumerable<object[]> RejectedWorkflows
    {
        get
        {
            string continuousIntegration = ContinuousIntegration.ReplaceLineEndings("\n");
            string fullContinuousIntegration = FullContinuousIntegration.ReplaceLineEndings("\n");

            yield return ["malformed-yaml", continuousIntegration + "\n  broken: ["];
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

    [TestMethod]
    public void ValidateActivePesterWorkflows_AcceptedTopology_Passes()
    {
        PowerShellToolchainPolicy.ValidateActivePesterWorkflows(
            ContinuousIntegration,
            FullContinuousIntegration,
            Manifest);
    }

    [TestMethod]
    [DynamicData(nameof(AcceptedScalarForms))]
    public void ValidateActivePesterWorkflows_EquivalentScalarForms_Pass(
        string name,
        string continuousIntegration)
    {
        _ = name;

        PowerShellToolchainPolicy.ValidateActivePesterWorkflows(
            continuousIntegration,
            FullContinuousIntegration,
            Manifest);
    }

    [TestMethod]
    public void ValidateActivePesterWorkflows_EquivalentPowerShellSyntax_Passes()
    {
        string continuousIntegration = ContinuousIntegration
            .Replace(
                "Install-Module Pester -RequiredVersion 6.2.0 -Force",
                "Install-Module 'Pester' -RequiredVersion '6.2.0' -Force")
            .Replace(
                "./tests/Invoke-PesterShards.ps1 -Path ./tests",
                "./tests/Invoke-PesterShards.ps1 -path './tests'",
                StringComparison.Ordinal);

        PowerShellToolchainPolicy.ValidateActivePesterWorkflows(
            continuousIntegration,
            FullContinuousIntegration,
            Manifest);
    }

    [TestMethod]
    public void ValidateActivePesterWorkflows_UnrelatedReusableJob_Passes()
    {
        string continuousIntegration = ContinuousIntegration.Replace(
          "jobs:",
          "jobs:\n  delegated:\n    uses: example/repository/.github/workflows/reusable.yml@main");

        PowerShellToolchainPolicy.ValidateActivePesterWorkflows(
          continuousIntegration,
          FullContinuousIntegration,
          Manifest);
    }

    [TestMethod]
    public void ValidateActivePesterWorkflows_UnrelatedAnchoredJob_Passes()
    {
        string continuousIntegration = ContinuousIntegration.Replace(
          "jobs:",
          "env:\n  VALUE: &value accepted\njobs:\n  unrelated:\n    runs-on: ubuntu-latest\n    env:\n      VALUE: *value\n    steps:\n      - run: echo accepted");

        PowerShellToolchainPolicy.ValidateActivePesterWorkflows(
          continuousIntegration,
          FullContinuousIntegration,
          Manifest);
    }

    [TestMethod]
    public void ValidateActivePesterWorkflows_UnrelatedAnchoredWorkflow_Passes()
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

    [TestMethod]
    public void ValidateActivePesterWorkflows_UnrelatedRunString_Passes()
    {
        string continuousIntegration = ContinuousIntegration.Replace(
          "jobs:",
          "jobs:\n  unrelated:\n    runs-on: ubuntu-latest\n    steps:\n      - shell: pwsh\n        run: Write-Host 'Invoke-Pester is not called'");

        PowerShellToolchainPolicy.ValidateActivePesterWorkflows(
          continuousIntegration,
          FullContinuousIntegration,
          Manifest);
    }

    [TestMethod]
    public void ValidateActivePesterWorkflows_UnrelatedBashScript_Passes()
    {
        string continuousIntegration = ContinuousIntegration.Replace(
            "jobs:",
            "jobs:\n  unrelated:\n    runs-on: ubuntu-latest\n    steps:\n      - shell: bash\n        run: |\n          for item in Invoke-Pester; do\n            echo \"$item\"\n          done");

        PowerShellToolchainPolicy.ValidateActivePesterWorkflows(
            continuousIntegration,
            FullContinuousIntegration,
            Manifest);
    }

    [TestMethod]
    public void ValidateActivePesterWorkflows_UnrelatedScalarSequence_Passes()
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

    [TestMethod]
    public void ValidateActivePesterWorkflows_UnexpectedRunnerWorkflow_ThrowsPolicyException()
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

    [TestMethod]
    [DynamicData(nameof(RejectedWorkflows))]
    public void ValidateActivePesterWorkflows_RejectedTopology_ThrowsPolicyException(
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