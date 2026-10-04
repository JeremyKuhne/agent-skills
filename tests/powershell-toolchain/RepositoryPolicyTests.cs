// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Diagnostics;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace PowerShellToolchain.Tests;

/// <summary>
///  Tests repository and scaffolded test-toolchain metadata, managed compiler policies, and workflow
///  execution policies.
/// </summary>
[TestClass]
public sealed partial class RepositoryPolicyTests
{
    private static readonly string RepositoryRoot = FindRepositoryRoot();
    private static readonly string[] GeneratedTestFileNames =
    [
        "Agents.Tests.ps1",
        "EvaluationScenarios.Tests.ps1",
        "Marketplace.Tests.ps1",
        "Mcp.Tests.ps1",
        "Plugin.Tests.ps1",
        "Repository.Tests.ps1"
    ];

    /// <summary>
    ///  Verifies that the checked-in manifest parses as schema 1, PowerShell 7.4, and Pester
    ///  compatibility and execution versions 6.2.0.
    /// </summary>
    [TestMethod]
    public void CheckedInManifestAcceptedShapeReturnsTypedPolicy()
    {
        ToolchainManifest manifest = LoadManifest();

        Assert.AreEqual(1, manifest.SchemaVersion);
        Assert.AreEqual("7.4", manifest.TestMinimumVersion);
        Assert.AreEqual("6.2.0", manifest.PesterCompatibilityMinimumVersion);
        Assert.AreEqual("6.2.0", manifest.PesterExecutionVersion);
    }

    /// <summary>
    ///  Verifies that exactly 17 Pester test files are discovered beneath the repository test directory
    ///  and that each file's requirements match the checked-in manifest.
    /// </summary>
    [TestMethod]
    public void TrackedPesterTestsAcceptedRequirementsPass()
    {
        ToolchainManifest manifest = LoadManifest();
        string[] testFiles = Directory.GetFiles(
            Path.Join(RepositoryRoot, "tests"),
            "*.Tests.ps1",
            SearchOption.AllDirectories);

        Assert.HasCount(17, testFiles);
        foreach (string testFile in testFiles)
        {
            PowerShellToolchainPolicy.ValidateTestRequirements(
                File.ReadAllText(testFile),
                manifest);
        }
    }

    /// <summary>
    ///  Verifies that the distribution scaffold emits exactly the six expected top-level Pester test
    ///  files and that their requirements match the repository manifest.
    /// </summary>
    [TestMethod]
    public void GeneratedPesterTestsAcceptedRequirementsPass()
    {
        ToolchainManifest manifest = LoadManifest();
        string temporaryRoot = Path.Join(
            Path.GetTempPath(),
            $"agent-skills-toolchain-{Guid.NewGuid():N}");

        string generatedRoot = Path.Join(temporaryRoot, "generated");

        try
        {
            Directory.CreateDirectory(temporaryRoot);
            ScaffoldRepository(generatedRoot, "distribution");

            string[] testFiles = Directory.GetFiles(
                Path.Join(generatedRoot, "tests"),
                "*.Tests.ps1",
                SearchOption.TopDirectoryOnly);

            string[] fileNames = testFiles
                .Select(path => Path.GetFileName(path)
                    ?? throw new InvalidOperationException("A generated test path must have a file name."))
                .Order(StringComparer.Ordinal)
                .ToArray();

            CollectionAssert.AreEqual(
                GeneratedTestFileNames,
                fileNames);

            foreach (string testFile in testFiles)
            {
                PowerShellToolchainPolicy.ValidateTestRequirements(
                    File.ReadAllText(testFile),
                    manifest);
            }
        }
        finally
        {
            if (Directory.Exists(temporaryRoot))
            {
                Directory.Delete(temporaryRoot, recursive: true);
            }
        }
    }

    /// <summary>
    ///  Scaffolds validated, team-CI, and distribution repositories and verifies byte-for-byte runner
    ///  parity plus the applicable generated-workflow policies.
    /// </summary>
    [TestMethod]
    public void GeneratedPesterExecutionAcceptedOutputsPass()
    {
        ToolchainManifest manifest = LoadManifest();
        byte[] canonicalRunner = File.ReadAllBytes(
            Path.Join(RepositoryRoot, "tests", "Invoke-PesterShards.ps1"));

        string temporaryRoot = Path.Join(
            Path.GetTempPath(),
            $"agent-skills-generated-execution-{Guid.NewGuid():N}");

        try
        {
            Directory.CreateDirectory(temporaryRoot);
            foreach (string infrastructure in new[] { "validated", "team-ci", "distribution" })
            {
                string generatedRoot = Path.Join(temporaryRoot, infrastructure);
                ScaffoldRepository(generatedRoot, infrastructure);
                PowerShellToolchainPolicy.ValidateGeneratedRunner(
                    canonicalRunner,
                    File.ReadAllBytes(Path.Join(
                        generatedRoot,
                        "tests",
                        "Invoke-PesterShards.ps1")));

                if (string.Equals(infrastructure, "team-ci", StringComparison.Ordinal))
                {
                    PowerShellToolchainPolicy.ValidateGeneratedTeamContinuousIntegration(
                        ReadGeneratedWorkflows(generatedRoot),
                        manifest);
                }
                else if (string.Equals(
                    infrastructure,
                    "distribution",
                    StringComparison.Ordinal))
                {
                    PowerShellToolchainPolicy.ValidateGeneratedDistributionWorkflows(
                        ReadGeneratedWorkflows(generatedRoot),
                        manifest);
                }
            }
        }
        finally
        {
            if (Directory.Exists(temporaryRoot))
            {
                Directory.Delete(temporaryRoot, recursive: true);
            }
        }
    }

    /// <summary>
    ///  Verifies that the canonical shard runner's host requirement and Pester-version default match
    ///  the checked-in manifest.
    /// </summary>
    [TestMethod]
    public void CanonicalRunnerAcceptedMetadataPasses()
    {
        ToolchainManifest manifest = LoadManifest();
        string runnerPath = Path.Join(RepositoryRoot, "tests", "Invoke-PesterShards.ps1");

        PowerShellToolchainPolicy.ValidateRunnerMetadata(
            File.ReadAllText(runnerPath),
            manifest);
    }

    /// <summary>
    ///  Verifies that the checked-in YAML workflows satisfy active Pester host, bootstrap, runner,
    ///  and path policies.
    /// </summary>
    [TestMethod]
    public void ActivePesterWorkflowsAcceptedTopologyPasses()
    {
        ToolchainManifest manifest = LoadManifest();
        string workflowRoot = Path.Join(RepositoryRoot, ".github", "workflows");
        IReadOnlyDictionary<string, string> workflows = Directory
            .GetFiles(workflowRoot, "*.*", SearchOption.TopDirectoryOnly)
            .Where(path => path.EndsWith(".yml", StringComparison.OrdinalIgnoreCase)
                || path.EndsWith(".yaml", StringComparison.OrdinalIgnoreCase))
            .ToDictionary(
                path => Path.GetRelativePath(RepositoryRoot, path).Replace('\\', '/'),
                File.ReadAllText,
                StringComparer.Ordinal);

        PowerShellToolchainPolicy.ValidateActivePesterWorkflows(workflows, manifest);
    }

    /// <summary>
    ///  Verifies that the checked-in CI job and coverage settings satisfy the managed file-creation
    ///  matrix, Release-test, and production-source coverage policies.
    /// </summary>
    [TestMethod]
    public void ManagedFileCreationWorkflowAcceptedPolicyPasses()
    {
        PowerShellToolchainPolicy.ValidateManagedFileCreationWorkflow(
            File.ReadAllText(Path.Join(RepositoryRoot, ".github", "workflows", "ci.yml")),
            File.ReadAllText(Path.Join(
                RepositoryRoot,
                "tests",
                "dotnet-file-creation",
                "coverage.config.xml")));
    }

    private static void ScaffoldRepository(string generatedRoot, string infrastructure)
    {
        string temporaryRoot = Path.GetDirectoryName(generatedRoot)
            ?? throw new InvalidOperationException("Generated root has no parent directory.");

        string launcherPath = Path.Join(temporaryRoot, "Invoke-Scaffold.ps1");
        string scaffoldPath = Path.Join(
            RepositoryRoot,
            ".agents",
            "skills",
            "create-skill-repo",
            "scripts",
            "New-SkillRepository.ps1");

        File.WriteAllText(
            launcherPath,
            """
            param(
                [Parameter(Mandatory)] [string] $Scaffold,
                [Parameter(Mandatory)] [string] $Root,
                [Parameter(Mandatory)] [string] $Infrastructure
            )

            $parameters = @{
                Root = $Root
                Name = 'policy-fixture'
                Description = 'Generated policy fixture.'
                Role = 'source'
                Infrastructure = $Infrastructure
                Visibility = 'public'
                Audience = 'public'
                Owner = 'Example'
                SkipGit = $true
            }
            if ($Infrastructure -eq 'distribution') {
                $parameters.DistributionSurfaces = @(
                    'direct', 'plugin', 'marketplace', 'agents', 'mcp')
                $parameters.IncludeEvaluations = $true
            }

            & $Scaffold @parameters
            """);

        ProcessStartInfo startInfo = new("pwsh")
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false
        };

        foreach (string argument in new[]
                 {
                     "-NoProfile",
                     "-File",
                     launcherPath,
                     "-Scaffold",
                     scaffoldPath,
                     "-Root",
                     generatedRoot,
                     "-Infrastructure",
                     infrastructure
                 })
        {
            startInfo.ArgumentList.Add(argument);
        }

        _ = RunRepositoryProcess(startInfo, "Scaffolder");
    }

    private static Dictionary<string, string> ReadGeneratedWorkflows(
        string generatedRoot)
    {
        string workflowRoot = Path.Join(generatedRoot, ".github", "workflows");
        return Directory
            .GetFiles(workflowRoot, "*.*", SearchOption.TopDirectoryOnly)
            .Where(path => path.EndsWith(".yml", StringComparison.OrdinalIgnoreCase)
                || path.EndsWith(".yaml", StringComparison.OrdinalIgnoreCase))
            .ToDictionary(
                path => Path.GetRelativePath(generatedRoot, path).Replace('\\', '/'),
                File.ReadAllText,
                StringComparer.Ordinal);
    }

    private static ToolchainManifest LoadManifest()
    {
        return PowerShellToolchainPolicy.ParseManifest(
            File.ReadAllText(Path.Join(RepositoryRoot, "tools", "powershell-toolchain.json")));
    }

    private static string FindRepositoryRoot()
    {
        for (DirectoryInfo? directory = new(AppContext.BaseDirectory);
             directory is not null;
             directory = directory.Parent)
        {
            if (File.Exists(Path.Join(directory.FullName, "AGENTS.md"))
                && File.Exists(Path.Join(directory.FullName, "tests", "Invoke-PesterShards.ps1")))
            {
                return directory.FullName;
            }
        }

        throw new InvalidOperationException("Could not locate the repository root.");
    }
}