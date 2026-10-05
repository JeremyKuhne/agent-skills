// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  Verifies an explicitly provisioned owned asset closure without downloading files or running inference.
/// </summary>
public static class GroundingAssets
{
    /// <summary>
    ///  Parses the original strict manifest and verifies every declared path, size, and raw-byte pin.
    /// </summary>
    /// <param name="root">The ordinary local directory owning the manifest and assets.</param>
    /// <param name="manifestPath">The relative or owned absolute manifest path.</param>
    /// <returns>The source-bound verified closure.</returns>
    public static VerifiedGroundingAssets Load(string root, string manifestPath)
    {
        string owner = Path.GetFullPath(root);
        string path = ResolveOwned(owner, manifestPath);
        string text = ArtifactStore.Decode(File.ReadAllBytes(path));
        GroundingAssetManifest manifest = ContractJson.Read<GroundingAssetManifest>(
            ContractJson.Parse(text), "grounding-assets.v1");

        ProfileValidator.UniqueIds(manifest.Files.Select(value => value.Role), "grounding asset role");
        Dictionary<string, string> paths = new(StringComparer.Ordinal);
        HashSet<string> uniquePaths = new(OperatingSystem.IsWindows()
            ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal);

        foreach (GroundingAssetFile file in manifest.Files)
        {
            string asset = OwnedPaths.Resolve(owner, file.Path);
            if (!uniquePaths.Add(asset) || asset.Equals(path, OperatingSystem.IsWindows()
                ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal))
            {
                throw new EvaluationContractException("Grounding assets require distinct files separate from their manifest.");
            }

            if (!Uri.TryCreate(file.Source, UriKind.Absolute, out Uri? source)
                || source.Scheme is not ("https" or "fixture")
                || (source.Scheme == "https"
                    && (!source.AbsolutePath.Contains(manifest.ModelRevision, StringComparison.Ordinal)
                        || source.Query.Length != 0
                        || source.Fragment.Length != 0))
                || string.IsNullOrWhiteSpace(manifest.ModelId)
                || string.IsNullOrWhiteSpace(manifest.License))
            {
                throw new EvaluationContractException("Explicit immutable HTTPS or synthetic fixture asset provenance is required.");
            }

            FileInfo info = new(asset);
            if (info.Length != file.Bytes || ContractJson.HashFile(asset) != file.Sha256)
            {
                throw new EvaluationContractException($"Grounding asset bytes or SHA-256 changed: '{file.Role}'.");
            }

            paths.Add(file.Role, asset);
        }

        if (!paths.ContainsKey("model") || !paths.ContainsKey("sentencepiece"))
        {
            throw new EvaluationContractException("A grounding manifest requires model and sentencepiece assets.");
        }

        string manifestRevision = ContractJson.HashText(text);
        string revision = ContractJson.Revision(new { manifest, manifestRevision });
        return new(owner, path, manifestRevision, revision, manifest, paths);
    }

    /// <summary>
    ///  Rejects changes to any original asset or manifest before accepting a diagnostic report.
    /// </summary>
    /// <param name="assets">The originally checked asset closure.</param>
    public static void RequireUnchanged(VerifiedGroundingAssets assets)
    {
        VerifiedGroundingAssets current = Load(assets.Root, assets.ManifestPath);
        StringComparison comparison = OperatingSystem.IsWindows()
            ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;

        if (current.AssetRevision != assets.AssetRevision
            || current.ManifestRevision != assets.ManifestRevision
            || ContractJson.Revision(current.Manifest) != ContractJson.Revision(assets.Manifest)
            || current.Paths.Count != assets.Paths.Count
            || current.Paths.Any(value => !assets.Paths.TryGetValue(value.Key, out string? original)
                || !value.Value.Equals(original, comparison)))
        {
            throw new EvaluationContractException("Grounding assets or manifest changed during diagnostic evaluation.");
        }
    }

    /// <summary>
    ///  Resolves an absolute or relative input only within its ordinary owning directory.
    /// </summary>
    /// <param name="root">The input owner.</param>
    /// <param name="path">The relative or owned absolute path.</param>
    /// <returns>The checked absolute file path.</returns>
    public static string ResolveOwned(string root, string path)
    {
        string owner = Path.GetFullPath(root);
        string absolute = Path.GetFullPath(path, owner);
        return OwnedPaths.Resolve(owner, Path.GetRelativePath(owner, absolute));
    }
}
