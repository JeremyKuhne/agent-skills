// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Reflection;
using System.Runtime.ExceptionServices;
using System.Text;
using System.Text.Json;

namespace SkillQuality.Oracle;

internal static class Program
{
    private static readonly List<object> s_checks = [];

    private static void Require(bool condition, string message)
    {
        if (!condition)
        {
            throw new InvalidOperationException(message);
        }
    }

    private static void Check(string id, Action action)
    {
        try
        {
            action();
            s_checks.Add(new { id, status = "passed", evidence = "Observed contract assertion passed." });
        }
        catch (Exception exception)
        {
            s_checks.Add(new
            {
                id, status = "failed",
                evidence = $"{exception.GetType().Name}: {exception.Message}"
            });
        }
    }

    private static Type Subject(string name) =>
        Assembly.GetExecutingAssembly().GetTypes().Single(type => type.Name == name
            && !type.IsNested && type.IsAbstract && type.IsSealed);

    private static object? Invoke(MethodInfo method, object?[] arguments)
    {
        try
        {
            return method.Invoke(null, arguments);
        }
        catch (TargetInvocationException exception) when (exception.InnerException is not null)
        {
            ExceptionDispatchInfo.Capture(exception.InnerException).Throw();
            throw;
        }
    }

    private static MethodInfo PublishMethod()
    {
        MethodInfo? method = Subject("SaveText").GetMethod("Publish", BindingFlags.Public | BindingFlags.Static,
            [typeof(string), typeof(Action<TextWriter>), typeof(bool)]);
        Require(method is not null && method.ReturnType == typeof(void), "Expected the public static void Publish API.");
        return method!;
    }

    private static void Publish(string path, Action<TextWriter> write, bool overwrite) =>
        Invoke(PublishMethod(), [path, write, overwrite]);

    private static void Export(string root)
    {
        string directory = Path.Join(root, "export");
        Directory.CreateDirectory(directory);
        string path = Path.Join(directory, "export with spaces.txt");
        byte[] original = [0, 1, 2, 255, 13, 10];
        string content = "new \u03B1 text\r\n";
        byte[] expected = new UTF8Encoding(false).GetBytes(content);

        Check("publish-new-utf8", () =>
        {
            Publish(path, writer => writer.Write(content), overwrite: false);
            Require(File.ReadAllBytes(path).SequenceEqual(expected), "New export bytes differ or contain a BOM.");
        });
        Check("no-overwrite-preserves", () =>
        {
            File.WriteAllBytes(path, original);
            try
            {
                Publish(path, writer => writer.Write("replacement"), overwrite: false);
            }
            catch (Exception exception)
            {
                Console.Error.WriteLine($"Existing destination refused: {exception.GetType().Name}: {exception.Message}");
            }

            Require(File.ReadAllBytes(path).SequenceEqual(original), "overwrite:false changed the existing destination.");
        });
        Check("overwrite-publishes", () =>
        {
            File.WriteAllBytes(path, original);
            Publish(path, writer => writer.Write(content), overwrite: true);
            Require(File.ReadAllBytes(path).SequenceEqual(expected), "Overwrite did not publish exactly the new UTF-8 bytes.");
        });
        Check("failed-callback-preserves", () =>
        {
            File.WriteAllBytes(path, original);
            InvalidOperationException expectedError = new("controlled callback failure");
            Exception? observed = null;
            try
            {
                Publish(path, writer =>
                {
                    writer.Write("partial");
                    writer.Flush();
                    throw expectedError;
                }, overwrite: true);
            }
            catch (Exception exception)
            {
                observed = exception;
            }

            Require(observed is not null, "The callback failure was swallowed.");
            Require(File.ReadAllBytes(path).SequenceEqual(original), "The callback failure changed existing bytes.");
        });
        Check("owned-temp-cleanup", () =>
        {
            string sentinel = Path.Join(directory, "unrelated.tmp");
            File.WriteAllText(sentinel, "keep");
            foreach (bool overwrite in new[] { false, true })
            {
                string target = Path.Join(directory, $"success-{overwrite}.txt");
                if (overwrite)
                {
                    File.WriteAllBytes(target, original);
                }

                string[] before = Directory.GetFileSystemEntries(directory);
                Publish(target, writer => writer.Write(content), overwrite);
                string[] expectedEntries = before.Append(target).Distinct().Order().ToArray();
                Require(Directory.GetFileSystemEntries(directory).Order().SequenceEqual(expectedEntries),
                    "A successful export left temporary files or removed a pre-existing file.");
                Require(File.ReadAllBytes(target).SequenceEqual(expected), "Successful publication changed the text.");
                Require(File.ReadAllText(sentinel) == "keep", "Cleanup changed an unrelated file.");
            }

            foreach (bool overwrite in new[] { false, true })
            {
                string target = Path.Join(directory, $"failure-{overwrite}.txt");
                if (overwrite)
                {
                    File.WriteAllBytes(target, original);
                }

                string[] before = Directory.GetFileSystemEntries(directory).Order().ToArray();
                Exception? failure = null;
                try
                {
                    Publish(target, writer =>
                    {
                        writer.Write("partial");
                        writer.Flush();
                        throw new InvalidOperationException("controlled failure");
                    }, overwrite);
                }
                catch (Exception exception)
                {
                    failure = exception;
                }

                Require(failure is not null, "The callback failure was swallowed.");
                Console.Error.WriteLine($"Expected callback failure: {failure?.GetType().Name}: {failure?.Message}");
                Require(Directory.GetFileSystemEntries(directory).Order().SequenceEqual(before),
                    "A failed export left new files or removed a pre-existing file.");
                Require(File.ReadAllText(sentinel) == "keep", "Cleanup changed an unrelated file.");
            }
        });
    }

    private static T WithScratch<T>(Func<string, T> callback)
    {
        MethodInfo method = Subject("Scratch").GetMethods(BindingFlags.Public | BindingFlags.Static)
            .Single(item => item.Name == "WithScratch" && item.IsGenericMethodDefinition
                && item.GetGenericArguments().Length == 1 && item.GetParameters().Length == 1);
        Type parameter = method.GetParameters()[0].ParameterType;
        Require(parameter.IsGenericType && parameter.GetGenericTypeDefinition() == typeof(Func<,>)
            && parameter.GetGenericArguments()[0] == typeof(string)
            && parameter.GetGenericArguments()[1] == method.GetGenericArguments()[0]
            && method.ReturnType == method.GetGenericArguments()[0], "Expected the public WithScratch<T>(Func<string,T>) API.");
        return (T)Invoke(method.MakeGenericMethod(typeof(T)), [callback])!;
    }

    private static void Scratch(string root)
    {
        string temporaryRoot = Path.GetFullPath(Path.GetTempPath());
        StringComparer pathComparer = OperatingSystem.IsWindows() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal;
        string? captured = null;
        Check("owned-os-temp-subdirectory", () => WithScratch(path =>
        {
            captured = path;
            Require(Path.IsPathFullyQualified(path) && Directory.Exists(path), "Scratch directory was not absolute and present.");
            string relative = Path.GetRelativePath(temporaryRoot, Path.GetFullPath(path));
            Require(relative != "." && relative != ".." && !relative.StartsWith(".." + Path.DirectorySeparatorChar)
                && !Path.IsPathRooted(relative), "Scratch path was not beneath the owning process temporary root.");
            return 0;
        }));
        Check("unique-per-call", () =>
        {
            string first = WithScratch(path => path);
            string second = WithScratch(path => path);
            Require(!pathComparer.Equals(first, second), "Successive calls reused the same scratch path.");
            WithScratch(outer => WithScratch(inner =>
            {
                Require(!pathComparer.Equals(outer, inner) && Directory.Exists(outer), "Nested calls shared or removed an active directory.");
                return 0;
            }));
        });
        Check("return-value", () => Require(WithScratch(_ => 1729) == 1729, "The callback return value changed."));
        Check("normal-cleanup", () =>
        {
            string path = WithScratch(directory =>
            {
                Directory.CreateDirectory(Path.Join(directory, "nested"));
                File.WriteAllText(Path.Join(directory, "nested", "owned.txt"), "owned");
                return directory;
            });
            Require(!Directory.Exists(path), "Success left callback-created scratch contents.");
        });
        Check("exception-cleanup", () =>
        {
            captured = null;
            try
            {
                WithScratch<int>(directory =>
                {
                    captured = directory;
                    File.WriteAllText(Path.Join(directory, "partial.txt"), "partial");
                    throw new InvalidOperationException("controlled callback failure");
                });
            }
            catch (InvalidOperationException)
            {
            }

            Require(captured is not null && !Directory.Exists(captured), "Exception left scratch contents or never called the callback.");
        });
        Check("exception-identity", () =>
        {
            InvalidOperationException expected = new("original callback exception");
            Exception? observed = null;
            try
            {
                WithScratch<int>(_ => throw expected);
            }
            catch (Exception exception)
            {
                observed = exception;
            }

            Require(ReferenceEquals(expected, observed), "The original callback exception was swallowed or replaced.");
        });
        Check("unrelated-directory-preserved", () =>
        {
            string sentinel = Path.Join(temporaryRoot, "unrelated-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(sentinel);
            try
            {
                string file = Path.Join(sentinel, "keep.txt");
                File.WriteAllText(file, "keep");
                WithScratch(directory =>
                {
                    Require(Path.GetFullPath(directory) != sentinel, "A pre-existing unrelated directory was reused.");
                    File.WriteAllText(Path.Join(directory, "owned.txt"), "owned");
                    return 0;
                });
                Require(File.Exists(file) && File.ReadAllText(file) == "keep", "Cleanup removed unrelated temporary contents.");
            }
            finally
            {
                if (Directory.Exists(sentinel))
                {
                    Directory.Delete(sentinel, recursive: true);
                }
            }
        });
    }

    private static int Main(string[] args)
    {
        if (args.Length != 3 || args[0] is not ("dotnet-preserve-export" or "dotnet-disposable-scratch"))
        {
            Console.Error.WriteLine("Specify the case, owned work directory, and receipt path.");
            return 3;
        }

        if (args[0] == "dotnet-preserve-export")
        {
            Export(args[1]);
        }
        else
        {
            Scratch(args[1]);
        }

        File.WriteAllText(args[2], JsonSerializer.Serialize(new { schemaVersion = 1, caseId = args[0], checks = s_checks }));
        return 0;
    }
}
