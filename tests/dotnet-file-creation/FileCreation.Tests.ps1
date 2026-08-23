#requires -Version 7.0

# Behavioral assertions behind the dotnet-file-creation skill. These run on every platform and
# branch at run time, because the whole point of the guidance is that the same API behaves
# differently on Windows and Unix. A test that skipped the other platform would pin nothing.
#
# PowerShell 7 hosts the .NET runtime directly, so these exercise the real System.IO surface.

Describe 'Cross-platform file creation behavior' {

    BeforeAll {
        $ErrorActionPreference = 'Stop'

        $script:OwnerOnlyFile = [System.IO.UnixFileMode]'UserRead, UserWrite'
        $script:OwnerOnlyDirectory = [System.IO.UnixFileMode]'UserRead, UserWrite, UserExecute'

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

        It 'creates the temp subdirectory owner-only on Unix and rejects the query on Windows' {
            # The parent temp directory is world-writable on Unix, so this API is the only
            # built-in way to get a private scratch directory without doing the work yourself.
            $root = New-TempRoot
            try {
                if ($IsWindows) {
                    Get-ThrownException { Get-Mode -Path $root } |
                        Should -BeOfType ([System.PlatformNotSupportedException])
                }
                else {
                    Get-Mode -Path $root | Should -Be $script:OwnerOnlyDirectory
                }
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }

        It 'creates a zero-byte temp file, owner-only on Unix' {
            $file = [System.IO.Path]::GetTempFileName()
            try {
                (Get-Item -LiteralPath $file).Length | Should -Be 0
                if (-not $IsWindows) {
                    Get-Mode -Path $file | Should -Be $script:OwnerOnlyFile
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

        It 'creates a file with exactly the requested owner-only mode on Unix' -Skip:$IsWindows {
            $root = New-TempRoot
            try {
                $path = New-FileWithMode -Path (Join-Path $root 'private.txt') -Mode $script:OwnerOnlyFile
                Get-Mode -Path $path | Should -Be $script:OwnerOnlyFile
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }

        It 'never grants more than the requested mode on Unix' -Skip:$IsWindows {
            # umask can only clear bits, so a permissive request may be reduced. A restrictive
            # request always survives, which is why owner-only modes are safe to rely on.
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

        It 'applies an explicit directory mode to the leaf only, so create each level on Unix' -Skip:$IsWindows {
            # Directory.CreateDirectory(path, mode) applies the mode to the leaf it creates.
            # Intermediates it has to create along the way get the process default instead, which
            # is the opposite of the Windows behavior where a supplied descriptor covers them all.
            $root = New-TempRoot
            try {
                $leaf = Join-Path $root 'a/b/c'
                [System.IO.Directory]::CreateDirectory($leaf, $script:OwnerOnlyDirectory) | Out-Null
                Get-Mode -Path $leaf | Should -Be $script:OwnerOnlyDirectory

                # Creating every level explicitly is what actually protects the whole chain.
                $stepwise = $root
                foreach ($segment in @('x', 'y', 'z')) {
                    $stepwise = Join-Path $stepwise $segment
                    [System.IO.Directory]::CreateDirectory($stepwise, $script:OwnerOnlyDirectory) | Out-Null
                    Get-Mode -Path $stepwise | Should -Be $script:OwnerOnlyDirectory
                }
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    Context 'Creation semantics that are the same everywhere' {

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
            # .NET emulates share modes on Unix, so this holds on both platforms between .NET
            # processes. It is not enforced against non-.NET processes on Unix.
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

        It 'blocks deleting an open file on Windows and unlinks it on Unix' {
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

        It 'treats paths case-insensitively on Windows and case-sensitively on Unix' {
            $root = New-TempRoot
            try {
                $path = Join-Path $root 'casetest.txt'
                Set-Content -LiteralPath $path -Value 'x' -NoNewline

                $upper = Join-Path $root 'CASETEST.TXT'
                [System.IO.File]::Exists($upper) | Should -Be ([bool]$IsWindows)
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }

        It 'sets the hidden attribute on Windows and ignores it on Unix' {
            # On Unix the hidden attribute is derived from a leading dot in the name and cannot be
            # set independently. SetAttributes does not throw, it simply has no effect.
            $root = New-TempRoot
            try {
                $path = Join-Path $root 'visible.txt'
                Set-Content -LiteralPath $path -Value 'x' -NoNewline
                [System.IO.File]::SetAttributes($path, [System.IO.FileAttributes]::Hidden)

                $isHidden = [System.IO.File]::GetAttributes($path).HasFlag([System.IO.FileAttributes]::Hidden)
                $isHidden | Should -Be ([bool]$IsWindows)

                $dotted = Join-Path $root '.dotted.txt'
                Set-Content -LiteralPath $dotted -Value 'x' -NoNewline
                if (-not $IsWindows) {
                    [System.IO.File]::GetAttributes($dotted).HasFlag(
                        [System.IO.FileAttributes]::Hidden) | Should -BeTrue
                }
            }
            finally { Remove-Item -LiteralPath $root -Recurse -Force }
        }
    }

    Context 'Where the runtime puts per-user and machine state' {

        It 'places per-user data under the user profile on every platform' {
            $profilePath = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
            $profilePath | Should -Not -BeNullOrEmpty

            foreach ($folder in @('ApplicationData', 'LocalApplicationData')) {
                $path = [Environment]::GetFolderPath([Environment+SpecialFolder]::$folder)
                $path | Should -Not -BeNullOrEmpty
                $path.StartsWith($profilePath, [StringComparison]::OrdinalIgnoreCase) |
                    Should -BeTrue -Because "$folder should live under the user profile"
            }
        }

        It 'places machine-wide data outside the user profile on every platform' {
            $profilePath = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
            $common = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)

            $common | Should -Not -BeNullOrEmpty
            $common.StartsWith($profilePath, [StringComparison]::OrdinalIgnoreCase) | Should -BeFalse
        }
    }
}
