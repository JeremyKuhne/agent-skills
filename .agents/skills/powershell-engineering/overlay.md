---
core: powershell-engineering
core-pin: 4cb6038943c3f66164717d011b8b7b7ac5e6d3c2
---

# PowerShell engineering overlay

## Repository bindings

- The [toolchain manifest](../../../tools/powershell-toolchain.json) sets the
  retained-test PowerShell minimum to 7.4, Pester compatibility to 6.2.0 or
  later, and the repository execution lock to 6.2.0. It does not yet set the
  floor for every operational or shipped script.
- Run focused retained PowerShell tests through the
  [isolated shard runner](../../../tests/Invoke-PesterShards.ps1) with `-Path`
  pointing to the affected `*.Tests.ps1` file. Run the full suite with
  `./tests/Invoke-PesterShards.ps1 -Path ./tests`. Keep discovered, passed,
  skipped, and incomplete work distinct.
- The [managed toolchain project](../../../tests/powershell-toolchain/PowerShellToolchain.Tests.csproj)
  owns repository metadata and workflow policy. Run `dotnet restore ./tests/powershell-toolchain/PowerShellToolchain.Tests.csproj --locked-mode`.
  Then run `dotnet test --project ./tests/powershell-toolchain/PowerShellToolchain.Tests.csproj --configuration Release --no-restore`.
  Its pass does not prove PowerShell process behavior.
- The [CI workflow](../../../.github/workflows/ci.yml) runs Linux ARM64 and
  Windows scaffold lanes plus separate managed tests. Report only the hosts
  whose owning behavior lane actually ran; a skip is not host evidence.
- [AGENTS.md](../../../AGENTS.md) owns its
  [Copilot mirror](../../../.github/copilot-instructions.md); regenerate with
  `./tools/Validate-AgentFiles.ps1 -Fix`. The generated portfolio matrix in
  [skills/README.md](../../../skills/README.md) comes from
  `./tools/Update-SkillCatalog.ps1 -Apply`. Use the
  [ownership inventory](../../../docs/powershell-test-ownership-inventory.md)
  to identify generated consumer templates and their behavior tests.
- The [engineering plan](../../../docs/powershell-engineering-plan.md) defers
  coverage ratchets and the provisional global 80/90 targets. Do not present
  them as active gates or combine managed and PowerShell percentages.
- Follow [AGENTS.md](../../../AGENTS.md) for commit, push, pull-request, and
  real-model-run approval boundaries; [RELEASING.md](../../../RELEASING.md)
  owns the separate release gates.
