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

        CommandAst[] imports = ast.FindAll(
                node => node is CommandAst command &&
                    string.Equals(
                        command.GetCommandName(),
                        "Import-Module",
                        StringComparison.OrdinalIgnoreCase),
                searchNestedScriptBlocks: true)
            .Cast<CommandAst>()
            .Where(command => CommandImportsPester(command))
            .ToArray();
        if (imports.Length != 1 || !ImportsAcceptedPesterVersion(imports[0]))
        {
            throw new ToolchainPolicyException(
                "The Pester runner must import Pester once with -RequiredVersion $PesterVersion.");
        }
    }

    private static bool CommandImportsPester(CommandAst command)
    {
        return command.CommandElements
            .OfType<StringConstantExpressionAst>()
            .Skip(1)
            .Any(element => string.Equals(
                element.Value,
                "Pester",
                StringComparison.OrdinalIgnoreCase));
    }

    private static bool ImportsAcceptedPesterVersion(CommandAst command)
    {
        for (int index = 1; index < command.CommandElements.Count - 1; index++)
        {
            if (command.CommandElements[index] is CommandParameterAst parameter &&
                string.Equals(
                    parameter.ParameterName,
                    "RequiredVersion",
                    StringComparison.OrdinalIgnoreCase) &&
                command.CommandElements[index + 1] is VariableExpressionAst value &&
                string.Equals(
                    value.VariablePath.UserPath,
                    "PesterVersion",
                    StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
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