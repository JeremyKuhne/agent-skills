// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace SkillEvaluation.Tests;

/// <summary>
///  Verifies literal artifact checks and grounding-ledger validation.
/// </summary>
[TestClass]
public sealed class LiteralTests
{
    private const string ValidBody = "## Summary\n\nPreserve the body.\n\n## Validation\n\nWindows: 14 tests passed.\n";

    /// <summary>
    ///  Verifies passing literal checks leave usefulness and claim support pending.
    /// </summary>
    [TestMethod]
    public void ValidLiteralArtifactRemainsPendingForUsefulness()
    {
        using TestWorkspace workspace = new();
        ValidatedScenario scenario = workspace.Scenario();
        ArtifactEvaluation result = ContentEvaluator.Evaluate(scenario,
            new Dictionary<string, string> { ["body"] = ValidBody });

        Assert.AreEqual(QualityState.Passed, result.LiteralStatus);
        Assert.AreEqual(QualityState.Pending, result.UsefulOutcome);
        Assert.IsTrue(result.Checks.Where(value => value.Dimension is
            CheckDimension.RequiredClaim or CheckDimension.ForbiddenClaim)
            .All(value => value.State == QualityState.Pending));
    }

    /// <summary>
    ///  Verifies broken literal contracts fail both literal status and useful outcome.
    /// </summary>
    /// <param name="text">The artifact text that violates the literal contract.</param>
    [TestMethod]
    [DataRow("```markdown\n## Summary\n## Validation\nWindows: 14 tests passed.\n```\n")]
    [DataRow("## Summary\n\nHard-wrapped\nparagraph.\n\n## Validation\n\nWindows: 14 tests passed.\n")]
    [DataRow("## Summary\n\nPreserve the body.\n\n## Validation\n\nWindows: 15 tests passed.\n")]
    [DataRow("Done.")]
    public void BrokenLiteralContractCannotPass(string text)
    {
        using TestWorkspace workspace = new();
        ArtifactEvaluation result = ContentEvaluator.Evaluate(workspace.Scenario(),
            new Dictionary<string, string> { ["body"] = text });

        Assert.AreEqual(QualityState.Failed, result.LiteralStatus);
        Assert.AreEqual(QualityState.Failed, result.UsefulOutcome);
    }

    /// <summary>
    ///  Verifies emphasis and CRLF preserve literal labels while block quotes do not.
    /// </summary>
    [TestMethod]
    public void MarkdownEmphasisAndCrLfDoNotBreakLiteralLabels()
    {
        ContentProfile profile = TestWorkspace.Profile() with
        {
            LiteralChecks = [new("force", "body", LiteralKind.StartsWith, "Required:")],
            RequiredClaims = []
        };

        CheckResult[] results = LiteralEvaluator.Evaluate(
            "**Required:** Correct the ordering.\r\n", "body", profile);

        Assert.AreEqual(QualityState.Passed, results[0].State);
        var span = results[0].Span;
        Assert.IsNotNull(span);
        Assert.AreEqual(1, span.Line);
        Assert.AreEqual(QualityState.Failed, LiteralEvaluator.Evaluate(
            "> Required: Correct the ordering.\n", "body", profile)[0].State);
    }

    /// <summary>
    ///  Verifies a consistent ledger does not qualify the artifact's usefulness.
    /// </summary>
    [TestMethod]
    public void ConsistentLedgerDoesNotAttestProseSupport()
    {
        using TestWorkspace workspace = new();
        ContentProfile profile = TestWorkspace.Profile() with
        {
            Ledger = new(LedgerMode.Required, "body", "grounding-ledger/v1")
        };

        string text = ValidBody + """

            ```json
            {"schemaVersion":1,"entries":[{"factId":"compatibility","state":"unknown","kind":"fact"}]}
            ```
            """;

        ArtifactEvaluation result = ContentEvaluator.Evaluate(workspace.Scenario(profile),
            new Dictionary<string, string> { ["body"] = text });

        Assert.AreEqual(QualityState.Passed,
            result.Checks.Single(value => value.Dimension == CheckDimension.Ledger).State);

        Assert.AreEqual(QualityState.Pending, result.UsefulOutcome);
    }

    /// <summary>
    ///  Verifies invalid ledgers produce an explicit content failure with a diagnostic detail.
    /// </summary>
    /// <param name="text">The invalid ledger text.</param>
    [TestMethod]
    [DataRow("""{"schemaVersion":1,"entries":[]}""")]
    [DataRow("""{"schemaVersion":1,"entries":[{"factId":"compatibility","state":"verified","kind":"fact"}]}""")]
    [DataRow("""{"schemaVersion":1,"entries":[{"factId":"missing","state":"unknown","kind":"fact"}]}""")]
    [DataRow("""{"schemaVersion":1,"entries":[{"factId":"compatibility","state":"unknown","kind":"fact"},{"factId":"compatibility","state":"unknown","kind":"fact"}]}""")]
    [DataRow("""{"schemaVersion":1,"entries":null}""")]
    [DataRow("not JSON")]
    public void InvalidLedgerIsAnExplicitContentFailure(string text)
    {
        ContentProfile profile = TestWorkspace.Profile() with
        {
            Ledger = new(LedgerMode.Required, "body", "grounding-ledger/v1")
        };

        CheckResult result = LiteralEvaluator.CheckLedger(text, "body", profile);
        Assert.AreEqual(QualityState.Failed, result.State);
        Assert.IsFalse(string.IsNullOrWhiteSpace(result.Detail));
    }
}
