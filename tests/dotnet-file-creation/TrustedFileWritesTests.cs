using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace DotNetFileCreation.Tests;

[TestClass]
public sealed class TrustedFileWritesTests
{
    public static IEnumerable<object[]> InvalidKeys
    {
        get
        {
            yield return [""];
            yield return ["."];
            yield return [".."];
            yield return ["../escape"];
            yield return ["folder/child"];
            yield return ["folder\\child"];
            yield return ["c:relative"];
            yield return ["/absolute"];
            yield return ["\\root-relative"];
            yield return ["\\\\server\\share"];
            yield return ["key:stream"];
            yield return ["trailing."];
            yield return ["trailing "];
            yield return ["UPPERCASE"];
            yield return [new string('a', 65)];
        }
    }

    [TestMethod]
    [DynamicData(nameof(InvalidKeys))]
    public void CreateNew_InvalidKey_ThrowsBeforeCreatingFile(string key)
    {
        string root = CreateTempRoot();
        try
        {
            Assert.ThrowsExactly<ArgumentException>(
                () => TrustedFileWrites.CreateNew(root, key).Dispose());
            Assert.AreEqual(0, Directory.GetFileSystemEntries(root).Length);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [TestMethod]
    public void GetPathAndCreateNew_InvalidParent_ThrowWithoutCreatingDirectory()
    {
        string root = CreateTempRoot();
        string missing = Path.Join(root, "missing-parent");
        try
        {
            Assert.ThrowsExactly<ArgumentException>(
                () => TrustedFileWrites.GetPath("relative", "settings"));
            Assert.ThrowsExactly<DirectoryNotFoundException>(
                () => TrustedFileWrites.CreateNew(missing, "settings").Dispose());
            Assert.IsFalse(Directory.Exists(missing));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [TestMethod]
    public void CreateNew_DeviceLikeKey_MapsSafeLeafAndRefusesOverwrite()
    {
        string root = CreateTempRoot();
        try
        {
            string path = TrustedFileWrites.GetPath(root, "con");
            Assert.AreEqual("item-con.bin", Path.GetFileName(path));

            using (FileStream stream = TrustedFileWrites.CreateNew(root, "con"))
            {
                Assert.IsFalse(stream.CanRead);
                Assert.IsTrue(stream.CanWrite);
                stream.WriteByte(42);
            }

            Assert.ThrowsExactly<IOException>(
                () => TrustedFileWrites.CreateNew(root, "con").Dispose());
            CollectionAssert.AreEqual(new byte[] { 42 }, File.ReadAllBytes(path));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [TestMethod]
    public void CreateScratch_Dispose_RemovesFile()
    {
        string root = CreateTempRoot();
        try
        {
            string path;
            using (FileStream stream = TrustedFileWrites.CreateScratch(root))
            {
                path = stream.Name;
                Assert.IsTrue(File.Exists(path));
                Assert.IsTrue(stream.CanRead);
                Assert.IsTrue(stream.CanWrite);
                stream.WriteByte(42);
                stream.Position = 0;
                Assert.AreEqual(42, stream.ReadByte());
            }

            Assert.IsFalse(File.Exists(path));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [TestMethod]
    public void PublishLastWriterWins_ExistingDestination_ReplacesWithoutStagingFiles()
    {
        string root = CreateTempRoot();
        try
        {
            TrustedFileWrites.PublishLastWriterWins(root, "settings", [1, 2, 3]);
            TrustedFileWrites.PublishLastWriterWins(root, "settings", [4, 5, 6]);

            string path = TrustedFileWrites.GetPath(root, "settings");
            CollectionAssert.AreEqual(new byte[] { 4, 5, 6 }, File.ReadAllBytes(path));
            Assert.AreEqual(1, Directory.GetFileSystemEntries(root).Length);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [TestMethod]
    public void PublishLastWriterWins_ReplacementFailure_CleansStagingFileAndPreservesDestination()
    {
        string root = CreateTempRoot();
        try
        {
            string path = TrustedFileWrites.GetPath(root, "settings");
            Directory.CreateDirectory(path);
            string marker = Path.Join(path, "keep.txt");
            File.WriteAllText(marker, "existing");

            Exception exception = Assert.Throws<Exception>(() =>
                TrustedFileWrites.PublishLastWriterWins(root, "settings", [1, 2, 3]));
            Assert.IsTrue(
                exception is IOException or UnauthorizedAccessException,
                $"Unexpected exception type: {exception.GetType().FullName}");

            Assert.AreEqual("existing", File.ReadAllText(marker));
            Assert.AreEqual(1, Directory.GetFileSystemEntries(root).Length);
            Assert.AreEqual(0, Directory.GetFiles(root, ".stage-*", SearchOption.TopDirectoryOnly).Length);
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    private static string CreateTempRoot()
    {
        return Directory.CreateTempSubdirectory("skilltest_").FullName;
    }
}