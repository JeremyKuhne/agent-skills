# Storage call sites

This is synthetic .NET 10 source for a storage review. Methods represent
independent features; a scoped review need not review every method. Do not invoke
the maintenance operation against real files.

## Public index

`SavePublicIndex` and `ReadPublicIndex` run unelevated on Windows, Linux, and
macOS in the normal per-user cache location. The cache contains JSON generated
from bundled public product data, is bounded to 16 KiB, and contains no personal
data, secrets, paths to execute, or privileged policy. There is one writer and
no reads overlap a write. Any syntactically valid JSON is acceptable to the
consumer. Missing or invalid entries can be rebuilt from the bundled data;
other I/O errors are reported to the caller. The cache need not survive a crash.

## Refresh token

`SaveRefreshToken` uses the same normal per-user cache location and the same
single-writer, non-overlapping usage on all three platforms. Its input is a live
server refresh credential, not a sample token. The user can obtain another by
signing in. No credential-store API is in use, and no additional access-policy
validation or encryption is performed. There are no actual credentials in this
fixture.

## Record header

`ReadRecordLength` reads a four-byte little-endian record header through the
application's `Stream` abstraction. Wrappers and a truncated file can reach this
method. A complete header must be consumed before the length is returned.

## Launch count

`IncrementLaunchCount` uses an already initialized per-user counter. The feature
owner has not established whether multiple application instances can update it
at the same time. There is no documented decision about retaining every
increment. The file contains no credentials or privileged policy.

## Maintenance service

`RunMaintenanceJob` is called by a Windows LocalSystem service. An unelevated
user supplies `requestPath`, which points to a job file inside that user's
LocalAppData directory. That user writes the entire job-file content. The
service performs no other authorization or target validation before calling
this method. The target need not be under the user's profile.

## Theme defaults and user preferences

`ResolveTheme` and `SaveTheme` belong to an ordinary unelevated Windows desktop
application. The packaged theme is the initial fallback; an optional machine
theme supplies the starting value for every user; an optional user theme may
override it. An absent or empty value means no override. Theme is not enforced
policy and contains no secret or device-specific value. One process writes
preferences for each user; there are no overlapping writes in this case.

The machine-defaults file is under an application directory in ProgramData,
provisioned with known-good ownership and ACLs by the installer. Ordinary users
can read it but only an administrator or installer can write it. The normal
settings UI passes this machine-defaults path to `SaveTheme` whenever a user
changes their theme. No separate user save path or Reset behavior has been
implemented. Administrator updates to defaults must still reach users who have
not made an explicit choice or who have reset their choice.

## Mandatory upload policy

`ResolveUploadPolicy` runs inside a service that is the authoritative decision
maker for uploading data outside the machine. Its `mandatoryAllowUploads` value
comes from a correctly provisioned administrator-controlled policy store. That
source has already been authenticated and validated; missing or invalid policy
stops the operation before this method. The administrator locks this key to the
policy value; it is not an overrideable default.

An ordinary user can supply `userAllowUploads` through their preferences.
The service passes both values to this method and permits uploads when it returns
`true`. No further policy check occurs after the return. These facts are separate
from the theme defaults and from the maintenance-job feature.
