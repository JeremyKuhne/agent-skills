# Primary documentation index

Curated links behind the `windows-acls` guidance, grouped by the question they
answer.

## Access control model

- [Access control lists](https://learn.microsoft.com/windows/win32/secauthz/access-control-lists)
- [Access control entries](https://learn.microsoft.com/windows/win32/secauthz/access-control-entries)
- [DACLs and ACEs](https://learn.microsoft.com/windows/win32/secauthz/dacls-and-aces)
- [Order of ACEs in a DACL](https://learn.microsoft.com/windows/win32/secauthz/order-of-aces-in-a-dacl) - explicit ACEs precede inherited ACEs; explicit denies precede explicit allows; inherited denies precede inherited allows at each inheritance level
- [Creating a DACL](https://learn.microsoft.com/windows/win32/secbp/creating-a-dacl) - includes the guidance against NULL DACLs
- [Access tokens](https://learn.microsoft.com/windows/win32/secauthz/access-tokens)
- [SID attributes in an access token](https://learn.microsoft.com/windows/win32/secauthz/sid-attributes-in-an-access-token) - enabled SIDs participate in allow and deny checks; deny-only SIDs participate only in deny checks
- [CheckTokenMembership](https://learn.microsoft.com/windows/win32/api/securitybaseapi/nf-securitybaseapi-checktokenmembership) - tests whether a SID is present and enabled; it is not an object access check
- [ACCESS_MASK](https://learn.microsoft.com/windows/win32/secauthz/access-mask) - defines object-specific, standard, generic, and `MAXIMUM_ALLOWED` bits
- [How access check works](https://learn.microsoft.com/windows/win32/secauthz/how-dacls-control-access-to-an-object) - Windows examines matching ACEs sequentially and stops at a matching deny or when allows grant every requested right
- [Using Authz API](https://learn.microsoft.com/windows/win32/secauthz/using-authz-api)
- [AuthzAccessCheck](https://learn.microsoft.com/windows/win32/api/authz/nf-authz-authzaccesscheck) - evaluates a security descriptor for a client context and returns granted masks
- [AUTHZ_ACCESS_REPLY](https://learn.microsoft.com/windows/win32/api/authz/ns-authz-authz_access_reply) - carries one granted mask and authorization result per requested object type
- [AuthzInitializeContextFromToken](https://learn.microsoft.com/windows/win32/api/authz/nf-authz-authzinitializecontextfromtoken) - preferred context source when an access token is available
- [AuthzInitializeContextFromSid](https://learn.microsoft.com/windows/win32/api/authz/nf-authz-authzinitializecontextfromsid) - reconstructs a less complete context when only a valid user or computer SID is available
- [GetEffectiveRightsFromAcl](https://learn.microsoft.com/windows/win32/api/aclapi/nf-aclapi-geteffectiverightsfromaclw) - legacy shortcut with documented omissions; Microsoft points to its Authz example instead

## Inheritance and propagation

- [Inheritance](https://learn.microsoft.com/windows/win32/secauthz/inheritance)
- [ACE inheritance rules](https://learn.microsoft.com/windows/win32/secauthz/ace-inheritance-rules) - the `OI`/`CI`/`IO`/`NP` matrix
- [Automatic propagation of inheritable ACEs](https://learn.microsoft.com/windows/win32/secauthz/automatic-propagation-of-inheritable-aces) - describes merging inherited ACEs unless `SE_DACL_PROTECTED` is set; the measured .NET create path differs
- [SetNamedSecurityInfo](https://learn.microsoft.com/windows/win32/api/aclapi/nf-aclapi-setnamedsecurityinfow)
- [SetSecurityInfo](https://learn.microsoft.com/windows/win32/api/aclapi/nf-aclapi-setsecurityinfo)
- [SECURITY_DESCRIPTOR_CONTROL](https://learn.microsoft.com/windows/win32/secauthz/security-descriptor-control) - the `SE_DACL_PROTECTED` and `SE_DACL_AUTO_INHERITED` bits

## Ownership

- [Owners and ownership](https://learn.microsoft.com/windows/win32/secauthz/owners-and-ownership) - an owner implicitly holds `READ_CONTROL` and `WRITE_DAC`
- [TOKEN_OWNER](https://learn.microsoft.com/windows/win32/api/winnt/ns-winnt-token_owner) - a SID may own an object only if the token carries it with `SE_GROUP_OWNER`
- [Privilege constants](https://learn.microsoft.com/windows/win32/secauthz/privilege-constants) - `SeRestorePrivilege` permits assigning an otherwise unrelated valid owner SID
- [System objects: Default owner for objects created by members of the Administrators group](https://learn.microsoft.com/previous-versions/windows/it-pro/windows-10/security/threat-protection/security-policy-settings/system-objects-default-owner-for-objects-created-by-members-of-the-administrators-group)
- [Well-known SIDs](https://learn.microsoft.com/windows-server/identity/ad-ds/manage/understand-security-identifiers)

## File and directory rights

- [File security and access rights](https://learn.microsoft.com/windows/win32/fileio/file-security-and-access-rights)
- [File access rights constants](https://learn.microsoft.com/windows/win32/fileio/file-access-rights-constants) - defines `FILE_DELETE_CHILD`
- [Standard access rights](https://learn.microsoft.com/windows/win32/secauthz/standard-access-rights) - `DELETE`, `WRITE_DAC`, `WRITE_OWNER`
- [Creating a security descriptor for a new object](https://learn.microsoft.com/windows/win32/secauthz/creating-a-security-descriptor-for-a-new-object-in-c--)

## Integrity levels and elevation

- [Mandatory integrity control](https://learn.microsoft.com/windows/win32/secauthz/mandatory-integrity-control)
- [Centralized authorization policy](https://learn.microsoft.com/windows/win32/secauthz/centralized-authorization-policy)
- [SECURITY_INFORMATION](https://learn.microsoft.com/windows/win32/secauthz/security-information) - identifies owner, DACL, mandatory-label, resource-attribute, and central-policy-scope information
- [How User Account Control works](https://learn.microsoft.com/windows/security/identity-protection/user-account-control/how-user-account-control-works) - filtered administrator tokens and deny-only groups
- [User Account Control security policy settings](https://learn.microsoft.com/windows/security/identity-protection/user-account-control/settings-and-configuration)

## Reparse points

- [Reparse points](https://learn.microsoft.com/windows/win32/fileio/reparse-points)
- [Hard links and junctions](https://learn.microsoft.com/windows/win32/fileio/hard-links-and-junctions)
- [Symbolic link effects on file system functions](https://learn.microsoft.com/windows/win32/fileio/symbolic-link-effects-on-file-systems-functions) - deleting a link deletes the link, not the target
- [Create symbolic links privilege](https://learn.microsoft.com/windows/security/threat-protection/security-policy-settings/create-symbolic-links) - required for symlinks, not for junctions

## Paths

- [File path formats on Windows systems](https://learn.microsoft.com/dotnet/standard/io/file-path-formats) - normalization, trailing dots and spaces, legacy device names
- [Naming files, paths, and namespaces](https://learn.microsoft.com/windows/win32/fileio/naming-a-file)

## Where state belongs

- [KNOWNFOLDERID](https://learn.microsoft.com/windows/win32/shell/knownfolderid) - the canonical list, including `FOLDERID_LocalAppData`, `FOLDERID_RoamingAppData`, `FOLDERID_ProgramData`
- [Environment.SpecialFolder](https://learn.microsoft.com/dotnet/api/system.environment.specialfolder)
- [Isolated storage in multi-user environments](https://learn.microsoft.com/dotnet/standard/io/isolated-storage#impact-in-multi-user-environments) - per-user stores versus machine stores as a trust boundary
- [ProgramData folder location](https://learn.microsoft.com/windows-hardware/customize/desktop/unattend/microsoft-windows-shell-setup-folderlocations-programdata)
- [Registry hives](https://learn.microsoft.com/windows/win32/sysinfo/registry-hives)
- [Accessing an alternate registry view](https://learn.microsoft.com/windows/win32/winprog64/accessing-an-alternate-registry-view) - WOW64 redirection
- [RegCreateKeyEx](https://learn.microsoft.com/windows/win32/api/winreg/nf-winreg-regcreatekeyexw) - reports whether it created a key or opened an existing one

## Installer-provisioned locations

- [MsiLockPermissionsEx table](https://learn.microsoft.com/windows/win32/msi/msilockpermissionsex-table)
- [LockPermissions table](https://learn.microsoft.com/windows/win32/msi/lockpermissions-table) - the older mechanism; cannot express deny ACEs or inheritance
- [Securing resources](https://learn.microsoft.com/windows/win32/msi/securing-resources-)
- [Guidelines for authoring secure installations](https://learn.microsoft.com/windows/win32/msi/guidelines-for-authoring-secure-installations)

## Secrets

- [ProtectedData class (DPAPI)](https://learn.microsoft.com/dotnet/api/system.security.cryptography.protecteddata)
- [Windows Credential Manager](https://learn.microsoft.com/windows/win32/api/wincred/nf-wincred-credwritew)

## .NET APIs

- [DirectorySecurity](https://learn.microsoft.com/dotnet/api/system.security.accesscontrol.directorysecurity)
- [FileSecurity](https://learn.microsoft.com/dotnet/api/system.security.accesscontrol.filesecurity)
- [FileSystemAclExtensions](https://learn.microsoft.com/dotnet/api/system.io.filesystemaclextensions) - create, open, read, and write file and directory security
- [FileSystemAclExtensions.CreateDirectory](https://learn.microsoft.com/dotnet/api/system.io.filesystemaclextensions.createdirectory) - returns an existing directory without applying the supplied descriptor
- [FileSystemAclExtensions.Create](https://learn.microsoft.com/dotnet/api/system.io.filesystemaclextensions.create) - can open an existing file with an exact `FileSystemRights` request
- [CommonObjectSecurity.GetAccessRules](https://learn.microsoft.com/dotnet/api/system.security.accesscontrol.commonobjectsecurity.getaccessrules) - enumerates stored access rules; it does not evaluate a token
- [ObjectSecurity.SetAccessRuleProtection](https://learn.microsoft.com/dotnet/api/system.security.accesscontrol.objectsecurity.setaccessruleprotection)
- [FileSystemRights](https://learn.microsoft.com/dotnet/api/system.security.accesscontrol.filesystemrights)
- [InheritanceFlags](https://learn.microsoft.com/dotnet/api/system.security.accesscontrol.inheritanceflags) and [PropagationFlags](https://learn.microsoft.com/dotnet/api/system.security.accesscontrol.propagationflags)
- [RegistrySecurity](https://learn.microsoft.com/dotnet/api/system.security.accesscontrol.registrysecurity)
- [RegistryKey.CreateSubKey](https://learn.microsoft.com/dotnet/api/microsoft.win32.registrykey.createsubkey) - creates a key or opens an existing key
- [RegistryKey.OpenSubKey](https://learn.microsoft.com/dotnet/api/microsoft.win32.registrykey.opensubkey) - can request exact `RegistryRights` on the returned handle
- [WindowsIdentity](https://learn.microsoft.com/dotnet/api/system.security.principal.windowsidentity) and [WindowsPrincipal](https://learn.microsoft.com/dotnet/api/system.security.principal.windowsprincipal)
- [WindowsPrincipal.IsInRole](https://learn.microsoft.com/dotnet/api/system.security.principal.windowsprincipal.isinrole) - tests one enabled role in the represented token, with documented UAC behavior
- [WindowsIdentity.RunImpersonated](https://learn.microsoft.com/dotnet/api/system.security.principal.windowsidentity.runimpersonated) - performs a managed operation under a supplied access token

## Continuous integration

- [GitHub-hosted runners reference](https://docs.github.com/actions/reference/runners/github-hosted-runners) - "Windows virtual machines are configured to run as administrators with User Account Control (UAC) disabled"
- [Microsoft-hosted agents](https://learn.microsoft.com/azure/devops/pipelines/agents/hosted)
