// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json;

namespace SkillEvaluation;

/// <summary>
///  Reports matched skill-quality evidence with frozen denominators and no automatic qualification.
/// </summary>
public static class SkillQualityReports
{
    /// <summary>
    ///  Validates original JSON before constructing typed campaign inputs.
    /// </summary>
    /// <param name="json">The original frozen campaign and observed evidence.</param>
    /// <returns>The source-valid campaign.</returns>
    public static SkillQualityCampaign Parse(string json)
    {
        SkillQualityCampaign campaign = ContractJson.Read<SkillQualityCampaign>(
            ContractJson.Parse(json), "skill-quality-campaign.v1");

        Validate(campaign);
        return campaign;
    }

    /// <summary>
    ///  Builds a descriptive per-skill scorecard from scheduled rows and exact matching observed records.
    /// </summary>
    /// <param name="campaign">The frozen inventory and actual candidate/grade evidence.</param>
    /// <returns>The conservative JSON report with missing/disputed rows and explicit denominators.</returns>
    public static JsonElement Build(SkillQualityCampaign campaign)
    {
        _ = ContractJson.Read<SkillQualityCampaign>(
            ContractJson.Parse(ContractJson.Serialize(campaign)), "skill-quality-campaign.v1");

        Validate(campaign);
        Dictionary<string, SkillQualityRunRecord> actual = campaign.ActualRunRecords.ToDictionary(Key);
        var rows = campaign.ExpectedRunInventory.Select(expected =>
        {
            actual.TryGetValue(Key(expected), out SkillQualityRunRecord? observed);
            SkillQualityJudgeRecord[] judges = campaign.JudgeRecords.Where(judge => Key(judge) == Key(expected)).ToArray();
            SkillQualityCriterion[] criteria = campaign.Criteria.Where(item => item.SkillId == expected.SkillId).ToArray();
            var items = criteria.Select(criterion =>
            {
                SkillQualityJudgeState[] states = judges.Select(judge =>
                    judge.Judgments.Single(item => item.ItemId == criterion.ItemId).State).ToArray();

                string state = GradeState(states);
                return new { criterion.ItemId, criterion.HardGate, state };
            }).ToArray();

            string outcome = RunOutcome(observed,
                items.Where(item => item.HardGate).Select(item => item.state).ToArray());

            return new
            {
                expected.SkillId, expected.CaseId, expected.ModelId, expected.Condition, expected.Repetition,
                expected.InputRevision,
                artifactRevision = observed?.ArtifactRevision,
                status = observed?.Status,
                safety = observed?.Safety,
                infrastructure = observed?.Infrastructure,
                outcome, items,
                attempted = observed?.Status is SkillQualityRunStatus.Attempted or SkillQualityRunStatus.Completed,
                completed = observed?.Status == SkillQualityRunStatus.Completed,
                executable = observed?.OracleOutcome,
                hardChecks = observed?.HardChecks,
                grades = judges.Select(judge => new { judge.JudgeId, judge.Judgments }).ToArray(),
                usage = observed?.Usage,
                elapsedMs = observed?.ElapsedMs
            };
        }).ToArray();

        List<SkillQualityComparison> comparisons = [];
        foreach (var group in rows.GroupBy(row => (row.SkillId, row.CaseId, row.ModelId, row.Repetition)))
        {
            foreach (var pair in new[]
            {
                (Name: "current-minus-no-skill", Baseline: SkillQualityCondition.NoSkill, Candidate: SkillQualityCondition.Current),
                (Name: "revised-minus-current", Baseline: SkillQualityCondition.Current, Candidate: SkillQualityCondition.Revised)
            })
            {
                if (!group.Any(row => row.Condition == pair.Baseline) || !group.Any(row => row.Condition == pair.Candidate))
                {
                    continue;
                }

                var baseline = group.Single(row => row.Condition == pair.Baseline);
                var candidate = group.Single(row => row.Condition == pair.Candidate);
                comparisons.Add(new(group.Key.SkillId, group.Key.CaseId, group.Key.ModelId,
                    group.Key.Repetition, pair.Name, baseline.outcome, candidate.outcome,
                    ComparisonOutcome(baseline.outcome, candidate.outcome)));
            }
        }

        return ContractJson.Parse(ContractJson.Serialize(new
        {
            schemaVersion = 1, campaign.CampaignId, campaign.CriteriaRevision,
            authority = "descriptive-and-provisional; executable evidence cannot be overruled by model grades",
            scheduled = rows.Length,
            attempted = rows.Count(row => row.attempted),
            completed = rows.Count(row => row.completed),
            notRun = rows.Count(row => row.outcome == "not-run"),
            caseClusters = rows.Select(row => row.SkillId + ":" + row.CaseId).Distinct().Count(),
            bySkill = rows.GroupBy(row => (row.SkillId, row.ModelId, row.Condition)).Select(group => new
            {
                group.Key.SkillId, group.Key.ModelId, group.Key.Condition,
                scheduled = group.Count(),
                attempted = group.Count(row => row.attempted),
                completed = group.Count(row => row.completed),
                outcomes = group.GroupBy(row => row.outcome).ToDictionary(state => state.Key, state => state.Count()),
                provisionalPassRate = new
                {
                    numerator = group.Count(row => row.outcome == "provisional-pass"),
                    denominator = group.Count(),
                    value = (double)group.Count(row => row.outcome == "provisional-pass") / group.Count()
                }
            }).ToArray(),
            rows,
            comparisons,
            pairedCounts = comparisons.GroupBy(row => row.Comparison).Select(group => new
            {
                comparison = group.Key,
                scheduledPairs = group.Count(),
                decidedPairs = group.Count(row => row.Outcome != "pending"),
                pendingPairs = group.Count(row => row.Outcome == "pending"),
                wins = group.Count(row => row.Outcome == "win"),
                losses = group.Count(row => row.Outcome == "loss"),
                ties = group.Count(row => row.Outcome.StartsWith("tie", StringComparison.Ordinal))
            }).ToArray(),
            judgeAgreement = rows.SelectMany(row => row.items).Count(item =>
                item.state is "provisional-pass" or "provisional-fail"),
            judgeDisagreement = rows.SelectMany(row => row.items).Count(item => item.state == "disputed"),
            missingJudgments = rows.SelectMany(row => row.items).Count(item => item.state == "missing-judgment"),
            usage = new
            {
                generation = campaign.ActualRunRecords.Select(row => row.Usage).ToArray(),
                grading = campaign.JudgeRecords.Select(row => row.Usage).ToArray(),
                missingGenerationReceipts = campaign.ActualRunRecords.Count(row => row.Usage is null),
                missingGradingReceipts = campaign.JudgeRecords.Count(row => row.Usage is null)
            },
            usefulPassedCount = 0, usefulOutcome = "pending", calibrationStatus = "pending",
            uncertainty = "Descriptive matched cases only; repetitions and generator models share case clusters. No IID interval or qualification claim."
        }));
    }

    /// <summary>
    ///  Validates identity, exact expected criteria, source revisions, and coherent execution evidence.
    /// </summary>
    /// <param name="campaign">The typed campaign to check.</param>
    private static void Validate(SkillQualityCampaign campaign)
    {
        ArgumentNullException.ThrowIfNull(campaign);
        ProfileValidator.UniqueIds(campaign.ExpectedSkillIds, "pilot skill");
        ArtifactStore.RequireRevision(campaign.CriteriaRevision);
        if (campaign.ExpectedRunInventory.Length == 0 || campaign.Criteria.Length == 0)
        {
            throw new EvaluationContractException("A frozen nonempty inventory and grading criteria are required.");
        }

        foreach (string skill in campaign.ExpectedSkillIds)
        {
            SkillQualityCriterion[] criteria = campaign.Criteria.Where(item => item.SkillId == skill).ToArray();
            ProfileValidator.UniqueIds(criteria.Select(item => item.ItemId), "skill-quality criterion");
            if (criteria.Length == 0 || !criteria.Any(item => item.HardGate))
            {
                throw new EvaluationContractException("Each expected skill requires frozen hard criteria.");
            }
        }

        if (campaign.Criteria.Any(item => !campaign.ExpectedSkillIds.Contains(item.SkillId)))
        {
            throw new EvaluationContractException("A criterion references an unscheduled skill.");
        }

        Dictionary<string, SkillQualityRunRecord> expected = Map(campaign.ExpectedRunInventory);
        Dictionary<string, SkillQualityRunRecord> actual = Map(campaign.ActualRunRecords);
        foreach (SkillQualityRunRecord row in campaign.ExpectedRunInventory)
        {
            if (!campaign.ExpectedSkillIds.Contains(row.SkillId)
                || row.Status != SkillQualityRunStatus.Scheduled
                || row.ArtifactRevision is not null
                || row.Safety != SkillQualityCheckState.Pending
                || row.Infrastructure != SkillQualityCheckState.Pending
                || row.OracleOutcome is not null
                || row.HardChecks.Length != 0
                || row.Usage is not null
                || row.ElapsedMs is not null)
            {
                throw new EvaluationContractException("Expected inventory contains observed outcomes or an unknown skill.");
            }

            ArtifactStore.RequireRevision(row.InputRevision);
        }

        foreach (var group in campaign.ExpectedRunInventory.GroupBy(row => (row.SkillId, row.CaseId, row.ModelId, row.Repetition)))
        {
            if (group.Select(row => row.InputRevision).Distinct().Count() != 1)
            {
                throw new EvaluationContractException("Matched conditions have different task input revisions.");
            }
        }

        foreach (SkillQualityRunRecord row in campaign.ActualRunRecords)
        {
            if (!expected.TryGetValue(Key(row), out SkillQualityRunRecord? source) || source.InputRevision != row.InputRevision)
            {
                throw new EvaluationContractException("An observed run is not bound to the frozen scheduled task.");
            }

            if (row.Status == SkillQualityRunStatus.Scheduled)
            {
                throw new EvaluationContractException("Actual run records must represent attempted or completed work.");
            }

            ProfileValidator.UniqueIds(row.HardChecks.Select(check => check.Id), "executable check");
            if (row.Status == SkillQualityRunStatus.Completed && (row.ArtifactRevision is null
                || row.Infrastructure != SkillQualityCheckState.Passed))
            {
                throw new EvaluationContractException("A completed candidate requires captured artifacts and successful infrastructure.");
            }

            if (row.ArtifactRevision is null && (row.OracleOutcome is
                SkillQualityOracleOutcome.Passed or SkillQualityOracleOutcome.Failed || row.HardChecks.Length != 0))
            {
                throw new EvaluationContractException("Executable evidence requires the captured artifact revision.");
            }

            if (row.ArtifactRevision is not null)
            {
                ArtifactStore.RequireRevision(row.ArtifactRevision);
            }

            if (row.OracleOutcome == SkillQualityOracleOutcome.None && row.HardChecks.Length != 0)
            {
                throw new EvaluationContractException("Non-applicable executable checks cannot also claim observed hard-check results.");
            }
        }

        HashSet<string> judgeKeys = new(StringComparer.Ordinal);
        foreach (SkillQualityJudgeRecord judge in campaign.JudgeRecords)
        {
            if (!actual.TryGetValue(Key(judge), out SkillQualityRunRecord? row)
                || row.InputRevision != judge.InputRevision
                || row.ArtifactRevision != judge.ArtifactRevision
                || !judgeKeys.Add(Key(judge) + ":" + judge.JudgeId))
            {
                throw new EvaluationContractException("A judge duplicates or grades different/absent candidate evidence.");
            }

            SkillQualityCriterion[] criteria = campaign.Criteria.Where(item => item.SkillId == row.SkillId).ToArray();
            ProfileValidator.UniqueIds(judge.Judgments.Select(item => item.ItemId), "model grading item");
            bool complete = criteria.Select(item => item.ItemId).ToHashSet(StringComparer.Ordinal)
                .SetEquals(judge.Judgments.Select(item => item.ItemId));

            if (!complete)
            {
                throw new EvaluationContractException("A judge omitted or introduced grading criteria.");
            }

            if (judge.Judgments.Any(item => item.HardGate != criteria.Single(criterion => criterion.ItemId == item.ItemId).HardGate))
            {
                throw new EvaluationContractException("A judge changed or omitted the frozen grading criteria.");
            }
        }
    }

    /// <summary>
    ///  Makes an exact-key map, rejecting duplicate rows instead of choosing an arbitrary observed result.
    /// </summary>
    /// <param name="rows">The inventory or actual evidence rows.</param>
    /// <returns>The unique run map.</returns>
    private static Dictionary<string, SkillQualityRunRecord> Map(SkillQualityRunRecord[] rows)
    {
        Dictionary<string, SkillQualityRunRecord> result = new(StringComparer.Ordinal);
        foreach (SkillQualityRunRecord row in rows)
        {
            if (!result.TryAdd(Key(row), row))
            {
                throw new EvaluationContractException("Duplicate skill-quality run identity.");
            }
        }

        return result;
    }

    /// <summary>
    ///  Identifies one frozen task/model/condition/repetition row.
    /// </summary>
    /// <param name="row">The candidate run.</param>
    /// <returns>The exact matching key.</returns>
    private static string Key(SkillQualityRunRecord row) =>
        $"{row.SkillId}:{row.CaseId}:{row.ModelId}:{row.Condition}:{row.Repetition}";

    /// <summary>
    ///  Identifies the candidate row referenced by an independently recorded grade.
    /// </summary>
    /// <param name="row">The model grade.</param>
    /// <returns>The exact candidate key.</returns>
    private static string Key(SkillQualityJudgeRecord row) =>
        $"{row.SkillId}:{row.CaseId}:{row.ModelId}:{row.Condition}:{row.Repetition}";

    /// <summary>
    ///  Distinguishes real outcome comparisons from absent, disputed, or infrastructure-failed evidence.
    /// </summary>
    /// <param name="outcome">The per-run descriptive outcome.</param>
    /// <returns>Whether a task-quality comparison is supported.</returns>
    private static bool Decided(string outcome) =>
        outcome is "provisional-pass" or "provisional-fail" or "failed-executable";

    /// <summary>
    ///  Separates missing and conflicting grades from two agreeing provisional verdicts.
    /// </summary>
    /// <param name="states">The independent grades for one frozen item.</param>
    /// <returns>The descriptive grading state.</returns>
    private static string GradeState(SkillQualityJudgeState[] states)
    {
        if (states.Length != 2)
        {
            return "missing-judgment";
        }

        if (states.Contains(SkillQualityJudgeState.Pending))
        {
            return "pending";
        }

        if (states.Distinct().Count() > 1)
        {
            return "disputed";
        }

        return states[0] switch
        {
            SkillQualityJudgeState.Passed => "provisional-pass",
            SkillQualityJudgeState.Failed => "provisional-fail",
            _ => "pending"
        };
    }

    /// <summary>
    ///  Preserves executable failure precedence and incomplete hard judgments.
    /// </summary>
    /// <param name="run">The actual candidate evidence, absent if never run.</param>
    /// <param name="hardStates">The frozen hard-item grade states.</param>
    /// <returns>The conservative descriptive task outcome.</returns>
    private static string RunOutcome(SkillQualityRunRecord? run, string[] hardStates)
    {
        if (run is null)
        {
            return "not-run";
        }

        if (run.Infrastructure == SkillQualityCheckState.Failed)
        {
            return "infrastructure-failed";
        }

        if (run.Safety == SkillQualityCheckState.Failed)
        {
            return "safety-failed";
        }

        if (run.OracleOutcome == SkillQualityOracleOutcome.Failed
            || run.HardChecks.Any(check => check.Status == SkillQualityCheckState.Failed))
        {
            return "failed-executable";
        }

        if (run.Status != SkillQualityRunStatus.Completed
            || run.Infrastructure != SkillQualityCheckState.Passed
            || run.Safety != SkillQualityCheckState.Passed)
        {
            return "pending";
        }

        if (hardStates.Contains("disputed"))
        {
            return "disputed";
        }

        if (hardStates.Contains("provisional-fail"))
        {
            return "provisional-fail";
        }

        if (run.OracleOutcome is null or SkillQualityOracleOutcome.Pending
            || run.HardChecks.Any(check => check.Status != SkillQualityCheckState.Passed)
            || hardStates.Any(state => state is "pending" or "missing-judgment"))
        {
            return "pending";
        }

        return "provisional-pass";
    }

    /// <summary>
    ///  Computes a matched descriptive outcome only when both task verdicts are decided.
    /// </summary>
    /// <param name="baseline">The reference candidate outcome.</param>
    /// <param name="candidate">The candidate condition outcome.</param>
    /// <returns>A win, loss, tie, or pending comparison.</returns>
    private static string ComparisonOutcome(string baseline, string candidate)
    {
        if (!Decided(baseline) || !Decided(candidate))
        {
            return "pending";
        }

        if (baseline == candidate)
        {
            return "tie";
        }

        if (candidate == "provisional-pass")
        {
            return "win";
        }

        return baseline == "provisional-pass" ? "loss" : "tie-both-failed";
    }
}
