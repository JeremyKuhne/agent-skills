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

            RequireExactValue(testMinimumVersion, "7.4", "powerShell.testMinimumVersion");
            RequireExactValue(
                compatibilityMinimumVersion,
                "6.2.0",
                "pester.compatibilityMinimumVersion");
            RequireExactValue(executionVersion, "6.2.0", "pester.executionVersion");

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
            throw new ToolchainPolicyException(
                "The toolchain manifest is not valid JSON.",
                exception);
        }
        catch (KeyNotFoundException exception)
        {
            throw new ToolchainPolicyException(
                "The toolchain manifest is missing a required property.",
                exception);
        }
    }

    public static void ValidateTestRequirements(string script, ToolchainManifest manifest)
    {
        (ScriptBlockAst ast, Token[] tokens) = ParseScript(script, "PowerShell test");
        ValidateHostRequirement(ast, tokens, manifest, "PowerShell test");

        var pesterRequirements = ast.ScriptRequirements!.RequiredModules
            .Where(module => string.Equals(
                module.Name,
                "Pester",
                StringComparison.OrdinalIgnoreCase))
            .ToArray();
        if (pesterRequirements.Length != 1)
        {
            throw new ToolchainPolicyException(
                "The PowerShell test must contain exactly one Pester module requirement.");
        }

        var pester = pesterRequirements[0];
        Version expectedVersion = Version.Parse(manifest.PesterCompatibilityMinimumVersion);
        if (pester.Version != expectedVersion ||
            pester.RequiredVersion is not null ||
            pester.MaximumVersion is not null)
        {
            throw new ToolchainPolicyException(
                $"The PowerShell test must declare Pester ModuleVersion '{manifest.PesterCompatibilityMinimumVersion}'.");
        }
    }

    public static void ValidateRunnerMetadata(string script, ToolchainManifest manifest)
    {
        (ScriptBlockAst ast, Token[] tokens) = ParseScript(script, "Pester runner");
        ValidateHostRequirement(ast, tokens, manifest, "Pester runner");

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
    }

    private static (ScriptBlockAst Ast, Token[] Tokens) ParseScript(
        string script,
        string subject)
    {
        ScriptBlockAst ast = Parser.ParseInput(
            script,
            out Token[] tokens,
            out ParseError[] parseErrors);
        if (parseErrors.Length != 0)
        {
            throw new ToolchainPolicyException(
                $"The {subject} has parse errors: {parseErrors[0].Message}");
        }

        return (ast, tokens);
    }

    private static void ValidateHostRequirement(
        ScriptBlockAst ast,
        IEnumerable<Token> tokens,
        ToolchainManifest manifest,
        string subject)
    {
        if (ast.ScriptRequirements is null || CountVersionRequirements(tokens) != 1)
        {
            throw new ToolchainPolicyException(
                $"The {subject} must contain exactly one version requirement.");
        }

        Version expectedVersion = Version.Parse(manifest.TestMinimumVersion);
        if (ast.ScriptRequirements.RequiredPSVersion != expectedVersion)
        {
            throw new ToolchainPolicyException(
                $"The {subject} must require PowerShell {manifest.TestMinimumVersion} exactly.");
        }
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
            if (parseErrors.Length == 0 &&
                directive.ScriptRequirements?.RequiredPSVersion is not null)
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

    private static void RequireExactValue(string actual, string expected, string path)
    {
        if (actual != expected)
        {
            throw new ToolchainPolicyException($"{path} must be exactly '{expected}'.");
        }
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