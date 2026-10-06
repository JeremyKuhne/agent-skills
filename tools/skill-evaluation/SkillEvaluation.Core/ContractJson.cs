// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Json.Schema;

namespace SkillEvaluation;

/// <summary>
///  Serializes evaluation contracts, validates bundled schemas, and computes content revisions.
/// </summary>
public static class ContractJson
{
    /// <summary>
    ///  Caches bundled schemas by their resource names.
    /// </summary>
    private static readonly ConcurrentDictionary<string, JsonSchema> Schemas = new();

    /// <summary>
    ///  Gets the shared strict, case-sensitive settings for evaluation contract JSON.
    /// </summary>
    public static JsonSerializerOptions Options { get; } = CreateOptions();

    /// <summary>
    ///  Creates the strict serializer settings shared by evaluation contracts.
    /// </summary>
    /// <returns>Indented camel-case settings that reject unknown properties and numeric enum values.</returns>
    private static JsonSerializerOptions CreateOptions()
    {
        JsonSerializerOptions options = new()
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            PropertyNameCaseInsensitive = false,
            UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
            WriteIndented = true
        };

        options.Converters.Add(new JsonStringEnumConverter(
            JsonNamingPolicy.KebabCaseLower, allowIntegerValues: false));

        return options;
    }

    /// <summary>
    ///  Parses JSON while rejecting duplicate object-property names.
    /// </summary>
    /// <param name="json">The JSON text to parse.</param>
    /// <returns>A detached root element that remains valid after the parser is disposed.</returns>
    public static JsonElement Parse(string json)
    {
        using JsonDocument document = JsonDocument.Parse(json);
        RejectDuplicateProperties(document.RootElement, "$");
        return document.RootElement.Clone();
    }

    /// <summary>
    ///  Recursively rejects duplicate property names within each JSON object.
    /// </summary>
    /// <param name="element">The object, array, or scalar to inspect.</param>
    /// <param name="path">The diagnostic path of the current element.</param>
    private static void RejectDuplicateProperties(JsonElement element, string path)
    {
        if (element.ValueKind == JsonValueKind.Object)
        {
            HashSet<string> names = new(StringComparer.Ordinal);
            foreach (JsonProperty property in element.EnumerateObject())
            {
                if (!names.Add(property.Name))
                {
                    throw new EvaluationContractException(
                        $"Duplicate JSON property at {path}.{property.Name}.");
                }

                RejectDuplicateProperties(property.Value, $"{path}.{property.Name}");
            }
        }
        else if (element.ValueKind == JsonValueKind.Array)
        {
            int index = 0;
            foreach (JsonElement item in element.EnumerateArray())
            {
                RejectDuplicateProperties(item, $"{path}[{index++}]");
            }
        }
    }

    /// <summary>
    ///  Validates an element against a bundled schema and deserializes it.
    /// </summary>
    /// <typeparam name="T">The evaluation contract type.</typeparam>
    /// <param name="element">The JSON value to validate and deserialize.</param>
    /// <param name="schemaName">The bundled schema name without its JSON file extension.</param>
    /// <returns>The schema-valid, non-null deserialized value.</returns>
    public static T Read<T>(JsonElement element, string schemaName)
    {
        JsonSchema schema = Schemas.GetOrAdd(schemaName, LoadSchema);
        if (!schema.Evaluate(element).IsValid)
        {
            throw new EvaluationContractException(
                $"JSON does not satisfy {schemaName}; check required fields, types, versions, and allowed values.");
        }

        return element.Deserialize<T>(Options)
            ?? throw new EvaluationContractException($"A {schemaName} object is required.");
    }

    /// <summary>
    ///  Builds an isolated draft-2020-12 schema from an embedded resource.
    /// </summary>
    /// <param name="name">The bundled schema name without its JSON file extension.</param>
    /// <returns>The bundled schema with its own registry.</returns>
    private static JsonSchema LoadSchema(string name)
    {
        using Stream stream = typeof(ContractJson).Assembly.GetManifestResourceStream(
            $"SkillEvaluation.Schemas.{name}.json")
            ?? throw new EvaluationContractException($"Missing bundled schema '{name}'.");

        using JsonDocument document = JsonDocument.Parse(stream);
        return JsonSchema.Build(document.RootElement.Clone(), new BuildOptions
        {
            Dialect = Dialect.Draft202012,
            SchemaRegistry = new()
        });
    }

    /// <summary>
    ///  Serializes a value using the evaluation contract settings.
    /// </summary>
    /// <typeparam name="T">The serialized value's type.</typeparam>
    /// <param name="value">The value to serialize.</param>
    /// <returns>Indented JSON with camel-case property names and kebab-case enum names.</returns>
    public static string Serialize<T>(T value) => JsonSerializer.Serialize(value, Options);

    /// <summary>
    ///  Computes a SHA-256 revision from unmodified bytes.
    /// </summary>
    /// <param name="bytes">The bytes to hash.</param>
    /// <returns>The uppercase hexadecimal SHA-256 hash.</returns>
    public static string HashBytes(ReadOnlySpan<byte> bytes) =>
        Convert.ToHexString(SHA256.HashData(bytes));

    /// <summary>
    ///  Computes a SHA-256 revision after normalizing CRLF to LF and encoding as UTF-8.
    /// </summary>
    /// <param name="text">The text to normalize and hash.</param>
    /// <returns>The uppercase hexadecimal SHA-256 hash of the normalized UTF-8 bytes.</returns>
    public static string HashText(string text) =>
        HashBytes(Encoding.UTF8.GetBytes(text.Replace("\r\n", "\n", StringComparison.Ordinal)));

    /// <summary>
    ///  Computes a SHA-256 revision from a file's raw bytes.
    /// </summary>
    /// <param name="path">The path of the file to read.</param>
    /// <returns>The uppercase hexadecimal SHA-256 hash of the file bytes.</returns>
    public static string HashFile(string path)
    {
        using FileStream stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream));
    }

    /// <summary>
    ///  Computes a revision of a value's serialized contract JSON.
    /// </summary>
    /// <typeparam name="T">The serialized value's type.</typeparam>
    /// <param name="value">The value whose serialized representation is hashed.</param>
    /// <returns>The uppercase hexadecimal SHA-256 hash of the serialized value.</returns>
    public static string Revision<T>(T value) => HashText(Serialize(value));

    /// <summary>
    ///  Writes indented contract JSON to a new UTF-8 file with a trailing LF.
    /// </summary>
    /// <typeparam name="T">The serialized value's type.</typeparam>
    /// <param name="path">The file path to create without overwriting an existing file.</param>
    /// <param name="value">The contract value to write.</param>
    public static void WriteNew<T>(string path, T value)
    {
        using FileStream stream = new(path, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        byte[] bytes = Encoding.UTF8.GetBytes(Serialize(value) + "\n");
        stream.Write(bytes);
    }
}
