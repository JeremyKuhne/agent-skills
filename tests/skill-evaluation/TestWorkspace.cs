// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Touki;

namespace SkillEvaluation.Tests;

/// <summary>
///  Owns temporary scenario, workspace, and run-evidence files for an evaluation test.
/// </summary>
internal sealed class TestWorkspace : DisposableBase
{
    /// <summary>
    ///  Gets the unique temporary root owned by this test.
    /// </summary>
    public string Root { get; } = Path.Join(Path.GetTempPath(), $"skill-content-test-{Guid.NewGuid():N}");

    /// <summary>
    ///  Gets the directory for the fixture's first run.
    /// </summary>
    public string RunDirectory => Path.Join(Root, "source", "test-case", "run-1");

    /// <summary>
    ///  Gets the live artifact workspace within the run directory.
    /// </summary>
    public string Workspace => Path.Join(RunDirectory, "workspace");

    /// <summary>
    ///  Gets the scenario JSON file path.
    /// </summary>
    public string ScenarioPath => Path.Join(Root, "scenario.json");

    /// <summary>
    ///  The fixed revision used for scenario and scorer evidence in test fixtures.
    /// </summary>
    public const string ScenarioRevision = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";

    /// <summary>
    ///  Creates the temporary workspace directory.
    /// </summary>
    public TestWorkspace()
    {
        Directory.CreateDirectory(Workspace);
    }

    /// <summary>
    ///  Copies the portable synthetic bank and its pinned rubric closure into this isolated test owner.
    /// </summary>
    /// <param name="mutate">An optional explicit mutation of the source JSON before writing.</param>
    /// <returns>The owned bank path.</returns>
    public string WriteReviewBank(Action<JsonObject>? mutate = null)
    {
        string root = FindRepositoryRoot();
        foreach (string relative in new[]
        {
            "evals/rubrics/technical-writing.v2.json",
            "skills/technical-writing/SKILL.md",
            "skills/technical-writing/artifact-patterns.md"
        })
        {
            string destination = OwnedPaths.Resolve(Root, relative, requireFile: false);
            string parent = Path.GetDirectoryName(destination)
                ?? throw new InvalidOperationException("Fixture files require a parent directory.");

            Directory.CreateDirectory(parent);
            File.Copy(OwnedPaths.Resolve(root, relative), destination);
        }

        string sourcePath = OwnedPaths.Resolve(root, "evals/fixtures/output-quality/review-packets.v1.json");
        JsonObject bank = JsonNode.Parse(File.ReadAllText(sourcePath)) as JsonObject
            ?? throw new InvalidOperationException("The public packet fixture must be an object.");

        mutate?.Invoke(bank);
        string input = Path.Join(Root, "inputs");
        Directory.CreateDirectory(input);
        string path = Path.Join(input, "bank.json");
        File.WriteAllText(path, bank.ToJsonString(ContractJson.Options));
        return path;
    }

    /// <summary>
    ///  Creates the fixture's content profile with verified test facts and unknown compatibility.
    /// </summary>
    /// <param name="source">The artifact source to use for the body target.</param>
    /// <returns>The profile with literal checks and no required grounding ledger.</returns>
    public static ContentProfile Profile(ArtifactSource source = ArtifactSource.LastMessage) => new(
        1, ArtifactKind.PrDescription,
        [new("body", source, source == ArtifactSource.File ? "body draft.md" : null)],
        [
            new("tests", "14 tests passed on Windows.", EvidenceState.Verified, FactKind.Fact, "scenario-input"),
            new("compatibility", "Compatibility impact is unknown.", EvidenceState.Unknown, FactKind.Fact, "scenario-input")
        ],
        [new("test-result", "body", "14 tests passed on Windows.", ["tests"], ["14", "Windows"])],
        [new("compatibility-claim", "body", "Compatibility is verified.", "certainty-upgrade", ["compatibility"])],
        [
            new("summary", "body", LiteralKind.Heading, "Summary", 2),
            new("validation", "body", LiteralKind.Heading, "Validation", 2),
            new("line-shape", "body", LiteralKind.SingleLineParagraphs)
        ],
        [],
        new(LedgerMode.Off));

    /// <summary>
    ///  Writes and validates a scenario using the supplied profile or the default fixture profile.
    /// </summary>
    /// <param name="profile">The profile to write, or <see langword="null"/> for the default fixture profile.</param>
    /// <returns>The validated scenario loaded from the written file.</returns>
    public ValidatedScenario Scenario(ContentProfile? profile = null)
    {
        object[] scenarios =
        [
            new
            {
                id = "test-case",
                prompt = "Prepare a local artifact using these facts:\n{{suppliedFacts}}\nReturn the artifact.",
                contentEvaluation = profile ?? Profile()
            }

        ];

        File.WriteAllText(ScenarioPath, ContractJson.Serialize(new { schemaVersion = 1, scenarios }));
        JsonElement scenario = ProfileValidator.LoadScenarios(ScenarioPath)[0];
        ValidatedScenario? validated = ProfileValidator.Validate(scenario, Root);
        Assert.IsNotNull(validated);
        return validated;
    }

    /// <summary>
    ///  Writes assistant-message events and the accompanying run-output files.
    /// </summary>
    /// <param name="text">The first assistant message and transcript text.</param>
    /// <param name="closing">An optional terminal assistant message.</param>
    public void WriteOutput(string text, string? closing = null)
    {
        string Event(string value) => JsonSerializer.Serialize(
            new { type = "assistant.message", data = new { content = value } });

        File.WriteAllText(Path.Join(RunDirectory, "stdout.jsonl"),
            Event(text) + "\n" + (closing is null ? "" : Event(closing) + "\n"), new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));

        File.WriteAllText(Path.Join(RunDirectory, "stderr.txt"), "");
        File.WriteAllText(Path.Join(RunDirectory, "transcript.md"), text);
        File.WriteAllText(Path.Join(RunDirectory, "shim.log"), "");
    }

    /// <summary>
    ///  Writes a one-run source summary using synthetic executor metadata.
    /// </summary>
    /// <param name="receipt">The capture revisions, or <see langword="null"/> for a run without a manifest.</param>
    /// <param name="safetyPassed">Whether the source run passed its safety checks.</param>
    public void WriteSummary(CaptureReceipt? receipt, bool safetyPassed = true)
    {
        object[] runs =
        [
            new
            {
                ScenarioId = "test-case",
                RunNumber = 1,
                Model = "fake-model",
                Passed = true,
                SafetyPassed = safetyPassed,
                TimedOut = false,
                ExitCode = 0,
                Error = (string?)null,
                ModelOutputRevision = ArtifactStore.OutputRevision(RunDirectory),
                ScenarioRevision,
                ArtifactManifestRevision = receipt?.ArtifactManifestRevision,
                ContentProfileRevision = receipt?.ProfileRevision,
                ContentInputRevision = receipt?.InputRevision
            }

        ];

        File.WriteAllText(Path.Join(Root, "source", "summary.json"),
            JsonSerializer.Serialize(new
            {
                SchemaVersion = 1,
                Model = "fake-model",
                CopilotVersion = "fake-executor",
                ScorerRevision = ScenarioRevision,
                RunCount = 1,
                Runs = runs
            }));
    }

    /// <summary>
    ///  Finds the ancestor of the test output that contains the plugin manifest and evaluations directory.
    /// </summary>
    /// <returns>The repository directory containing both fixture markers.</returns>
    public static string FindRepositoryRoot()
    {
        for (DirectoryInfo? directory = new(AppContext.BaseDirectory); directory is not null; directory = directory.Parent)
        {
            if (File.Exists(Path.Join(directory.FullName, "plugin.json"))
                && Directory.Exists(Path.Join(directory.FullName, "evals")))
            {
                return directory.FullName;
            }
        }

        throw new InvalidOperationException("Repository root was not found.");
    }

    /// <summary>
    ///  Deletes the owned temporary root during explicit disposal.
    /// </summary>
    /// <param name="disposing">Whether cleanup is requested through explicit disposal.</param>
    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            Directory.Delete(Root, recursive: true);
        }
    }
}
