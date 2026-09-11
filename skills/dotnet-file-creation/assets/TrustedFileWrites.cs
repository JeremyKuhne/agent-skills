#nullable enable

using System;
using System.IO;

public static class TrustedFileWrites
{
    public static string GetPath(string trustedDirectory, string key)
    {
        ArgumentException.ThrowIfNullOrEmpty(trustedDirectory);
        ArgumentException.ThrowIfNullOrEmpty(key);

        if (!Path.IsPathFullyQualified(trustedDirectory))
        {
            throw new ArgumentException("The trusted directory must be fully qualified.", nameof(trustedDirectory));
        }

        if (key.Length > 64)
        {
            throw new ArgumentException("The key must contain at most 64 characters.", nameof(key));
        }

        foreach (char character in key)
        {
            if (character is not (>= 'a' and <= 'z' or >= '0' and <= '9' or '-' or '_'))
            {
                throw new ArgumentException("Use only lowercase ASCII letters, digits, hyphens, and underscores.", nameof(key));
            }
        }

        string root = Path.GetFullPath(trustedDirectory);
        return Path.Join(root, $"item-{key}.bin");
    }

    public static FileStream CreateNew(string trustedDirectory, string key)
    {
        return OpenNew(GetPath(trustedDirectory, key), FileAccess.Write, FileOptions.None);
    }

    public static FileStream CreateScratch(string trustedDirectory)
    {
        string path = GetPath(trustedDirectory, $"scratch-{Guid.NewGuid():N}");
        return OpenNew(path, FileAccess.ReadWrite, FileOptions.DeleteOnClose);
    }

    public static void PublishLastWriterWins(string trustedDirectory, string key, byte[] payload)
    {
        ArgumentNullException.ThrowIfNull(payload);

        string destination = GetPath(trustedDirectory, key);
        string directory = Path.GetDirectoryName(destination)!;
        string temporary = Path.Join(directory, $".stage-{Guid.NewGuid():N}.tmp");
        bool temporaryCreated = false;

        try
        {
            using (FileStream stream = OpenNew(temporary, FileAccess.Write, FileOptions.None))
            {
                temporaryCreated = true;
                stream.Write(payload);
                stream.Flush(flushToDisk: true);
            }

            File.Move(temporary, destination, overwrite: true);
        }
        catch (Exception operationError)
        {
            if (temporaryCreated)
            {
                try
                {
                    File.Delete(temporary);
                }
                catch (Exception cleanupError)
                {
                    throw new AggregateException(
                        "Publication failed and staging cleanup also failed.",
                        operationError,
                        cleanupError);
                }
            }

            throw;
        }
    }

    private static FileStream OpenNew(string path, FileAccess access, FileOptions fileOptions)
    {
        FileStreamOptions options = new()
        {
            Mode = FileMode.CreateNew,
            Access = access,
            Share = FileShare.None,
            Options = fileOptions,
        };

        if (!OperatingSystem.IsWindows())
        {
            options.UnixCreateMode = UnixFileMode.UserRead | UnixFileMode.UserWrite;
        }

        FileStream stream = File.Open(path, options);
        if (OperatingSystem.IsWindows())
        {
            return stream;
        }

        try
        {
            UnixFileMode required = UnixFileMode.UserRead | UnixFileMode.UserWrite;
            UnixFileMode actual = File.GetUnixFileMode(stream.SafeFileHandle);
            if ((actual & required) != required)
            {
                throw new UnauthorizedAccessException(
                    "The created file does not grant the owner read and write access.");
            }

            return stream;
        }
        catch (Exception operationError)
        {
            try
            {
                stream.Dispose();
                File.Delete(path);
            }
            catch (Exception cleanupError)
            {
                throw new AggregateException(
                    "File creation failed and cleanup also failed.",
                    operationError,
                    cleanupError);
            }

            throw;
        }
    }
}