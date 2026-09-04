# Bounded named-pipe echo sample

This .NET 10 console application is the buildable version of the named-pipe and
framing patterns in the skill. It uses byte mode, a four-byte big-endian length
header, a 64 KiB payload limit, asynchronous I/O, `CurrentUserOnly`, a fixed
worker count, separate connection/request/idle deadlines, and supervised
cancellation shutdown.

The CLI client allows five seconds to connect and another five seconds to write
the request and read the complete reply. Each connected server worker allows
thirty seconds for the first frame byte, then five seconds for the remaining
frame and response write. A stalled client loses only its own connection. An
unexpected worker failure cancels and drains the other workers before the
server reports the failure. The helper overloads accept custom positive,
finite timeout values.

An access-denied accept drops the rejected peer and resumes listening. The
worker count limits active handlers; on Unix, additional connections can enter
the socket backlog and wait under their request deadline.

Build the sample:

```pwsh
dotnet build BoundedPipeEcho.csproj --configuration Release
```

Start a server for up to four concurrent clients:

```pwsh
dotnet run --project BoundedPipeEcho.csproj --configuration Release -- `
  server sample.echo 4
```

Run a client from another terminal:

```pwsh
dotnet run --project BoundedPipeEcho.csproj --configuration Release -- `
  client sample.echo "hello"
```

The echoed response is written to standard output. Press Ctrl+C in the server
terminal to cancel pending accepts and stop the workers.
