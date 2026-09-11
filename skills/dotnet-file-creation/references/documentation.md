# Primary documentation index

Curated links behind the `dotnet-file-creation` guidance, grouped by the
question they answer.

The sources consulted for the security and publication review on 2026-09-09 are
summarized in [research.md](research.md), alongside execution results and gaps.
This index also retains the broader API reference list. API documentation
supplies contracts within its stated scope; versioned runtime source supplies
implementation evidence, not a promise for every runtime or filesystem.

## Trust boundaries and independent guidance

- [SEI CERT FIO15-C: secure directories](https://cmu-sei.github.io/secure-coding-standards/sei-cert-c-coding-standard/recommendations/input-output-fio/fio15-c) - trusted owners, stable ancestors, and the loose binding between paths and objects
- [Windows file security and access rights](https://learn.microsoft.com/windows/win32/fileio/file-security-and-access-rights) - file-inheritable ACLs, object-specific access checks, and traversal privilege
- [Windows DeleteFile](https://learn.microsoft.com/windows/win32/api/fileapi/nf-fileapi-deletefilew) - delete sharing, parent delete-child rights, and open-handle lifetime
- [Apple chmod manual source](https://raw.githubusercontent.com/apple-oss-distributions/file_cmds/main/chmod/chmod.1) - macOS ACL entries, inheritance, and delete/delete-child rights are separate from ordinary mode bits
- [Linux umask(2)](https://man7.org/linux/man-pages/man2/umask.2.html) - owner bits can be masked out; default ACLs change the creation calculation
- [Linux rename(2)](https://man7.org/linux/man-pages/man2/rename.2.html) - atomic namespace replacement, open descriptors, and ambiguous NFS failure
- [Linux fsync(2)](https://man7.org/linux/man-pages/man2/fsync.2.html) - file synchronization does not necessarily synchronize its directory entry
- [SQLite atomic commit](https://www.sqlite.org/atomiccommit.html) - a real durability protocol, storage assumptions, and crash testing
- [SQLite corruption hazards](https://www.sqlite.org/howtocorrupt.html) - locking failures, unlinking live files, and incomplete synchronization

## Inspected .NET implementation

These source links are pinned to the .NET 10.0.0 release. Recheck the deployed
runtime when an implementation detail controls the decision.

- [Unix filesystem implementation](https://raw.githubusercontent.com/dotnet/runtime/v10.0.0/src/libraries/System.Private.CoreLib/src/System/IO/FileSystem.Unix.cs) - leaf-only explicit directory modes, existing-directory reuse, rename and cross-device copy fallback
- [Windows filesystem implementation](https://raw.githubusercontent.com/dotnet/runtime/v10.0.0/src/libraries/System.Private.CoreLib/src/System/IO/FileSystem.Windows.cs) - delegation to Windows move and replace primitives
- [Unix SafeFileHandle implementation](https://raw.githubusercontent.com/dotnet/runtime/v10.0.0/src/libraries/System.Private.CoreLib/src/Microsoft/Win32/SafeHandles/SafeFileHandle.Unix.cs) - exclusive create, coarse best-effort sharing, and managed unlink for `DeleteOnClose`

## Creating and opening

- [File class](https://learn.microsoft.com/dotnet/api/system.io.file)
- [File.Open](https://learn.microsoft.com/dotnet/api/system.io.file.open)
- [File.Create](https://learn.microsoft.com/dotnet/api/system.io.file.create)
- [File.OpenHandle](https://learn.microsoft.com/dotnet/api/system.io.file.openhandle)
- [FileStreamOptions](https://learn.microsoft.com/dotnet/api/system.io.filestreamoptions)
- [FileMode](https://learn.microsoft.com/dotnet/api/system.io.filemode) - `CreateNew` is the atomic create-if-absent
- [FileAccess](https://learn.microsoft.com/dotnet/api/system.io.fileaccess)
- [FileShare](https://learn.microsoft.com/dotnet/api/system.io.fileshare)
- [FileOptions](https://learn.microsoft.com/dotnet/api/system.io.fileoptions) - `DeleteOnClose`, `Asynchronous`, `WriteThrough`
- [RandomAccess](https://learn.microsoft.com/dotnet/api/system.io.randomaccess) - handle-based positional I/O

## Permissions

- [UnixFileMode enum](https://learn.microsoft.com/dotnet/api/system.io.unixfilemode)
- [FileStreamOptions.UnixCreateMode](https://learn.microsoft.com/dotnet/api/system.io.filestreamoptions.unixcreatemode) - the setter carries `[UnsupportedOSPlatform("windows")]`
- [File.GetUnixFileMode](https://learn.microsoft.com/dotnet/api/system.io.file.getunixfilemode)
- [File.SetUnixFileMode](https://learn.microsoft.com/dotnet/api/system.io.file.setunixfilemode)
- [Directory.CreateDirectory(String, UnixFileMode)](https://learn.microsoft.com/dotnet/api/system.io.directory.createdirectory)
- [FileSystemAclExtensions](https://learn.microsoft.com/dotnet/api/system.io.filesystemaclextensions) - the Windows counterpart
- [OperatingSystem.IsWindows](https://learn.microsoft.com/dotnet/api/system.operatingsystem.iswindows) - the guard CA1416 recognizes
- [CA1416: Validate platform compatibility](https://learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules/ca1416)
- [Platform compatibility analyzer](https://learn.microsoft.com/dotnet/standard/analyzers/platform-compat-analyzer)
- [Annotating APIs as platform-specific](https://learn.microsoft.com/dotnet/standard/analyzers/platform-compat-analyzer#advanced-scenarios)

## Temporary files

- [Directory.CreateTempSubdirectory](https://learn.microsoft.com/dotnet/api/system.io.directory.createtempsubdirectory) - documents the `700` mode on Unix
- [Path.GetTempPath](https://learn.microsoft.com/dotnet/api/system.io.path.gettemppath)
- [Windows GetTempPath2](https://learn.microsoft.com/windows/win32/api/fileapi/nf-fileapi-gettemppath2w) - SYSTEM's `SystemTemp` override, non-SYSTEM search order, retained links, and no access validation
- [Path.GetTempFileName](https://learn.microsoft.com/dotnet/api/system.io.path.gettempfilename) - the Windows 65,535-name limit was removed in .NET 8
- [Path.GetRandomFileName](https://learn.microsoft.com/dotnet/api/system.io.path.getrandomfilename)

## Where state belongs

- [Environment.SpecialFolder](https://learn.microsoft.com/dotnet/api/system.environment.specialfolder)
- [Environment.GetFolderPath](https://learn.microsoft.com/dotnet/api/system.environment.getfolderpath) - the default option returns an empty string when the directory does not exist; `Create` creates it
- [.NET 8+ GetFolderPath changes on Unix](https://learn.microsoft.com/dotnet/core/compatibility/core-libraries/8.0/getfolderpath-unix) - macOS maps both application-data identifiers to Application Support, not Linux XDG locations
- [KNOWNFOLDERID](https://learn.microsoft.com/windows/win32/shell/knownfolderid) - the Windows canonical list
- [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/latest/) - separate configuration, data, cache, state, and runtime directories; absolute environment paths
- [Isolated storage in multi-user environments](https://learn.microsoft.com/dotnet/standard/io/isolated-storage#impact-in-multi-user-environments)
- [File Access Guide for macOS](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html)

## Paths

- [File path formats on Windows systems](https://learn.microsoft.com/dotnet/standard/io/file-path-formats) - normalization, trailing dots and spaces, legacy device names
- [Path class](https://learn.microsoft.com/dotnet/api/system.io.path)
- [Path.Join](https://learn.microsoft.com/dotnet/api/system.io.path.join) - joins without allowing a rooted later segment to replace the root
- [Path.Combine](https://learn.microsoft.com/dotnet/api/system.io.path.combine) - a rooted later segment discards the earlier path; use only when that replacement is intended or inputs have been constrained
- [Path.IsPathRooted](https://learn.microsoft.com/dotnet/api/system.io.path.ispathrooted) - detects root syntax, including Windows rooted-relative paths
- [Path.IsPathFullyQualified](https://learn.microsoft.com/dotnet/api/system.io.path.ispathfullyqualified) - detects whether current drive or directory state can affect resolution
- [Path.GetFullPath](https://learn.microsoft.com/dotnet/api/system.io.path.getfullpath) - use the overload with a fully qualified base for deterministic relative-path resolution
- [Maximum path length limitation](https://learn.microsoft.com/windows/win32/fileio/maximum-file-path-limitation) - manifest and policy requirements for native Win32 callers
- [Naming files, paths, and namespaces](https://learn.microsoft.com/windows/win32/fileio/naming-a-file)

## Links and reparse points

- [File.CreateSymbolicLink](https://learn.microsoft.com/dotnet/api/system.io.file.createsymboliclink)
- [File.ResolveLinkTarget](https://learn.microsoft.com/dotnet/api/system.io.file.resolvelinktarget)
- [Symbolic link effects on file system functions](https://learn.microsoft.com/windows/win32/fileio/symbolic-link-effects-on-file-systems-functions)
- [Create symbolic links privilege](https://learn.microsoft.com/windows/security/threat-protection/security-policy-settings/create-symbolic-links)

## Moving, replacing, and durability

- [File.Move](https://learn.microsoft.com/dotnet/api/system.io.file.move)
- [File.Replace](https://learn.microsoft.com/dotnet/api/system.io.file.replace) - requires an existing destination, accepts an optional backup, and has platform-specific metadata semantics
- [FileStream.Flush(Boolean)](https://learn.microsoft.com/dotnet/api/system.io.filestream.flush)
- [FileStream.SafeFileHandle](https://learn.microsoft.com/dotnet/api/system.io.filestream.safefilehandle)

## Attributes and metadata

- [FileAttributes](https://learn.microsoft.com/dotnet/api/system.io.fileattributes)
- [File.SetAttributes](https://learn.microsoft.com/dotnet/api/system.io.file.setattributes)
- [FileSystemInfo.UnixFileMode](https://learn.microsoft.com/dotnet/api/system.io.filesysteminfo.unixfilemode)

## Secrets

- [ProtectedData class (DPAPI)](https://learn.microsoft.com/dotnet/api/system.security.cryptography.protecteddata) - Windows only
- [Safe storage of app secrets in development](https://learn.microsoft.com/aspnet/core/security/app-secrets)
- [Data Protection in ASP.NET Core](https://learn.microsoft.com/aspnet/core/security/data-protection/introduction)

## Background

- [File and stream I/O](https://learn.microsoft.com/dotnet/standard/io/)
- [Common I/O tasks](https://learn.microsoft.com/dotnet/standard/io/common-i-o-tasks)
- [FileStream performance improvements in .NET 6](https://devblogs.microsoft.com/dotnet/file-io-improvements-in-dotnet-6/)
- [Breaking change: FileStream strategy](https://learn.microsoft.com/dotnet/core/compatibility/core-libraries/6.0/filestream-doesnt-allocate-buffer)
- [open(2)](https://man7.org/linux/man-pages/man2/open.2.html) and [umask(2)](https://man7.org/linux/man-pages/man2/umask.2.html) - what the mode argument actually does
