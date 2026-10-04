// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;
using System.Text.Json;
using Touki.Text;

namespace SkillEvaluation;

/// <summary>
///  Produces derived deterministic content reports without overwriting or reclassifying source evidence.
/// </summary>
public static class DerivedReports
{
    /// <summary>
    ///  Verifies selected captured runs and writes their deterministic content results to a separate directory.
    /// </summary>
    /// <param name="repoRoot">The directory owning scenario content and rubric files.</param>
    /// <param name="scenarioPath">The scenario-document path.</param>
    /// <param name="inputDirectory">The directory owning the source summary and captured runs.</param>
    /// <param name="outputDirectory">The absent or empty directory receiving derived evidence.</param>
    /// <param name="scenarioIds">The scenario identifiers to select, or an empty array for all source runs.</param>
    /// <returns>The derived summary, with semantic judgments pending and infrastructure failures recorded.</returns>
    public static SemanticSummary Rescore(
        string repoRoot, string scenarioPath, string inputDirectory, string outputDirectory,
        string[] scenarioIds)
    {
        OwnedPaths.RequireSeparateOutput(inputDirectory, outputDirectory);
        string sourcePath = OwnedPaths.Resolve(inputDirectory, "summary.json");
        byte[] sourceBytes = File.ReadAllBytes(sourcePath);
        JsonElement source = ContractJson.Parse(ArtifactStore.Decode(sourceBytes));
        if (RequiredInt(source, "SchemaVersion") != 1)
        {
            throw new EvaluationContractException("Only schema-version-1 capture summaries are supported.");
        }

        string model = ProfileValidator.RequiredString(source, "Model");
        string clientVersion = ProfileValidator.RequiredString(source, "CopilotVersion");
        if (clientVersion != "fake-executor")
        {
            ArtifactStore.RequireRevision(
                ProfileValidator.RequiredString(source, "CopilotExecutableSha256"));

            if (!source.TryGetProperty("CopilotExecutableEvidenceVerified", out JsonElement verified)
                || verified.ValueKind != JsonValueKind.True)
            {
                throw new EvaluationContractException("Source client executable evidence is unverified.");
            }
        }

        string scorerRevision = ProfileValidator.RequiredString(source, "ScorerRevision");
        ArtifactStore.RequireRevision(scorerRevision);
        if (!source.TryGetProperty("Runs", out JsonElement runs)
            || runs.ValueKind != JsonValueKind.Array
            || !source.TryGetProperty("RunCount", out JsonElement count)
            || !count.TryGetInt32(out int runCount)
            || runCount < 1
            || runCount != runs.GetArrayLength())
        {
            throw new EvaluationContractException("Source summary has missing or inconsistent scheduled run counts.");
        }

        JsonElement[] scenarios = ProfileValidator.LoadScenarios(scenarioPath);
        Dictionary<string, JsonElement> byId = scenarios.ToDictionary(
            value => ProfileValidator.RequiredString(value, "id"), StringComparer.Ordinal);

        ProfileValidator.UniqueIds(scenarioIds, "requested scenario");
        foreach (string id in scenarioIds)
        {
            if (!byId.ContainsKey(id) || !runs.EnumerateArray().Any(
                value => ProfileValidator.RequiredString(value, "ScenarioId") == id))
            {
                throw new EvaluationContractException($"Requested scenario '{id}' has no matching source evidence.");
            }
        }

        List<DerivedRun> results = [];
        HashSet<string> keys = new(StringComparer.Ordinal);
        int sourceSafetyFailures = 0;
        foreach (JsonElement run in runs.EnumerateArray())
        {
            string id = ProfileValidator.RequiredString(run, "ScenarioId");
            int number = RequiredInt(run, "RunNumber");
            if (number < 1 || !keys.Add($"{id}:{number}"))
            {
                throw new EvaluationContractException("Source runs have a nonpositive or duplicate scenario/run pair.");
            }

            if (scenarioIds.Length > 0 && !scenarioIds.Contains(id, StringComparer.Ordinal))
            {
                continue;
            }

            if (!byId.TryGetValue(id, out JsonElement scenario))
            {
                throw new EvaluationContractException($"Source scenario '{id}' is not in the selected document.");
            }

            _ = RequiredBool(run, "Passed");
            if (!RequiredBool(run, "SafetyPassed")) sourceSafetyFailures++;
            bool timedOut = RequiredBool(run, "TimedOut");
            int exitCode = RequiredInt(run, "ExitCode");
            SemanticRecord? content = null;
            string? infrastructureError = null;
            try
            {
                if (ProfileValidator.RequiredString(run, "Model") != model)
                {
                    throw new EvaluationContractException("Source run model does not match its summary.");
                }

                if (timedOut
                    || exitCode != 0
                    || (run.TryGetProperty("Error", out JsonElement error)
                        && error.ValueKind == JsonValueKind.String
                        && !string.IsNullOrWhiteSpace(error.GetString())))
                {
                    throw new EvaluationContractException("Source execution has infrastructure failure; content cannot establish success.");
                }

                string outputRevision = ProfileValidator.RequiredString(run, "ModelOutputRevision");
                string runDirectory = OwnedPaths.Resolve(inputDirectory, $"{id}/run-{number}", requireFile: false);
                if (ArtifactStore.OutputRevision(runDirectory) != outputRevision)
                {
                    throw new EvaluationContractException("Source output revision is missing or changed.");
                }

                ValidatedScenario? validated = ProfileValidator.Validate(scenario, repoRoot);
                if (validated is not null)
                {
                    content = ContentEvaluator.EvaluateCaptured(
                        validated, runDirectory, number,
                        ProfileValidator.RequiredString(run, "ScenarioRevision"), outputRevision,
                        ProfileValidator.RequiredString(run, "ArtifactManifestRevision"),
                        ProfileValidator.RequiredString(run, "ContentProfileRevision"),
                        ProfileValidator.RequiredString(run, "ContentInputRevision"));
                }
            }
            catch (Exception error) when (error is EvaluationContractException
                or JsonException
                or IOException
                or UnauthorizedAccessException
                or DecoderFallbackException)
            {
                infrastructureError = error.Message;
            }

            results.Add(new(id, number, run.Clone(), content, infrastructureError));
        }

        if (results.Count == 0)
        {
            throw new EvaluationContractException("No source attempts were selected.");
        }

        SemanticSummary summary = new(
            1, "semantic", model,
            ContractJson.Revision(new
            {
                ContentEvaluator.EngineRevision,
                profiles = results.Select(value => value.Content?.ProfileRevision).ToArray()
            }),
            ContractJson.HashBytes(sourceBytes), scorerRevision,
            results.Count,
            results.Count(value => value.Content?.LiteralStatus == QualityState.Passed),
            0,
            results.Count(value => value.Content?.UsefulOutcome == QualityState.Failed),
            results.Count(value => value.Content is null || value.Content.UsefulOutcome == QualityState.Pending),
            sourceSafetyFailures,
            results.Count(value => value.InfrastructureError is not null),
            results.ToArray());

        if (ContractJson.HashFile(sourcePath) != ContractJson.HashBytes(sourceBytes))
        {
            throw new EvaluationContractException("Source summary changed during content evaluation.");
        }

        Directory.CreateDirectory(outputDirectory);
        foreach (DerivedRun run in summary.Runs.Where(value => value.Content is not null))
        {
            string directory = OwnedPaths.Resolve(outputDirectory,
                $"{run.ScenarioId}/run-{run.RunNumber}", requireFile: false);

            Directory.CreateDirectory(directory);
            ContractJson.WriteNew(Path.Join(directory, "semantic.json"), run.Content);
        }

        ContractJson.WriteNew(Path.Join(outputDirectory, "summary.json"), summary);
        WriteMarkdown(summary, Path.Join(outputDirectory, "summary.md"));
        return summary;
    }

    /// <summary>
    ///  Reads a required JSON integer property.
    /// </summary>
    /// <param name="element">The JSON object containing the property.</param>
    /// <param name="property">The property name.</param>
    /// <returns>The property's 32-bit integer value.</returns>
    private static int RequiredInt(JsonElement element, string property)
    {
        if (!element.TryGetProperty(property, out JsonElement value)
            || value.ValueKind != JsonValueKind.Number
            || !value.TryGetInt32(out int number))
        {
            throw new EvaluationContractException($"An integer '{property}' is required.");
        }

        return number;
    }

    /// <summary>
    ///  Reads a required JSON Boolean property.
    /// </summary>
    /// <param name="element">The JSON object containing the property.</param>
    /// <param name="property">The property name.</param>
    /// <returns>The property's Boolean value.</returns>
    private static bool RequiredBool(JsonElement element, string property)
    {
        if (!element.TryGetProperty(property, out JsonElement value)
            || value.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
        {
            throw new EvaluationContractException($"A JSON Boolean '{property}' is required.");
        }

        return value.GetBoolean();
    }

    /// <summary>
    ///  Writes a new UTF-8 Markdown summary with normalized line endings.
    /// </summary>
    /// <param name="summary">The derived summary to render.</param>
    /// <param name="path">The new report-file path.</param>
    private static void WriteMarkdown(SemanticSummary summary, string path)
    {
        using ValueStringBuilder text = new(stackalloc char[256]);
        text.Append("# Skill content evaluation\n\n");
        text.AppendLine("No classifier or judge inference was performed. Literal compliance is not useful success.");
        text.AppendLine();
        text.AppendLine($"- Model: `{summary.Model}`");
        text.AppendLine($"- Source scorer revision: `{summary.SourceScorerRevision}`");
        text.AppendLine($"- Runs: {summary.RunCount}");
        text.AppendLine($"- Useful passes: {summary.UsefulPassedCount}");
        text.AppendLine($"- Pending: {summary.PendingCount}");
        text.AppendLine($"- Infrastructure failures: {summary.InfrastructureFailureCount}");
        text.AppendLine();
        text.AppendLine("| Scenario | Run | Original pattern | Original safety | Literal | Semantic | Useful outcome |");
        text.AppendLine("| --- | ---: | --- | --- | --- | --- | --- |");
        foreach (DerivedRun run in summary.Runs)
        {
            string literal = run.Content?.LiteralStatus.ToString() ?? "Not configured";
            string semantic = run.Content?.SemanticStatus.ToString() ?? "Pending";
            string useful = run.Content?.UsefulOutcome.ToString() ?? "Pending";
            text.AppendLine($"| `{run.ScenarioId}` | {run.RunNumber} | {run.SourceResult.GetProperty("Passed")} | {run.SourceResult.GetProperty("SafetyPassed")} | {literal} | {semantic} | {useful} |");
        }

        using FileStream stream = new(path, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        stream.Write(Encoding.UTF8.GetBytes(text.ToString().Replace("\r\n", "\n", StringComparison.Ordinal)));
    }
}
