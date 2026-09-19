using System.Management.Automation.Language;
using System.Text.RegularExpressions;
using YamlDotNet.RepresentationModel;

namespace PowerShellToolchain.Tests;

internal static partial class PowerShellToolchainPolicy
{
    private const string GeneratedSkillsPath = ".github/workflows/skills.yml";
    private const string GeneratedReleasePath = ".github/workflows/release.yml";
    private static readonly Regex UnresolvedTemplateToken = new(
        @"\{\{[A-Z][A-Z0-9_]*\}\}",
        RegexOptions.CultureInvariant);

    public static void ValidateGeneratedRunner(
        ReadOnlySpan<byte> canonicalRunner,
        ReadOnlySpan<byte> generatedRunner)
    {
        if (!canonicalRunner.SequenceEqual(generatedRunner))
        {
            throw new ToolchainPolicyException(
                "The generated Pester runner must be byte-identical to the canonical runner.");
        }
    }

    public static void ValidateGeneratedTeamContinuousIntegration(
        IReadOnlyDictionary<string, string> workflows,
        ToolchainManifest manifest)
    {
        ValidateGeneratedPesterWorkflows(workflows, [GeneratedSkillsPath], manifest);
    }

    public static void ValidateGeneratedDistributionWorkflows(
        IReadOnlyDictionary<string, string> workflows,
        ToolchainManifest manifest)
    {
        ValidateGeneratedPesterWorkflows(
            workflows,
            [GeneratedSkillsPath, GeneratedReleasePath],
            manifest);
    }

    private static void ValidateGeneratedPesterWorkflows(
        IReadOnlyDictionary<string, string> workflows,
        string[] expectedRunnerWorkflows,
        ToolchainManifest manifest)
    {
        Dictionary<string, ParsedWorkflow> parsed = workflows.ToDictionary(
            entry => entry.Key,
            entry => ParseGeneratedWorkflow(entry.Key, entry.Value),
            StringComparer.Ordinal);
        Dictionary<string, RunnerCommandInfo[]> commands = parsed.ToDictionary(
            entry => entry.Key,
            entry => FindGeneratedCommands(entry.Value),
            StringComparer.Ordinal);

        foreach (string path in expectedRunnerWorkflows)
        {
            if (!parsed.TryGetValue(path, out ParsedWorkflow? workflow))
            {
                throw new ToolchainPolicyException(
                    $"Generated output is missing {path}.");
            }

            ValidateGeneratedMode(
                workflow,
                commands[path],
                workflows[path],
                manifest);
        }

        RunnerCommandInfo[] allCommands = commands.Values.SelectMany(value => value).ToArray();
        string[] runnerWorkflows = allCommands
            .Where(command => command.Kind == CommandKind.Runner)
            .Select(command => command.WorkflowPath)
            .Order(StringComparer.Ordinal)
            .ToArray();
        if (!runnerWorkflows.SequenceEqual(
                expectedRunnerWorkflows.Order(StringComparer.Ordinal),
                StringComparer.Ordinal))
        {
            throw new ToolchainPolicyException(
                "Generated workflows must contain exactly the accepted static runner invocations.");
        }

        if (allCommands.Any(command => command.Kind == CommandKind.DirectPester))
        {
            throw new ToolchainPolicyException(
                "Generated workflows must invoke Pester only through the canonical runner.");
        }
    }

    private static ParsedWorkflow ParseGeneratedWorkflow(string path, string yaml)
    {
        if (path.EndsWith(".tmpl", StringComparison.OrdinalIgnoreCase))
        {
            throw new ToolchainPolicyException(
                "Generated workflow policy requires emitted files, not raw templates.");
        }

        if (UnresolvedTemplateToken.IsMatch(yaml))
        {
            throw new ToolchainPolicyException(
                $"{path} contains an unresolved template token.");
        }

        ParsedWorkflow workflow = ParseWorkflow(path, yaml);
        return workflow;
    }

    private static void RejectGeneratedModeIndirection(
        string path,
        string yaml,
        string jobId)
    {
        YamlStream stream = new();
        stream.Load(new StringReader(yaml));
        YamlMappingNode root = (YamlMappingNode)stream.Documents[0].RootNode;
        YamlMappingNode jobs = RequireMapping(RequireNode(root, "jobs", path), $"{path}.jobs");
        YamlNode job = RequireNode(jobs, jobId, $"{path}.jobs");
        if (HasIndirection(job))
        {
            throw new ToolchainPolicyException(
            $"{path} must not use anchors, aliases, or merge keys in the Pester job.");
        }
    }

    private static RunnerCommandInfo[] FindGeneratedCommands(ParsedWorkflow workflow)
    {
        List<RunnerCommandInfo> result = [];
        foreach ((string jobId, WorkflowJob? job) in workflow.Value.Jobs)
        {
            if (job?.Steps is null)
            {
                continue;
            }

            for (int stepIndex = 0; stepIndex < job.Steps.Count; stepIndex++)
            {
                WorkflowStep? step = job.Steps[stepIndex];
                if (step?.Run is null ||
                    !string.Equals(step.Shell, "pwsh", StringComparison.Ordinal))
                {
                    continue;
                }

                ScriptBlockAst script = ParsePowerShell(
                    step.Run,
                    $"{workflow.Path}.{jobId}.steps[{stepIndex}].run");
                result.AddRange(FindPowerShellCommands(script).Select(command =>
                    new RunnerCommandInfo(
                        workflow.Path,
                        jobId,
                        stepIndex,
                        step,
                        script,
                        command,
                        Classify(command))));
            }
        }

        return result.ToArray();
    }

    private static void ValidateGeneratedMode(
        ParsedWorkflow workflow,
        RunnerCommandInfo[] commands,
        string yaml,
        ToolchainManifest manifest)
    {
        RunnerCommandInfo[] runners = commands
            .Where(command => command.Kind == CommandKind.Runner)
            .ToArray();
        if (runners.Length != 1 ||
            !workflow.Value.Jobs.TryGetValue(runners[0].JobId, out WorkflowJob? job) ||
            job is null ||
            job.Condition is not null)
        {
            throw new ToolchainPolicyException(
                $"{workflow.Path} must contain one unconditional Pester job.");
        }

        RejectGeneratedModeIndirection(workflow.Path, yaml, runners[0].JobId);
        RunnerCommandInfo[] jobCommands = commands
            .Where(command => string.Equals(
                command.JobId,
                runners[0].JobId,
                StringComparison.Ordinal))
            .ToArray();
        RunnerCommandInfo[] installs = jobCommands
            .Where(command => command.Kind == CommandKind.Install)
            .ToArray();
        if (installs.Length != 1 ||
            installs[0].StepIndex >= runners[0].StepIndex ||
            !HasStepContract(installs[0].Step, condition: null) ||
            !HasStepContract(runners[0].Step, condition: null) ||
            !HasAcceptedRunnerArguments(
                runners[0].Script,
                runners[0].Command,
                ["./tests"]) ||
            !IsAcceptedInstall(installs[0], manifest))
        {
            throw new ToolchainPolicyException(
                $"{workflow.Path} must use the accepted generated bootstrap and runner steps.");
        }
    }
}