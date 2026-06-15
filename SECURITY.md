# Security Policy

## Reporting a vulnerability

Please report security vulnerabilities privately - not in public issues.

Use GitHub's private vulnerability reporting: open the **Security** tab of this
repository and choose **Report a vulnerability**, or go directly to
<https://github.com/JeremyKuhne/agent-skills/security/advisories/new>. This opens
a private advisory visible only to the maintainer.

Include, as far as you can:

- a description of the issue and its impact;
- the version (tag or commit) affected;
- steps to reproduce;
- any known workaround.

## Scope

This repository distributes **agent skills** - instructions that AI coding agents
load and act on - together with a plugin manifest and Model Context Protocol (MCP)
server configuration. The security-relevant surface is the content itself, not a
running service. In scope:

- skill or agent content that could steer an agent into unsafe actions, exfiltrate
  data, or carry a prompt-injection payload;
- the plugin manifest (`plugin.json`), the marketplace listing, or the MCP
  configuration (`.mcp.json`) pointing a consumer at an unexpected or malicious
  server;
- weaknesses in the provenance or pinning guidance that would let a vendored copy
  be substituted without detection.

## Supported versions

This project is pre-1.0. Fixes land on the `main` branch and ship in the next
tagged release; only the latest release line is supported, so update your pinned
version to pick up a fix.

## Response

This is a personal open-source project maintained on a best-effort basis. You can
expect an initial acknowledgement; please allow a reasonable window for a fix
before any public disclosure.
