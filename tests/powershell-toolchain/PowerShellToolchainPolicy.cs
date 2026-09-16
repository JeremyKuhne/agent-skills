using System.Management.Automation.Language;
using System.Text.Json;

namespace PowerShellToolchain.Tests;

internal sealed record ToolchainManifest(
    int SchemaVersion,
    string TestMinimumVersion,
    string PesterCompatibilityMinimumVersion,
    string PesterExecutionVersion);

internal sealed class ToolchainPolicyException(string message, Exception? innerException = null)
    : Exception(message, innerException);

internal static class PowerShellToolchainPolicy
{
    public static ToolchainManifest ParseManifest(string json)
    {
        try
        {
            using JsonDocument document = JsonDocument.Parse(json);
            JsonElement root = RequireObject(document.RootElement, "manifest");
            RequireProperties(root, "manifest", "schemaVersion", "powerShell", "pester");

            JsonElement schemaVersion = root.GetProperty("schemaVersion");
            if (schemaVersion.ValueKind != JsonValueKind.Number ||
                schemaVersion.GetRawText() != "1")
            {
                throw new ToolchainPolicyException("schemaVersion must be the JSON token 1.");
            }

            JsonElement powerShell = RequireObject(root.GetProperty("powerShell"), "powerShell");
            RequireProperties(powerShell, "powerShell", "testMinimumVersion");
            string testMinimumVersion = RequireString(
                powerShell.GetProperty("testMinimumVersion"),
                "powerShell.testMinimumVersion");

            JsonElement pester = RequireObject(root.GetProperty("pester"), "pester");
            RequireProperties(
                pester,
                "pester",
                "compatibilityMinimumVersion",
                "executionVersion");
            string compatibilityMinimumVersion = RequireString(
                pester.GetProperty("compatibilityMinimumVersion"),
                "pester.compatibilityMinimumVersion");
            string executionVersion = RequireString(
                pester.GetProperty("executionVersion"),
                "pester.executionVersion");

            if (testMinimumVersion != "7.4")
            {
                throw new ToolchainPolicyException(
                    "powerShell.testMinimumVersion must be exactly '7.4'.");
            }

            if (compatibilityMinimumVersion != "6.2.0")
            {
                throw new ToolchainPolicyException(
                    "pester.compatibilityMinimumVersion must be exactly '6.2.0'.");
            }

            if (executionVersion != "6.2.0")
            {
                throw new ToolchainPolicyException(
                    "pester.executionVersion must be exactly '6.2.0'.");
            }

            return new ToolchainManifest(
                1,
                testMinimumVersion,
                compatibilityMinimumVersion,
                executionVersion);
        }
        catch (ToolchainPolicyException)
        {
            throw;
        }
        catch (JsonException exception)
        {
            throw new ToolchainPolicyException("The toolchain manifest is not valid JSON.", exception);
        }
        catch (KeyNotFoundException exception)
        {
            throw new ToolchainPolicyException("The toolchain manifest is missing a required property.", exception);
        }
    }

    public static void ValidateTestRequirements(string script, ToolchainManifest manifest)
    {
        ScriptBlockAst ast = Parser.ParseInput(
            script,
            out Token[] tokens,
            out ParseError[] parseErrors);
        if (parseErrors.Length != 0)
        {
            throw new ToolchainPolicyException(
                $"The PowerShell test has parse errors: {parseErrors[0].Message}");
        }

        ScriptRequirements? requirements = ast.ScriptRequirements;
        if (requirements is null || CountVersionRequirements(tokens) != 1)
        {
            throw new ToolchainPolicyException(
                "The PowerShell test must contain exactly one version requirement.");
        }

        Version expectedPowerShellVersion = Version.Parse(manifest.TestMinimumVersion);
        if (requirements.RequiredPSVersion != expectedPowerShellVersion)
        {
            throw new ToolchainPolicyException(
                $"The PowerShell test must require version {manifest.TestMinimumVersion} exactly.");
        }

        var pesterRequirements = requirements.RequiredModules
            .Where(module => string.Equals(module.Name, "Pester", StringComparison.OrdinalIgnoreCase))
            .ToArray();
        if (pesterRequirements.Length != 1)
        {
            throw new ToolchainPolicyException(
                "The PowerShell test must contain exactly one Pester module requirement.");
        }

        var pester = pesterRequirements[0];
        Version expectedPesterVersion = Version.Parse(manifest.PesterCompatibilityMinimumVersion);
        if (pester.Version != expectedPesterVersion ||
            pester.RequiredVersion is not null ||
            pester.MaximumVersion is not null)
        {
            throw new ToolchainPolicyException(
                $"The PowerShell test must declare Pester ModuleVersion '{manifest.PesterCompatibilityMinimumVersion}'.");
        }
    }

    public static void ValidateRunnerRequirements(string script, ToolchainManifest manifest)
    {
        ScriptBlockAst ast = Parser.ParseInput(
            script,
            out _,
            out ParseError[] parseErrors);
        if (parseErrors.Length != 0)
        {
            throw new ToolchainPolicyException(
                $"The Pester runner has parse errors: {parseErrors[0].Message}");
        }

        if (ast.ScriptRequirements?.RequiredPSVersion != Version.Parse(manifest.TestMinimumVersion))
        {
            throw new ToolchainPolicyException(
                $"The Pester runner must require PowerShell {manifest.TestMinimumVersion} exactly.");
        }

        ParameterAst[] parameters = ast.ParamBlock?.Parameters
            .Where(parameter => string.Equals(
                parameter.Name.VariablePath.UserPath,
                "PesterVersion",
                StringComparison.OrdinalIgnoreCase))
            .ToArray() ?? [];
        if (parameters.Length != 1)
        {
            throw new ToolchainPolicyException(
                "The Pester runner must declare exactly one PesterVersion parameter.");
        }

        ParameterAst parameter = parameters[0];
        bool hasVersionType = parameter.Attributes
            .OfType<TypeConstraintAst>()
            .Any(attribute => string.Equals(
                attribute.TypeName.FullName,
                "version",
                StringComparison.OrdinalIgnoreCase));
        if (!hasVersionType ||
            parameter.DefaultValue is not StringConstantExpressionAst defaultValue ||
            defaultValue.Value != manifest.PesterExecutionVersion)
        {
            throw new ToolchainPolicyException(
                $"The Pester runner must default a typed PesterVersion parameter to '{manifest.PesterExecutionVersion}'.");
        }

        CommandAst[] executionVersionLocks = ast.FindAll(
                node => node is CommandAst command &&
                    IsCommandName(command.GetCommandName(), "New-Variable", "nv"),
                searchNestedScriptBlocks: true)
            .Cast<CommandAst>()
            .ToArray();
        if (executionVersionLocks.Length != 1 ||
            !IsCanonicalExecutionVersionLock(executionVersionLocks[0], ast))
        {
            throw new ToolchainPolicyException(
                "The Pester runner must immediately create a constant RequiredPesterVersion from PesterVersion.");
        }

        if (HasExecutionVersionWrite(ast))
        {
            throw new ToolchainPolicyException(
                "The Pester runner must not assign to its execution-version variables.");
        }

        if (HasVariableMutationCommand(ast, executionVersionLocks[0]))
        {
            throw new ToolchainPolicyException(
                "The Pester runner must not use variable mutation commands.");
        }

        if (HasDynamicExecution(ast))
        {
            throw new ToolchainPolicyException(
                "The Pester runner must not use dynamic command execution.");
        }

        CommandAst[] imports = ast.FindAll(
                node => node is CommandAst command &&
                    IsImportCommandName(command.GetCommandName()),
                searchNestedScriptBlocks: true)
            .Cast<CommandAst>()
            .ToArray();
        if (imports.Length != 1 ||
            !IsCanonicalWorkerImport(imports[0], ast) ||
            !HasAcceptedImportArguments(imports[0]))
        {
            throw new ToolchainPolicyException(
                "The Pester runner must import Pester once with -RequiredVersion $RequiredPesterVersion.");
        }
    }

    private static bool IsImportCommandName(string? commandName)
    {
        return string.Equals(commandName, "Import-Module", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(commandName, "ipmo", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsCanonicalExecutionVersionLock(CommandAst command, ScriptBlockAst script)
    {
        if (!string.Equals(command.GetCommandName(), "New-Variable", StringComparison.OrdinalIgnoreCase) ||
            command.InvocationOperator != TokenKind.Unknown ||
            command.Parent is not PipelineAst pipeline ||
            pipeline.Parent != script.EndBlock ||
            script.EndBlock.Statements.FirstOrDefault() != pipeline)
        {
            return false;
        }

        string? name = null;
        bool sawValue = false;
        bool sawOption = false;
        bool sawErrorAction = false;
        for (int index = 1; index < command.CommandElements.Count; index++)
        {
            if (command.CommandElements[index] is not CommandParameterAst parameter)
            {
                return false;
            }

            if (string.Equals(parameter.ParameterName, "Name", StringComparison.OrdinalIgnoreCase))
            {
                if (name is not null ||
                    !TryGetStringArgument(command, parameter, ref index, out name))
                {
                    return false;
                }
            }
            else if (string.Equals(parameter.ParameterName, "Value", StringComparison.OrdinalIgnoreCase))
            {
                if (sawValue ||
                    !TryGetVariableArgument(command, parameter, ref index, "PesterVersion"))
                {
                    return false;
                }

                sawValue = true;
            }
            else if (string.Equals(parameter.ParameterName, "Option", StringComparison.OrdinalIgnoreCase))
            {
                if (sawOption ||
                    !TryGetStringArgument(command, parameter, ref index, out string? option) ||
                    !string.Equals(option, "Constant", StringComparison.OrdinalIgnoreCase))
                {
                    return false;
                }

                sawOption = true;
            }
            else if (string.Equals(parameter.ParameterName, "ErrorAction", StringComparison.OrdinalIgnoreCase))
            {
                if (sawErrorAction ||
                    !TryGetStringArgument(command, parameter, ref index, out string? errorAction) ||
                    !string.Equals(errorAction, "Stop", StringComparison.OrdinalIgnoreCase))
                {
                    return false;
                }

                sawErrorAction = true;
            }
            else
            {
                return false;
            }
        }

        return string.Equals(name, "RequiredPesterVersion", StringComparison.OrdinalIgnoreCase) &&
            sawValue &&
            sawOption &&
            sawErrorAction;
    }

    private static bool HasExecutionVersionWrite(ScriptBlockAst ast)
    {
        return ast.FindAll(
                node => node switch
                {
                    AssignmentStatementAst assignment =>
                        ReferencesExecutionVersion(assignment.Left),
                    UnaryExpressionAst unary =>
                        IsMutationOperator(unary.TokenKind) &&
                        ReferencesExecutionVersion(unary.Child),
                    _ => false
                },
                searchNestedScriptBlocks: true)
            .Any();
    }

    private static bool HasVariableMutationCommand(ScriptBlockAst ast, CommandAst executionVersionLock)
    {
        return ast.FindAll(
                node => node is CommandAst command &&
                    command != executionVersionLock &&
                    IsVariableMutationCommand(command.GetCommandName()),
                searchNestedScriptBlocks: true)
            .Any();
    }

    private static bool HasDynamicExecution(ScriptBlockAst ast)
    {
        return ast.FindAll(
                node => node is CommandAst command &&
                    (command.InvocationOperator != TokenKind.Unknown ||
                     IsCommandName(command.GetCommandName(), "Invoke-Expression", "iex")),
                searchNestedScriptBlocks: true)
            .Any();
    }

    private static bool IsVariableMutationCommand(string? commandName)
    {
        return IsCommandName(
            commandName,
            "Set-Variable",
            "set",
            "sv",
            "New-Variable",
            "nv",
            "Clear-Variable",
            "clv",
            "Remove-Variable",
            "rv");
    }

    private static bool IsCommandName(string? commandName, params string[] acceptedNames)
    {
        if (commandName is null)
        {
            return false;
        }

        int qualifier = commandName.LastIndexOf('\\');
        ReadOnlySpan<char> unqualifiedName = commandName.AsSpan(qualifier + 1);
        foreach (string acceptedName in acceptedNames)
        {
            if (unqualifiedName.Equals(acceptedName, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }

    private static bool IsMutationOperator(TokenKind tokenKind)
    {
        return tokenKind is TokenKind.PlusPlus or
            TokenKind.PostfixPlusPlus or
            TokenKind.MinusMinus or
            TokenKind.PostfixMinusMinus;
    }

    private static bool ReferencesExecutionVersion(Ast ast)
    {
        return ast.Find(
                node => node is VariableExpressionAst variable &&
                    (IsExecutionVersionName(variable, "PesterVersion") ||
                     IsExecutionVersionName(variable, "RequiredPesterVersion")),
                searchNestedScriptBlocks: true) is not null;
    }

    private static bool IsExecutionVersionName(
        VariableExpressionAst variable,
        string expectedName)
    {
        string userPath = variable.VariablePath.UserPath;
        int qualifier = userPath.LastIndexOf(':');
        return userPath.AsSpan(qualifier + 1).Equals(
            expectedName,
            StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsUnqualifiedVariableName(
        VariableExpressionAst variable,
        string expectedName)
    {
        return string.Equals(
            variable.VariablePath.UserPath,
            expectedName,
            StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsCanonicalWorkerImport(CommandAst command, ScriptBlockAst script)
    {
        if (!string.Equals(
                command.GetCommandName(),
                "Import-Module",
                StringComparison.OrdinalIgnoreCase) ||
            command.InvocationOperator != TokenKind.Unknown ||
            command.Parent is not PipelineAst pipeline ||
            pipeline.Parent is not StatementBlockAst block ||
            block.Parent is not IfStatementAst conditional ||
            !conditional.Clauses.Any(clause =>
                clause.Item2 == block &&
                clause.Item2.Statements.Contains(pipeline) &&
                IsShardModeCondition(clause.Item1)))
        {
            return false;
        }

        return conditional.Parent == script.EndBlock;
    }

    private static bool IsShardModeCondition(PipelineBaseAst condition)
    {
        if (condition is not PipelineAst pipeline ||
            pipeline.PipelineElements.Count != 1 ||
            pipeline.PipelineElements[0] is not CommandExpressionAst commandExpression ||
            commandExpression.Expression is not UnaryExpressionAst unary ||
            unary.TokenKind != TokenKind.Not ||
            unary.Child is not InvokeMemberExpressionAst invocation ||
            !invocation.Static ||
            invocation.Expression is not TypeExpressionAst type ||
            !string.Equals(type.TypeName.FullName, "string", StringComparison.OrdinalIgnoreCase) ||
            invocation.Member is not StringConstantExpressionAst member ||
            !string.Equals(member.Value, "IsNullOrWhiteSpace", StringComparison.OrdinalIgnoreCase) ||
            invocation.Arguments.Count != 1 ||
            invocation.Arguments[0] is not VariableExpressionAst variable)
        {
            return false;
        }

        return string.Equals(
            variable.VariablePath.UserPath,
            "ShardPath",
            StringComparison.OrdinalIgnoreCase);
    }

    private static bool ReferencesVariable(Ast ast, string variableName)
    {
        return ast.Find(
                node => node is VariableExpressionAst variable &&
                    string.Equals(
                        variable.VariablePath.UserPath,
                        variableName,
                        StringComparison.OrdinalIgnoreCase),
                searchNestedScriptBlocks: true) is not null;
    }

    private static bool HasAcceptedImportArguments(CommandAst command)
    {
        string? moduleName = null;
        bool sawRequiredVersion = false;
        bool sawForce = false;
        bool sawErrorAction = false;

        for (int index = 1; index < command.CommandElements.Count; index++)
        {
            CommandElementAst element = command.CommandElements[index];
            if (element is StringConstantExpressionAst positionalName)
            {
                if (moduleName is not null)
                {
                    return false;
                }

                moduleName = positionalName.Value;
                continue;
            }

            if (element is not CommandParameterAst parameter)
            {
                return false;
            }

            if (string.Equals(parameter.ParameterName, "Name", StringComparison.OrdinalIgnoreCase))
            {
                if (moduleName is not null ||
                    !TryGetStringArgument(command, parameter, ref index, out moduleName))
                {
                    return false;
                }
            }
            else if (string.Equals(
                         parameter.ParameterName,
                         "RequiredVersion",
                         StringComparison.OrdinalIgnoreCase))
            {
                if (sawRequiredVersion ||
                    !TryGetVariableArgument(
                        command,
                        parameter,
                        ref index,
                        "RequiredPesterVersion"))
                {
                    return false;
                }

                sawRequiredVersion = true;
            }
            else if (string.Equals(parameter.ParameterName, "Force", StringComparison.OrdinalIgnoreCase))
            {
                if (sawForce || parameter.Argument is not null)
                {
                    return false;
                }

                sawForce = true;
            }
            else if (string.Equals(
                         parameter.ParameterName,
                         "ErrorAction",
                         StringComparison.OrdinalIgnoreCase))
            {
                if (sawErrorAction ||
                    !TryGetStringArgument(command, parameter, ref index, out string? errorAction) ||
                    !string.Equals(errorAction, "Stop", StringComparison.OrdinalIgnoreCase))
                {
                    return false;
                }

                sawErrorAction = true;
            }
            else
            {
                return false;
            }
        }

        return string.Equals(moduleName, "Pester", StringComparison.OrdinalIgnoreCase) &&
            sawRequiredVersion;
    }

    private static bool TryGetStringArgument(
        CommandAst command,
        CommandParameterAst parameter,
        ref int index,
        out string? value)
    {
        if (parameter.Argument is StringConstantExpressionAst attached)
        {
            value = attached.Value;
            return true;
        }

        if (parameter.Argument is not null ||
            index + 1 >= command.CommandElements.Count ||
            command.CommandElements[index + 1] is not StringConstantExpressionAst separated)
        {
            value = null;
            return false;
        }

        index++;
        value = separated.Value;
        return true;
    }

    private static bool TryGetVariableArgument(
        CommandAst command,
        CommandParameterAst parameter,
        ref int index,
        string variableName)
    {
        VariableExpressionAst? value = parameter.Argument as VariableExpressionAst;
        if (parameter.Argument is null &&
            index + 1 < command.CommandElements.Count &&
            command.CommandElements[index + 1] is VariableExpressionAst separated)
        {
            index++;
            value = separated;
        }

        return value is not null && IsUnqualifiedVariableName(value, variableName);
    }

    private static int CountVersionRequirements(IEnumerable<Token> tokens)
    {
        int count = 0;
        foreach (Token token in tokens)
        {
            if (token.Kind != TokenKind.Comment ||
                !token.Text.StartsWith("#requires", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            ScriptBlockAst directive = Parser.ParseInput(
                token.Text,
                out _,
                out ParseError[] parseErrors);
            if (parseErrors.Length == 0 && directive.ScriptRequirements?.RequiredPSVersion is not null)
            {
                count++;
            }
        }

        return count;
    }

    private static JsonElement RequireObject(JsonElement value, string path)
    {
        if (value.ValueKind != JsonValueKind.Object)
        {
            throw new ToolchainPolicyException($"{path} must be an object.");
        }

        return value;
    }

    private static string RequireString(JsonElement value, string path)
    {
        if (value.ValueKind != JsonValueKind.String)
        {
            throw new ToolchainPolicyException($"{path} must be a string.");
        }

        return value.GetString()!;
    }

    private static void RequireProperties(
        JsonElement value,
        string path,
        params string[] expectedNames)
    {
        HashSet<string> expected = new(expectedNames, StringComparer.Ordinal);
        HashSet<string> observed = new(StringComparer.Ordinal);
        foreach (JsonProperty property in value.EnumerateObject())
        {
            if (!observed.Add(property.Name))
            {
                throw new ToolchainPolicyException(
                    $"{path} contains duplicate property '{property.Name}'.");
            }

            if (!expected.Contains(property.Name))
            {
                throw new ToolchainPolicyException(
                    $"{path} contains unknown property '{property.Name}'.");
            }
        }

        foreach (string expectedName in expected)
        {
            if (!observed.Contains(expectedName))
            {
                throw new ToolchainPolicyException(
                    $"{path} is missing required property '{expectedName}'.");
            }
        }
    }
}