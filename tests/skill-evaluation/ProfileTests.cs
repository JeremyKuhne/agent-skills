// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace SkillEvaluation.Tests;

/// <summary>
///  Verifies scenario inventory, profile validation, and content-profile revisions.
/// </summary>
[TestClass]
public sealed class ProfileTests
{
    /// <summary>
    ///  Verifies legacy scenarios and pilot profiles retain their expected inventory.
    /// </summary>
    [TestMethod]
    public void LegacyScenariosAndPilotProfilesLoadWithoutChangingInventory()
    {
        string root = TestWorkspace.FindRepositoryRoot();
        int total = 0;
        int profiled = 0;
        foreach (string path in Directory.GetFiles(Path.Join(root, "evals", "scenarios"), "*.json"))
        {
            JsonElement[] scenarios = ProfileValidator.LoadScenarios(path);
            total += scenarios.Length;
            foreach (JsonElement scenario in scenarios)
            {
                if (ProfileValidator.Validate(scenario, root) is not null)
                {
                    profiled++;
                }
            }
        }

        Assert.AreEqual(126, total);
        Assert.AreEqual(2, profiled);
    }

    /// <summary>
    ///  Verifies supplied facts render into the prompt and changes update the profile revision.
    /// </summary>
    [TestMethod]
    public void FactsAreRenderedFromOneSourceAndChangeTheProfileRevision()
    {
        using TestWorkspace workspace = new();
        ValidatedScenario original = workspace.Scenario();
        Assert.Contains("14 tests passed on Windows.", original.Preparation.Prompt);
        Assert.DoesNotContain("{{suppliedFacts}}", original.Preparation.Prompt);
        ContentProfile changed = original.Profile with
        {
            SuppliedFacts = [
                original.Profile.SuppliedFacts[0] with { Text = "15 tests passed on Windows." },
                original.Profile.SuppliedFacts[1]
            ],
            RequiredClaims = [original.Profile.RequiredClaims[0] with
            {
                Text = "15 tests passed on Windows.",
                VerbatimTokens = ["15", "Windows"]
            }]
        };

        ValidatedScenario updated = workspace.Scenario(changed);
        Assert.AreNotEqual(original.Preparation.ProfileRevision, updated.Preparation.ProfileRevision);
        Assert.Contains("15 tests passed on Windows.", updated.Preparation.Prompt);
        Assert.DoesNotContain("14 tests passed", updated.Preparation.Prompt);
    }

    /// <summary>
    ///  Gets named mutations that make a declared content profile invalid.
    /// </summary>
    public static IEnumerable<object[]> InvalidProfiles
    {
        get
        {
            yield return ["null-profile", (Action<JsonObject>)(node => node["contentEvaluation"] = null)];
            yield return ["unknown-version", (Action<JsonObject>)(node => GetContentEvaluation(node)["schemaVersion"] = 2)];
            yield return ["null-facts", (Action<JsonObject>)(node => GetContentEvaluation(node)["suppliedFacts"] = null)];
            yield return ["empty-facts", (Action<JsonObject>)(node =>
                GetContentEvaluation(node)["suppliedFacts"] = new JsonArray())];

            yield return ["numeric-mode", (Action<JsonObject>)(node =>
            {
                JsonNode? ledger = GetContentEvaluation(node)["ledger"];
                Assert.IsNotNull(ledger);
                ledger["mode"] = 0;
            })];

            yield return ["unknown-field", (Action<JsonObject>)(node => GetContentEvaluation(node)["surprise"] = true)];
            yield return ["duplicate-target", (Action<JsonObject>)(node =>
            {
                JsonNode? targets = GetContentEvaluation(node)["artifactTargets"];
                Assert.IsNotNull(targets);
                targets.AsArray().Add(GetFirstProfileItem(node, "artifactTargets").DeepClone());
            })];

            yield return ["unknown-fact", (Action<JsonObject>)(node =>
                GetFirstProfileItem(node, "requiredClaims")["factRefs"] = new JsonArray("missing"))];

            yield return ["unknown-target", (Action<JsonObject>)(node =>
                GetFirstProfileItem(node, "literalChecks")["targetId"] = "missing")];

            yield return ["stale-literal", (Action<JsonObject>)(node =>
                GetFirstProfileItem(node, "suppliedFacts")["text"] = "15 tests passed on Windows.")];

            yield return ["stale-prompt", (Action<JsonObject>)(node =>
                node["prompt"] = "Use the old facts: 14 tests passed on Windows.")];

            yield return ["repeated-placeholder", (Action<JsonObject>)(node =>
                node["prompt"] = "{{suppliedFacts}} {{suppliedFacts}}")];

            yield return ["escaping-file", (Action<JsonObject>)(node =>
            {
                JsonObject target = GetFirstProfileItem(node, "artifactTargets");
                target["source"] = "file";
                target["path"] = "../outside.md";
            })];
        }
    }

    /// <summary>
    ///  Verifies each invalid declared-profile mutation is rejected.
    /// </summary>
    /// <param name="name">The mutation's test-data name.</param>
    /// <param name="mutate">The mutation to apply to a valid scenario.</param>
    [TestMethod]
    [DynamicData(nameof(InvalidProfiles))]
    public void InvalidDeclaredProfileIsRejected(string name, Action<JsonObject> mutate)
    {
        _ = name;
        using TestWorkspace workspace = new();
        _ = workspace.Scenario();
        JsonNode? document = JsonNode.Parse(File.ReadAllText(workspace.ScenarioPath));
        Assert.IsNotNull(document);
        JsonNode? scenarios = document["scenarios"];
        Assert.IsNotNull(scenarios);
        JsonNode? firstScenario = scenarios[0];
        Assert.IsNotNull(firstScenario);
        JsonObject scenario = firstScenario.DeepClone().AsObject();

        mutate(scenario);
        Assert.ThrowsExactly<EvaluationContractException>(() =>
            ProfileValidator.Validate(ContractJson.Parse(scenario.ToJsonString()), workspace.Root));
    }

    /// <summary>
    ///  Verifies duplicate JSON properties are rejected before they can be collapsed.
    /// </summary>
    [TestMethod]
    public void DuplicateJsonPropertiesAreNotCollapsedIntoValidInput()
    {
        Assert.ThrowsExactly<EvaluationContractException>(() =>
            ContractJson.Parse("""{"mode": "off", "mode": "required"}"""));
    }

    /// <summary>
    ///  Verifies a legacy scenario without a profile remains unconfigured.
    /// </summary>
    [TestMethod]
    public void MissingProfileIsNotConfiguredRatherThanPassed()
    {
        JsonElement scenario = ContractJson.Parse("""{"id":"legacy","prompt":"Legacy prompt."}""");
        Assert.IsNull(ProfileValidator.Validate(scenario, TestWorkspace.FindRepositoryRoot()));
    }

    /// <summary>
    ///  Verifies a mismatched rubric revision is rejected during profile validation.
    /// </summary>
    [TestMethod]
    public void RubricFileChangeIsRejectedBeforePreparingTheCandidate()
    {
        string root = TestWorkspace.FindRepositoryRoot();
        JsonElement original = ProfileValidator.LoadScenarios(
            Path.Join(root, "evals", "scenarios", "technical-writing.json"))
            .Single(value => value.GetProperty("id").GetString() == "technical-writing-artifact-pull-request");

        JsonNode? originalNode = JsonNode.Parse(original.GetRawText());
        Assert.IsNotNull(originalNode);
        JsonObject mutated = originalNode.AsObject();
        GetFirstProfileItem(mutated, "rubricRefs")["revision"] = TestWorkspace.ScenarioRevision;
        Assert.ThrowsExactly<EvaluationContractException>(() =>
            ProfileValidator.Validate(ContractJson.Parse(mutated.ToJsonString()), root));
    }

    private static JsonObject GetContentEvaluation(JsonObject scenario)
    {
        JsonNode? profile = scenario["contentEvaluation"];
        Assert.IsNotNull(profile);
        return profile.AsObject();
    }

    private static JsonObject GetFirstProfileItem(JsonObject scenario, string propertyName)
    {
        JsonNode? items = GetContentEvaluation(scenario)[propertyName];
        Assert.IsNotNull(items);
        JsonNode? item = items.AsArray()[0];
        Assert.IsNotNull(item);
        return item.AsObject();
    }
}
