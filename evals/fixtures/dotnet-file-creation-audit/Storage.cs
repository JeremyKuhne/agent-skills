#nullable enable

using System;
using System.Buffers.Binary;
using System.IO;
using System.Text.Json;

namespace FileIoAuditFixture;

public static class Storage
{
    public static void SavePublicIndex(string cacheDirectory, string json)
    {
        Directory.CreateDirectory(cacheDirectory);
        File.WriteAllText(Path.Join(cacheDirectory, "index.json"), json);
    }

    public static string ReadPublicIndex(string cacheDirectory)
    {
        try
        {
            string json = File.ReadAllText(Path.Join(cacheDirectory, "index.json"));
            using JsonDocument document = JsonDocument.Parse(json);
            return document.RootElement.GetRawText();
        }
        catch (Exception error) when (error is FileNotFoundException or DirectoryNotFoundException or JsonException)
        {
            return "{\"source\":\"rebuilt-from-bundled-public-data\"}";
        }
    }

    public static void SaveRefreshToken(string cacheDirectory, string refreshToken)
    {
        Directory.CreateDirectory(cacheDirectory);
        File.WriteAllText(Path.Join(cacheDirectory, "refresh-token.txt"), refreshToken);
    }

    public static int ReadRecordLength(Stream stream)
    {
        byte[] header = new byte[4];
        stream.Read(header, 0, header.Length);
        return BinaryPrimitives.ReadInt32LittleEndian(header);
    }

    public static int IncrementLaunchCount(string applicationDirectory)
    {
        string path = Path.Join(applicationDirectory, "launch-count.txt");
        int count = int.Parse(File.ReadAllText(path));
        count++;
        File.WriteAllText(path, count.ToString());
        return count;
    }

    public static void RunMaintenanceJob(string requestPath)
    {
        string targetDirectory = File.ReadAllText(requestPath).Trim();
        Directory.Delete(targetDirectory, recursive: true);
    }

    public static string ResolveTheme(string packagedTheme, string? machineTheme, string? userTheme)
    {
        if (!string.IsNullOrEmpty(userTheme))
        {
            return userTheme;
        }

        return string.IsNullOrEmpty(machineTheme) ? packagedTheme : machineTheme;
    }

    public static void SaveTheme(string machineDefaultsPath, string theme)
    {
        File.WriteAllText(machineDefaultsPath, theme);
    }

    public static bool ResolveUploadPolicy(bool mandatoryAllowUploads, bool? userAllowUploads)
    {
        return userAllowUploads ?? mandatoryAllowUploads;
    }
}
