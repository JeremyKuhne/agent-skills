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
    ///  Verifies each named executable hard check needs a real pass, not an unassessed or inapplicable state.
    /// </summary>
    /// <param name="state">The observed named hard-check state.</param>
    /// <param name="outcome">The expected descriptive task outcome.</param>
    /// <param name="comparison">The expected matched comparison against a passing baseline.</param>
    [TestMethod]
    [DataRow(SkillQualityCheckState.Passed, "provisional-pass", "tie")]
    [DataRow(SkillQualityCheckState.Failed, "failed-executable", "loss")]
    [DataRow(SkillQualityCheckState.Pending, "pending", "pending")]
    [DataRow(SkillQualityCheckState.NotApplicable, "pending", "pending")]
    public void BuildRequiresEveryExecutableHardCheckToPass(
        SkillQualityCheckState state, string outcome, string comparison)
    {
        SkillQualityRunRecord baseline = Run(SkillQualityCondition.NoSkill);
        SkillQualityRunRecord current = Run(SkillQualityCondition.Current) with
        {
            OracleOutcome = SkillQualityOracleOutcome.Passed,
            HardChecks = [new("compile", "Compiler", state,
                "Controlled executable check state.", "The named hard check must pass.")]
        };

        SkillQualityJudgeRecord[] judges =
        [
            Judge(baseline, SkillQualityModelId.Gpt61Sol, SkillQualityJudgeState.Passed),
            Judge(baseline, SkillQualityModelId.Gpt6Luna, SkillQualityJudgeState.Passed),
            Judge(current, SkillQualityModelId.Gpt61Sol, SkillQualityJudgeState.Passed),
            Judge(current, SkillQualityModelId.Gpt6Luna, SkillQualityJudgeState.Passed)
        ];

        JsonElement report = SkillQualityReports.Build(Campaign([baseline, current], judges));
        Assert.AreEqual(outcome, report.GetProperty("rows")[1].GetProperty("outcome").GetString());
        Assert.AreEqual(comparison, report.GetProperty("comparisons")[0].GetProperty("outcome").GetString());
    }

    /// <summary>
    ///  Verifies work that never started belongs only in expected inventory, even when gates claim results.
    /// </summary>
    /// <param name="oracle">The misleading scheduled row's declared oracle result.</param>
    [TestMethod]
    [DataRow(SkillQualityOracleOutcome.None)]
    [DataRow(SkillQualityOracleOutcome.Passed)]
    [DataRow(SkillQualityOracleOutcome.Failed)]
    [DataRow(SkillQualityOracleOutcome.Pending)]
    public void ParseRejectsScheduledActualRows(SkillQualityOracleOutcome oracle)
    {
        SkillQualityRunRecord current = Run(SkillQualityCondition.Current) with
        {
            Status = SkillQualityRunStatus.Scheduled,
            OracleOutcome = oracle
        };

        SkillQualityCampaign campaign = Campaign([current], []);
        string json = ContractJson.Serialize(campaign);
        Assert.ThrowsExactly<EvaluationContractException>(() => SkillQualityReports.Parse(json));
        Assert.ThrowsExactly<EvaluationContractException>(() => SkillQualityReports.Build(campaign));
    }

    /// <summary>
    ///  Verifies attempted executable observations cannot affect verdicts without a captured artifact identity.
    /// </summary>
    /// <param name="oracle">The attempted run's oracle result or absence.</param>
    /// <param name="check">The named hard-check observation, when present.</param>
    [TestMethod]
    [DataRow(SkillQualityOracleOutcome.Passed, null)]
    [DataRow(SkillQualityOracleOutcome.Failed, null)]
    [DataRow(null, SkillQualityCheckState.Passed)]
    [DataRow(null, SkillQualityCheckState.Failed)]
    [DataRow(null, SkillQualityCheckState.Pending)]
    [DataRow(null, SkillQualityCheckState.NotApplicable)]
    [DataRow(SkillQualityOracleOutcome.Pending, SkillQualityCheckState.Passed)]
    public void ParseRejectsUnboundExecutableEvidence(
        SkillQualityOracleOutcome? oracle, SkillQualityCheckState? check)
    {
        SkillQualityRunRecord current = Run(SkillQualityCondition.Current) with
        {
            Status = SkillQualityRunStatus.Attempted,
            ArtifactRevision = null,
            OracleOutcome = oracle,
            HardChecks = check is SkillQualityCheckState state
                ? [new("compile", "Compiler", state, "An observed check.", "Must hold for the executed artifact.")]
                : []
        };

        SkillQualityCampaign unbound = Campaign([current], []);
        Assert.ThrowsExactly<EvaluationContractException>(() => SkillQualityReports.Parse(ContractJson.Serialize(unbound)));
        Assert.ThrowsExactly<EvaluationContractException>(() => SkillQualityReports.Build(unbound));
        SkillQualityCampaign bound = Campaign([current with { ArtifactRevision = new('C', 64) }], []);
        Assert.IsNotNull(SkillQualityReports.Parse(ContractJson.Serialize(bound)));
        JsonElement report = SkillQualityReports.Build(bound);
        Assert.AreEqual(1, report.GetProperty("attempted").GetInt32());
        Assert.AreEqual(0, report.GetProperty("completed").GetInt32());
    }

    /// <summary>
    ///  Verifies absent executable observations remain valid and pending before an artifact is captured.
    /// </summary>
    /// <param name="oracle">The unexecuted oracle declaration.</param>
    [TestMethod]
    [DataRow(stringArrayData: null)]
    [DataRow(SkillQualityOracleOutcome.Pending)]
    [DataRow(SkillQualityOracleOutcome.None)]
    public void BuildPreservesArtifactlessAttemptsWithoutExecutableEvidence(SkillQualityOracleOutcome? oracle)
    {
        SkillQualityRunRecord current = Run(SkillQualityCondition.Current) with
        {
            Status = SkillQualityRunStatus.Attempted,
            ArtifactRevision = null,
            OracleOutcome = oracle
        };

        SkillQualityCampaign campaign = Campaign([current], []);
        Assert.IsNotNull(SkillQualityReports.Parse(ContractJson.Serialize(campaign)));
        JsonElement report = SkillQualityReports.Build(campaign);
        Assert.AreEqual("pending", report.GetProperty("rows")[1].GetProperty("outcome").GetString());
        Assert.AreEqual(1, report.GetProperty("notRun").GetInt32());
        Assert.AreEqual(1, report.GetProperty("attempted").GetInt32());
        Assert.AreEqual(0, report.GetProperty("completed").GetInt32());
    }

    /// <summary>
    ///  Verifies an incomplete judgment is pending rather than a conflicting terminal verdict.
    /// </summary>
    /// <param name="first">The first judge's state.</param>
    /// <param name="second">The second judge's state.</param>
    [TestMethod]
    [DataRow(SkillQualityJudgeState.Pending, SkillQualityJudgeState.Passed)]
    [DataRow(SkillQualityJudgeState.Passed, SkillQualityJudgeState.Pending)]
    [DataRow(SkillQualityJudgeState.Pending, SkillQualityJudgeState.Failed)]
    [DataRow(SkillQualityJudgeState.Failed, SkillQualityJudgeState.Pending)]
    [DataRow(SkillQualityJudgeState.Pending, SkillQualityJudgeState.Pending)]
    public void BuildPendingJudgmentsDoNotCountAsDisagreement(
        SkillQualityJudgeState first, SkillQualityJudgeState second)
    {
        SkillQualityRunRecord current = Run(SkillQualityCondition.Current);
        JsonElement report = SkillQualityReports.Build(Campaign([current],
            [Judge(current, SkillQualityModelId.Gpt61Sol, first),
                Judge(current, SkillQualityModelId.Gpt6Luna, second)]));

        JsonElement row = report.GetProperty("rows")[1];
        Assert.AreEqual("pending", row.GetProperty("items")[0].GetProperty("state").GetString());
        Assert.AreEqual("pending", row.GetProperty("outcome").GetString());
        Assert.AreEqual(0, report.GetProperty("judgeDisagreement").GetInt32());
        Assert.AreEqual(0, report.GetProperty("judgeAgreement").GetInt32());
        Assert.AreEqual(1, report.GetProperty("missingJudgments").GetInt32());
        Assert.AreEqual("pending", report.GetProperty("comparisons")[0].GetProperty("outcome").GetString());
    }

    /// <summary>
    ///  Verifies invalid actual evidence fails through the public command without producing a scorecard.
    /// </summary>
    [TestMethod]
    public void QualityReportCliRejectsScheduledAndUnboundExecutableEvidence()
    {
        using TestWorkspace workspace = new();
        string path = Path.Join(workspace.Root, "campaign.json");
        SkillQualityRunRecord scheduled = Run(SkillQualityCondition.Current) with
        {
            Status = SkillQualityRunStatus.Scheduled
        };

        SkillQualityRunRecord unbound = Run(SkillQualityCondition.Current) with
        {
            Status = SkillQualityRunStatus.Attempted,
            ArtifactRevision = null,
            OracleOutcome = SkillQualityOracleOutcome.Failed
        };

        foreach (SkillQualityRunRecord row in new[] { scheduled, unbound })
        {
            File.WriteAllText(path, ContractJson.Serialize(Campaign([row], [])));
            StringWriter output = new();
            StringWriter error = new();
            Assert.AreEqual(3, Program.Run(["quality-report", "--campaign", path], output, error));
            Assert.AreEqual("", output.ToString());
            Assert.Contains("Skill evaluation failed:", error.ToString());
        }
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
