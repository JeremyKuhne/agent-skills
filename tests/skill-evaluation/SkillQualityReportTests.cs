// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using SkillEvaluation.Cli;

namespace SkillEvaluation.Tests;

/// <summary>
///  Checks hand-counted paired quality metrics, exact grading provenance, and conservative missing states.
/// </summary>
[TestClass]
public sealed class SkillQualityReportTests
{
    /// <summary>
    ///  Verifies a pass rate uses the scheduled denominator even when no actual run or judge exists.
    /// </summary>
    [TestMethod]
    public void BuildRetainsMissingScheduledRows()
    {
        JsonElement report = SkillQualityReports.Build(Campaign([], []));
        Assert.AreEqual(2, report.GetProperty("scheduled").GetInt32());
        Assert.AreEqual(0, report.GetProperty("completed").GetInt32());
        Assert.AreEqual(2, report.GetProperty("notRun").GetInt32());
        Assert.AreEqual(1, report.GetProperty("pairedCounts")[0].GetProperty("pendingPairs").GetInt32());
        Assert.AreEqual(0, report.GetProperty("usefulPassedCount").GetInt32());
        Assert.AreEqual("pending", report.GetProperty("calibrationStatus").GetString());
    }

    /// <summary>
    ///  Verifies comparisons use actual candidate evidence, not outcomes in the expected inventory.
    /// </summary>
    [TestMethod]
    public void BuildComputesActualWinLossAndTie()
    {
        SkillQualityRunRecord baseline = Run(SkillQualityCondition.NoSkill);
        SkillQualityRunRecord current = Run(SkillQualityCondition.Current);
        SkillQualityJudgeRecord[] judges =
        [
            Judge(baseline, SkillQualityModelId.Gpt61Sol, SkillQualityJudgeState.Failed),
            Judge(baseline, SkillQualityModelId.Gpt6Luna, SkillQualityJudgeState.Failed),
            Judge(current, SkillQualityModelId.Gpt61Sol, SkillQualityJudgeState.Passed),
            Judge(current, SkillQualityModelId.Gpt6Luna, SkillQualityJudgeState.Passed)
        ];

        JsonElement report = SkillQualityReports.Build(Campaign([baseline, current], judges));
        Assert.AreEqual("win", report.GetProperty("comparisons")[0].GetProperty("outcome").GetString());
        Assert.AreEqual(2, report.GetProperty("judgeAgreement").GetInt32());
        Assert.AreEqual(0, report.GetProperty("judgeDisagreement").GetInt32());
        Assert.AreEqual("provisional-pass", report.GetProperty("rows")[1].GetProperty("outcome").GetString());
        report = SkillQualityReports.Build(Campaign([baseline, current],
            judges.Select(judge => judge with
            {
                Judgments = [new("task", HardGate: true,
                    judge.Condition == SkillQualityCondition.NoSkill ? SkillQualityJudgeState.Passed : SkillQualityJudgeState.Failed,
                    "Exact fixture artifact evidence.", "Reversed fixture quality outcome.")]
            }).ToArray()));

        Assert.AreEqual("loss", report.GetProperty("comparisons")[0].GetProperty("outcome").GetString());
    }

    /// <summary>
    ///  Verifies an executable failure cannot be overruled by agreeing model passes.
    /// </summary>
    [TestMethod]
    public void BuildExecutableFailureIsDecisive()
    {
        SkillQualityRunRecord current = Run(SkillQualityCondition.Current) with
        {
            OracleOutcome = SkillQualityOracleOutcome.Failed,
            HardChecks = [new("build", "Build output", SkillQualityCheckState.Failed,
                "Compiler returned exit1.", "Delivered code does not compile.")]
        };

        JsonElement report = SkillQualityReports.Build(Campaign([current],
            [Judge(current, SkillQualityModelId.Gpt61Sol, SkillQualityJudgeState.Passed),
                Judge(current, SkillQualityModelId.Gpt6Luna, SkillQualityJudgeState.Passed)]));

        Assert.AreEqual("failed-executable", report.GetProperty("rows")[1].GetProperty("outcome").GetString());
    }

    /// <summary>
    ///  Verifies disagreeing hard verdicts are not averaged and missing usage is not fabricated.
    /// </summary>
    [TestMethod]
    public void BuildPreservesDisagreementAndUnknownUsage()
    {
        SkillQualityRunRecord current = Run(SkillQualityCondition.Current);
        JsonElement report = SkillQualityReports.Build(Campaign([current],
            [Judge(current, SkillQualityModelId.Gpt61Sol, SkillQualityJudgeState.Passed),
                Judge(current, SkillQualityModelId.Gpt6Luna, SkillQualityJudgeState.Failed)]));

        Assert.AreEqual("disputed", report.GetProperty("rows")[1].GetProperty("outcome").GetString());
        Assert.AreEqual(1, report.GetProperty("judgeDisagreement").GetInt32());
        Assert.AreEqual(JsonValueKind.Null, report.GetProperty("rows")[1].GetProperty("usage").ValueKind);
        Assert.AreEqual("pending", report.GetProperty("comparisons")[0].GetProperty("outcome").GetString());
    }

    /// <summary>
    ///  Verifies duplicates, mismatched input/artifacts, and missing criteria fail before reporting.
    /// </summary>
    [TestMethod]
    public void ParseRejectsInvalidFrozenEvidence()
    {
        SkillQualityRunRecord current = Run(SkillQualityCondition.Current);
        SkillQualityJudgeRecord grade = Judge(current, SkillQualityModelId.Gpt61Sol, SkillQualityJudgeState.Passed);
        SkillQualityCampaign valid = Campaign([current], [grade]);
        SkillQualityCampaign[] invalid =
        [
            valid with { ActualRunRecords = [current, current] },
            valid with { ActualRunRecords = [current with { InputRevision = new('B', 64) }] },
            valid with { JudgeRecords = [grade with { ArtifactRevision = new('B', 64) }] },
            valid with { JudgeRecords = [grade, grade] },
            valid with { JudgeRecords = [grade with { Judgments = [] }] },
            valid with { ExpectedRunInventory = [Run(SkillQualityCondition.NoSkill), current] }
        ];

        foreach (SkillQualityCampaign campaign in invalid)
        {
            Assert.ThrowsExactly<EvaluationContractException>(() =>
                SkillQualityReports.Parse(ContractJson.Serialize(campaign)));
        }
    }

    /// <summary>
    ///  Verifies the public report command preserves missing rows and actionable failures without qualification.
    /// </summary>
    [TestMethod]
    public void QualityReportCliPreservesMissingRowsAndExecutableEvidence()
    {
        using TestWorkspace workspace = new();
        string path = Path.Join(workspace.Root, "campaign with spaces.json");
        SkillQualityRunRecord current = Run(SkillQualityCondition.Current) with
        {
            OracleOutcome = SkillQualityOracleOutcome.Failed,
            HardChecks = [new("compile", "Compiler", SkillQualityCheckState.Failed,
                "Compiler returned exit 1.", "Delivered code does not compile.")]
        };

        File.WriteAllText(path, ContractJson.Serialize(Campaign([current], [])));
        StringWriter output = new();
        StringWriter error = new();
        int exit = Program.Run(["quality-report", "--campaign", path], output, error);
        Assert.AreEqual(0, exit, error.ToString());
        Assert.AreEqual("", error.ToString());
        JsonElement report = ContractJson.Parse(output.ToString());
        Assert.AreEqual(2, report.GetProperty("scheduled").GetInt32());
        Assert.AreEqual(1, report.GetProperty("notRun").GetInt32());
        Assert.AreEqual("failed-executable", report.GetProperty("rows")[1].GetProperty("outcome").GetString());
        Assert.AreEqual(current.ArtifactRevision, report.GetProperty("rows")[1].GetProperty("artifactRevision").GetString());
        Assert.AreEqual("Compiler returned exit 1.",
            report.GetProperty("rows")[1].GetProperty("hardChecks")[0].GetProperty("evidence").GetString());

        Assert.AreEqual("pending", report.GetProperty("usefulOutcome").GetString());
        Assert.AreEqual(0, report.GetProperty("usefulPassedCount").GetInt32());
    }

    /// <summary>
    ///  Verifies original malformed JSON is rejected rather than completed with typed defaults.
    /// </summary>
    [TestMethod]
    public void QualityReportCliRejectsMissingSourceFields()
    {
        using TestWorkspace workspace = new();
        string path = Path.Join(workspace.Root, "campaign.json");
        JsonObject source = JsonNode.Parse(ContractJson.Serialize(Campaign([Run(SkillQualityCondition.Current)], [])))
            as JsonObject ?? throw new InvalidOperationException("Expected an object.");

        JsonObject actual = source["actualRunRecords"]?[0] as JsonObject
            ?? throw new InvalidOperationException("Expected an actual candidate.");

        Assert.IsTrue(actual.Remove("usage"));
        File.WriteAllText(path, source.ToJsonString());
        StringWriter output = new();
        StringWriter error = new();
        Assert.AreEqual(3, Program.Run(["quality-report", "--campaign", path], output, error));
        Assert.AreEqual("", output.ToString());
        Assert.Contains("Skill evaluation failed:", error.ToString());
        Assert.Contains("skill-quality-campaign.v1", error.ToString());
    }

    /// <summary>
    ///  Makes a two-condition frozen pilot fixture with no expected outcome assertions.
    /// </summary>
    /// <param name="runs">The actual observed candidates.</param>
    /// <param name="judges">The separate artifact-bound model grades.</param>
    /// <returns>The strict fixture campaign.</returns>
    private static SkillQualityCampaign Campaign(SkillQualityRunRecord[] runs, SkillQualityJudgeRecord[] judges) => new(
        1, "pilot", new('A', 64), ["technical-writing"],
        [new("technical-writing", "task", HardGate: true)],
        [Scheduled(SkillQualityCondition.NoSkill), Scheduled(SkillQualityCondition.Current)],
        runs, judges);

    /// <summary>
    ///  Makes one completed synthetic candidate with explicit non-applicable execution oracle.
    /// </summary>
    /// <param name="condition">The candidate exposure condition.</param>
    /// <returns>The fixture run.</returns>
    private static SkillQualityRunRecord Run(SkillQualityCondition condition) => new(
        "technical-writing", "case", "gpt-6.1-sol", condition, 1, new('A', 64), new('C', 64),
        SkillQualityRunStatus.Completed, SkillQualityCheckState.Passed, SkillQualityCheckState.Passed,
        SkillQualityOracleOutcome.None, [], Usage: null, ElapsedMs: null);

    /// <summary>
    ///  Creates an expected candidate without predeclaring any actual safety, artifact, or oracle result.
    /// </summary>
    /// <param name="condition">The frozen exposure condition.</param>
    /// <returns>The scheduled fixture row.</returns>
    private static SkillQualityRunRecord Scheduled(SkillQualityCondition condition) => new(
        "technical-writing", "case", "gpt-6.1-sol", condition, 1, new('A', 64), ArtifactRevision: null,
        SkillQualityRunStatus.Scheduled, SkillQualityCheckState.Pending, SkillQualityCheckState.Pending,
        OracleOutcome: null, [], Usage: null, ElapsedMs: null);

    /// <summary>
    ///  Makes one independent fixture grade tied to the captured artifact revision.
    /// </summary>
    /// <param name="run">The exact candidate row.</param>
    /// <param name="model">The allowed grader identity.</param>
    /// <param name="state">The explicit fixture verdict.</param>
    /// <returns>The artifact-bound grade.</returns>
    private static SkillQualityJudgeRecord Judge(
        SkillQualityRunRecord run, SkillQualityModelId model, SkillQualityJudgeState state) => new(
        model, run.SkillId, run.CaseId, run.ModelId, run.Condition, run.Repetition,
        run.InputRevision, run.ArtifactRevision ?? throw new InvalidOperationException("Fixture artifact missing."),
        [new("task", HardGate: true, state, "Exact fixture artifact evidence.", "Controlled independent fixture judgment.")],
        Usage: null, ElapsedMs: null);
}
