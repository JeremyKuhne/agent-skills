#requires -Version 7.0

# These tests exercise the real System.IO surface on the host runtime and filesystem.
# Platform-specific cases do not certify other hosts, ACL policies, or crash recovery.

Describe 'Cross-platform file creation behavior' {

    BeforeAll {
        $ErrorActionPreference = 'Stop'

        $script:OwnerOnlyFile = [System.IO.UnixFileMode]'UserRead, UserWrite'
        $script:OwnerOnlyDirectory = [System.IO.UnixFileMode]'UserRead, UserWrite, UserExecute'

        $recipePath = Join-Path $PSScriptRoot '../../skills/dotnet-file-creation/assets/TrustedFileWrites.cs'
        if (-not ('TrustedFileWrites' -as [type])) {
            Add-Type -Path $recipePath
        }

        $ordinaryRecipePath = Join-Path $PSScriptRoot '../../skills/dotnet-file-creation/assets/OrdinaryPreferences.cs'
        if (-not ('OrdinaryPreferences' -as [type])) {
            Add-Type -Path $ordinaryRecipePath
        }

        function New-TempRoot {
            [System.IO.Directory]::CreateTempSubdirectory('skilltest_').FullName
        }

        # PowerShell wraps exceptions from .NET method calls and property sets, so an assertion on
        # the outer type would never see the exception the runtime actually threw.
        function Get-ThrownException {
            param([scriptblock] $Action)

            try {
                & $Action
                return $null
            }
            catch {
                $exception = $_.Exception
                while ($null -ne $exception.InnerException -and (
                        $exception -is [System.Management.Automation.MethodInvocationException] -or
                        $exception -is [System.Management.Automation.SetValueInvocationException])) {
                    $exception = $exception.InnerException
                }
                return $exception
            }
        }

        function Get-Mode {
            param([string] $Path)
            [System.IO.File]::GetUnixFileMode($Path)
        }

        function New-FileWithMode {
            param([string] $Path, [System.IO.UnixFileMode] $Mode)

            $options = [System.IO.FileStreamOptions]::new()
            $options.Mode = [System.IO.FileMode]::CreateNew
            $options.Access = [System.IO.FileAccess]::Write
            if (-not $IsWindows) {
                $options.UnixCreateMode = $Mode
            }

            $stream = [System.IO.File]::Open($Path, $options)
            $stream.Dispose()
            $Path
        }
    }

    Context 'Ordinary application preferences' {

        It 'rejects an unavailable or relative application-data root: <Root>' -ForEach @(
            @{ Root = '' }
            @{ Root = 'relative' }
        ) {
            Get-ThrownException { [OrdinaryPreferences]::CreateDirectory($Root) } |
                Should -BeOfType ([System.ArgumentException])
        }

        It 'creates the app directory, saves preferences, and replaces a longer previous value' {
            $root = New-TempRoot
            try {
                $first = [System.Text.Encoding]::UTF8.GetBytes('{"theme":"system"}')
                $second = [System.Text.Encoding]::UTF8.GetBytes('{}')
                $path = [OrdinaryPreferences]::Save($root, $first)
                $path | Should -Be ([System.IO.Path]::Join($root, 'ExampleApp', 'settings.json'))
                [System.IO.File]::ReadAllText($path) | Should -Be '{"theme":"system"}'

                [OrdinaryPreferences]::Save($root, $second) | Should -Be $path
                [System.IO.File]::ReadAllText($path) | Should -Be '{}'
                @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetDirectoryName($path)) -Force).Count |
                    Should -Be 1
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }

        It 'reuses ordinary existing application storage without altering unrelated content' {
            $root = New-TempRoot
            try {
                $directory = [OrdinaryPreferences]::CreateDirectory($root)
                $unrelated = [System.IO.Path]::Join($directory, 'keep.txt')
                [System.IO.File]::WriteAllText($unrelated, 'keep')

                [OrdinaryPreferences]::Save($root, [System.Text.Encoding]::UTF8.GetBytes('{}')) | Out-Null

                [System.IO.File]::ReadAllText($unrelated) | Should -Be 'keep'
                [OrdinaryPreferences]::CreateDirectory($root) | Should -Be $directory
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }

        It 'reports a failed replacement and removes only its staging file' {
            $root = New-TempRoot
            try {
                $directory = [OrdinaryPreferences]::CreateDirectory($root)
                $destination = [System.IO.Path]::Join($directory, 'settings.json')
                [System.IO.Directory]::CreateDirectory($destination) | Out-Null
                $marker = [System.IO.Path]::Join($destination, 'keep.txt')
                [System.IO.File]::WriteAllText($marker, 'keep')

                { [OrdinaryPreferences]::Save($root, [System.Text.Encoding]::UTF8.GetBytes('{}')) } |
                    Should -Throw

                [System.IO.File]::ReadAllText($marker) | Should -Be 'keep'
                @(Get-ChildItem -LiteralPath $directory -Force).Count | Should -Be 1
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }

        It 'requests restrictive modes for new ordinary app storage and preferences on Unix' -Skip:$IsWindows {
            $root = New-TempRoot
            try {
                $path = [OrdinaryPreferences]::Save($root, [System.Text.Encoding]::UTF8.GetBytes('{}'))
                $directoryMode = Get-Mode -Path ([System.IO.Path]::GetDirectoryName($path))
                $fileMode = Get-Mode -Path $path

                ([int]$directoryMode -band 0x1FF -band -bnot [int]$script:OwnerOnlyDirectory) | Should -Be 0
                ([int]$fileMode -band 0x1FF -band -bnot [int]$script:OwnerOnlyFile) | Should -Be 0
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    Context 'Trusted-parent recipes' {

        It 'rejects unsafe application keys before creating a file: <Key>' -ForEach @(
            @{ Key = '' }
            @{ Key = '.' }
            @{ Key = '..' }
            @{ Key = '../escape' }
            @{ Key = 'folder/child' }
            @{ Key = 'folder\child' }
            @{ Key = 'c:relative' }
            @{ Key = '/absolute' }
            @{ Key = '\root-relative' }
            @{ Key = '\\server\share' }
            @{ Key = 'key:stream' }
            @{ Key = 'trailing.' }
            @{ Key = 'trailing ' }
            @{ Key = 'UPPERCASE' }
            @{ Key = ('a' * 65) }
        ) {
            $root = New-TempRoot
            try {
                Get-ThrownException { [TrustedFileWrites]::CreateNew($root, $Key).Dispose() } |
                    Should -BeOfType ([System.ArgumentException])
                @(Get-ChildItem -LiteralPath $root -Force).Count | Should -Be 0
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }

        It 'requires a fully qualified parent and does not create missing parents' {
            Get-ThrownException { [TrustedFileWrites]::GetPath('relative', 'settings') } |
                Should -BeOfType ([System.ArgumentException])

            $missing = Join-Path $TestDrive 'missing-parent'
            Get-ThrownException { [TrustedFileWrites]::CreateNew($missing, 'settings').Dispose() } |
                Should -BeOfType ([System.IO.DirectoryNotFoundException])
            $missing | Should -Not -Exist
        }

        It 'maps a device-like key to a safe leaf and refuses to overwrite it' {
            $root = New-TempRoot
            try {
                $path = [TrustedFileWrites]::GetPath($root, 'con')
                [System.IO.Path]::GetFileName($path) | Should -Be 'item-con.bin'
                $stream = [TrustedFileWrites]::CreateNew($root, 'con')
                try {
                    $stream.CanRead | Should -BeFalse
                    $stream.CanWrite | Should -BeTrue
                    $stream.WriteByte(42)
                }
                finally { $stream.Dispose() }

                Get-ThrownException { [TrustedFileWrites]::CreateNew($root, 'con').Dispose() } |
                    Should -BeOfType ([System.IO.IOException])
                [System.IO.File]::ReadAllBytes($path) | Should -Be @(42)
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }

        It 'removes scratch on normal disposal' {
            $root = New-TempRoot
            try {
                $stream = [TrustedFileWrites]::CreateScratch($root)
                $path = $stream.Name
                try {
                    $path | Should -Exist
                    $stream.CanRead | Should -BeTrue
                    $stream.CanWrite | Should -BeTrue
                    $stream.WriteByte(42)
                    $stream.Position = 0
                    $stream.ReadByte() | Should -Be 42
                }
                finally { $stream.Dispose() }
                $path | Should -Not -Exist
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }

        It 'publishes a new destination and replaces it without leaving staging files' {
            $root = New-TempRoot
            try {
                [TrustedFileWrites]::PublishLastWriterWins($root, 'settings', [byte[]](1, 2, 3))
                [TrustedFileWrites]::PublishLastWriterWins($root, 'settings', [byte[]](4, 5, 6))
                $path = [TrustedFileWrites]::GetPath($root, 'settings')
                [System.IO.File]::ReadAllBytes($path) | Should -Be @(4, 5, 6)
                @(Get-ChildItem -LiteralPath $root -Force).Count | Should -Be 1
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }

        It 'cleans its staging file when the destination cannot be replaced' {
            $root = New-TempRoot
            try {
                $path = [TrustedFileWrites]::GetPath($root, 'settings')
                [System.IO.Directory]::CreateDirectory($path) | Out-Null
                $marker = Join-Path $path 'keep.txt'
                [System.IO.File]::WriteAllText($marker, 'existing')

                { [TrustedFileWrites]::PublishLastWriterWins($root, 'settings', [byte[]](1, 2, 3)) } |
                    Should -Throw

                [System.IO.File]::ReadAllText($marker) | Should -Be 'existing'
                @(Get-ChildItem -LiteralPath $root -Force).Count | Should -Be 1
                @(Get-ChildItem -LiteralPath $root -Filter '.stage-*' -Force).Count | Should -Be 0
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }

        It 'creates and publishes files without group or other mode bits on Unix' -Skip:$IsWindows {
            $root = New-TempRoot
            try {
                $stream = [TrustedFileWrites]::CreateNew($root, 'new')
                try {
                    $mode = [System.IO.File]::GetUnixFileMode($stream.SafeFileHandle)
                    ([int]$mode -band -bnot [int]$script:OwnerOnlyFile) | Should -Be 0
                }
                finally { $stream.Dispose() }

                [TrustedFileWrites]::PublishLastWriterWins($root, 'settings', [byte[]](1, 2, 3))
                $mode = Get-Mode -Path ([TrustedFileWrites]::GetPath($root, 'settings'))
                ([int]$mode -band -bnot [int]$script:OwnerOnlyFile) | Should -Be 0
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }

        It 'inherits the deliberately restricted Windows file ACL for new and published files' -Skip:(-not $IsWindows) {
            $root = New-TempRoot
            $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
            try {
                $security = [System.Security.AccessControl.DirectorySecurity]::new()
                $security.SetAccessRuleProtection($true, $false)
                $inheritance = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
                $security.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new(
                    $identity.User,
                    [System.Security.AccessControl.FileSystemRights]::FullControl,
                    $inheritance,
                    [System.Security.AccessControl.PropagationFlags]::None,
                    [System.Security.AccessControl.AccessControlType]::Allow))
                [System.IO.FileSystemAclExtensions]::SetAccessControl(
                    [System.IO.DirectoryInfo]::new($root), $security)

                [TrustedFileWrites]::CreateNew($root, 'new').Dispose()
                [TrustedFileWrites]::PublishLastWriterWins($root, 'published', [byte[]](1, 2, 3))

                foreach ($key in @('new', 'published')) {
                    $file = [System.IO.FileInfo]::new([TrustedFileWrites]::GetPath($root, $key))
                    $acl = [System.IO.FileSystemAclExtensions]::GetAccessControl($file)
                    $rules = @($acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
                    $rules.Count | Should -Be 1
                    $rules[0].IdentityReference.Value | Should -Be $identity.User.Value
                    $rules[0].AccessControlType | Should -Be 'Allow'
                    $rules[0].IsInherited | Should -BeTrue
                }
            }
            finally {
                $identity.Dispose()
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }

        It 'retains old readers and handles backend refusal without damaging the destination' {
            $root = New-TempRoot
            try {
                [TrustedFileWrites]::PublishLastWriterWins($root, 'settings', [byte[]](42))
                $path = [TrustedFileWrites]::GetPath($root, 'settings')
                $reader = [System.IO.File]::Open($path, 'Open', 'Read', 'Read, Delete')
                try {
                    $failure = Get-ThrownException {
                        [TrustedFileWrites]::PublishLastWriterWins($root, 'settings', [byte[]](43))
                    }
                    $reader.ReadByte() | Should -Be 42
                    if ($IsWindows -and $null -ne $failure) {
                        ($failure -is [System.IO.IOException] -or
                            $failure -is [System.UnauthorizedAccessException]) | Should -BeTrue
                        [System.IO.File]::ReadAllBytes($path) | Should -Be @(42)
                    }
                    else {
                        $failure | Should -BeNullOrEmpty
                        [System.IO.File]::ReadAllBytes($path) | Should -Be @(43)
                    }
                    @(Get-ChildItem -LiteralPath $root -Force).Count | Should -Be 1
                }
                finally { $reader.Dispose() }
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }

        It 'preserves the destination and cleans staging when Windows delete sharing is denied' -Skip:(-not $IsWindows) {
            $root = New-TempRoot
            try {
                [TrustedFileWrites]::PublishLastWriterWins($root, 'settings', [byte[]](42))
                $path = [TrustedFileWrites]::GetPath($root, 'settings')
                $reader = [System.IO.File]::Open($path, 'Open', 'Read', 'Read')
                try {
                    $failure = Get-ThrownException {
                        [TrustedFileWrites]::PublishLastWriterWins($root, 'settings', [byte[]](43))
                    }
                    ($failure -is [System.IO.IOException] -or
                        $failure -is [System.UnauthorizedAccessException]) | Should -BeTrue
                    $reader.ReadByte() | Should -Be 42
                    @(Get-ChildItem -LiteralPath $root -Force).Count | Should -Be 1
                }
                finally { $reader.Dispose() }
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    Context 'Temporary state' {

        It 'creates a temp subdirectory under the temp path' {
            $root = New-TempRoot
            try {
                $root | Should -Exist
                @(Get-ChildItem -LiteralPath $root -Force).Count | Should -Be 0
                $root.StartsWith([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()),
                    [StringComparison]::OrdinalIgnoreCase) | Should -BeTrue
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }

        It 'requests no group or other directory mode bits on Unix and rejects the query on Windows' {
            $root = New-TempRoot
            try {
                if ($IsWindows) {
                    Get-ThrownException { Get-Mode -Path $root } |
                        Should -BeOfType ([System.PlatformNotSupportedException])
                }
                else {
                    ([int](Get-Mode -Path $root) -band 0x1FF -band -bnot [int]$script:OwnerOnlyDirectory) |
                        Should -Be 0
                }
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }

        It 'creates a zero-byte temp file with no extra ordinary mode bits on Unix' {
            $file = [System.IO.Path]::GetTempFileName()
            try {
                (Get-Item -LiteralPath $file).Length | Should -Be 0
                if (-not $IsWindows) {
                    ([int](Get-Mode -Path $file) -band 0x1FF -band -bnot [int]$script:OwnerOnlyFile) |
                        Should -Be 0
                }
            }
            finally { Remove-Item -LiteralPath $file -Force }
        }
    }

    Context 'Explicit permissions' {

        It 'rejects UnixCreateMode on Windows and honors it on Unix' {
            # The attribute sits on the setter, so CA1416 flags an unguarded assignment at build
            # time and the setter throws at run time. Guard the assignment, not the open call.
            $options = [System.IO.FileStreamOptions]::new()

            if ($IsWindows) {
                Get-ThrownException { $options.UnixCreateMode = $script:OwnerOnlyFile } |
                    Should -BeOfType ([System.PlatformNotSupportedException])
            }
            else {
                { $options.UnixCreateMode = $script:OwnerOnlyFile } | Should -Not -Throw
                $options.UnixCreateMode | Should -Be $script:OwnerOnlyFile
            }
        }

        It 'creates a file without granting bits beyond the requested owner-only mode on Unix' -Skip:$IsWindows {
            $root = New-TempRoot
            try {
                $path = New-FileWithMode -Path (Join-Path $root 'private.txt') -Mode $script:OwnerOnlyFile
                ([int](Get-Mode -Path $path) -band -bnot [int]$script:OwnerOnlyFile) | Should -Be 0
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }

        It 'never grants more than the requested mode on Unix' -Skip:$IsWindows {
            $root = New-TempRoot
            try {
                $requested = [System.IO.UnixFileMode]'UserRead, UserWrite, GroupRead, GroupWrite, OtherRead, OtherWrite'
                $path = New-FileWithMode -Path (Join-Path $root 'permissive.txt') -Mode $requested
                $actual = Get-Mode -Path $path

                ([int]$actual -band -bnot [int]$requested) | Should -Be 0
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }

        It 'rejects SetUnixFileMode on Windows and round-trips it on Unix' {
            $root = New-TempRoot
            try {
                $path = Join-Path $root 'mode.txt'
                Set-Content -LiteralPath $path -Value 'x' -NoNewline

                if ($IsWindows) {
                    Get-ThrownException { [System.IO.File]::SetUnixFileMode($path, $script:OwnerOnlyFile) } |
                        Should -BeOfType ([System.PlatformNotSupportedException])
                }
                else {
                    [System.IO.File]::SetUnixFileMode($path, $script:OwnerOnlyFile)
                    Get-Mode -Path $path | Should -Be $script:OwnerOnlyFile
                }
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }

        It 'does not tighten an existing file through UnixCreateMode' -Skip:$IsWindows {
            $root = New-TempRoot
            try {
                $path = Join-Path $root 'existing.txt'
                [System.IO.File]::WriteAllText($path, 'existing')
                $existingMode = [System.IO.UnixFileMode]'UserRead, UserWrite, GroupRead'
                [System.IO.File]::SetUnixFileMode($path, $existingMode)
                $options = [System.IO.FileStreamOptions]::new()
                $options.Mode = [System.IO.FileMode]::OpenOrCreate
                $options.Access = [System.IO.FileAccess]::ReadWrite
                $options.UnixCreateMode = $script:OwnerOnlyFile

                [System.IO.File]::Open($path, $options).Dispose()

                Get-Mode -Path $path | Should -Be $existingMode
                [System.IO.File]::ReadAllText($path) | Should -Be 'existing'
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }

        It 'does not tighten an existing directory through CreateDirectory' -Skip:$IsWindows {
            $root = New-TempRoot
            try {
                $path = Join-Path $root 'existing'
                [System.IO.Directory]::CreateDirectory($path) | Out-Null
                $existingMode = [System.IO.UnixFileMode]'UserRead, UserWrite, UserExecute, GroupRead, GroupExecute'
                [System.IO.File]::SetUnixFileMode($path, $existingMode)

                [System.IO.Directory]::CreateDirectory($path, $script:OwnerOnlyDirectory) | Out-Null

                Get-Mode -Path $path | Should -Be $existingMode
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }

        It 'applies an explicit directory mode to the leaf only, so create each level on Unix' -Skip:$IsWindows {
            # Directory.CreateDirectory(path, mode) applies the mode to the leaf it creates.
            # Intermediates it has to create along the way get the process default instead, which
            # is the opposite of the Windows behavior where a supplied descriptor covers them all.
            $root = New-TempRoot
            try {
                $leaf = Join-Path $root 'a/b/c'
                [System.IO.Directory]::CreateDirectory($leaf, $script:OwnerOnlyDirectory) | Out-Null
                ([int](Get-Mode -Path $leaf) -band 0x1FF -band -bnot [int]$script:OwnerOnlyDirectory) |
                    Should -Be 0

                # Creating every level explicitly is what actually protects the whole chain.
                $stepwise = $root
                foreach ($segment in @('x', 'y', 'z')) {
                    $stepwise = Join-Path $stepwise $segment
                    [System.IO.Directory]::CreateDirectory($stepwise, $script:OwnerOnlyDirectory) | Out-Null
                    ([int](Get-Mode -Path $stepwise) -band 0x1FF -band -bnot [int]$script:OwnerOnlyDirectory) |
                        Should -Be 0
                }
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    Context 'Creation semantics that are the same everywhere' {

        It 'replaces earlier Path.Combine segments but keeps earlier Path.Join segments' {
            $root = Join-Path $TestDrive 'trusted-root'
            $rootedSegment = if ($IsWindows) { 'C:\outside' } else { '/outside' }

            [System.IO.Path]::IsPathRooted($rootedSegment) | Should -BeTrue
            [System.IO.Path]::Combine($root, $rootedSegment) | Should -Be $rootedSegment
            [System.IO.Path]::Join($root, $rootedSegment).StartsWith(
                "$root$([System.IO.Path]::DirectorySeparatorChar)",
                [StringComparison]::Ordinal) | Should -BeTrue
        }

        It 'distinguishes rooted paths from fully qualified paths' {
            if ($IsWindows) {
                [System.IO.Path]::IsPathRooted('C:relative') | Should -BeTrue
                [System.IO.Path]::IsPathFullyQualified('C:relative') | Should -BeFalse
                [System.IO.Path]::IsPathRooted('\root-relative') | Should -BeTrue
                [System.IO.Path]::IsPathFullyQualified('\root-relative') | Should -BeFalse
                [System.IO.Path]::IsPathFullyQualified('C:\absolute') | Should -BeTrue
            }
            else {
                [System.IO.Path]::IsPathRooted('relative') | Should -BeFalse
                [System.IO.Path]::IsPathFullyQualified('relative') | Should -BeFalse
                [System.IO.Path]::IsPathRooted('/absolute') | Should -BeTrue
                [System.IO.Path]::IsPathFullyQualified('/absolute') | Should -BeTrue
            }
        }

        It 'resolves relative paths deterministically only with a fully qualified base' {
            $firstBase = Join-Path $TestDrive 'base-a'
            $secondBase = Join-Path $TestDrive 'base-b'
            [System.IO.Directory]::CreateDirectory($firstBase) | Out-Null
            [System.IO.Directory]::CreateDirectory($secondBase) | Out-Null
            $originalDirectory = [Environment]::CurrentDirectory

            try {
                [Environment]::CurrentDirectory = $firstBase
                $firstAmbientResult = [System.IO.Path]::GetFullPath('child.txt')
                [Environment]::CurrentDirectory = $secondBase
                $secondAmbientResult = [System.IO.Path]::GetFullPath('child.txt')

                $firstAmbientResult | Should -Not -Be $secondAmbientResult
                [System.IO.Path]::GetFullPath('child.txt', $firstBase) |
                    Should -Be ([System.IO.Path]::Join($firstBase, 'child.txt'))

                if ($IsWindows) {
                    $baseDrive = $firstBase[0]
                    $otherDrive = if ($baseDrive -eq 'C') { 'D' } else { 'C' }
                    [System.IO.Path]::GetFullPath("${baseDrive}:same-drive.txt", $firstBase) |
                        Should -Be ([System.IO.Path]::Join($firstBase, 'same-drive.txt'))
                    [System.IO.Path]::GetFullPath("${otherDrive}:other-drive.txt", $firstBase) |
                        Should -Be "${otherDrive}:\other-drive.txt"
                    [System.IO.Path]::GetFullPath('\root-relative.txt', $firstBase) |
                        Should -Be ([System.IO.Path]::Join(
                            [System.IO.Path]::GetPathRoot($firstBase),
                            'root-relative.txt'))
                }

                Get-ThrownException {
                    [System.IO.Path]::GetFullPath('child.txt', 'relative-base')
                } | Should -BeOfType ([System.ArgumentException])
            }
            finally { [Environment]::CurrentDirectory = $originalDirectory }
        }

        It 'requires a trailing separator when checking path containment' {
            $root = [System.IO.Path]::GetFullPath((Join-Path $TestDrive 'root'))
            $inside = [System.IO.Path]::GetFullPath(
                [System.IO.Path]::Join($root, 'folder', 'child.txt'),
                $root)
            $sibling = [System.IO.Path]::GetFullPath(
                [System.IO.Path]::Join($root, '..', 'root2', 'child.txt'),
                $root)
            $rootPrefix = "$root$([System.IO.Path]::DirectorySeparatorChar)"

            $inside.StartsWith($rootPrefix, [StringComparison]::Ordinal) |
                Should -BeTrue
            $sibling.StartsWith($root, [StringComparison]::Ordinal) |
                Should -BeTrue
            $sibling.StartsWith($rootPrefix, [StringComparison]::Ordinal) |
                Should -BeFalse
        }

        It 'retains the existing separator on a filesystem root containment prefix' {
            $root = [System.IO.Path]::GetPathRoot($TestDrive)
            [System.IO.Path]::TrimEndingDirectorySeparator($root) |
                Should -Be $root

            $rootPrefix = if ([System.IO.Path]::EndsInDirectorySeparator($root)) {
                $root
            }
            else { "$root$([System.IO.Path]::DirectorySeparatorChar)" }

            $rootPrefix | Should -Be $root
            [System.IO.Path]::Join($root, 'child.txt').StartsWith(
                $rootPrefix,
                [StringComparison]::Ordinal) | Should -BeTrue
        }

        It 'does not mistake lexical containment for physical containment through a directory link' {
            $root = New-TempRoot
            try {
                $inside = Join-Path $root 'inside'
                $outside = Join-Path $root 'outside'
                [System.IO.Directory]::CreateDirectory($inside) | Out-Null
                [System.IO.Directory]::CreateDirectory($outside) | Out-Null
                $link = Join-Path $inside 'redirect'
                if ($IsWindows) {
                    New-Item -ItemType Junction -Path $link -Target $outside | Out-Null
                }
                else {
                    [System.IO.Directory]::CreateSymbolicLink($link, $outside) | Out-Null
                }

                $candidate = [System.IO.Path]::GetFullPath((Join-Path $link 'payload.txt'), $inside)
                $candidate.StartsWith(
                    "$inside$([System.IO.Path]::DirectorySeparatorChar)",
                    [StringComparison]::Ordinal) | Should -BeTrue

                [System.IO.File]::WriteAllText($candidate, 'outside')
                [System.IO.File]::ReadAllText((Join-Path $outside 'payload.txt')) | Should -Be 'outside'
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }

        It 'fails an exclusive create when the file already exists' {
            $root = New-TempRoot
            try {
                $path = Join-Path $root 'exclusive.txt'
                Set-Content -LiteralPath $path -Value 'x' -NoNewline

                Get-ThrownException { [System.IO.File]::Open($path, [System.IO.FileMode]::CreateNew).Dispose() } |
                    Should -BeOfType ([System.IO.IOException])
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }

        It 'enforces FileShare.None against a second open' {
            # .NET takes advisory flock locks on Unix, so cooperating native processes can honor
            # them too. This same-process assertion pins the default runtime behavior only.
            $root = New-TempRoot
            try {
                $path = Join-Path $root 'share.txt'
                Set-Content -LiteralPath $path -Value 'x' -NoNewline

                $first = [System.IO.File]::Open($path, 'Open', 'Read', 'None')
                try {
                    Get-ThrownException { [System.IO.File]::Open($path, 'Open', 'Read', 'Read').Dispose() } |
                        Should -BeOfType ([System.IO.IOException])
                }
                finally { $first.Dispose() }
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }

        It 'replaces an existing destination with File.Move overwrite' {
            $root = New-TempRoot
            try {
                $source = Join-Path $root 'src.txt'
                $destination = Join-Path $root 'dst.txt'
                Set-Content -LiteralPath $source -Value 'new' -NoNewline
                Set-Content -LiteralPath $destination -Value 'old' -NoNewline

                [System.IO.File]::Move($source, $destination, $true)

                Get-Content -LiteralPath $destination -Raw | Should -Be 'new'
                Test-Path -LiteralPath $source | Should -BeFalse
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    Context 'Creation semantics that differ by platform' {

        It 'blocks deleting a file opened without delete sharing on Windows and unlinks it on Unix' {
            $root = New-TempRoot
            try {
                $path = Join-Path $root 'open.txt'
                Set-Content -LiteralPath $path -Value 'x' -NoNewline

                $held = [System.IO.File]::Open($path, 'Open', 'Read', 'None')
                try {
                    if ($IsWindows) {
                        Get-ThrownException { [System.IO.File]::Delete($path) } |
                            Should -BeOfType ([System.IO.IOException])
                    }
                    else {
                        { [System.IO.File]::Delete($path) } | Should -Not -Throw
                        Test-Path -LiteralPath $path | Should -BeFalse
                    }
                }
                finally { $held.Dispose() }
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }

        It 'allows deleting an open file when delete sharing and filesystem permissions permit' {
            $root = New-TempRoot
            try {
                $path = Join-Path $root 'delete-shared.txt'
                [System.IO.File]::WriteAllBytes($path, [byte[]](42))
                $held = [System.IO.File]::Open($path, 'Open', 'Read', 'Read, Delete')
                try {
                    { [System.IO.File]::Delete($path) } | Should -Not -Throw
                    $held.ReadByte() | Should -Be 42
                }
                finally { $held.Dispose() }
                $path | Should -Not -Exist
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }

        It 'distinguishes Windows read sharing from coarser Unix advisory sharing' {
            $root = New-TempRoot
            try {
                $path = Join-Path $root 'read-shared.txt'
                [System.IO.File]::WriteAllText($path, 'existing')
                $held = [System.IO.File]::Open($path, 'Open', 'Read', 'Read')
                try {
                    if ($IsWindows) {
                        Get-ThrownException { [System.IO.File]::Open($path, 'Open', 'Write', 'ReadWrite').Dispose() } |
                            Should -BeOfType ([System.IO.IOException])
                    }
                    else {
                        { [System.IO.File]::Open($path, 'Open', 'Write', 'ReadWrite').Dispose() } |
                            Should -Not -Throw
                    }
                }
                finally { $held.Dispose() }
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }

        It 'follows the filesystem case sensitivity rather than the operating system' {
            $root = New-TempRoot
            try {
                $path = Join-Path $root 'casetest.txt'
                Set-Content -LiteralPath $path -Value 'x' -NoNewline
                $caseInsensitive = [System.IO.File]::Exists((Join-Path $root 'CASETEST.TXT'))

                # The name as written always resolves, whatever the volume does.
                [System.IO.File]::Exists($path) | Should -BeTrue

                $alternate = Join-Path $root 'CASETEST.TXT'
                if ($caseInsensitive) {
                    [System.IO.File]::ReadAllText($alternate) | Should -Be 'x'
                }
                else {
                    [System.IO.File]::WriteAllText($alternate, 'distinct')
                    [System.IO.File]::ReadAllText($path) | Should -Be 'x'
                    [System.IO.File]::ReadAllText($alternate) | Should -Be 'distinct'
                }
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }

        It 'sets the hidden attribute on Windows and ignores it on Linux' {
            # On Linux the hidden attribute is derived from a leading dot in the name and cannot be
            # set independently. SetAttributes does not throw, it simply has no effect. macOS has a
            # real UF_HIDDEN flag and was not measured, so it is left unasserted.
            $root = New-TempRoot
            try {
                $path = Join-Path $root 'visible.txt'
                Set-Content -LiteralPath $path -Value 'x' -NoNewline
                [System.IO.File]::SetAttributes($path, [System.IO.FileAttributes]::Hidden)

                $isHidden = [System.IO.File]::GetAttributes($path).HasFlag([System.IO.FileAttributes]::Hidden)

                if ($IsWindows) {
                    $isHidden | Should -BeTrue
                }
                elseif ($IsLinux) {
                    $isHidden | Should -BeFalse -Because 'the attribute is derived from a leading dot'

                    $dotted = Join-Path $root '.dotted.txt'
                    Set-Content -LiteralPath $dotted -Value 'x' -NoNewline
                    [System.IO.File]::GetAttributes($dotted).HasFlag(
                        [System.IO.FileAttributes]::Hidden) | Should -BeTrue
                }
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    Context 'Where the runtime puts per-user and machine state' {

        It 'resolves per-user data folders from platform defaults and XDG overrides' {
            $profilePath = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
            $profilePath | Should -Not -BeNullOrEmpty

            $folders = @(
                @{ Folder = [Environment+SpecialFolder]::ApplicationData; Override = 'XDG_CONFIG_HOME' }
                @{ Folder = [Environment+SpecialFolder]::LocalApplicationData; Override = 'XDG_DATA_HOME' }
            )

            $originalOverrides = @{}
            try {
                if ($IsLinux) {
                    foreach ($folder in $folders) {
                        $originalOverrides[$folder.Override] = [Environment]::GetEnvironmentVariable(
                            $folder.Override)
                        [Environment]::SetEnvironmentVariable($folder.Override, $null)
                    }
                }

                foreach ($folder in $folders) {
                    $path = [Environment]::GetFolderPath(
                        $folder.Folder,
                        [Environment+SpecialFolderOption]::Create)
                    $path | Should -Not -BeNullOrEmpty
                    $path | Should -Exist
                    [System.IO.Path]::IsPathFullyQualified($path) | Should -BeTrue
                }

                if ($IsLinux) {
                    foreach ($folder in $folders) {
                        $override = Join-Path $TestDrive $folder.Override
                        [Environment]::SetEnvironmentVariable($folder.Override, $override)
                        $path = [Environment]::GetFolderPath(
                            $folder.Folder,
                            [Environment+SpecialFolderOption]::Create)

                        $path | Should -Be $override -Because "$($folder.Folder) honors its XDG override"
                        $path | Should -Exist
                    }
                }
            }
            finally {
                if ($IsLinux) {
                    foreach ($folder in $folders) {
                        [Environment]::SetEnvironmentVariable(
                            $folder.Override, $originalOverrides[$folder.Override])
                    }
                }
            }
        }

        It 'returns a qualified machine-wide location when one is available without assuming writability' {
            $common = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)

            if (-not [string]::IsNullOrEmpty($common)) {
                [System.IO.Path]::IsPathFullyQualified($common) | Should -BeTrue
            }
        }
    }
}
