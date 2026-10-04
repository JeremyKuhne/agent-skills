// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;
using System.Text.Json;

namespace SkillEvaluation;

/// <summary>
///  Captures immutable artifact snapshots and verifies their source evidence before reading them.
/// </summary>
public static class ArtifactStore
{
    private static readonly UTF8Encoding StrictUtf8 = new(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true);

    /// <summary>
    ///  Computes a revision from the run's output files, including explicit markers for missing files.
    /// </summary>
    /// <param name="runDirectory">The directory containing captured executor output.</param>
    /// <returns>The uppercase SHA-256 revision of the output-file inventory and hashes.</returns>
    public static string OutputRevision(string runDirectory)
    {
        List<string> names = ["stdout.jsonl", "stderr.txt", "transcript.md"];
        foreach (string name in new[] { "usage.json", "telemetry.jsonl" })
        {
            if (File.Exists(Path.Join(runDirectory, name)))
            {
                names.Add(name);
            }
        }

        names.Add("shim.log");
        return ContractJson.HashText(string.Join("\n", names.Select(name =>
        {
            string path = OwnedPaths.Resolve(runDirectory, name, requireFile: false);
            return $"{name}:{(File.Exists(path) ? ContractJson.HashFile(path) : "MISSING")}";
        })));
    }

    /// <summary>
    ///  Reads the final assistant-message event, retaining empty content rather than selecting an earlier message.
    /// </summary>
    /// <param name="path">The strict UTF-8 JSON-lines event file.</param>
    /// <returns>The final message text and its one-based event-file line number.</returns>
    public static (string Text, int EventLine) LastMessage(string path)
    {
        string? text = null;
        int eventLine = 0;
        int lineNumber = 0;
        foreach (string line in File.ReadLines(path, StrictUtf8))
        {
            lineNumber++;
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            JsonElement item = ContractJson.Parse(line);
            string type = ProfileValidator.RequiredString(item, "type");
            if (type != "assistant.message")
            {
                continue;
            }

            if (!item.TryGetProperty("data", out JsonElement data)
                || data.ValueKind != JsonValueKind.Object)
            {
                throw new EvaluationContractException($"Assistant event on line {lineNumber} has no data object.");
            }

            if (!data.TryGetProperty("content", out JsonElement content)
                || content.ValueKind == JsonValueKind.Null)
            {
                text = "";
            }
            else if (content.ValueKind == JsonValueKind.String)
            {
                text = content.GetString()
                    ?? throw new EvaluationContractException($"Assistant content on line {lineNumber} is not text.");
            }
            else
            {
                throw new EvaluationContractException($"Assistant content on line {lineNumber} is not text.");
            }

            eventLine = lineNumber;
        }

        return text is null
            ? throw new EvaluationContractException("No terminal assistant.message artifact was captured.")
            : (text, eventLine);
    }

    /// <summary>
    ///  Decodes strict UTF-8 bytes, removing an optional leading UTF-8 byte-order mark.
    /// </summary>
    /// <param name="bytes">The encoded artifact bytes.</param>
    /// <returns>The decoded text.</returns>
    public static string Decode(byte[] bytes)
    {
        int offset = HasBom(bytes) ? 3 : 0;
        return StrictUtf8.GetString(bytes, offset, bytes.Length - offset);
    }

    /// <summary>
    ///  Identifies a leading UTF-8 byte-order mark.
    /// </summary>
    /// <param name="bytes">The encoded bytes to inspect.</param>
    /// <returns>Whether the bytes begin with a UTF-8 byte-order mark.</returns>
    private static bool HasBom(byte[] bytes) =>
        bytes.Length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF;

    /// <summary>
    ///  Captures declared artifacts and a revisioned manifest without overwriting existing evidence.
    /// </summary>
    /// <param name="scenario">The validated scenario and its artifact declarations.</param>
    /// <param name="workspace">The directory owning declared file artifacts.</param>
    /// <param name="runDirectory">The directory containing executor output and receiving snapshots.</param>
    /// <param name="runNumber">The positive run number.</param>
    /// <param name="scenarioRevision">The uppercase SHA-256 revision of the source scenario.</param>
    /// <returns>The profile, manifest, and output revisions together with the captured artifact count.</returns>
    public static CaptureReceipt Capture(
        ValidatedScenario scenario, string workspace, string runDirectory,
        int runNumber, string scenarioRevision)
    {
        RequireRevision(scenarioRevision);
        if (runNumber < 1)
        {
            throw new EvaluationContractException("Run number must be positive.");
        }

        OwnedPaths.RejectLink(runDirectory);
        string manifestPath = OwnedPaths.Resolve(runDirectory, "artifacts.json", requireFile: false);
        string artifactsDirectory = OwnedPaths.Resolve(runDirectory, "artifacts", requireFile: false);
        if (File.Exists(manifestPath) || Directory.Exists(artifactsDirectory))
        {
            throw new EvaluationContractException("Capture artifacts already exist; immutable evidence cannot be overwritten.");
        }

        List<(ArtifactSnapshot Snapshot, byte[] Bytes)> captured = [];
        foreach (ArtifactTarget target in scenario.Profile.ArtifactTargets)
        {
            byte[] bytes;
            int? eventLine = null;
            if (target.Source == ArtifactSource.LastMessage)
            {
                (string text, int line) = LastMessage(OwnedPaths.Resolve(runDirectory, "stdout.jsonl"));
                bytes = StrictUtf8.GetBytes(text);
                eventLine = line;
            }
            else
            {
                string path = target.Path
                    ?? throw new EvaluationContractException($"Artifact '{target.Id}' requires a file path.");

                bytes = File.ReadAllBytes(OwnedPaths.Resolve(workspace, path));
            }

            _ = Decode(bytes);
            captured.Add((new(
                target.Id, target.Source, target.Path, $"artifacts/{target.Id}.utf8",
                HasBom(bytes) ? "utf-8-bom" : "utf-8", ContractJson.HashBytes(bytes),
                eventLine), bytes));
        }

        string outputRevision = OutputRevision(runDirectory);
        Directory.CreateDirectory(artifactsDirectory);
        foreach ((ArtifactSnapshot snapshot, byte[] bytes) in captured)
        {
            using FileStream stream = new(
                OwnedPaths.Resolve(runDirectory, snapshot.StoredPath, requireFile: false),
                FileMode.CreateNew, FileAccess.Write, FileShare.None);

            stream.Write(bytes);
        }

        ArtifactManifest manifest = new(
            1, scenario.Id, runNumber, scenarioRevision,
            scenario.Preparation.ProfileRevision, scenario.Preparation.InputRevision, outputRevision,
            captured.Select(item => item.Snapshot).ToArray());

        _ = ContractJson.Read<ArtifactManifest>(
            ContractJson.Parse(ContractJson.Serialize(manifest)), "artifact-manifest.v1");

        ContractJson.WriteNew(manifestPath, manifest);
        return new(scenario.Preparation.ProfileRevision, scenario.Preparation.InputRevision,
            ContractJson.HashFile(manifestPath),
            outputRevision, captured.Count);
    }

    /// <summary>
    ///  Reads snapshots only after verifying their revisions, declarations, and captured source evidence.
    /// </summary>
    /// <param name="scenario">The validated scenario against which artifacts are evaluated.</param>
    /// <param name="runDirectory">The directory owning the captured output, manifest, and snapshots.</param>
    /// <param name="runNumber">The expected source run number.</param>
    /// <param name="scenarioRevision">The expected source scenario revision.</param>
    /// <param name="outputRevision">The expected captured output revision.</param>
    /// <param name="manifestRevision">The expected artifact-manifest revision.</param>
    /// <param name="sourceProfileRevision">The profile revision recorded when the artifacts were captured.</param>
    /// <param name="sourceInputRevision">The input revision recorded for the prompt sent to the model.</param>
    /// <returns>Verified artifact text indexed by target identifier.</returns>
    public static Dictionary<string, string> ReadVerified(
        ValidatedScenario scenario, string runDirectory, int runNumber,
        string scenarioRevision, string outputRevision, string manifestRevision,
        string sourceProfileRevision, string sourceInputRevision)
    {
        RequireRevision(outputRevision);
        RequireRevision(manifestRevision);
        RequireRevision(sourceInputRevision);
        string manifestPath = OwnedPaths.Resolve(runDirectory, "artifacts.json");
        if (ContractJson.HashFile(manifestPath) != manifestRevision
            || OutputRevision(runDirectory) != outputRevision)
        {
            throw new EvaluationContractException("Captured output or artifact manifest changed.");
        }

        ArtifactManifest manifest = ContractJson.Read<ArtifactManifest>(
            ContractJson.Parse(File.ReadAllText(manifestPath)), "artifact-manifest.v1");

        if (manifest.ScenarioId != scenario.Id
            || manifest.RunNumber != runNumber
            || manifest.ScenarioRevision != scenarioRevision
            || manifest.ProfileRevision != sourceProfileRevision
            || manifest.InputRevision != sourceInputRevision
            || manifest.InputRevision != scenario.Preparation.InputRevision
            || manifest.ModelOutputRevision != outputRevision
            || manifest.Artifacts.Length != scenario.Profile.ArtifactTargets.Length)
        {
            throw new EvaluationContractException("Artifact manifest does not match the source run and content profile.");
        }

        ProfileValidator.UniqueIds(manifest.Artifacts.Select(value => value.TargetId), "captured artifact");
        Dictionary<string, string> contents = new(StringComparer.Ordinal);
        foreach (ArtifactTarget target in scenario.Profile.ArtifactTargets)
        {
            ArtifactSnapshot snapshot = manifest.Artifacts.SingleOrDefault(
                value => value.TargetId == target.Id)
                ?? throw new EvaluationContractException($"Missing artifact target '{target.Id}'.");

            if (snapshot.Source != target.Source
                || snapshot.SourcePath != target.Path
                || snapshot.StoredPath != $"artifacts/{target.Id}.utf8")
            {
                throw new EvaluationContractException($"Artifact declaration changed for '{target.Id}'.");
            }

            byte[] bytes = File.ReadAllBytes(OwnedPaths.Resolve(runDirectory, snapshot.StoredPath));
            if (ContractJson.HashBytes(bytes) != snapshot.Sha256
                || snapshot.Encoding != (HasBom(bytes) ? "utf-8-bom" : "utf-8"))
            {
                throw new EvaluationContractException($"Artifact bytes changed for '{target.Id}'.");
            }

            if (target.Source == ArtifactSource.LastMessage)
            {
                (string text, int line) = LastMessage(OwnedPaths.Resolve(runDirectory, "stdout.jsonl"));
                if (line != snapshot.AssistantEventLine
                    || ContractJson.HashBytes(StrictUtf8.GetBytes(text)) != snapshot.Sha256)
                {
                    throw new EvaluationContractException("Last-message snapshot does not match the terminal source event.");
                }
            }

            contents.Add(target.Id, Decode(bytes));
        }

        return contents;
    }

    /// <summary>
    ///  Requires a SHA-256 revision encoded as 64 uppercase hexadecimal characters.
    /// </summary>
    /// <param name="revision">The revision to validate.</param>
    internal static void RequireRevision(string revision)
    {
        if (revision.Length != 64 || revision.Any(character =>
            !char.IsAsciiDigit(character) && character is not (>= 'A' and <= 'F')))
        {
            throw new EvaluationContractException("A SHA-256 revision in uppercase hexadecimal is required.");
        }
    }
}
