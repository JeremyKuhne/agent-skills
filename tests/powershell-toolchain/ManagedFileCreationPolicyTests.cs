using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace PowerShellToolchain.Tests;

[TestClass]
public sealed class ManagedFileCreationPolicyTests
{
    private const string Workflow = """
        on:
          pull_request:
        jobs:
          dotnet-file-creation:
            runs-on: '${{ matrix.os }}'
            strategy:
              matrix:
                include:
                  - os: ubuntu-24.04-arm
                    coverage: false
                  - os: windows-latest
                    coverage: true
            steps:
              - name: Run tests
                if: matrix.coverage == false
                shell: pwsh
                run: >-
                  dotnet test
                  --project ./tests/dotnet-file-creation/DotNetFileCreation.Tests.csproj
                  --configuration Release
              - name: Run tests with coverage
                if: matrix.coverage == true
                shell: pwsh
                run: |
                  $coveragePath = Join-Path $env:RUNNER_TEMP 'coverage.xml'
                  dotnet test `
                    --project ./tests/dotnet-file-creation/DotNetFileCreation.Tests.csproj `
                    --configuration Release `
                    --coverage `
                    --coverage-settings ./tests/dotnet-file-creation/coverage.config.xml `
                    --coverage-output $coveragePath `
                    --coverage-output-format cobertura
                  Write-Host 'Report inspection remains a hosted runtime check.'
        """;

    private const string CoverageSettings = """
        <?xml version="1.0" encoding="utf-8"?>
        <Configuration>
          <CodeCoverage>
            <Sources>
              <Include>
                <Source>.*[\\/]skills[\\/]dotnet-file-creation[\\/]assets[\\/]TrustedFileWrites\.cs$</Source>
              </Include>
            </Sources>
          </CodeCoverage>
        </Configuration>
        """;

    private const string CoverageReport = """
        <?xml version="1.0" encoding="utf-8"?>
        <coverage>
          <packages>
            <package>
              <classes>
                <class name="TrustedFileWrites" filename="C:\repo\skills\dotnet-file-creation\assets\TrustedFileWrites.cs">
                  <lines>
                    <line number="1" hits="1" />
                  </lines>
                </class>
              </classes>
            </package>
          </packages>
        </coverage>
        """;

    public static IEnumerable<object[]> RejectedWorkflows
    {
        get
        {
            string workflow = Workflow.ReplaceLineEndings("\n");
            yield return ["missing-job", workflow.Replace(
                "dotnet-file-creation:",
                "renamed-file-creation:")];
            yield return ["wrong-matrix-host", workflow.Replace(
                "runs-on: '${{ matrix.os }}'",
                "runs-on: windows-latest")];
            yield return ["missing-os", workflow.Replace(
                "os: ubuntu-24.04-arm",
                "omitted: ubuntu-24.04-arm")];
            yield return ["missing-coverage", workflow.Replace(
                "coverage: false",
                "omitted: false")];
            yield return ["null-coverage", workflow.Replace(
                "coverage: false",
                "coverage: null")];
            yield return ["string-coverage", workflow.Replace(
                "coverage: false",
                "coverage: 'false'")];
            yield return ["numeric-coverage", workflow.Replace(
                "coverage: false",
                "coverage: 0")];
            yield return ["duplicate-coverage", workflow.Replace(
                "coverage: false",
                "coverage: false\n        coverage: true")];
            yield return ["duplicate-host", workflow.Replace(
                "os: windows-latest",
                "os: ubuntu-24.04-arm")];
            yield return ["missing-host-row", workflow.Replace(
                "          - os: windows-latest\n            coverage: true\n",
                string.Empty)];
            yield return ["extra-row", workflow.Replace(
                "          - os: windows-latest\n            coverage: true",
                "          - os: windows-latest\n            coverage: true\n          - os: macos-latest\n            coverage: false")];
            yield return ["extra-matrix-key", workflow.Replace(
                "coverage: false",
                "coverage: false\n        architecture: arm64")];
            yield return ["both-conditions-false", workflow.Replace(
                "if: matrix.coverage == true",
                "if: matrix.coverage == false")];
            yield return ["both-conditions-true", workflow.Replace(
                "if: matrix.coverage == false",
                "if: matrix.coverage == true")];
            yield return ["missing-condition", workflow.Replace(
                "        if: matrix.coverage == false\n",
                string.Empty)];
            yield return ["swapped-conditions", workflow
                .Replace("matrix.coverage == false", "matrix.__swap__ == false")
                .Replace("matrix.coverage == true", "matrix.coverage == false")
                .Replace("matrix.__swap__ == false", "matrix.coverage == true")];
            yield return ["missing-shell", workflow.Replace(
                "        shell: pwsh\n        run: >-",
                "        run: >-")];
            yield return ["wrong-shell", workflow.Replace(
                "shell: pwsh",
                "shell: bash")];
            yield return ["wrong-project", workflow.Replace(
                "./tests/dotnet-file-creation/DotNetFileCreation.Tests.csproj",
                "./tests/dotnet-pipes/DotNetPipes.Tests.csproj")];
            yield return ["debug-configuration", workflow.Replace(
                "--configuration Release",
                "--configuration Debug")];
            yield return ["pester-wrapper", ReplaceFirst(
                workflow,
                "dotnet test",
                "Invoke-Pester ./tests/dotnet-file-creation")];
            yield return ["missing-coverage-settings", workflow.Replace(
                "    --coverage-settings ./tests/dotnet-file-creation/coverage.config.xml `\n",
                string.Empty)];
            yield return ["wrong-coverage-settings", workflow.Replace(
                "./tests/dotnet-file-creation/coverage.config.xml",
                "./tests/coverage.config.xml")];
            yield return ["wrong-output-format", workflow.Replace(
                "--coverage-output-format cobertura",
                "--coverage-output-format xml")];
            yield return ["additional-pester", workflow.Replace(
                "          Write-Host 'Report inspection remains a hosted runtime check.'",
                "          Invoke-Pester ./tests/dotnet-file-creation\n          Write-Host 'Report inspection remains a hosted runtime check.'")];
        }
    }

    public static IEnumerable<object[]> RejectedCoverageReports
    {
        get
        {
            yield return ["empty", "<coverage />"];
            yield return ["wrong-source", CoverageReport.Replace(
                "skills\\dotnet-file-creation\\assets\\TrustedFileWrites.cs",
                "tests\\dotnet-file-creation\\TrustedFileWritesTests.cs")];
            yield return ["no-covered-lines", CoverageReport.Replace("hits=\"1\"", "hits=\"0\"")];
            yield return ["malformed", "<coverage>"];
        }
    }

    [TestMethod]
    public void ValidateManagedFileCreationWorkflow_AcceptedPolicy_Passes()
    {
        PowerShellToolchainPolicy.ValidateManagedFileCreationWorkflow(
            Workflow,
            CoverageSettings);
    }

    [TestMethod]
    public void ValidateManagedFileCreationWorkflow_UnrelatedConditionalStep_Passes()
    {
        string workflow = Workflow.Replace(
            "      - name: Run tests",
            "      - name: Prepare Linux test environment\n        if: matrix.coverage == false\n        shell: pwsh\n        run: |\n          # dotnet test in a comment is not a command.\n          Write-Host 'dotnet test is handled elsewhere'\n      - name: Run tests".ReplaceLineEndings());
        Assert.AreNotEqual(Workflow, workflow);

        PowerShellToolchainPolicy.ValidateManagedFileCreationWorkflow(
            workflow,
            CoverageSettings);
    }

    [TestMethod]
    [DynamicData(nameof(RejectedWorkflows))]
    public void ValidateManagedFileCreationWorkflow_RejectedMutation_ThrowsPolicyException(
        string name,
        string workflow)
    {
        Assert.AreNotEqual(Workflow.ReplaceLineEndings("\n"), workflow, name);
        Assert.ThrowsExactly<ToolchainPolicyException>(() =>
            PowerShellToolchainPolicy.ValidateManagedFileCreationWorkflow(
                workflow,
                CoverageSettings),
            name);
    }

    [TestMethod]
    public void ValidateManagedFileCreationWorkflow_WrongCoverageSource_ThrowsPolicyException()
    {
        string settings = CoverageSettings.Replace(
            "skills[\\\\/]dotnet-file-creation[\\\\/]assets[\\\\/]TrustedFileWrites\\.cs",
            "tests[\\\\/]dotnet-file-creation[\\\\/]TrustedFileWritesTests\\.cs");
        Assert.AreNotEqual(CoverageSettings, settings);

        Assert.ThrowsExactly<ToolchainPolicyException>(() =>
            PowerShellToolchainPolicy.ValidateManagedFileCreationWorkflow(
                Workflow,
                settings));
    }

    [TestMethod]
    public void ValidateManagedFileCreationWorkflow_MalformedCoverageSettings_ThrowsPolicyException()
    {
        Assert.ThrowsExactly<ToolchainPolicyException>(() =>
            PowerShellToolchainPolicy.ValidateManagedFileCreationWorkflow(
                Workflow,
                "<Configuration>"));
    }

    [TestMethod]
    public void ValidateManagedFileCreationCoverageReport_AcceptedReport_Passes()
    {
        PowerShellToolchainPolicy.ValidateManagedFileCreationCoverageReport(CoverageReport);
    }

    [TestMethod]
    [DynamicData(nameof(RejectedCoverageReports))]
    public void ValidateManagedFileCreationCoverageReport_RejectedReport_ThrowsPolicyException(
        string name,
        string report)
    {
        Assert.AreNotEqual(CoverageReport, report, name);
        Assert.ThrowsExactly<ToolchainPolicyException>(() =>
            PowerShellToolchainPolicy.ValidateManagedFileCreationCoverageReport(report),
            name);
    }

    private static string ReplaceFirst(string value, string oldValue, string newValue)
    {
        int index = value.IndexOf(oldValue, StringComparison.Ordinal);
        Assert.IsGreaterThanOrEqualTo(0, index, $"Fixture is missing '{oldValue}'.");
        return string.Concat(value.AsSpan(0, index), newValue, value.AsSpan(index + oldValue.Length));
    }
}
