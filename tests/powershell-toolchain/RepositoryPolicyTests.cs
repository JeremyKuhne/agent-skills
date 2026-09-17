using System.Diagnostics;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace PowerShellToolchain.Tests;

[TestClass]
public sealed class RepositoryPolicyTests
{
    private static readonly string RepositoryRoot = FindRepositoryRoot();

    [TestMethod]
    public void CheckedInManifest_AcceptedShape_ReturnsTypedPolicy()
    {
        ToolchainManifest manifest = LoadManifest();

        Assert.AreEqual(1, manifest.SchemaVersion);
        Assert.AreEqual("7.4", manifest.TestMinimumVersion);
        Assert.AreEqual("6.2.0", manifest.PesterCompatibilityMinimumVersion);
        Assert.AreEqual("6.2.0", manifest.PesterExecutionVersion);
    }

    [TestMethod]
    public void TrackedPesterTests_AcceptedRequirements_Pass()
    {
        ToolchainManifest manifest = LoadManifest();
        string[] testFiles = Directory.GetFiles(
            Path.Join(RepositoryRoot, "tests"),
            "*.Tests.ps1",
            SearchOption.AllDirectories);

        Assert.HasCount(16, testFiles);
        foreach (string testFile in testFiles)
        {
            PowerShellToolchainPolicy.ValidateTestRequirements(
                File.ReadAllText(testFile),
                manifest);
        }
    }

    [TestMethod]
    public void GeneratedPesterTests_AcceptedRequirements_Pass()
    {
        ToolchainManifest manifest = LoadManifest();
        string scaffoldPath = Path.Join(
            RepositoryRoot,
            ".agents",
            "skills",
            "create-skill-repo",
            "scripts",
            "New-SkillRepository.ps1");
        string temporaryRoot = Path.Join(
            Path.GetTempPath(),
            $"agent-skills-toolchain-{Guid.NewGuid():N}");
        string generatedRoot = Path.Join(temporaryRoot, "generated");
        string launcherPath = Path.Join(temporaryRoot, "Invoke-Scaffold.ps1");

        try
        {
            Directory.CreateDirectory(temporaryRoot);
            File.WriteAllText(
                launcherPath,
                """
                param(
                    [Parameter(Mandatory)] [string] $Scaffold,
                    [Parameter(Mandatory)] [string] $Root
                )

                & $Scaffold `
                    -Root $Root `
                    -Name policy-fixture `
                    -Description 'Generated policy fixture.' `
                    -Role source `
                    -Infrastructure distribution `
                    -Visibility public `
                    -Audience public `
                    -Owner Example `
                    -DistributionSurfaces direct,plugin,marketplace,agents,mcp `
                    -IncludeEvaluations `
                    -SkipGit
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
                         generatedRoot
                     })
            {
                startInfo.ArgumentList.Add(argument);
            }

            using Process process = Process.Start(startInfo)
                ?? throw new InvalidOperationException("The scaffold process did not start.");
            using CancellationTokenSource deadline = new(TimeSpan.FromMinutes(2));
            Task<string> outputTask = process.StandardOutput.ReadToEndAsync(deadline.Token);
            Task<string> errorTask = process.StandardError.ReadToEndAsync(deadline.Token);
            try
            {
                process.WaitForExitAsync(deadline.Token).GetAwaiter().GetResult();
            }
            finally
            {
                if (!process.HasExited)
                {
                    process.Kill(entireProcessTree: true);
                    process.WaitForExit();
                }
            }

            string output = outputTask.GetAwaiter().GetResult();
            string error = errorTask.GetAwaiter().GetResult();
            Assert.AreEqual(
                0,
                process.ExitCode,
                $"Scaffolder output:{Environment.NewLine}{output}{Environment.NewLine}{error}");

            string[] testFiles = Directory.GetFiles(
                Path.Join(generatedRoot, "tests"),
                "*.Tests.ps1",
                SearchOption.TopDirectoryOnly);
            string[] fileNames = testFiles
                .Select(Path.GetFileName)
                .Order(StringComparer.Ordinal)
                .ToArray()!;
            CollectionAssert.AreEqual(
                new[]
                {
                    "Agents.Tests.ps1",
                    "EvaluationScenarios.Tests.ps1",
                    "Marketplace.Tests.ps1",
                    "Mcp.Tests.ps1",
                    "Plugin.Tests.ps1",
                    "Repository.Tests.ps1"
                },
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

    [TestMethod]
    public void CanonicalRunner_AcceptedMetadata_Passes()
    {
        ToolchainManifest manifest = LoadManifest();
        string runnerPath = Path.Join(RepositoryRoot, "tests", "Invoke-PesterShards.ps1");

        PowerShellToolchainPolicy.ValidateRunnerMetadata(
            File.ReadAllText(runnerPath),
            manifest);
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
            if (File.Exists(Path.Join(directory.FullName, "AGENTS.md")) &&
                File.Exists(Path.Join(directory.FullName, "tests", "Invoke-PesterShards.ps1")))
            {
                return directory.FullName;
            }
        }

        throw new InvalidOperationException("Could not locate the repository root.");
    }
}