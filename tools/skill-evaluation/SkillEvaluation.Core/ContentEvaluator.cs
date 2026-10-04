// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  Evaluates deterministic content checks while leaving claims and rubrics pending qualified judgment.
/// </summary>
public static class ContentEvaluator
{
    /// <summary>
    ///  Gets the revision identifying the evaluation engine, dependency assemblies, and runtime.
    /// </summary>
    public static string EngineRevision { get; } = ContractJson.Revision(new
    {
        engine = "deterministic-content/v1",
        core = ContractJson.HashFile(typeof(ContentEvaluator).Assembly.Location),
        markdown = ContractJson.HashFile(typeof(Markdig.Markdown).Assembly.Location),
        schema = ContractJson.HashFile(typeof(Json.Schema.JsonSchema).Assembly.Location),
        runtime = Environment.Version.ToString()
    });

    /// <summary>
    ///  Evaluates declared artifacts for literal and ledger consistency without inferring semantic success.
    /// </summary>
    /// <param name="scenario">The validated scenario and its content requirements.</param>
    /// <param name="artifacts">Artifact text indexed by target identifier.</param>
    /// <returns>Deterministic checks, aggregate literal status, and a failed or pending useful outcome.</returns>
    public static ArtifactEvaluation Evaluate(
        ValidatedScenario scenario, IReadOnlyDictionary<string, string> artifacts)
    {
        List<CheckResult> checks = [];
        foreach (ArtifactTarget target in scenario.Profile.ArtifactTargets)
        {
            if (!artifacts.TryGetValue(target.Id, out string? text))
            {
                throw new EvaluationContractException($"Artifact '{target.Id}' is missing.");
            }

            checks.AddRange(LiteralEvaluator.Evaluate(text, target.Id, scenario.Profile));
        }

        if (scenario.Profile.Ledger.Mode != LedgerMode.Off)
        {
            string target = scenario.Profile.Ledger.TargetId
                ?? throw new EvaluationContractException("An enabled ledger requires an artifact target.");

            checks.Add(LiteralEvaluator.CheckLedger(artifacts[target], target, scenario.Profile));
        }

        foreach (RequiredClaim claim in scenario.Profile.RequiredClaims)
        {
            checks.Add(new(claim.Id, claim.TargetId, CheckDimension.RequiredClaim, QualityState.Pending,
                HardGate: true, $"Claim support is unassessed: {claim.Text}", FactRefs: claim.FactRefs));
        }

        foreach (ForbiddenClaim claim in scenario.Profile.ForbiddenClaims)
        {
            checks.Add(new(claim.Id, claim.TargetId, CheckDimension.ForbiddenClaim, QualityState.Pending,
                HardGate: true, $"Forbidden claim is unassessed: {claim.Text}", FactRefs: claim.FactRefs));
        }

        foreach (RubricItem item in scenario.RubricItems)
        {
            checks.Add(new(item.Id, "all-artifacts", CheckDimension.Rubric,
                QualityState.Pending, item.HardGate,
                $"Rubric requires qualified judgment: {item.PassCondition}"));
        }

        CheckResult[] literals = checks.Where(value => value.Dimension == CheckDimension.Literal).ToArray();
        QualityState literalState = literals.Length == 0 ? QualityState.NotApplicable
            : literals.Any(value => value.State == QualityState.Failed) ? QualityState.Failed
                : QualityState.Passed;

        return new(literalState,
            checks.Any(value => value.HardGate && value.State == QualityState.Failed)
                ? QualityState.Failed : QualityState.Pending, checks.ToArray());
    }

    /// <summary>
    ///  Verifies captured evidence and creates a schema-validated deterministic semantic record.
    /// </summary>
    /// <param name="scenario">The validated scenario used for the current evaluation.</param>
    /// <param name="runDirectory">The directory owning the captured run evidence.</param>
    /// <param name="runNumber">The expected source run number.</param>
    /// <param name="scenarioRevision">The expected source scenario revision.</param>
    /// <param name="outputRevision">The expected captured output revision.</param>
    /// <param name="manifestRevision">The expected artifact-manifest revision.</param>
    /// <param name="sourceProfileRevision">The captured profile revision, or null to use the current profile.</param>
    /// <param name="sourceInputRevision">The captured input revision, or null to use the current input.</param>
    /// <returns>A revisioned record whose semantic judgment remains pending.</returns>
    public static SemanticRecord EvaluateCaptured(
        ValidatedScenario scenario, string runDirectory, int runNumber,
        string scenarioRevision, string outputRevision, string manifestRevision,
        string? sourceProfileRevision = null, string? sourceInputRevision = null)
    {
        string sourceRevision = sourceProfileRevision ?? scenario.Preparation.ProfileRevision;
        string inputRevision = sourceInputRevision ?? scenario.Preparation.InputRevision;
        Dictionary<string, string> artifacts = ArtifactStore.ReadVerified(
            scenario, runDirectory, runNumber, scenarioRevision, outputRevision, manifestRevision,
            sourceRevision, inputRevision);

        ArtifactEvaluation evaluation = Evaluate(scenario, artifacts);
        SemanticRecord record = new(1, "semantic", scenario.Id, runNumber, scenario.Preparation.ProfileRevision,
            sourceRevision, scenario.Preparation.InputRevision,
            ContractJson.Revision(new { EngineRevision, scenario.Preparation.ProfileRevision }),
            outputRevision, manifestRevision, evaluation.LiteralStatus,
            QualityState.Pending, evaluation.UsefulOutcome, evaluation.Checks);

        return ContractJson.Read<SemanticRecord>(
            ContractJson.Parse(ContractJson.Serialize(record)), "semantic-record.v1");
    }
}
