// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;
using System.Text.Json;
using SkillEvaluation;
using SkillEvaluation.Onnx;

namespace SkillEvaluation.Cli;

/// <summary>
///  Provides command-line access to skill evaluation workflows.
/// </summary>
public static class Program
{
    /// <summary>
    ///  Runs a skill evaluation command using the console output and error streams.
    /// </summary>
    /// <param name="args">The command followed by paired named options and values.</param>
    /// <returns>The command exit code.</returns>
    public static int Main(string[] args) => Run(args, Console.Out, Console.Error);

    /// <summary>
    ///  Runs a skill evaluation command and writes its JSON result or failure message.
    /// </summary>
    /// <param name="args">The command followed by paired named options and values.</param>
    /// <param name="output">Receives the command result as JSON.</param>
    /// <param name="error">Receives contract and infrastructure failure messages.</param>
    /// <param name="groundingBackendFactory">
    ///  Optional explicit computation owner for deterministic integration tests; fixture evidence stays synthetic.
    /// </param>
    /// <returns>
    ///  0 for success, 1 for failed quality checks, 2 for safety failures,
    ///  or 3 for contract or infrastructure failures.
    /// </returns>
    public static int Run(
        string[] args, TextWriter output, TextWriter error,
        Func<VerifiedGroundingAssets, IGroundingBackend>? groundingBackendFactory = null)
    {
        try
        {
            if (args.Length == 0)
            {
                throw new EvaluationContractException(
                    "Specify prepare, validate-profile, capture, lint-artifact, check-ledger, rescore, validate-review-packets, export-review-packets, validate-grounding-assets, validate-grounding-review, or ground.");
            }

            Dictionary<string, string> options = ParseOptions(args[1..]);
            string Required(string name) =>
                options.Remove(name, out string? value)
                    ? value
                    : throw new EvaluationContractException($"Missing --{name}.");

            string Optional(string name, string fallback) =>
                options.Remove(name, out string? value)
                    ? value
                    : fallback;

            ValidatedScenario Scenario()
            {
                string root = Required("repo-root");
                string id = Required("scenario-id");
                JsonElement[] scenarios = ProfileValidator.LoadScenarios(Required("scenario"));
                JsonElement scenario = scenarios.SingleOrDefault(
                    value => ProfileValidator.RequiredString(value, "id") == id);

                if (scenario.ValueKind == JsonValueKind.Undefined)
                {
                    throw new EvaluationContractException($"Unknown scenario '{id}'.");
                }

                return ProfileValidator.Validate(scenario, root)
                    ?? throw new EvaluationContractException($"Scenario '{id}' has no content evaluation profile.");
            }

            void CompleteOptions()
            {
                if (options.Count != 0)
                {
                    throw new EvaluationContractException($"Unknown option --{options.Keys.First()}.");
                }
            }

            object result;
            int exitCode = 0;
            switch (args[0])
            {
                case "prepare":
                case "validate-profile":
                    string repoRoot = Required("repo-root");
                    JsonElement[] scenarios = ProfileValidator.LoadScenarios(Required("scenario"));
                    string selectedId = Optional("scenario-id", "");
                    CompleteOptions();
                    if (selectedId.Length > 0
                        && !scenarios.Any(value => ProfileValidator.RequiredString(value, "id") == selectedId))
                    {
                        throw new EvaluationContractException($"Unknown scenario '{selectedId}'.");
                    }

                    PreparedScenario?[] preparations =
                        scenarios
                            .Where(value =>
                                selectedId.Length == 0
                                    || ProfileValidator.RequiredString(value, "id") == selectedId)
                            .Select(value => ProfileValidator.Validate(value, repoRoot)?.Preparation)
                            .Where(value => value is not null)
                            .ToArray();

                    if (args[0] == "validate-profile" && preparations.Length == 0)
                    {
                        throw new EvaluationContractException("No content profile is configured in the selected scenarios.");
                    }

                    result = preparations;
                    break;
                case "capture":
                    ValidatedScenario captureScenario = Scenario();
                    string workspace = Required("workspace");
                    string runDirectory = Required("run-directory");
                    if (!int.TryParse(Required("run-number"), out int runNumber))
                    {
                        throw new EvaluationContractException("Run number must be a positive integer.");
                    }

                    string scenarioRevision = Required("scenario-revision");
                    CompleteOptions();
                    result = ArtifactStore.Capture(captureScenario, workspace, runDirectory, runNumber, scenarioRevision);
                    break;
                case "lint-artifact":
                case "check-ledger":
                    ValidatedScenario artifactScenario = Scenario();
                    string targetId = Required("target-id");
                    string artifactText = ArtifactStore.Decode(File.ReadAllBytes(Required("input")));
                    CompleteOptions();
                    if (!artifactScenario.Profile.ArtifactTargets.Any(value => value.Id == targetId))
                    {
                        throw new EvaluationContractException($"Unknown target '{targetId}'.");
                    }

                    if (args[0] == "check-ledger")
                    {
                        if (artifactScenario.Profile.Ledger.Mode == LedgerMode.Off
                            || artifactScenario.Profile.Ledger.TargetId != targetId)
                        {
                            throw new EvaluationContractException("No ledger is configured for this target.");
                        }

                        CheckResult ledger = LiteralEvaluator.CheckLedger(artifactText, targetId, artifactScenario.Profile);
                        result = ledger;
                        exitCode = ledger.State == QualityState.Failed ? 1 : 0;
                    }
                    else
                    {
                        CheckResult[] checks = LiteralEvaluator.Evaluate(
                            artifactText, targetId, artifactScenario.Profile);

                        QualityState state =
                            checks.Length == 0
                                ? QualityState.NotApplicable
                                : checks.Any(value => value.State == QualityState.Failed)
                                    ? QualityState.Failed
                                    : QualityState.Passed;

                        result = new ArtifactEvaluation(state,
                            state == QualityState.Failed ? QualityState.Failed : QualityState.Pending, checks);

                        exitCode = state == QualityState.Failed ? 1 : 0;
                    }

                    break;
                case "validate-review-packets":
                case "export-review-packets":
                    string packetRoot = Required("repo-root");
                    string packetPath = Required("packets");
                    string packetOutput = args[0] == "export-review-packets" ? Required("output-directory") : "";
                    CompleteOptions();
                    result = args[0] == "export-review-packets"
                        ? ReviewPacketReports.Export(packetRoot, packetPath, packetOutput)
                        : ReviewPackets.Load(packetRoot, packetPath).Summary;

                    break;
                case "validate-grounding-assets":
                    string validationAssetRoot = Required("asset-root");
                    string validationManifest = Required("manifest");
                    CompleteOptions();
                    result = GroundingAssets.Load(validationAssetRoot, validationManifest);
                    break;
                case "ground":
                    string groundingRoot = Required("repo-root");
                    string groundingPackets = Required("packets");
                    string groundingAssets = Required("asset-root");
                    string groundingManifest = Required("manifest");
                    string groundingReviewOwner = Required("review-owner");
                    string groundingReview = Required("review");
                    string groundingOutput = Required("output-directory");
                    if (!bool.TryParse(Required("report-only"), out bool diagnosticOnly) || !diagnosticOnly)
                    {
                        throw new EvaluationContractException("Grounding is explicitly report-only; --report-only true is required.");
                    }

                    CompleteOptions();
                    result = GroundingReports.Evaluate(
                        groundingRoot, groundingPackets, groundingAssets, groundingManifest,
                        groundingReviewOwner, groundingReview, groundingOutput,
                        groundingBackendFactory ?? (assets => new CpuNliBackend(assets)));

                    break;
                case "validate-grounding-review":
                    string reviewedRoot = Required("repo-root");
                    string reviewedPackets = Required("packets");
                    string reviewOwner = Required("review-owner");
                    string reviewPath = Required("review");
                    CompleteOptions();
                    ValidatedReviewPackets reviewedBank = ReviewPackets.Load(reviewedRoot, reviewedPackets);
                    result = GroundingHumanLabels.Load(reviewOwner, reviewPath,
                        reviewedBank, GroundingInference.Prepare(reviewedBank));

                    break;
                case "rescore":
                    string root = Required("repo-root");
                    string scenarioPath = Required("scenario");
                    string inputDirectory = Required("input-directory");
                    string outputDirectory = Required("output-directory");
                    string ids = Optional("scenario-ids", "");
                    string reportOnlyText = Optional("report-only", "false");
                    if (!bool.TryParse(reportOnlyText, out bool reportOnly))
                    {
                        throw new EvaluationContractException("--report-only must be true or false.");
                    }

                    CompleteOptions();
                    SemanticSummary summary = DerivedReports.Rescore(
                        root, scenarioPath, inputDirectory, outputDirectory,
                        ids.Length == 0 ? [] : ids.Split(','));

                    result = summary;
                    exitCode =
                        summary.SafetyFailureCount > 0
                            ? 2
                            : summary.InfrastructureFailureCount > 0
                                ? 3
                                : !reportOnly && summary.UsefulFailedCount > 0
                                    ? 1
                                    : 0;

                    break;
                default:
                    throw new EvaluationContractException($"Unsupported command '{args[0]}'.");
            }

            output.WriteLine(ContractJson.Serialize(result));
            return exitCode;
        }
        catch (Exception exception) when (exception is
            EvaluationContractException
                or JsonException
                or IOException
                or UnauthorizedAccessException
                or DecoderFallbackException
                or ArgumentException)
        {
            error.WriteLine($"Skill evaluation failed: {exception.Message}");
            return 3;
        }
        catch (Exception exception) when (NativeLibraryFailures.FindCause(exception) is Exception cause)
        {
            error.WriteLine($"Skill evaluation failed: {cause.Message}");
            return 3;
        }
    }

    /// <summary>
    ///  Parses named options and rejects malformed or duplicate entries.
    /// </summary>
    /// <param name="args">Pairs of option names prefixed with -- and their values.</param>
    /// <returns>An ordinal dictionary keyed by option names without the -- prefix.</returns>
    private static Dictionary<string, string> ParseOptions(string[] args)
    {
        if (args.Length % 2 != 0)
        {
            throw new EvaluationContractException("Every named option requires one value.");
        }

        Dictionary<string, string> options = new(StringComparer.Ordinal);
        for (int index = 0; index < args.Length; index += 2)
        {
            if (!args[index].StartsWith("--", StringComparison.Ordinal)
                || args[index].Length == 2
                || !options.TryAdd(args[index][2..], args[index + 1]))
            {
                throw new EvaluationContractException($"Invalid or duplicate option '{args[index]}'.");
            }
        }

        return options;
    }
}
