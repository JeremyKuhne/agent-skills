// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json;
using Touki.Text;

namespace SkillEvaluation;

/// <summary>
///  Validates scenario content contracts and prepares revisioned prompts from supplied facts and rubrics.
/// </summary>
public static class ProfileValidator
{
    /// <summary>
    ///  The single placeholder replaced with the scenario's supplied-fact inventory.
    /// </summary>
    public const string FactPlaceholder = "{{suppliedFacts}}";

    /// <summary>
    ///  Loads a nonempty version-one scenario document and requires unique scenario identifiers.
    /// </summary>
    /// <param name="path">The JSON scenario-document path.</param>
    /// <returns>The scenario objects from the validated document.</returns>
    public static JsonElement[] LoadScenarios(string path)
    {
        JsonElement document = ContractJson.Parse(File.ReadAllText(path));
        if (document.ValueKind != JsonValueKind.Object
            || !document.TryGetProperty("schemaVersion", out JsonElement version)
            || version.ValueKind != JsonValueKind.Number
            || !version.TryGetInt32(out int number)
            || number != 1
            || !document.TryGetProperty("scenarios", out JsonElement scenarios)
            || scenarios.ValueKind != JsonValueKind.Array
            || scenarios.GetArrayLength() == 0)
        {
            throw new EvaluationContractException("A nonempty schema-version-1 scenario document is required.");
        }

        JsonElement[] result = scenarios.EnumerateArray().Select(value => value.Clone()).ToArray();
        UniqueIds(result.Select(value => RequiredString(value, "id")), "scenario");
        return result;
    }

    /// <summary>
    ///  Validates a scenario's content profile, references, and rubric evidence, then renders its prompt.
    /// </summary>
    /// <param name="scenario">The scenario object to validate.</param>
    /// <param name="repoRoot">The directory owning declared artifact, rubric, and rubric-source paths.</param>
    /// <returns>The validated profile and preparation, or null when content evaluation is not declared.</returns>
    public static ValidatedScenario? Validate(JsonElement scenario, string repoRoot)
    {
        string id = RequiredString(scenario, "id");
        UniqueIds([id], "scenario");
        if (!scenario.TryGetProperty("contentEvaluation", out JsonElement profileJson))
        {
            return null;
        }

        ContentProfile profile = ContractJson.Read<ContentProfile>(profileJson, "content-profile.v1");
        UniqueIds(profile.ArtifactTargets.Select(value => value.Id), "artifact");
        UniqueIds(profile.SuppliedFacts.Select(value => value.Id), "fact");
        UniqueIds(profile.RequiredClaims.Select(value => value.Id)
            .Concat(profile.ForbiddenClaims.Select(value => value.Id))
            .Concat(profile.LiteralChecks.Select(value => value.Id)), "check");

        HashSet<string> targetIds = profile.ArtifactTargets.Select(value => value.Id)
            .ToHashSet(StringComparer.Ordinal);

        Dictionary<string, SuppliedFact> facts = profile.SuppliedFacts.ToDictionary(
            value => value.Id, StringComparer.Ordinal);

        HashSet<string> paths = new(OperatingSystem.IsWindows()
            ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal);

        if (profile.ArtifactTargets.Count(value => value.Source == ArtifactSource.LastMessage) > 1)
        {
            throw new EvaluationContractException("The terminal assistant message may be declared only once.");
        }

        foreach (ArtifactTarget target in profile.ArtifactTargets)
        {
            if (target.Source == ArtifactSource.File)
            {
                string path = target.Path
                    ?? throw new EvaluationContractException($"Artifact '{target.Id}' requires a file path.");

                string resolved = OwnedPaths.Resolve(repoRoot, path, requireFile: false);
                if (!paths.Add(resolved))
                {
                    throw new EvaluationContractException($"Duplicate artifact file '{target.Path}'.");
                }
            }
        }

        foreach (RequiredClaim claim in profile.RequiredClaims)
        {
            RequireTarget(targetIds, claim.TargetId);
            ValidateFactRefs(facts, claim.FactRefs);
            string sourceText = string.Join("\n", claim.FactRefs.Select(reference => facts[reference].Text));
            if (claim.VerbatimTokens.Any(token => !sourceText.Contains(token, StringComparison.Ordinal)))
            {
                throw new EvaluationContractException($"Claim '{claim.Id}' has a literal not present in its supplied facts.");
            }
        }

        foreach (ForbiddenClaim claim in profile.ForbiddenClaims)
        {
            RequireTarget(targetIds, claim.TargetId);
            ValidateFactRefs(facts, claim.FactRefs);
        }

        foreach (LiteralCheck check in profile.LiteralChecks)
        {
            RequireTarget(targetIds, check.TargetId);
        }

        if (profile.Ledger.Mode != LedgerMode.Off)
        {
            string target = profile.Ledger.TargetId
                ?? throw new EvaluationContractException("An enabled ledger requires an artifact target.");

            RequireTarget(targetIds, target);
        }

        List<RubricItem> rubricItems = [];
        HashSet<string> rubricPaths = new(StringComparer.Ordinal);
        foreach (RubricReference reference in profile.RubricRefs)
        {
            if (!rubricPaths.Add(reference.Path))
            {
                throw new EvaluationContractException($"Duplicate rubric reference '{reference.Path}'.");
            }

            string rubricPath = OwnedPaths.Resolve(repoRoot, reference.Path);
            string rubricText = File.ReadAllText(rubricPath);
            if (!ContractJson.HashText(rubricText).Equals(reference.Revision, StringComparison.Ordinal))
            {
                throw new EvaluationContractException($"Rubric revision changed: '{reference.Path}'.");
            }

            RubricDocument rubric = ContractJson.Read<RubricDocument>(
                ContractJson.Parse(rubricText), "rubric.v1");

            UniqueIds(rubric.Items.Select(value => value.Id), "rubric item");
            UniqueIds(reference.ItemIds, "referenced rubric item");
            foreach (string itemId in reference.ItemIds)
            {
                RubricItem item = rubric.Items.SingleOrDefault(value => value.Id == itemId)
                    ?? throw new EvaluationContractException($"Unknown rubric item '{itemId}'.");

                if (!item.ArtifactKinds.Contains(profile.ArtifactKind))
                {
                    throw new EvaluationContractException($"Rubric item '{itemId}' does not apply to this artifact kind.");
                }

                foreach (RubricSource source in item.Sources)
                {
                    string sourceText = File.ReadAllText(OwnedPaths.Resolve(repoRoot, source.Path))
                        .Replace("\r\n", "\n", StringComparison.Ordinal);

                    if (ContractJson.HashText(sourceText) != source.Revision
                        || !sourceText.Contains(source.Quote, StringComparison.Ordinal))
                    {
                        throw new EvaluationContractException($"Rubric source changed or quote is stale: '{source.Path}'.");
                    }
                }

                rubricItems.Add(item);
            }
        }

        UniqueIds(rubricItems.Select(value => value.Id), "selected rubric item");

        string prompt = RequiredString(scenario, "prompt");
        int placeholder = prompt.IndexOf(FactPlaceholder, StringComparison.Ordinal);
        if (placeholder < 0
            || prompt.IndexOf(FactPlaceholder, placeholder + FactPlaceholder.Length, StringComparison.Ordinal) >= 0)
        {
            throw new EvaluationContractException("Profiled prompts must contain exactly one {{suppliedFacts}} placeholder.");
        }

        using ValueStringBuilder factText = new(stackalloc char[256]);
        foreach (SuppliedFact fact in profile.SuppliedFacts)
        {
            factText.AppendLine($"- {fact.Id} [{fact.State.ToString().ToLowerInvariant()}, {fact.Kind.ToString().ToLowerInvariant()}]: {fact.Text}");
        }

        string renderedPrompt = prompt.Replace(FactPlaceholder,
            factText.ToString().TrimEnd().Replace("\r\n", "\n", StringComparison.Ordinal),
            StringComparison.Ordinal);

        string revision = ContractJson.Revision(new { profile, rubricItems });
        string inputRevision = ContractJson.Revision(new
        {
            prompt, profile.ArtifactKind, profile.ArtifactTargets, profile.SuppliedFacts, profile.Ledger
        });

        return new(id, profile, rubricItems.ToArray(), new(id, renderedPrompt, revision, inputRevision));
    }

    /// <summary>
    ///  Requires unique references to known supplied facts.
    /// </summary>
    /// <param name="facts">The supplied facts indexed by identifier.</param>
    /// <param name="references">The referenced fact identifiers.</param>
    private static void ValidateFactRefs(Dictionary<string, SuppliedFact> facts, string[] references)
    {
        UniqueIds(references, "fact reference");
        foreach (string reference in references)
        {
            if (!facts.ContainsKey(reference))
            {
                throw new EvaluationContractException($"Unknown fact reference '{reference}'.");
            }
        }
    }

    /// <summary>
    ///  Requires a declared artifact target identifier.
    /// </summary>
    /// <param name="targets">The declared target identifiers.</param>
    /// <param name="id">The target identifier to validate.</param>
    private static void RequireTarget(HashSet<string> targets, string id)
    {
        if (!targets.Contains(id))
        {
            throw new EvaluationContractException($"Unknown artifact target '{id}'.");
        }
    }

    /// <summary>
    ///  Reads a required nonempty string property from a JSON object.
    /// </summary>
    /// <param name="element">The JSON object containing the property.</param>
    /// <param name="property">The property name.</param>
    /// <returns>The nonempty property value.</returns>
    public static string RequiredString(JsonElement element, string property)
    {
        if (element.ValueKind != JsonValueKind.Object
            || !element.TryGetProperty(property, out JsonElement value)
            || value.ValueKind != JsonValueKind.String
            || value.GetString() is not string text
            || string.IsNullOrWhiteSpace(text))
        {
            throw new EvaluationContractException($"A nonempty string '{property}' is required.");
        }

        return text;
    }

    /// <summary>
    ///  Requires unique identifiers made from lowercase ASCII letters and digits in nonempty hyphenated segments.
    /// </summary>
    /// <param name="ids">The identifiers to validate.</param>
    /// <param name="kind">The identifier category used in validation errors.</param>
    internal static void UniqueIds(IEnumerable<string> ids, string kind)
    {
        HashSet<string> seen = new(StringComparer.Ordinal);
        foreach (string id in ids)
        {
            if (string.IsNullOrWhiteSpace(id)
                || id.Split('-').Any(segment => segment.Length == 0
                    || segment.Any(character => !char.IsAsciiDigit(character) && character is not (>= 'a' and <= 'z')))
                || !seen.Add(id))
            {
                throw new EvaluationContractException($"Invalid or duplicate {kind} ID '{id}'.");
            }
        }
    }
}
