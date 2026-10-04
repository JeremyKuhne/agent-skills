// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace SkillEvaluation;

/// <summary>
///  Resolves owned relative paths and rejects traversal, links, and overlapping output directories.
/// </summary>
public static class OwnedPaths
{
    /// <summary>
    ///  Resolves a relative path beneath its owner without traversing links or parent segments.
    /// </summary>
    /// <param name="root">The directory that owns the path.</param>
    /// <param name="relative">The relative path, using slash or backslash separators.</param>
    /// <param name="requireFile">Whether the resolved path must name an existing file.</param>
    /// <returns>The resolved absolute path.</returns>
    public static string Resolve(string root, string relative, bool requireFile = true)
    {
        if (string.IsNullOrWhiteSpace(relative)
            || relative.StartsWith('/')
            || relative.StartsWith('\\')
            || relative.Contains(':'))
        {
            throw new EvaluationContractException($"A relative owned path is required: '{relative}'.");
        }

        string[] segments = relative.Split(['/', '\\']);
        if (segments.Any(segment => string.IsNullOrWhiteSpace(segment) || segment is "." or ".."))
        {
            throw new EvaluationContractException($"Path traversal or an empty segment is not allowed: '{relative}'.");
        }

        string current = Path.GetFullPath(root);
        RejectLink(current);
        foreach (string segment in segments)
        {
            current = Path.Join(current, segment);
            RejectLink(current);
        }

        if (requireFile && !File.Exists(current))
        {
            throw new EvaluationContractException($"Declared file is missing: '{relative}'.");
        }

        return current;
    }

    /// <summary>
    ///  Rejects an existing file or directory that is a link or reparse point.
    /// </summary>
    /// <param name="path">The filesystem path to inspect.</param>
    public static void RejectLink(string path)
    {
        if ((File.Exists(path) || Directory.Exists(path))
            && (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
        {
            throw new EvaluationContractException($"Links and reparse points are not permitted: '{path}'.");
        }
    }

    /// <summary>
    ///  Requires an absent or empty output directory that is disjoint from the input and has no linked ancestors.
    /// </summary>
    /// <param name="input">The source evidence directory.</param>
    /// <param name="output">The proposed derived-output directory.</param>
    public static void RequireSeparateOutput(string input, string output)
    {
        string source = Path.TrimEndingDirectorySeparator(Path.GetFullPath(input));
        string destination = Path.TrimEndingDirectorySeparator(Path.GetFullPath(output));
        StringComparison comparison = OperatingSystem.IsWindows()
            ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;

        if (source.Equals(destination, comparison)
            || source.StartsWith(destination + Path.DirectorySeparatorChar, comparison)
            || destination.StartsWith(source + Path.DirectorySeparatorChar, comparison))
        {
            throw new EvaluationContractException("Derived output must not equal, contain, or be inside the source directory.");
        }

        for (DirectoryInfo? directory = new(destination); directory is not null; directory = directory.Parent)
        {
            RejectLink(directory.FullName);
        }

        if (Directory.Exists(destination) && Directory.EnumerateFileSystemEntries(destination).Any())
        {
            throw new EvaluationContractException("Derived output directory must be empty.");
        }
    }
}
