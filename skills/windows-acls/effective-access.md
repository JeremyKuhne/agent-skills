# Evaluating descriptor access

Do not calculate effective rights by adding and subtracting ACE masks for one
SID. Windows evaluates a client context, not an isolated SID: the context can
include enabled and deny-only groups, restricted SIDs, privileges, a logon SID,
claims, and device groups. The descriptor's owner participates in the result too.

.NET does not wrap `AuthzAccessCheck`, so the practical question is which
narrower managed answer your feature actually needs. Authz evaluates the
security descriptors supplied by the caller against a client context; it does
not open the filesystem or registry object.

## Use managed APIs for narrower questions

`GetAccessControl`, `GetAccessRules`, and `WindowsPrincipal` never compare a
descriptor with a token. The first two read descriptor data; the last tests role
membership. Do not compose them into an effective-rights calculator. Opening an
object is different: it makes Windows run a real access check for the rights you
request.

| Question | Managed API | Result you may report |
| --- | --- | --- |
| Which owner and ACEs are stored? | `FileSystemAclExtensions.GetAccessControl` and `GetAccessRules` | Descriptor facts only. This is suitable for an ACL viewer or a fail-closed descriptor policy. |
| Is one SID enabled in this token? | `WindowsPrincipal.IsInRole(SecurityIdentifier)` | Token-specific role membership only. This is suitable when membership itself is the policy. |
| Can this token perform one file or registry operation now? | Perform the operation, or open the object with an exact `FileSystemRights` or `RegistryRights` request. | The operating system granted or denied that request at that time. |
| What mask does this client context receive from this supplied descriptor? | None; .NET does not wrap `AuthzAccessCheck`. | Nothing, until you add the native Authz flow below. |

### Inspect the descriptor without adjudicating it

Use
[`GetAccessControl`](https://learn.microsoft.com/dotnet/api/system.io.filesystemaclextensions.getaccesscontrol)
and
[`GetAccessRules`](https://learn.microsoft.com/dotnet/api/system.security.accesscontrol.commonobjectsecurity.getaccessrules)
to describe or validate the stored ACL:

```csharp
FileSecurity security = new FileInfo(path).GetAccessControl(
    AccessControlSections.Owner | AccessControlSections.Access);
AuthorizationRuleCollection rules = security.GetAccessRules(
    includeExplicit: true,
    includeInherited: true,
    targetType: typeof(SecurityIdentifier));
```

This is the right level for questions such as "is inheritance protected?" or
"does any allow ACE grant a dangerous right to an untrusted trustee?" It is not
the right level for "can this user write?" Reading the descriptor can itself be
denied even when the caller has other access to the file, so failure to retrieve
it is not an effective-access result.

### Use WindowsPrincipal only for role policy

Prefer the SID overload when the policy literally requires an enabled group:

```csharp
using WindowsIdentity identity = WindowsIdentity.GetCurrent();
WindowsPrincipal principal = new(identity);
SecurityIdentifier administrators = new(
    WellKnownSidType.BuiltinAdministratorsSid,
    domainSid: null);
bool enabledAdministrator = principal.IsInRole(administrators);
```

[`IsInRole`](https://learn.microsoft.com/dotnet/api/system.security.principal.windowsprincipal.isinrole)
answers for the token represented by that `WindowsIdentity`. Microsoft documents
that a UAC-filtered administrator token returns `false` for Administrators even
when the account belongs to that group. That makes the method useful for a
current-token role gate, but not for reporting directory-service membership or
whether the account could elevate.

Never enumerate allow and deny rules, call `IsInRole` for each trustee, and
combine the masks. The
[`WindowsPrincipal` implementation](https://source.dot.net/#System.Security.Principal.Windows/System/Security/Principal/WindowsPrincipal.cs)
uses `CheckTokenMembership`, which returns `true` only when a SID is present and
enabled. A deny-only SID therefore returns `false`, while Windows still applies
deny ACEs for that SID during an access check. The managed
[`WindowsIdentity.Groups`](https://learn.microsoft.com/dotnet/api/system.security.principal.windowsidentity.groups)
collection exposes identity references, not the SID attributes needed to repair
that omission. Such a loop also misses restricted-token evaluation, privileges,
owner rights, and ordered ACE processing.

### Perform the requested operation

For a concrete current-token question, let Windows answer it. The managed
[`FileSystemAclExtensions.Create`](https://learn.microsoft.com/dotnet/api/system.io.filesystemaclextensions.create)
overload takes an exact `FileSystemRights` mask, and with `FileMode.Open` it
opens an existing file rather than creating one:

```csharp
using FileStream stream = new FileInfo(path).Create(
    FileMode.Open,
    FileSystemRights.ReadData,
    FileShare.ReadWrite | FileShare.Delete,
    bufferSize: 4096,
    FileOptions.None,
    fileSecurity: null);
```

For a registry key, request the rights on the handle you will use:

```csharp
using RegistryKey? key = parent.OpenSubKey(
    name,
    RegistryKeyPermissionCheck.Default,
    RegistryRights.QueryValues);

if (key is null)
{
    throw new InvalidOperationException("The registry key does not exist.");
}
```

Keep and use the returned stream or key; closing it and reopening the name later
turns the check into a race. An access exception means the requested open was
not granted; `OpenSubKey` instead returns `null` when the key does not exist.
When the application already has the real operation - a read, a replace, a
delete - perform that instead. The file overload cannot open a directory, so
answer a directory question with the real directory operation. Given a token for
another identity,
[`WindowsIdentity.RunImpersonated`](https://learn.microsoft.com/dotnet/api/system.security.principal.windowsidentity.runimpersonated)
runs that operation under it.

A successful open proves only that Windows issued that handle with those rights.
A failure does not isolate the DACL as the cause: sharing modes, path
resolution, and object state also reject operations. This answers one operation
for one token; it yields no reusable mask and cannot evaluate an arbitrary SID.

## Choose the identity source

Reach for native Authz only when a diagnostic, policy editor, or custom resource
manager must report a descriptor-evaluation mask instead of performing an
operation. Keep the interop in one small Windows-only component; nothing above
approximates it safely.

| Available identity | Authz context | Meaning |
| --- | --- | --- |
| The caller's primary or impersonation token | `AuthzInitializeContextFromToken` | Preferred. It preserves the actual logon context and is the most complete input. The token needs `TOKEN_QUERY`. |
| Only a valid user or computer SID | `AuthzInitializeContextFromSid` with flags `0` | Reconstructed result. Authz attempts an S4U logon, then falls back to account group data when S4U is unavailable. It can fail if the caller cannot read domain group data. |
| An arbitrary SID with no account lookup | `AuthzInitializeContextFromSid` with `AUTHZ_SKIP_TOKEN_GROUPS` | Synthetic SID-only result. It intentionally omits group evaluation and is not the effective access of a logged-on user. |

Microsoft explicitly recommends
[`AuthzInitializeContextFromToken`](https://learn.microsoft.com/windows/win32/api/authz/nf-authz-authzinitializecontextfromtoken)
when possible. Its
[`AuthzInitializeContextFromSid`](https://learn.microsoft.com/windows/win32/api/authz/nf-authz-authzinitializecontextfromsid)
documentation says a token context is more complete and accurate. SID-based
fallback group lookup can omit logon-characteristic groups such as Interactive,
Network, and Anonymous.

Do not pass a group SID as though it identified a user. Current
`AuthzInitializeContextFromSid` requires a valid user or computer account unless
group evaluation is skipped. A group trustee does not by itself describe any
particular caller's effective rights.

## Evaluate the descriptor

Use this sequence for a diagnostic descriptor-access result:

1. Read the object's security descriptor with `Owner` and `Access` sections. `AuthzAccessCheck` requires both owner and DACL information for this flow.
2. Create an Authz resource manager with `AUTHZ_RM_FLAG_NO_AUDIT`.
3. Create the client context from the actual token when one is available;
   otherwise create the qualified SID-based context described above.
4. Set `AUTHZ_ACCESS_REQUEST.DesiredAccess` to
   [`MAXIMUM_ALLOWED`](https://learn.microsoft.com/windows/win32/secauthz/access-mask)
   and call
   [`AuthzAccessCheck`](https://learn.microsoft.com/windows/win32/api/authz/nf-authz-authzaccesscheck).
5. Check both the API return value and `AUTHZ_ACCESS_REPLY.Error[0]`. A `FALSE` return is an API failure. The reply error is the authorization result; `ERROR_ACCESS_DENIED` is an ordinary denial, including a `MAXIMUM_ALLOWED` result with a zero mask.
6. Free the client context and resource manager on every path.

The essential call shape is:

```csharp
AUTHZ_ACCESS_REQUEST request = new()
{
    DesiredAccess = MAXIMUM_ALLOWED
};
AUTHZ_ACCESS_REPLY reply = AllocateReply(1);

if (!AuthzAccessCheck(
        0,
        clientContext,
        ref request,
        nint.Zero,
        securityDescriptor,
        nint.Zero,
        0,
        ref reply,
        nint.Zero))
{
    throw new Win32Exception(Marshal.GetLastWin32Error());
}

uint resultCode = reply.Error[0];
uint grantedMask = reply.GrantedAccessMask[0];
bool granted = resultCode == ERROR_SUCCESS;
```

This intentionally shows the authorization flow rather than unsafe declarations
and allocation plumbing. Preserve `resultCode` in a reusable result type so a
denial is not reported as an interop failure. The official
[`GetEffectiveRightsFromAcl` example](https://learn.microsoft.com/windows/win32/api/aclapi/nf-aclapi-geteffectiverightsfromaclw)
contains a complete native Authz implementation. Generate or declare the Authz
APIs using the consuming codebase's established interop mechanism.

### Keep descriptor evaluation scoped

The flow above evaluates the owner and DACL supplied by the caller. Do not
describe it as the operating system opening the named object:

- It does not read the mandatory integrity label, resource attributes, or central access policy scope stored in the SACL.
- A child descriptor alone cannot account for a separate parent grant such as `FILE_DELETE_CHILD`.
- The no-callback resource manager shown here establishes no result for conditional or callback ACEs that require resource-manager policy or context attributes.
- Sharing mode, path resolution, object state, and a later descriptor change can still reject the real operation.

The result is a diagnostic snapshot. Never report the mask as a promise that a
later operation will succeed.

## Do not use the legacy shortcut as authority

`GetEffectiveRightsFromAcl` sounds like the direct answer, but Microsoft marks
it as potentially altered or unavailable and points to the Authz example
instead. Its documented result omits:

- implicit owner rights such as `READ_CONTROL` and `WRITE_DAC`;
- privileges held by the trustee;
- logon-session groups; and
- resource-manager policy, including rights supplied by a file's parent.

It also fails with `ERROR_INVALID_ACL` when the ACL contains an inherited deny
ACE. It can support a constrained ACL-reporting tool when those limits are part
of the contract. Do not use it for an authorization decision or describe its
mask as the operating system's final answer.
