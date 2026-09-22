using System.Globalization;
using System.Management.Automation.Language;
using System.Xml.Linq;
using YamlDotNet.Core;
using YamlDotNet.RepresentationModel;
using YamlDotNet.Serialization;
using PowerShellParser = System.Management.Automation.Language.Parser;

namespace PowerShellToolchain.Tests;

internal static partial class PowerShellToolchainPolicy
{
    private const string ManagedFileCreationJob = "dotnet-file-creation";
    private const string ManagedFileCreationProject =
        "./tests/dotnet-file-creation/DotNetFileCreation.Tests.csproj";
    private const string CoverageSettingsPath =
        "./tests/dotnet-file-creation/coverage.config.xml";
    private const string TrustedFileWritesSource =
        ".*[\\\\/]skills[\\\\/]dotnet-file-creation[\\\\/]assets[\\\\/]TrustedFileWrites\\.cs$";
    private const string TrustedFileWritesSuffix =
        "/skills/dotnet-file-creation/assets/TrustedFileWrites.cs";

    public static void ValidateManagedFileCreationWorkflow(
        string continuousIntegration,
        string coverageSettings)
    {
        ManagedWorkflow workflow = ParseManagedWorkflow(continuousIntegration);
        if (workflow.Jobs is null ||
            !workflow.Jobs.TryGetValue(ManagedFileCreationJob, out ManagedJob? job) ||
            job?.Strategy?.Matrix?.Include is not { } rows ||
            job.Steps is null ||
            !string.Equals(job.RunsOn, "${{ matrix.os }}", StringComparison.Ordinal))
        {
            throw new ToolchainPolicyException(
                "ci.yml must define the accepted managed file-creation job and matrix.");
        }

        ValidateManagedJobNode(continuousIntegration);
        ValidateManagedMatrix(rows);

        ManagedStep[] candidates = job.Steps
            .Where(step => step is not null && IsManagedTestCandidate(step))
            .Cast<ManagedStep>()
            .ToArray();
        if (candidates.Length != 2)
        {
            throw new ToolchainPolicyException(
                "The managed file-creation job must contain exactly two test steps.");
        }

        ValidateManagedCommand(
            FindManagedStep(candidates, "matrix.coverage == false"),
            expectsCoverage: false);
        ValidateManagedCommand(
            FindManagedStep(candidates, "matrix.coverage == true"),
            expectsCoverage: true);
        ValidateCoverageSettings(coverageSettings);
    }

    public static void ValidateManagedFileCreationCoverageReport(string coverageReport)
    {
        try
        {
            XDocument document = XDocument.Parse(coverageReport, LoadOptions.None);
            XElement? root = document.Root;
            XElement[] classes = root?
                .Element("packages")?
                .Elements("package")
                .SelectMany(package => package
                    .Element("classes")?
                    .Elements("class") ?? [])
                .Where(element => string.Equals(
                    (string?)element.Attribute("name"),
                    "TrustedFileWrites",
                    StringComparison.Ordinal))
                .ToArray() ?? [];
            if (!string.Equals(root?.Name.LocalName, "coverage", StringComparison.Ordinal) ||
                classes.Length != 1)
            {
                throw new ToolchainPolicyException(
                    "Coverage must contain exactly one TrustedFileWrites class.");
            }

            string source = ((string?)classes[0].Attribute("filename") ?? string.Empty)
                .Replace('\\', '/');
            if (!source.EndsWith(
                    TrustedFileWritesSuffix,
                    StringComparison.OrdinalIgnoreCase))
            {
                throw new ToolchainPolicyException(
                    "Coverage must report the TrustedFileWrites production source.");
            }

            XElement[] lines = classes[0]
                .Element("lines")?
                .Elements("line")
                .ToArray() ?? [];
            if (lines.Length == 0 || !lines.Any(line =>
                    int.TryParse(
                        (string?)line.Attribute("hits"),
                        NumberStyles.None,
                        CultureInfo.InvariantCulture,
                        out int hits) &&
                    hits > 0))
            {
                throw new ToolchainPolicyException(
                    "TrustedFileWrites coverage must contain a covered line.");
            }
        }
        catch (ToolchainPolicyException)
        {
            throw;
        }
        catch (System.Xml.XmlException exception)
        {
            throw new ToolchainPolicyException(
                "The managed file-creation coverage report is invalid.",
                exception);
        }
    }

    private static ManagedWorkflow ParseManagedWorkflow(string yaml)
    {
        try
        {
            return new DeserializerBuilder()
                .WithDuplicateKeyChecking()
                .WithAttemptingUnquotedStringTypeDeserialization()
                .IgnoreUnmatchedProperties()
                .Build()
                .Deserialize<ManagedWorkflow>(yaml) ??
                throw new ToolchainPolicyException("ci.yml must contain a workflow mapping.");
        }
        catch (ToolchainPolicyException)
        {
            throw;
        }
        catch (YamlException exception)
        {
            throw new ToolchainPolicyException("ci.yml is not accepted YAML.", exception);
        }
    }

    private static void ValidateManagedJobNode(string yaml)
    {
        try
        {
            YamlStream stream = new();
            stream.Load(new StringReader(yaml));
            if (stream.Documents.Count != 1 ||
                stream.Documents[0].RootNode is not YamlMappingNode root)
            {
                throw new ToolchainPolicyException("ci.yml must contain one mapping document.");
            }

            YamlMappingNode jobs = RequireMapping(
                RequireNode(root, "jobs", "ci.yml"),
                "ci.yml.jobs");
            YamlNode jobNode = RequireNode(jobs, ManagedFileCreationJob, "ci.yml.jobs");
            if (jobNode is not YamlMappingNode job || HasIndirection(jobNode))
            {
                throw new ToolchainPolicyException(
                    "The managed file-creation job must be a direct mapping without indirection.");
            }

            YamlMappingNode strategy = RequireMapping(
                RequireNode(job, "strategy", $"ci.yml.jobs.{ManagedFileCreationJob}"),
                $"ci.yml.jobs.{ManagedFileCreationJob}.strategy");
            YamlMappingNode matrix = RequireMapping(
                RequireNode(strategy, "matrix", $"ci.yml.jobs.{ManagedFileCreationJob}.strategy"),
                $"ci.yml.jobs.{ManagedFileCreationJob}.strategy.matrix");
            if (matrix.Children.Count != 1 || !HasMappingKey(matrix, "include"))
            {
                throw new ToolchainPolicyException(
                    "The managed file-creation matrix must contain only include.");
            }

            YamlSequenceNode include = RequireSequence(
                RequireNode(matrix, "include", $"ci.yml.jobs.{ManagedFileCreationJob}.strategy.matrix"),
                $"ci.yml.jobs.{ManagedFileCreationJob}.strategy.matrix.include");
            foreach (YamlNode rowNode in include)
            {
                if (rowNode is not YamlMappingNode row ||
                    row.Children.Count != 2 ||
                    !HasMappingKey(row, "os") ||
                    !HasMappingKey(row, "coverage"))
                {
                    throw new ToolchainPolicyException(
                        "Managed file-creation matrix rows must contain only os and coverage.");
                }
            }
        }
        catch (ToolchainPolicyException)
        {
            throw;
        }
        catch (YamlException exception)
        {
            throw new ToolchainPolicyException("ci.yml is not accepted YAML.", exception);
        }
    }

    private static void ValidateManagedMatrix(IReadOnlyList<ManagedMatrixRow?> rows)
    {
        if (rows.Count != 2 || rows.Any(row => row is null))
        {
            throw new ToolchainPolicyException(
                "The managed file-creation matrix must contain exactly two rows.");
        }

        ManagedMatrixRow?[] linux = rows.Where(row =>
            string.Equals(row?.OperatingSystem, "ubuntu-24.04-arm", StringComparison.Ordinal)).ToArray();
        ManagedMatrixRow?[] windows = rows.Where(row =>
            string.Equals(row?.OperatingSystem, "windows-latest", StringComparison.Ordinal)).ToArray();
        if (linux.Length != 1 || windows.Length != 1 ||
            linux[0]?.Coverage is not false || windows[0]?.Coverage is not true)
        {
            throw new ToolchainPolicyException(
                "The managed file-creation matrix must pair Linux with no coverage and Windows with coverage.");
        }
    }

    private static ManagedStep FindManagedStep(
        IReadOnlyList<ManagedStep> steps,
        string condition)
    {
        ManagedStep[] matches = steps
            .Where(step => string.Equals(step.Condition, condition, StringComparison.Ordinal))
            .ToArray();
        return matches.Length == 1
            ? matches[0]
            : throw new ToolchainPolicyException(
                $"The managed file-creation job must contain one '{condition}' test step.");
    }

    private static bool IsManagedTestCandidate(ManagedStep step)
    {
        if (step.Run is null)
        {
            return false;
        }

        ScriptBlockAst script = PowerShellParser.ParseInput(
            step.Run,
            out _,
            out ParseError[] errors);
        if (errors.Length != 0)
        {
            return false;
        }

        return FindPowerShellCommands(script).Any(command =>
            IsDotNetTest(command) ||
            Classify(command) is CommandKind.Runner or CommandKind.DirectPester);
    }

    private static void ValidateManagedCommand(ManagedStep step, bool expectsCoverage)
    {
        if (!string.Equals(step.Shell, "pwsh", StringComparison.Ordinal) ||
            step.Run is null)
        {
            throw new ToolchainPolicyException(
                "Managed file-creation test steps must explicitly use pwsh.");
        }

        ScriptBlockAst script = ParsePowerShell(step.Run, "ci.yml.dotnet-file-creation.run");
        CommandAst[] allCommands = FindPowerShellCommands(script);
        CommandAst[] dotnetTests = allCommands.Where(IsDotNetTest).ToArray();
        if (allCommands.Any(command =>
                Classify(command) is CommandKind.Runner or CommandKind.DirectPester) ||
            dotnetTests.Length != 1 ||
            dotnetTests[0].InvocationOperator != TokenKind.Unknown ||
            !IsTopLevelCommand(script, dotnetTests[0]))
        {
            throw new ToolchainPolicyException(
                "Managed file-creation steps must contain one top-level dotnet test command.");
        }

        string[] expected = expectsCoverage
            ?
            [
                "dotnet", "test", "--project", ManagedFileCreationProject,
                "--configuration", "Release", "--coverage", "--coverage-settings",
                CoverageSettingsPath, "--coverage-output", "$coveragePath",
                "--coverage-output-format", "cobertura"
            ]
            :
            [
                "dotnet", "test", "--project", ManagedFileCreationProject,
                "--configuration", "Release"
            ];
        string[] actual = dotnetTests[0].CommandElements
            .Select(CommandElementText)
            .ToArray();
        if (!actual.SequenceEqual(expected, StringComparer.Ordinal))
        {
            throw new ToolchainPolicyException(
                "Managed file-creation steps must use the accepted Release dotnet test command.");
        }

        if (!expectsCoverage && script.EndBlock.Statements.Count != 1)
        {
            throw new ToolchainPolicyException(
                "The noncoverage managed file-creation step must contain only dotnet test.");
        }
    }

    private static bool IsTopLevelCommand(ScriptBlockAst script, CommandAst command)
    {
        return command.Parent is PipelineAst pipeline &&
            pipeline.PipelineElements.Count == 1 &&
            pipeline.PipelineElements[0] == command &&
            script.EndBlock.Statements.Contains(pipeline);
    }

    private static bool IsDotNetTest(CommandAst command)
    {
        return string.Equals(command.GetCommandName(), "dotnet", StringComparison.OrdinalIgnoreCase) &&
            command.CommandElements.Count >= 2 &&
            command.CommandElements[1] is StringConstantExpressionAst verb &&
            string.Equals(verb.Value, "test", StringComparison.Ordinal);
    }

    private static string CommandElementText(CommandElementAst element)
    {
        return element switch
        {
            StringConstantExpressionAst text => text.Value,
            VariableExpressionAst variable => $"${variable.VariablePath.UserPath}",
            _ => element.Extent.Text
        };
    }

    private static void ValidateCoverageSettings(string coverageSettings)
    {
        try
        {
            XDocument document = XDocument.Parse(coverageSettings, LoadOptions.None);
            XElement? root = document.Root;
            string[] sources = root?
                .Element("CodeCoverage")?
                .Element("Sources")?
                .Element("Include")?
                .Elements("Source")
                .Select(element => element.Value)
                .ToArray() ?? [];
            if (!string.Equals(root?.Name.LocalName, "Configuration", StringComparison.Ordinal) ||
                sources.Length != 1 ||
                !string.Equals(sources[0], TrustedFileWritesSource, StringComparison.Ordinal))
            {
                throw new ToolchainPolicyException(
                    "Coverage settings must include only the TrustedFileWrites production source.");
            }
        }
        catch (ToolchainPolicyException)
        {
            throw;
        }
        catch (System.Xml.XmlException exception)
        {
            throw new ToolchainPolicyException(
                "The managed file-creation coverage settings are invalid.",
                exception);
        }
    }

    private static bool HasMappingKey(YamlMappingNode mapping, string key)
    {
        return mapping.Children.Keys.Any(candidate =>
            candidate is YamlScalarNode scalar &&
            string.Equals(scalar.Value, key, StringComparison.Ordinal));
    }

    private sealed class ManagedWorkflow
    {
        [YamlMember(Alias = "jobs")]
        public Dictionary<string, ManagedJob?>? Jobs { get; init; } = new(StringComparer.Ordinal);
    }

    private sealed class ManagedJob
    {
        [YamlMember(Alias = "runs-on")]
        public string? RunsOn { get; init; }

        [YamlMember(Alias = "strategy")]
        public ManagedStrategy? Strategy { get; init; }

        [YamlMember(Alias = "steps")]
        public List<ManagedStep?>? Steps { get; init; }
    }

    private sealed class ManagedStrategy
    {
        [YamlMember(Alias = "matrix")]
        public ManagedMatrix? Matrix { get; init; }
    }

    private sealed class ManagedMatrix
    {
        [YamlMember(Alias = "include")]
        public List<ManagedMatrixRow?>? Include { get; init; }
    }

    private sealed class ManagedMatrixRow
    {
        [YamlMember(Alias = "os")]
        public string? OperatingSystem { get; init; }

        [YamlMember(Alias = "coverage")]
        public object? Coverage { get; init; }
    }

    private sealed class ManagedStep
    {
        [YamlMember(Alias = "if")]
        public string? Condition { get; init; }

        [YamlMember(Alias = "shell")]
        public string? Shell { get; init; }

        [YamlMember(Alias = "run")]
        public string? Run { get; init; }
    }

}
