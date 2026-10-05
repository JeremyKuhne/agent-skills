// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation.Onnx;

/// <summary>
///  Binds the sole Windows-spiked preprocessing profile to its upstream/export/license and asset closure.
/// </summary>
public static class PinnedNliProfile
{
    /// <summary>
    ///  Compares the actual package informational version, not a deliberately stable assembly binding version.
    /// </summary>
    /// <param name="informationalVersion">The loaded tokenizer assembly's package/product identity.</param>
    /// <param name="expected">The exact package version pinned in the manifest.</param>
    public static void RequireTokenizerPackageVersion(string? informationalVersion, string expected)
    {
        if (string.IsNullOrWhiteSpace(informationalVersion)
            || informationalVersion.Split('+', 2)[0] != expected)
        {
            throw new EvaluationContractException("The tokenizer package identity differs from the pinned version.");
        }
    }

    /// <summary>
    ///  Reads the bundled manifest containing public source metadata, not model weights.
    /// </summary>
    /// <returns>The strict supported profile declaration.</returns>
    public static GroundingAssetManifest Read()
    {
        using Stream stream = typeof(PinnedNliProfile).Assembly.GetManifestResourceStream(
            "SkillEvaluation.Models.nli-deberta-v3-base.v1.json")
            ?? throw new EvaluationContractException("The pinned NLI profile is not bundled.");

        using StreamReader reader = new(stream);
        return ContractJson.Read<GroundingAssetManifest>(
            ContractJson.Parse(reader.ReadToEnd()), "grounding-assets.v1");
    }

    /// <summary>
    ///  Rejects unreviewed runtime profiles, missing supporting assets, and repinned exports before tokenization.
    /// </summary>
    /// <param name="assets">The strict locally verified closure.</param>
    public static void RequireSupported(VerifiedGroundingAssets assets)
    {
        GroundingAssetManifest actual = assets.Manifest;
        GroundingAssetManifest expected = Read();
        if (actual.ProfileId != expected.ProfileId
            || actual.ModelId != expected.ModelId
            || actual.ModelRevision != expected.ModelRevision
            || actual.License != expected.License
            || actual.Mode != expected.Mode
            || actual.MaximumTokens != expected.MaximumTokens
            || actual.RuntimeVersions != expected.RuntimeVersions
            || !actual.LabelOrder.SequenceEqual(expected.LabelOrder)
            || !actual.InputNames.SequenceEqual(expected.InputNames)
            || actual.Files.Length != expected.Files.Length)
        {
            throw new EvaluationContractException("This CPU adapter supports only the pinned DeBERTa NLI profile.");
        }

        foreach (GroundingAssetFile required in expected.Files)
        {
            GroundingAssetFile file = actual.Files.SingleOrDefault(value => value.Role == required.Role)
                ?? throw new EvaluationContractException($"Pinned supporting asset is missing: '{required.Role}'.");

            if (file.Sha256 != required.Sha256 || file.Bytes != required.Bytes || file.Source != required.Source)
            {
                throw new EvaluationContractException($"Unsupported pinned asset identity or provenance: '{required.Role}'.");
            }
        }
    }
}
