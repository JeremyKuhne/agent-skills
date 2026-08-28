#requires -Version 7.0

# Fact-regression assertions behind the windows-acls skill. Each test pins one claim the guidance
# depends on, so a Windows change that invalidates the advice fails here first.
#
# Outcomes that depend on the caller's token branch on elevation at run time rather than skipping.
# GitHub-hosted Windows runners are configured to run as administrators with UAC disabled, so a
# skipped elevated-only test would never run anywhere useful, and a skipped unelevated-only test
# would never run in CI. Branching keeps one live assertion in both environments.
#
# Everything uses System.IO.FileSystemAclExtensions rather than Get-Acl/Set-Acl. Set-Acl writes
# the SACL and therefore demands SeSecurityPrivilege, which an unelevated caller does not hold.

Describe 'Windows access control behavior' -Skip:(-not $IsWindows) {

    BeforeAll {
        $ErrorActionPreference = 'Stop'

        if ($null -eq ('WindowsAclPrivilegeNativeMethods' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class WindowsAclPrivilegeNativeMethods
{
    [StructLayout(LayoutKind.Sequential)]
    public struct Luid
    {
        public uint LowPart;
        public int HighPart;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct LuidAndAttributes
    {
        public Luid Luid;
        public uint Attributes;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PrivilegeSet
    {
        public uint PrivilegeCount;
        public uint Control;
        public LuidAndAttributes Privilege;
    }

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool LookupPrivilegeValue(string systemName, string name, out Luid luid);

    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool PrivilegeCheck(
        IntPtr token,
        ref PrivilegeSet requiredPrivileges,
        [MarshalAs(UnmanagedType.Bool)] out bool result);
}
'@
        }

        if ($null -eq ('WindowsAclAuthzNativeMethods' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class WindowsAclAuthzNativeMethods
{
    private const uint AuthzRmFlagNoAudit = 0x1;
    private const uint MaximumAllowed = 0x02000000;

    [StructLayout(LayoutKind.Sequential)]
    private struct Luid
    {
        public uint LowPart;
        public int HighPart;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct AuthzAccessRequest
    {
        public uint DesiredAccess;
        public IntPtr PrincipalSelfSid;
        public IntPtr ObjectTypeList;
        public uint ObjectTypeListLength;
        public IntPtr OptionalArguments;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct AuthzAccessReply
    {
        public uint ResultListLength;
        public IntPtr GrantedAccessMask;
        public IntPtr SaclEvaluationResults;
        public IntPtr Error;
    }

    [DllImport("authz.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AuthzInitializeResourceManager(
        uint flags,
        IntPtr accessCheck,
        IntPtr computeDynamicGroups,
        IntPtr freeDynamicGroups,
        string resourceManagerName,
        out IntPtr resourceManager);

    [DllImport("authz.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AuthzInitializeContextFromToken(
        uint flags,
        IntPtr token,
        IntPtr resourceManager,
        IntPtr expirationTime,
        Luid identifier,
        IntPtr dynamicGroupArguments,
        out IntPtr clientContext);

    [DllImport("authz.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AuthzInitializeContextFromSid(
        uint flags,
        IntPtr userSid,
        IntPtr resourceManager,
        IntPtr expirationTime,
        Luid identifier,
        IntPtr dynamicGroupArguments,
        out IntPtr clientContext);

    [DllImport("authz.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AuthzAccessCheck(
        uint flags,
        IntPtr clientContext,
        ref AuthzAccessRequest request,
        IntPtr auditEvent,
        IntPtr securityDescriptor,
        IntPtr optionalSecurityDescriptorArray,
        uint optionalSecurityDescriptorCount,
        ref AuthzAccessReply reply,
        IntPtr accessCheckResults);

    [DllImport("authz.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AuthzFreeContext(IntPtr clientContext);

    [DllImport("authz.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AuthzFreeResourceManager(IntPtr resourceManager);

    public static uint GetMaximumAllowedForToken(IntPtr token, byte[] securityDescriptor)
    {
        IntPtr resourceManager = IntPtr.Zero;
        IntPtr clientContext = IntPtr.Zero;
        try
        {
            ThrowIfFalse(AuthzInitializeResourceManager(
                AuthzRmFlagNoAudit,
                IntPtr.Zero,
                IntPtr.Zero,
                IntPtr.Zero,
                null,
                out resourceManager));
            ThrowIfFalse(AuthzInitializeContextFromToken(
                0,
                token,
                resourceManager,
                IntPtr.Zero,
                default,
                IntPtr.Zero,
                out clientContext));
            return GetMaximumAllowed(clientContext, securityDescriptor);
        }
        finally
        {
            if (clientContext != IntPtr.Zero)
            {
                AuthzFreeContext(clientContext);
            }
            if (resourceManager != IntPtr.Zero)
            {
                AuthzFreeResourceManager(resourceManager);
            }
        }
    }

    public static uint GetMaximumAllowedForSid(byte[] sid, byte[] securityDescriptor)
    {
        IntPtr resourceManager = IntPtr.Zero;
        IntPtr clientContext = IntPtr.Zero;
        GCHandle sidHandle = default;
        try
        {
            ThrowIfFalse(AuthzInitializeResourceManager(
                AuthzRmFlagNoAudit,
                IntPtr.Zero,
                IntPtr.Zero,
                IntPtr.Zero,
                null,
                out resourceManager));
            sidHandle = GCHandle.Alloc(sid, GCHandleType.Pinned);
            ThrowIfFalse(AuthzInitializeContextFromSid(
                0,
                sidHandle.AddrOfPinnedObject(),
                resourceManager,
                IntPtr.Zero,
                default,
                IntPtr.Zero,
                out clientContext));
            return GetMaximumAllowed(clientContext, securityDescriptor);
        }
        finally
        {
            if (sidHandle.IsAllocated)
            {
                sidHandle.Free();
            }
            if (clientContext != IntPtr.Zero)
            {
                AuthzFreeContext(clientContext);
            }
            if (resourceManager != IntPtr.Zero)
            {
                AuthzFreeResourceManager(resourceManager);
            }
        }
    }

    private static uint GetMaximumAllowed(IntPtr clientContext, byte[] securityDescriptor)
    {
        GCHandle descriptorHandle = default;
        IntPtr grantedAccess = IntPtr.Zero;
        IntPtr error = IntPtr.Zero;
        try
        {
            descriptorHandle = GCHandle.Alloc(securityDescriptor, GCHandleType.Pinned);
            grantedAccess = Marshal.AllocHGlobal(sizeof(uint));
            error = Marshal.AllocHGlobal(sizeof(uint));
            Marshal.WriteInt32(grantedAccess, 0);
            Marshal.WriteInt32(error, 0);

            var request = new AuthzAccessRequest { DesiredAccess = MaximumAllowed };
            var reply = new AuthzAccessReply
            {
                ResultListLength = 1,
                GrantedAccessMask = grantedAccess,
                Error = error
            };

            ThrowIfFalse(AuthzAccessCheck(
                0,
                clientContext,
                ref request,
                IntPtr.Zero,
                descriptorHandle.AddrOfPinnedObject(),
                IntPtr.Zero,
                0,
                ref reply,
                IntPtr.Zero));

            int accessError = Marshal.ReadInt32(error);
            if (accessError != 0)
            {
                throw new Win32Exception(accessError);
            }

            return unchecked((uint)Marshal.ReadInt32(grantedAccess));
        }
        finally
        {
            if (descriptorHandle.IsAllocated)
            {
                descriptorHandle.Free();
            }
            if (grantedAccess != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(grantedAccess);
            }
            if (error != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(error);
            }
        }
    }

    private static void ThrowIfFalse(bool succeeded)
    {
        if (!succeeded)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
    }
}
'@
        }

        function Test-CallerIsElevated {
            $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
            [System.Security.Principal.WindowsPrincipal]::new($identity).IsInRole(
                [System.Security.Principal.WindowsBuiltInRole]::Administrator)
        }

        function New-WellKnownSid {
            param([System.Security.Principal.WellKnownSidType] $Type)
            [System.Security.Principal.SecurityIdentifier]::new($Type, $null)
        }

        function Test-PrivilegeEnabled {
            param([string] $Name)

            $luid = [WindowsAclPrivilegeNativeMethods+Luid]::new()
            if (-not [WindowsAclPrivilegeNativeMethods]::LookupPrivilegeValue(
                    $null, $Name, [ref]$luid)) {
                throw [System.ComponentModel.Win32Exception]::new(
                    [System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
            }

            $privileges = [WindowsAclPrivilegeNativeMethods+PrivilegeSet]::new()
            $privileges.PrivilegeCount = 1
            $privileges.Control = 1
            $privilege = [WindowsAclPrivilegeNativeMethods+LuidAndAttributes]::new()
            $privilege.Luid = $luid
            $privileges.Privilege = $privilege
            $enabled = $false
            $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
            if (-not [WindowsAclPrivilegeNativeMethods]::PrivilegeCheck(
                    $identity.Token, [ref]$privileges, [ref]$enabled)) {
                throw [System.ComponentModel.Win32Exception]::new(
                    [System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
            }

            $enabled
        }

        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $script:Administrators = New-WellKnownSid -Type BuiltinAdministratorsSid
        $script:LocalSystem = New-WellKnownSid -Type LocalSystemSid
        $script:Users = New-WellKnownSid -Type BuiltinUsersSid
        $script:Me = $identity.User
        $script:DefaultOwner = $identity.Owner
        $script:BothInherit = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        $script:AccessOnly = [System.Security.AccessControl.AccessControlSections]::Access
        $script:OwnerOnly = [System.Security.AccessControl.AccessControlSections]::Owner

        function New-Rule {
            param(
                [System.Security.Principal.SecurityIdentifier] $Sid,
                [System.Security.AccessControl.FileSystemRights] $Rights,
                [System.Security.AccessControl.InheritanceFlags] $Inheritance = 'None',
                [System.Security.AccessControl.PropagationFlags] $Propagation = 'None',
                [System.Security.AccessControl.AccessControlType] $Type = 'Allow'
            )

            [System.Security.AccessControl.FileSystemAccessRule]::new($Sid, $Rights, $Inheritance, $Propagation, $Type)
        }

        function Get-DirectorySecurity {
            param([string] $Path, [System.Security.AccessControl.AccessControlSections] $Sections = $script:AccessOnly)
            [System.IO.FileSystemAclExtensions]::GetAccessControl([System.IO.DirectoryInfo]::new($Path), $Sections)
        }

        function Set-DirectorySecurity {
            param([string] $Path, [System.Security.AccessControl.DirectorySecurity] $Security)
            [System.IO.FileSystemAclExtensions]::SetAccessControl([System.IO.DirectoryInfo]::new($Path), $Security)
        }

        function Get-FileSecurity {
            param([string] $Path, [System.Security.AccessControl.AccessControlSections] $Sections = $script:AccessOnly)
            [System.IO.FileSystemAclExtensions]::GetAccessControl([System.IO.FileInfo]::new($Path), $Sections)
        }

        function Set-FileSecurity {
            param([string] $Path, [System.Security.AccessControl.FileSecurity] $Security)
            [System.IO.FileSystemAclExtensions]::SetAccessControl([System.IO.FileInfo]::new($Path), $Security)
        }

        function New-TestPath {
            Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        }

        # Creates a directory whose DACL is supplied at creation, the shape production code uses
        # when it needs a known descriptor rather than whatever the parent hands down.
        function New-DirectoryWithDacl {
            param([string] $Path, [System.Security.AccessControl.FileSystemAccessRule[]] $Rules)

            $security = [System.Security.AccessControl.DirectorySecurity]::new()
            foreach ($rule in $Rules) { $security.AddAccessRule($rule) }
            [System.IO.FileSystemAclExtensions]::CreateDirectory($security, $Path) | Out-Null
            $Path
        }

        function Get-RuleList {
            param([string] $Path)
            @((Get-DirectorySecurity -Path $Path).GetAccessRules(
                    $true, $true, [System.Security.Principal.SecurityIdentifier]))
        }

        function Test-HasRuleFor {
            param([string] $Path, [System.Security.Principal.SecurityIdentifier] $Sid)
            @(Get-RuleList -Path $Path | Where-Object { $_.IdentityReference -eq $Sid }).Count -gt 0
        }

        function Get-OwnerSid {
            param([string] $Path)
            (Get-DirectorySecurity -Path $Path -Sections $script:OwnerOnly).GetOwner(
                [System.Security.Principal.SecurityIdentifier])
        }

        # Restores caller access so the test drive can be cleaned even after a test writes a
        # descriptor that excludes the caller.
        function Restore-CallerAccess {
            param([string] $Path)
            if (-not (Test-Path -LiteralPath $Path)) { return }

            $targets = @($Path)
            $targets += @(Get-ChildItem -LiteralPath $Path -Recurse -Force -Directory -ErrorAction SilentlyContinue |
                    Where-Object { -not $_.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint) } |
                    Select-Object -ExpandProperty FullName)

            foreach ($target in $targets) {
                try {
                    $security = Get-DirectorySecurity -Path $target
                    $security.SetAccessRuleProtection($true, $true)
                    $security.AddAccessRule((New-Rule -Sid $script:Me -Rights FullControl -Inheritance $script:BothInherit))
                    Set-DirectorySecurity -Path $target -Security $security
                }
                catch { }
            }
        }
    }

    Context 'Elevation baseline' {

        It 'runs elevated on Windows CI' -Skip:(-not ($env:CI -or $env:TF_BUILD)) {
            # GitHub-hosted and Azure Pipelines Windows runners run as administrators with UAC
            # disabled. If that changes, the elevated branches below stop being exercised in CI.
            Test-CallerIsElevated | Should -BeTrue -Because 'Windows CI images run elevated'
        }

        It 'recognizes a privilege enabled by default for all users' {
            Test-PrivilegeEnabled -Name 'SeChangeNotifyPrivilege' | Should -BeTrue
        }
    }

    Context 'Ownership is the part an unelevated caller cannot forge' {

        It 'assigns a new owner only when the caller is elevated' {
            # SetOwner succeeds in memory in both cases. The difference appears only on commit, so
            # a test that asserts on SetOwner alone proves nothing about either environment.
            $path = New-TestPath
            New-Item -ItemType Directory -Path $path | Out-Null
            $originalOwner = Get-OwnerSid -Path $path

            $security = Get-DirectorySecurity -Path $path -Sections $script:OwnerOnly
            { $security.SetOwner($script:Administrators) } | Should -Not -Throw

            if (Test-CallerIsElevated) {
                { Set-DirectorySecurity -Path $path -Security $security } | Should -Not -Throw
                Get-OwnerSid -Path $path | Should -Be $script:Administrators
            }
            else {
                # A SID may own an object only if the creating token carries it with
                # SE_GROUP_OWNER. A standard user's token does not carry Administrators that way.
                { Set-DirectorySecurity -Path $path -Security $security } | Should -Throw
                Get-OwnerSid -Path $path | Should -Be $originalOwner
            }
        }

        It 'assigns SYSTEM only as SYSTEM or with SeRestorePrivilege enabled' {
            $path = New-TestPath
            New-Item -ItemType Directory -Path $path | Out-Null
            $originalOwner = Get-OwnerSid -Path $path

            $security = Get-DirectorySecurity -Path $path -Sections $script:OwnerOnly
            $security.SetOwner($script:LocalSystem)

            if ($script:Me -eq $script:LocalSystem -or (Test-PrivilegeEnabled -Name 'SeRestorePrivilege')) {
                { Set-DirectorySecurity -Path $path -Security $security } | Should -Not -Throw
                Get-OwnerSid -Path $path | Should -Be $script:LocalSystem
            }
            else {
                { Set-DirectorySecurity -Path $path -Security $security } | Should -Throw `
                    -Because 'assigning an unrelated owner requires SeRestorePrivilege to be enabled'
                Get-OwnerSid -Path $path | Should -Be $originalOwner
            }
        }

        It 'creates objects with the token default owner' {
            $path = New-TestPath
            New-Item -ItemType Directory -Path $path | Out-Null

            Get-OwnerSid -Path $path | Should -Be $script:DefaultOwner
        }
    }

    Context 'A DACL on its own proves nothing' {

        It 'lets any caller create a directory whose DACL names only Administrators and SYSTEM' {
            $path = New-TestPath
            New-DirectoryWithDacl -Path $path -Rules @(
                New-Rule -Sid $script:Administrators -Rights FullControl -Inheritance $script:BothInherit
                New-Rule -Sid $script:LocalSystem -Rights FullControl -Inheritance $script:BothInherit
            ) | Out-Null

            try {
                Test-HasRuleFor -Path $path -Sid $script:Administrators | Should -BeTrue
                Test-HasRuleFor -Path $path -Sid $script:Users | Should -BeFalse
                Test-HasRuleFor -Path $path -Sid $script:Me | Should -BeFalse
            }
            finally { Restore-CallerAccess -Path $path }
        }

        It 'lets the owner rewrite a DACL that grants the owner nothing' {
            # An owner keeps READ_CONTROL and WRITE_DAC implicitly, so a self-excluding DACL is
            # reversible at will. That is why the owner, not the DACL, is the durable check.
            $path = New-TestPath
            New-DirectoryWithDacl -Path $path -Rules @(
                New-Rule -Sid $script:Administrators -Rights FullControl -Inheritance $script:BothInherit
            ) | Out-Null

            try {
                $security = Get-DirectorySecurity -Path $path
                $security.AddAccessRule((New-Rule -Sid $script:Me -Rights FullControl -Inheritance $script:BothInherit))

                { Set-DirectorySecurity -Path $path -Security $security } | Should -Not -Throw
                Test-HasRuleFor -Path $path -Sid $script:Me | Should -BeTrue
            }
            finally { Restore-CallerAccess -Path $path }
        }
    }

    Context 'ACE order changes effective access' {

        It 'grants read when a matching allow completes the check before a later deny' {
            $path = New-TestPath
            [System.IO.File]::WriteAllText($path, 'receipt')
            [string] $currentUserSid = $script:Me.Value

            try {
                $allowFirst = [System.Security.AccessControl.FileSecurity]::new()
                $allowFirst.SetSecurityDescriptorSddlForm(
                    "D:P(A;;FR;;;WD)(D;;FR;;;$currentUserSid)", $script:AccessOnly)
                Set-FileSecurity -Path $path -Security $allowFirst

                $allowFirstOnDisk = Get-FileSecurity -Path $path
                $allowFirstRaw = [System.Security.AccessControl.RawSecurityDescriptor]::new(
                    $allowFirstOnDisk.GetSecurityDescriptorBinaryForm(), 0)
                $allowFirstOnDisk.AreAccessRulesCanonical | Should -BeFalse
                $allowFirstRaw.DiscretionaryAcl[0].AceType | Should -Be AccessAllowed
                $allowFirstRaw.DiscretionaryAcl[1].AceType | Should -Be AccessDenied
                [System.IO.File]::ReadAllText($path) | Should -Be 'receipt'

                $denyFirst = [System.Security.AccessControl.FileSecurity]::new()
                $denyFirst.SetSecurityDescriptorSddlForm(
                    "D:P(D;;FR;;;$currentUserSid)(A;;FR;;;WD)", $script:AccessOnly)
                Set-FileSecurity -Path $path -Security $denyFirst

                $denyFirstOnDisk = Get-FileSecurity -Path $path
                $denyFirstRaw = [System.Security.AccessControl.RawSecurityDescriptor]::new(
                    $denyFirstOnDisk.GetSecurityDescriptorBinaryForm(), 0)
                $denyFirstOnDisk.AreAccessRulesCanonical | Should -BeTrue
                $denyFirstRaw.DiscretionaryAcl[0].AceType | Should -Be AccessDenied
                $denyFirstRaw.DiscretionaryAcl[1].AceType | Should -Be AccessAllowed
                $readError = { [System.IO.File]::ReadAllText($path) } | Should -Throw -PassThru
                $readError.Exception.InnerException | Should -BeOfType ([System.UnauthorizedAccessException])
            }
            finally {
                $cleanup = [System.Security.AccessControl.FileSecurity]::new()
                $cleanup.SetSecurityDescriptorSddlForm(
                    "D:P(A;;FA;;;$currentUserSid)", $script:AccessOnly)
                Set-FileSecurity -Path $path -Security $cleanup
                Remove-Item -LiteralPath $path -Force
            }
        }
    }

    Context 'Reading effective rights' {

        It 'gets maximum allowed rights from the current access token' {
            $path = New-TestPath
            [System.IO.File]::WriteAllText($path, 'effective rights')
            [string] $currentUserSid = $script:Me.Value

            try {
                $security = [System.Security.AccessControl.FileSecurity]::new()
                $security.SetSecurityDescriptorSddlForm(
                    "O:${currentUserSid}D:P(D;;FW;;;$currentUserSid)(A;;FR;;;$currentUserSid)",
                    [System.Security.AccessControl.AccessControlSections]'Owner, Access')
                Set-FileSecurity -Path $path -Security $security

                $onDisk = Get-FileSecurity -Path $path -Sections 'Owner, Access'
                [byte[]] $descriptor = $onDisk.GetSecurityDescriptorBinaryForm()
                [uint32] $rights = [WindowsAclAuthzNativeMethods]::GetMaximumAllowedForToken(
                    $identity.Token, $descriptor)

                ($rights -band [uint32][System.Security.AccessControl.FileSystemRights]::ReadData) |
                    Should -Not -Be 0
                ($rights -band [uint32][System.Security.AccessControl.FileSystemRights]::WriteData) |
                    Should -Be 0
            }
            finally {
                $cleanup = [System.Security.AccessControl.FileSecurity]::new()
                $cleanup.SetSecurityDescriptorSddlForm(
                    "D:P(A;;FA;;;$currentUserSid)", $script:AccessOnly)
                Set-FileSecurity -Path $path -Security $cleanup
                Remove-Item -LiteralPath $path -Force
            }
        }

        It 'resolves group rights when initialized from the current user SID' {
            $path = New-TestPath
            [System.IO.File]::WriteAllText($path, 'group rights')
            [string] $currentUserSid = $script:Me.Value
            [byte[]] $currentUserSidBytes = [byte[]]::new($script:Me.BinaryLength)
            $script:Me.GetBinaryForm($currentUserSidBytes, 0)

            try {
                $security = [System.Security.AccessControl.FileSecurity]::new()
                $security.SetSecurityDescriptorSddlForm(
                    "O:${currentUserSid}D:P(A;;FR;;;BU)",
                    [System.Security.AccessControl.AccessControlSections]'Owner, Access')
                Set-FileSecurity -Path $path -Security $security

                $onDisk = Get-FileSecurity -Path $path -Sections 'Owner, Access'
                [byte[]] $descriptor = $onDisk.GetSecurityDescriptorBinaryForm()
                [uint32] $rights = [WindowsAclAuthzNativeMethods]::GetMaximumAllowedForSid(
                    $currentUserSidBytes, $descriptor)

                ($rights -band [uint32][System.Security.AccessControl.FileSystemRights]::ReadData) |
                    Should -Not -Be 0
            }
            finally {
                $cleanup = [System.Security.AccessControl.FileSecurity]::new()
                $cleanup.SetSecurityDescriptorSddlForm(
                    "D:P(A;;FA;;;$currentUserSid)", $script:AccessOnly)
                Set-FileSecurity -Path $path -Security $cleanup
                Remove-Item -LiteralPath $path -Force
            }
        }

        It 'does not infer file access from enabled group membership' {
            $path = New-TestPath
            [System.IO.File]::WriteAllText($path, 'membership is not access')
            [string] $currentUserSid = $script:Me.Value

            try {
                $security = [System.Security.AccessControl.FileSecurity]::new()
                $security.SetSecurityDescriptorSddlForm(
                    "D:P(D;;FR;;;$currentUserSid)(A;;FR;;;BU)", $script:AccessOnly)
                Set-FileSecurity -Path $path -Security $security

                $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
                $principal.IsInRole($script:Users) | Should -BeTrue
                $readError = { [System.IO.File]::ReadAllText($path) } |
                    Should -Throw -PassThru
                $readError.Exception.InnerException |
                    Should -BeOfType ([System.UnauthorizedAccessException])
            }
            finally {
                $cleanup = [System.Security.AccessControl.FileSecurity]::new()
                $cleanup.SetSecurityDescriptorSddlForm(
                    "D:P(A;;FA;;;$currentUserSid)", $script:AccessOnly)
                Set-FileSecurity -Path $path -Security $cleanup
                Remove-Item -LiteralPath $path -Force
            }
        }

        It 'opens an existing file with an exact managed rights request' {
            $path = New-TestPath
            [System.IO.File]::WriteAllText($path, 'managed access request')
            [string] $currentUserSid = $script:Me.Value
            $file = [System.IO.FileInfo]::new($path)
            $share = [System.IO.FileShare]'ReadWrite, Delete'

            try {
                $security = [System.Security.AccessControl.FileSecurity]::new()
                $security.SetSecurityDescriptorSddlForm(
                    "D:P(D;;0x2;;;$currentUserSid)(A;;FR;;;$currentUserSid)",
                    $script:AccessOnly)
                Set-FileSecurity -Path $path -Security $security

                $stream = [System.IO.FileSystemAclExtensions]::Create(
                    $file,
                    [System.IO.FileMode]::Open,
                    [System.Security.AccessControl.FileSystemRights]::ReadData,
                    $share,
                    4096,
                    [System.IO.FileOptions]::None,
                    $null)
                try {
                    $stream.CanRead | Should -BeTrue
                }
                finally {
                    $stream.Dispose()
                }

                $writeError = {
                    [System.IO.FileSystemAclExtensions]::Create(
                        $file,
                        [System.IO.FileMode]::Open,
                        [System.Security.AccessControl.FileSystemRights]::WriteData,
                        $share,
                        4096,
                        [System.IO.FileOptions]::None,
                        $null).Dispose()
                } | Should -Throw -PassThru
                $writeError.Exception.InnerException |
                    Should -BeOfType ([System.UnauthorizedAccessException])
            }
            finally {
                $cleanup = [System.Security.AccessControl.FileSecurity]::new()
                $cleanup.SetSecurityDescriptorSddlForm(
                    "D:P(A;;FA;;;$currentUserSid)", $script:AccessOnly)
                Set-FileSecurity -Path $path -Security $cleanup
                Remove-Item -LiteralPath $path -Force
            }
        }
    }

    Context 'Directory rights govern the namespace, not just the object' {

        It 'removes and replaces a file whose own DACL denies delete when the parent allows it' {
            $parent = New-TestPath
            New-Item -ItemType Directory -Path $parent | Out-Null
            $victim = Join-Path $parent 'payload.bin'
            Set-Content -LiteralPath $victim -Value 'trusted' -NoNewline

            $security = Get-FileSecurity -Path $victim
            $security.SetAccessRuleProtection($true, $false)
            $security.AddAccessRule((New-Rule -Sid $script:Me -Rights 'Write, Delete' -Type Deny))
            $security.AddAccessRule((New-Rule -Sid $script:Me -Rights Read))
            Set-FileSecurity -Path $victim -Security $security

            try {
                # The deny is real: the file cannot be modified in place.
                { Set-Content -LiteralPath $victim -Value 'attacker' -NoNewline -ErrorAction Stop } | Should -Throw

                # But FILE_DELETE_CHILD on the parent substitutes for DELETE on the child, so the
                # file can be removed and recreated regardless of its own descriptor.
                { [System.IO.File]::Delete($victim) } | Should -Not -Throw
                Test-Path -LiteralPath $victim | Should -BeFalse

                Set-Content -LiteralPath $victim -Value 'attacker' -NoNewline
                Get-Content -LiteralPath $victim -Raw | Should -Be 'attacker'
            }
            finally { Restore-CallerAccess -Path $parent }
        }
    }

    Context 'Inheritance' {

        It 'inherits a parent inheritable ACE when the child is created without a descriptor' {
            $parent = New-TestPath
            New-Item -ItemType Directory -Path $parent | Out-Null
            $security = Get-DirectorySecurity -Path $parent
            $security.AddAccessRule((New-Rule -Sid $script:Users -Rights Write -Inheritance ContainerInherit))
            Set-DirectorySecurity -Path $parent -Security $security

            $child = Join-Path $parent 'plain'
            New-Item -ItemType Directory -Path $child | Out-Null

            try {
                Test-HasRuleFor -Path $child -Sid $script:Users | Should -BeTrue
            }
            finally { Restore-CallerAccess -Path $parent }
        }

        It 'suppresses parent inheritable ACEs when the child is created with a descriptor' {
            $parent = New-TestPath
            New-Item -ItemType Directory -Path $parent | Out-Null
            $security = Get-DirectorySecurity -Path $parent
            $security.AddAccessRule((New-Rule -Sid $script:Users -Rights Write -Inheritance ContainerInherit))
            Set-DirectorySecurity -Path $parent -Security $security

            $child = Join-Path $parent 'explicit'
            New-DirectoryWithDacl -Path $child -Rules @(
                New-Rule -Sid $script:Administrators -Rights FullControl -Inheritance $script:BothInherit
                New-Rule -Sid $script:Me -Rights FullControl -Inheritance $script:BothInherit
            ) | Out-Null

            try {
                Test-HasRuleFor -Path $child -Sid $script:Users | Should -BeFalse
                foreach ($rule in Get-RuleList -Path $child) { $rule.IsInherited | Should -BeFalse }
            }
            finally { Restore-CallerAccess -Path $parent }
        }

        It 'marks a directory created with an explicit descriptor as protected' {
            # Nothing in the calling code sets SE_DACL_PROTECTED. Supplying a DACL at creation
            # does it, and that is what stops later parent edits from reaching the object.
            $path = New-TestPath
            New-DirectoryWithDacl -Path $path -Rules @(
                New-Rule -Sid $script:Me -Rights FullControl -Inheritance $script:BothInherit
            ) | Out-Null

            try {
                (Get-DirectorySecurity -Path $path).AreAccessRulesProtected | Should -BeTrue
            }
            finally { Restore-CallerAccess -Path $path }
        }

        It 'protects an explicit descriptor even when it is marked auto-inherited' {
            $parent = New-TestPath
            New-Item -ItemType Directory -Path $parent | Out-Null
            $parentSecurity = Get-DirectorySecurity -Path $parent
            $parentSecurity.AddAccessRule((New-Rule -Sid $script:Users -Rights Write -Inheritance ContainerInherit))
            Set-DirectorySecurity -Path $parent -Security $parentSecurity

            $creator = [System.Security.AccessControl.DirectorySecurity]::new()
            $creator.SetOwner($script:Me)
            $creator.AddAccessRule((New-Rule -Sid $script:Me -Rights FullControl -Inheritance $script:BothInherit))
            $raw = [System.Security.AccessControl.RawSecurityDescriptor]::new(
                $creator.GetSecurityDescriptorBinaryForm(), 0)
            $flags = $raw.ControlFlags -bor
                [System.Security.AccessControl.ControlFlags]::DiscretionaryAclAutoInherited
            $raw = [System.Security.AccessControl.RawSecurityDescriptor]::new(
                $flags, $raw.Owner, $raw.Group, $raw.SystemAcl, $raw.DiscretionaryAcl)
            $binary = [byte[]]::new($raw.BinaryLength)
            $raw.GetBinaryForm($binary, 0)
            $creator.SetSecurityDescriptorBinaryForm($binary)

            $creatorFlags = [System.Security.AccessControl.RawSecurityDescriptor]::new(
                $creator.GetSecurityDescriptorBinaryForm(), 0).ControlFlags
            $creatorFlags.HasFlag(
                [System.Security.AccessControl.ControlFlags]::DiscretionaryAclAutoInherited) |
                Should -BeTrue

            $child = Join-Path $parent 'auto-inherited'
            [System.IO.FileSystemAclExtensions]::CreateDirectory($creator, $child) | Out-Null

            try {
                (Get-DirectorySecurity -Path $child).AreAccessRulesProtected | Should -BeTrue
                Test-HasRuleFor -Path $child -Sid $script:Users | Should -BeFalse
                foreach ($rule in Get-RuleList -Path $child) { $rule.IsInherited | Should -BeFalse }
            }
            finally { Restore-CallerAccess -Path $parent }
        }

        It 'does not propagate a later parent ACE into a protected child' {
            $parent = New-TestPath
            New-Item -ItemType Directory -Path $parent | Out-Null
            $child = Join-Path $parent 'protected'
            New-DirectoryWithDacl -Path $child -Rules @(
                New-Rule -Sid $script:Administrators -Rights FullControl -Inheritance $script:BothInherit
                New-Rule -Sid $script:Me -Rights FullControl -Inheritance $script:BothInherit
            ) | Out-Null

            try {
                $security = Get-DirectorySecurity -Path $parent
                $security.AddAccessRule((New-Rule -Sid $script:Users -Rights FullControl -Inheritance $script:BothInherit))
                Set-DirectorySecurity -Path $parent -Security $security

                Test-HasRuleFor -Path $parent -Sid $script:Users | Should -BeTrue
                Test-HasRuleFor -Path $child -Sid $script:Users | Should -BeFalse
            }
            finally { Restore-CallerAccess -Path $parent }
        }

        It 'applies the explicit descriptor to the intermediate directories it creates' {
            $root = New-TestPath
            $leaf = Join-Path $root 'a\b\c'
            New-DirectoryWithDacl -Path $leaf -Rules @(
                New-Rule -Sid $script:Administrators -Rights FullControl -Inheritance $script:BothInherit
                New-Rule -Sid $script:Me -Rights FullControl -Inheritance $script:BothInherit
            ) | Out-Null

            try {
                foreach ($level in @($root, (Join-Path $root 'a'), (Join-Path $root 'a\b'), $leaf)) {
                    Test-Path -LiteralPath $level | Should -BeTrue
                    Test-HasRuleFor -Path $level -Sid $script:Administrators | Should -BeTrue
                }

                (Get-DirectorySecurity -Path $root).AreAccessRulesProtected | Should -BeTrue
            }
            finally { Restore-CallerAccess -Path $root }
        }

        It 'carries an inherit-only ACE on the container and an effective one on the child' {
            # An inherit-only grant confers nothing on the container but everything below it. A
            # validator that ignores inherit-only rules would miss the grant entirely.
            $parent = New-TestPath
            New-Item -ItemType Directory -Path $parent | Out-Null
            $security = Get-DirectorySecurity -Path $parent
            $security.AddAccessRule((New-Rule -Sid $script:Users -Rights FullControl `
                        -Inheritance $script:BothInherit -Propagation InheritOnly))
            Set-DirectorySecurity -Path $parent -Security $security

            $child = Join-Path $parent 'child'
            New-Item -ItemType Directory -Path $child | Out-Null

            try {
                $parentRule = @(Get-RuleList -Path $parent | Where-Object { $_.IdentityReference -eq $script:Users })
                $parentRule.Count | Should -BeGreaterThan 0
                $parentRule[0].PropagationFlags | Should -Be ([System.Security.AccessControl.PropagationFlags]::InheritOnly)

                $childRule = @(Get-RuleList -Path $child | Where-Object { $_.IdentityReference -eq $script:Users })
                $childRule.Count | Should -BeGreaterThan 0
                $childRule[0].PropagationFlags | Should -Be ([System.Security.AccessControl.PropagationFlags]::None)
            }
            finally { Restore-CallerAccess -Path $parent }
        }
    }

    Context 'Reparse points' {

        It 'creates a directory junction without requiring elevation' {
            $target = New-TestPath
            New-Item -ItemType Directory -Path $target | Out-Null
            $junction = New-TestPath

            { New-Item -ItemType Junction -Path $junction -Target $target -ErrorAction Stop | Out-Null } |
                Should -Not -Throw

            (Get-Item -LiteralPath $junction -Force).Attributes.HasFlag(
                [System.IO.FileAttributes]::ReparsePoint) | Should -BeTrue
        }

        It 'reports the junction descriptor rather than the target descriptor' {
            $target = New-TestPath
            New-DirectoryWithDacl -Path $target -Rules @(
                New-Rule -Sid $script:Administrators -Rights FullControl -Inheritance $script:BothInherit
                New-Rule -Sid $script:Me -Rights FullControl -Inheritance $script:BothInherit
            ) | Out-Null
            $junction = New-TestPath
            New-Item -ItemType Junction -Path $junction -Target $target | Out-Null

            try {
                # The junction inherits from the test drive; the target carries an explicit DACL.
                # The reported descriptor identifies which object was actually queried.
                (Get-DirectorySecurity -Path $target).AreAccessRulesProtected | Should -BeTrue
                (Get-DirectorySecurity -Path $junction).AreAccessRulesProtected | Should -BeFalse
            }
            finally { Restore-CallerAccess -Path $target }
        }

        It 'deletes through an ancestor junction into the real target' {
            # Directory.Delete refuses to recurse through a reparse point only in the final path
            # segment. Windows resolves an ancestor junction before that check runs.
            $target = New-TestPath
            $realChild = Join-Path $target 'child'
            New-Item -ItemType Directory -Path $realChild | Out-Null
            Set-Content -LiteralPath (Join-Path $realChild 'data.txt') -Value 'real' -NoNewline

            $junction = New-TestPath
            New-Item -ItemType Junction -Path $junction -Target $target | Out-Null

            [System.IO.Directory]::Delete((Join-Path $junction 'child'), $true)

            Test-Path -LiteralPath $realChild | Should -BeFalse
            Test-Path -LiteralPath $target | Should -BeTrue
        }
    }
}
