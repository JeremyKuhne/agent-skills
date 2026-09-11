#nullable enable

using System;
using System.IO;

public static class OrdinaryPreferences
{
    public static string CreateDirectory(string applicationDataDirectory)
    {
        ArgumentException.ThrowIfNullOrEmpty(applicationDataDirectory);

        if (!Path.IsPathFullyQualified(applicationDataDirectory))
        {
            throw new ArgumentException(
                "The application-data directory must be fully qualified.",
                nameof(applicationDataDirectory));
        }

        string directory = Path.Join(Path.GetFullPath(applicationDataDirectory), "ExampleApp");

        if (OperatingSystem.IsWindows())
        {
            Directory.CreateDirectory(directory);
        }
        else
        {
            Directory.CreateDirectory(
                directory,
                UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
        }

        return directory;
    }

    public static string Save(string applicationDataDirectory, byte[] payload)
    {
        ArgumentNullException.ThrowIfNull(payload);

        string directory = CreateDirectory(applicationDataDirectory);
        string destination = Path.Join(directory, "settings.json");
        string temporary = Path.Join(directory, $".settings-{Guid.NewGuid():N}.tmp");
        FileStreamOptions options = new()
        {
            Mode = FileMode.CreateNew,
            Access = FileAccess.Write,
            Share = FileShare.None,
        };

        if (!OperatingSystem.IsWindows())
        {
            options.UnixCreateMode = UnixFileMode.UserRead | UnixFileMode.UserWrite;
        }

        FileStream stream = File.Open(temporary, options);
        try
        {
            using (stream)
            {
                EnsureOwnerAccess(stream);
                stream.Write(payload);
            }

            File.Move(temporary, destination, overwrite: true);
            return destination;
        }
        catch (Exception operationError)
        {
            try
            {
                File.Delete(temporary);
            }
            catch (Exception cleanupError)
            {
                throw new AggregateException("Save failed and staging cleanup also failed.", operationError, cleanupError);
            }

            throw;
        }
    }

    private static void EnsureOwnerAccess(FileStream stream)
    {
        if (OperatingSystem.IsWindows())
        {
            return;
        }

        UnixFileMode required = UnixFileMode.UserRead | UnixFileMode.UserWrite;
        UnixFileMode actual = File.GetUnixFileMode(stream.SafeFileHandle);
        if ((actual & required) != required)
        {
            throw new UnauthorizedAccessException(
                "The created settings file does not grant the owner read and write access.");
        }
    }
}