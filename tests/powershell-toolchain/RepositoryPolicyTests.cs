using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace PowerShellToolchain.Tests;

[TestClass]
public sealed class RepositoryPolicyTests
{
    private static readonly string RepositoryRoot = FindRepositoryRoot();

    [TestMethod]
    public void CheckedInManifest_AcceptedShape_ReturnsTypedPolicy()
    {
        string manifestPath = Path.Join(RepositoryRoot, "tools", "powershell-toolchain.json");

        ToolchainManifest manifest = PowerShellToolchainPolicy.ParseManifest(
            File.ReadAllText(manifestPath));

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
    public void GeneratedPesterTestTemplates_AcceptedRequirements_Pass()
    {
        ToolchainManifest manifest = LoadManifest();
        string templateRoot = Path.Join(
            RepositoryRoot,
            ".agents",
            "skills",
            "create-skill-repo",
            "scripts",
            "template");
        string[] templateFiles = Directory.GetFiles(
            templateRoot,
            "*.Tests.ps1.tmpl",
            SearchOption.AllDirectories);

        Assert.HasCount(6, templateFiles);
        foreach (string templateFile in templateFiles)
        {
            PowerShellToolchainPolicy.ValidateTestRequirements(
                File.ReadAllText(templateFile),
                manifest);
        }
    }

    [TestMethod]
    public void CanonicalRunner_AcceptedRequirements_Pass()
    {
        ToolchainManifest manifest = LoadManifest();
        string runnerPath = Path.Join(RepositoryRoot, "tests", "Invoke-PesterShards.ps1");

        PowerShellToolchainPolicy.ValidateRunnerRequirements(
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