# Choose the implementation boundary

Use this decision before adding a PowerShell implementation or extending an existing
one. Familiarity, nearby scripts, and easy string manipulation are not ownership
evidence.

## Decision table

| Question | Keep PowerShell when | Choose another boundary when |
| --- | --- | --- |
| What behavior is under test? | It is parameter binding, pipeline, stream, module, provider, remoting, environment, or shell-entry behavior. | It is another language's grammar, a managed API contract, a binary format, or external-tool semantics. |
| What API already owns the semantics? | PowerShell's parser, runtime, engine APIs, or process entry point is authoritative. | A maintained parser, schema validator, compiler, platform API, or CLI already exists. |
| What is the independent oracle? | A public PowerShell boundary, fresh process receipt, or observed host result can decide correctness. | The proposed test would copy the implementation's outputs or internal branches. |
| How large is the state model? | The state is small, explicit, and naturally represented by PowerShell. | Correctness needs a typed state machine, reusable supervision, or broad cross-process aggregation. |

## Greenfield check

Before extending a repository pattern, write down:

1. **Subject:** the behavior being decided.
2. **Owner:** the runtime, parser, API, tool, or platform authoritative for it.
3. **Oracle:** evidence independent from the implementation.
4. **PowerShell role:** implementation, orchestration, adapter, or no role.
5. **Alternative:** one credible maintained or managed boundary.
6. **Canary:** the smallest comparison that could disprove the preferred choice.

Choose the simpler boundary only after the canary exercises the difficult behavior. A
short implementation is not simpler when it creates a second parser or an unbounded
control-flow model.

## Stop and reconsider

Reopen the premise when any of these occurs:

- each review round discovers a new syntax or execution class;
- tests mainly encode the latest bypass example;
- comments, strings, quoting, nesting, aliases, or control flow require growing
  exclusion lists;
- a validator is expected to resist compromised or arbitrary scripts without a security
  design;
- the agent cannot name the subject, owner, oracle, and stopping condition; or
- the same feature could call a maintained parser or typed API with less policy surface.

Preserve reusable evidence when replacing an implementation: accepted contracts,
fixtures, parser choices, host observations, and validation receipts can survive even
when the code should not.
