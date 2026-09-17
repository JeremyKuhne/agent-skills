using System.Management.Automation.Language;
using YamlDotNet.Core;
using YamlDotNet.RepresentationModel;
using YamlDotNet.Serialization;
using PowerShellParser = System.Management.Automation.Language.Parser;

namespace PowerShellToolchain.Tests;

internal static partial class PowerShellToolchainPolicy
{
    private const string CiPath = ".github/workflows/ci.yml";
    private const string FullCiPath = ".github/workflows/full-ci.yml";
    private const string RunnerCommand = "./tests/Invoke-PesterShards.ps1";
    private const string WindowsCondition = "steps.windows-filesystem.outputs.affected == 'true'";
    public static void ValidateActivePesterWorkflows(
        string continuousIntegration,
        string fullContinuousIntegration,
        ToolchainManifest manifest)
    {
        ValidateActivePesterWorkflows(
            new Dictionary<string, string>(StringComparer.Ordinal)
            {
                [CiPath] = continuousIntegration,
                [FullCiPath] = fullContinuousIntegration
            },
            manifest);
    }

    public static void ValidateActivePesterWorkflows(
        IReadOnlyDictionary<string, string> workflows,
        ToolchainManifest manifest)
    {
        ParsedWorkflow continuous = ParseRequired(workflows, CiPath);
        ParsedWorkflow full = ParseRequired(workflows, FullCiPath);
        RunnerCommandInfo[] continuousCommands = FindCommands(continuous);
        RunnerCommandInfo[] fullCommands = FindCommands(full);

        ValidateMode(
            continuous,
            continuousCommands,
            "scaffold-linux",
            "ubuntu-24.04-arm",
            condition: null,
            ["./tests"],
            manifest);
        ValidateMode(
            continuous,
            continuousCommands,
            "scaffold-windows",
            "windows-latest",
            WindowsCondition,
            ["tests/windows-acls", "tests/dotnet-file-creation"],
            manifest);
        RequireFullTriggers(full);
        ValidateMode(
            full,
            fullCommands,
            "scaffold-windows",
            "windows-latest",
            condition: null,
            ["./tests"],
            manifest);

        RunnerCommandInfo[] expectedRunners =
        [
            .. continuousCommands.Where(command => command.Kind == CommandKind.Runner),
            .. fullCommands.Where(command => command.Kind == CommandKind.Runner)
        ];
        if (expectedRunners.Length != 3)
        {
            throw new ToolchainPolicyException(
                "Active workflows must contain exactly the three accepted static runner invocations.");
        }

        if (continuousCommands.Concat(fullCommands).Any(command =>
                command.Kind == CommandKind.DirectPester))
        {
            throw new ToolchainPolicyException(
                "Active workflows must invoke Pester only through the canonical runner.");
        }

        foreach ((string path, string yaml) in workflows.Where(entry =>
                     !string.Equals(entry.Key, CiPath, StringComparison.Ordinal) &&
                     !string.Equals(entry.Key, FullCiPath, StringComparison.Ordinal) &&
                     ContainsPesterRunCandidate(entry.Value)))
        {
            ParsedWorkflow additional = ParseWorkflow(path, yaml);
            if (FindCommands(additional).Any(command =>
                    command.Kind is CommandKind.Runner or CommandKind.DirectPester))
            {
                throw new ToolchainPolicyException(
                    $"{path} contains an unexpected static Pester invocation.");
            }
        }
    }

    private static void ValidateMode(
        ParsedWorkflow workflow,
        IEnumerable<RunnerCommandInfo> workflowCommands,
        string jobId,
        string host,
        string? condition,
        string[] expectedPaths,
        ToolchainManifest manifest)
    {
        if (!workflow.Value.Jobs.TryGetValue(jobId, out WorkflowJob? job) ||
            job is null ||
            !string.Equals(job.RunsOn, host, StringComparison.Ordinal) ||
            job.Condition is not null)
        {
            throw new ToolchainPolicyException(
                $"{workflow.Path} must contain the accepted {jobId} job.");
        }

        RunnerCommandInfo[] commands = workflowCommands
            .Where(command => string.Equals(command.JobId, jobId, StringComparison.Ordinal))
            .ToArray();
        RunnerCommandInfo[] runners = commands
            .Where(command => command.Kind == CommandKind.Runner)
            .ToArray();
        RunnerCommandInfo[] installs = commands
            .Where(command => command.Kind == CommandKind.Install)
            .ToArray();
        if (runners.Length != 1 || installs.Length != 1 ||
            installs[0].StepIndex >= runners[0].StepIndex ||
            !HasStepContract(installs[0].Step, condition) ||
            !HasStepContract(runners[0].Step, condition) ||
            !HasAcceptedRunnerArguments(
                runners[0].Script,
                runners[0].Command,
                expectedPaths) ||
            !IsAcceptedInstall(installs[0], manifest))
        {
            throw new ToolchainPolicyException(
                $"{workflow.Path} {jobId} must use the accepted bootstrap and runner steps.");
        }

        if (commands.Any(command => command.Kind == CommandKind.DirectPester))
        {
            throw new ToolchainPolicyException(
                $"{workflow.Path} {jobId} must invoke Pester through the canonical runner.");
        }
    }

    private static bool HasStepContract(WorkflowStep step, string? condition)
    {
        return string.Equals(step.Shell, "pwsh", StringComparison.Ordinal) &&
            string.Equals(step.Condition, condition, StringComparison.Ordinal);
    }

    private static bool IsAcceptedInstall(
        RunnerCommandInfo install,
        ToolchainManifest manifest)
    {
        ScriptBlockAst script = ParsePowerShell(
            install.Step.Run!,
            $"{install.WorkflowPath}.{install.JobId}.steps[{install.StepIndex}].run");
        CommandAst[] commands = FindPowerShellCommands(script);
        if (commands.Length != 1 ||
            Classify(commands[0]) != CommandKind.Install ||
            !IsSingleTopLevelCommand(script, "Install-Module"))
        {
            return false;
        }

        string[] versions = FindLiteralParameterValues(commands[0], "RequiredVersion");
        return versions.Length == 1 &&
            string.Equals(versions[0], manifest.PesterExecutionVersion, StringComparison.Ordinal);
    }

    private static ParsedWorkflow ParseRequired(
        IReadOnlyDictionary<string, string> workflows,
        string path)
    {
        if (!workflows.TryGetValue(path, out string? yaml))
        {
            throw new ToolchainPolicyException($"The active workflow set is missing {path}.");
        }

        return ParseWorkflow(path, yaml);
    }

    private static ParsedWorkflow ParseWorkflow(string path, string yaml)
    {
        try
        {
            YamlStream stream = new();
            stream.Load(new StringReader(yaml));
            if (stream.Documents.Count != 1 ||
                stream.Documents[0].RootNode is not YamlMappingNode root)
            {
                throw new ToolchainPolicyException($"{path} must contain one mapping document.");
            }

            _ = RequireMapping(RequireNode(root, "on", path), $"{path}.on");
            RejectNullOwnedJobShapes(path, root);
            RejectOwnedIndirection(path, root);
            WorkflowFile? workflow = new DeserializerBuilder()
                .WithDuplicateKeyChecking()
                .IgnoreUnmatchedProperties()
                .Build()
                .Deserialize<WorkflowFile>(yaml);
            if (workflow?.On is null || workflow.Jobs is null)
            {
                throw new ToolchainPolicyException($"{path} must define on and jobs mappings.");
            }

            return new ParsedWorkflow(path, workflow);
        }
        catch (ToolchainPolicyException)
        {
            throw;
        }
        catch (YamlException exception)
        {
            throw new ToolchainPolicyException($"{path} is not accepted YAML.", exception);
        }
    }

    private static void RejectNullOwnedJobShapes(string path, YamlMappingNode root)
    {
        YamlMappingNode jobs = RequireMapping(RequireNode(root, "jobs", path), $"{path}.jobs");
        string[] ownedJobIds = string.Equals(path, CiPath, StringComparison.Ordinal)
            ? ["scaffold-linux", "scaffold-windows"]
            : string.Equals(path, FullCiPath, StringComparison.Ordinal)
                ? ["scaffold-windows"]
                : [];
        foreach (string jobId in ownedJobIds)
        {
            YamlNode jobNode = RequireNode(jobs, jobId, $"{path}.jobs");
            if (jobNode is not YamlMappingNode job)
            {
                throw new ToolchainPolicyException($"{path}.jobs.{jobId} must be a mapping.");
            }

            if (RequireNode(job, "steps", $"{path}.jobs.{jobId}") is not YamlSequenceNode)
            {
                throw new ToolchainPolicyException(
                    $"{path}.jobs.{jobId}.steps must be a sequence.");
            }
        }
    }

    private static void RejectOwnedIndirection(string path, YamlMappingNode root)
    {
        if (!string.Equals(path, CiPath, StringComparison.Ordinal) &&
            !string.Equals(path, FullCiPath, StringComparison.Ordinal))
        {
            return;
        }

        YamlMappingNode jobs = RequireMapping(RequireNode(root, "jobs", path), $"{path}.jobs");
        YamlNode[] owned = string.Equals(path, CiPath, StringComparison.Ordinal)
            ?
            [
                RequireNode(jobs, "scaffold-linux", $"{path}.jobs"),
                RequireNode(jobs, "scaffold-windows", $"{path}.jobs")
            ]
            :
            [
                RequireNode(root, "on", path),
                RequireNode(jobs, "scaffold-windows", $"{path}.jobs")
            ];
        if (owned.Any(HasIndirection))
        {
            throw new ToolchainPolicyException(
                $"{path} must not use anchors, aliases, or merge keys in policy-owned mappings.");
        }
    }

    private static bool HasIndirection(YamlNode node)
    {
        if (!node.Anchor.IsEmpty ||
            node is YamlScalarNode scalar && string.Equals(scalar.Value, "<<", StringComparison.Ordinal))
        {
            return true;
        }

        return node switch
        {
            YamlMappingNode mapping => mapping.Children.Any(entry =>
                HasIndirection(entry.Key) || HasIndirection(entry.Value)),
            YamlSequenceNode sequence => sequence.Children.Any(HasIndirection),
            _ => false
        };
    }

    private static RunnerCommandInfo[] FindCommands(ParsedWorkflow workflow)
    {
        return workflow.Value.Jobs.SelectMany(job =>
            job.Value.Steps.SelectMany((step, stepIndex) =>
            {
                if (step.Run is null ||
                    !string.Equals(step.Shell, "pwsh", StringComparison.Ordinal))
                {
                    return [];
                }

                ScriptBlockAst script = ParsePowerShell(
                    step.Run,
                    $"{workflow.Path}.{job.Key}.steps[{stepIndex}].run");
                return FindPowerShellCommands(script)
                    .Select(command => new RunnerCommandInfo(
                        workflow.Path,
                        job.Key,
                        stepIndex,
                        step,
                        script,
                        command,
                        Classify(command)));
            })).ToArray();
    }

    private static CommandKind Classify(CommandAst command)
    {
        string? name = command.GetCommandName();
        if (name is not null && name.Replace('\\', '/').Split('/')[^1].Equals(
                "Invoke-PesterShards.ps1",
                StringComparison.OrdinalIgnoreCase))
        {
            return CommandKind.Runner;
        }

        if (command.InvocationOperator == TokenKind.Unknown &&
            string.Equals(name, "Install-Module", StringComparison.OrdinalIgnoreCase) &&
            command.CommandElements.Count >= 2 &&
            command.CommandElements[1] is StringConstantExpressionAst module &&
            string.Equals(module.Value, "Pester", StringComparison.OrdinalIgnoreCase))
        {
            return CommandKind.Install;
        }

        int qualifier = name?.LastIndexOf('\\') ?? -1;
        return name is not null && name.AsSpan(qualifier + 1).Equals(
            "Invoke-Pester",
            StringComparison.OrdinalIgnoreCase)
                ? CommandKind.DirectPester
                : CommandKind.Other;
    }

    private static ScriptBlockAst ParsePowerShell(string script, string path)
    {
        ScriptBlockAst ast = PowerShellParser.ParseInput(
            script,
            out _,
            out ParseError[] errors);
        if (errors.Length != 0)
        {
            throw new ToolchainPolicyException(
                $"{path} is not valid PowerShell: {errors[0].Message}");
        }

        return ast;
    }

    private static string[] FindLiteralParameterValues(CommandAst command, string parameterName)
    {
        List<string> values = [];
        for (int index = 2; index < command.CommandElements.Count; index++)
        {
            if (command.CommandElements[index] is not CommandParameterAst parameter)
            {
                return [];
            }

            bool target = string.Equals(
                parameter.ParameterName,
                parameterName,
                StringComparison.OrdinalIgnoreCase);
            StringConstantExpressionAst? value = parameter.Argument as StringConstantExpressionAst;
            if (value is null && parameter.Argument is null &&
                index + 1 < command.CommandElements.Count &&
                command.CommandElements[index + 1] is not CommandParameterAst)
            {
                value = command.CommandElements[++index] as StringConstantExpressionAst;
            }

            if (target)
            {
                if (value is null)
                {
                    return [];
                }

                values.Add(value.Value);
            }
        }

        return values.ToArray();
    }

    private static CommandAst[] FindPowerShellCommands(ScriptBlockAst script)
    {
        return script.FindAll(node => node is CommandAst, searchNestedScriptBlocks: true)
            .Cast<CommandAst>()
            .ToArray();
    }

    private static bool ContainsPesterCandidate(string text)
    {
        return text.Contains("Invoke-PesterShards.ps1", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("Invoke-Pester", StringComparison.OrdinalIgnoreCase) ||
            text.Contains("Install-Module Pester", StringComparison.OrdinalIgnoreCase);
    }

    private static bool HasAcceptedRunnerArguments(
        ScriptBlockAst script,
        CommandAst command,
        string[] expectedPaths)
    {
        if (!string.Equals(command.GetCommandName(), RunnerCommand, StringComparison.Ordinal) ||
            command.InvocationOperator != TokenKind.Unknown ||
            command.CommandElements.Count != 3 ||
            command.CommandElements[1] is not CommandParameterAst parameter ||
            !string.Equals(parameter.ParameterName, "Path", StringComparison.OrdinalIgnoreCase) ||
            parameter.Argument is not null)
        {
            return false;
        }

        if (expectedPaths.Length == 1)
        {
            return command.CommandElements[2] is StringConstantExpressionAst path &&
                string.Equals(path.Value, expectedPaths[0], StringComparison.Ordinal) &&
                IsSingleTopLevelCommand(script, RunnerCommand);
        }

        if (command.CommandElements[2] is not VariableExpressionAst variable ||
            !string.Equals(variable.VariablePath.UserPath, "paths", StringComparison.OrdinalIgnoreCase) ||
            script.EndBlock.Statements.Count != 2 ||
            script.EndBlock.Statements[0] is not AssignmentStatementAst assignment ||
            assignment.Operator != TokenKind.Equals ||
            assignment.Left is not VariableExpressionAst target ||
            !string.Equals(target.VariablePath.UserPath, "paths", StringComparison.OrdinalIgnoreCase) ||
            assignment.Right is not CommandExpressionAst right ||
            right.Expression is not ArrayExpressionAst arrayExpression ||
            arrayExpression.SubExpression.Statements.Count != 1 ||
            arrayExpression.SubExpression.Statements[0] is not PipelineAst arrayPipeline ||
            arrayPipeline.PipelineElements.Count != 1 ||
            arrayPipeline.PipelineElements[0] is not CommandExpressionAst arrayCommand ||
            arrayCommand.Expression is not ArrayLiteralAst arrayLiteral ||
            command.Parent is not PipelineAst runnerPipeline ||
            script.EndBlock.Statements[1] != runnerPipeline ||
            runnerPipeline.PipelineElements.Count != 1 ||
            runnerPipeline.PipelineElements[0] != command)
        {
            return false;
        }

        string[] paths = arrayLiteral.Elements
            .OfType<StringConstantExpressionAst>()
            .Select(value => value.Value)
            .ToArray();
        return paths.Length == arrayLiteral.Elements.Count &&
            paths.SequenceEqual(expectedPaths, StringComparer.Ordinal);
    }

    private static bool ContainsPesterRunCandidate(string yaml)
    {
        try
        {
            YamlStream stream = new();
            stream.Load(new StringReader(yaml));
            return stream.Documents.Any(document =>
                HasPesterRunValue(document.RootNode));
        }
        catch (YamlException)
        {
            return false;
        }
    }

    private static bool HasPesterRunValue(YamlNode node)
    {
        return node switch
        {
            YamlMappingNode mapping => mapping.Children.Any(entry =>
                entry.Key is YamlScalarNode key &&
                string.Equals(key.Value, "run", StringComparison.Ordinal) &&
                entry.Value is YamlScalarNode run &&
                run.Value is not null &&
                ContainsPesterCandidate(run.Value) ||
                HasPesterRunValue(entry.Value)),
            YamlSequenceNode sequence => sequence.Children.Any(HasPesterRunValue),
            _ => false
        };
    }

    private static bool IsSingleTopLevelCommand(ScriptBlockAst script, string commandName)
    {
        return script.EndBlock.Statements.Count == 1 &&
            script.EndBlock.Statements[0] is PipelineAst pipeline &&
            pipeline.PipelineElements.Count == 1 &&
            pipeline.PipelineElements[0] is CommandAst command &&
            string.Equals(command.GetCommandName(), commandName, StringComparison.OrdinalIgnoreCase);
    }

    private static void RequireFullTriggers(ParsedWorkflow full)
    {
        if (!full.Value.On.ContainsKey("workflow_dispatch") ||
            !full.Value.On.TryGetValue("schedule", out object? schedule) ||
            schedule is not IList<object> { Count: > 0 })
        {
            throw new ToolchainPolicyException(
                $"{FullCiPath} must run on schedule and manual dispatch.");
        }
    }

    private static YamlNode RequireNode(YamlMappingNode mapping, string key, string path)
    {
        foreach ((YamlNode candidate, YamlNode value) in mapping.Children)
        {
            if (candidate is YamlScalarNode scalar &&
                string.Equals(scalar.Value, key, StringComparison.Ordinal))
            {
                return value;
            }
        }

        throw new ToolchainPolicyException($"{path} is missing '{key}'.");
    }

    private static YamlMappingNode RequireMapping(YamlNode node, string path)
    {
        return node as YamlMappingNode ??
            throw new ToolchainPolicyException($"{path} must be a mapping.");
    }

    private static YamlSequenceNode RequireSequence(YamlNode node, string path)
    {
        return node as YamlSequenceNode ??
            throw new ToolchainPolicyException($"{path} must be a sequence.");
    }

    private sealed record ParsedWorkflow(string Path, WorkflowFile Value);
    private sealed record RunnerCommandInfo(
        string WorkflowPath,
        string JobId,
        int StepIndex,
        WorkflowStep Step,
        ScriptBlockAst Script,
        CommandAst Command,
        CommandKind Kind);

    private enum CommandKind
    {
        Other,
        Install,
        Runner,
        DirectPester
    }

    private sealed class WorkflowFile
    {
        [YamlMember(Alias = "on")]
        public Dictionary<string, object?> On { get; init; } = new(StringComparer.Ordinal);

        [YamlMember(Alias = "jobs")]
        public Dictionary<string, WorkflowJob> Jobs { get; init; } = new(StringComparer.Ordinal);
    }

    private sealed class WorkflowJob
    {
        [YamlMember(Alias = "runs-on")]
        public string? RunsOn { get; init; }

        [YamlMember(Alias = "if")]
        public string? Condition { get; init; }

        [YamlMember(Alias = "steps")]
        public List<WorkflowStep> Steps { get; init; } = [];
    }

    private sealed class WorkflowStep
    {
        [YamlMember(Alias = "if")]
        public string? Condition { get; init; }

        [YamlMember(Alias = "shell")]
        public string? Shell { get; init; }

        [YamlMember(Alias = "run")]
        public string? Run { get; init; }
    }
}