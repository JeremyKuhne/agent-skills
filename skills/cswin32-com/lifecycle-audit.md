# COM ownership and lifecycle audit

Detail for [cswin32-com](SKILL.md). Use this audit before implementing or
reviewing a COM leak, subscription-lifetime, adapter, or disposal fix. Reference
counts are only one part of correctness: the product must also establish the
cleanup trigger, represent every native registration, and remain valid when a
native call transfers ownership or reenters managed code.

## Build the ledger first

Record one row for every touched pointer, wrapper, cookie, release owner, or
native registration:

| Edge or value | Acquired or borrowed | Callee action | Transfer predicate | Activation trigger | Cleanup trigger | Identity and multiplicity | Failure and reentrancy |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Example event sink | caller owns one CCW reference | source retains on successful `Advise` | none | owner starts observation | owner calls `Unadvise` | cookie plus sink identity | callback may dispose owner |

Do not fill the table from names or comments alone. Trace the controlling call
path from owner creation to the native acquire, retain, or attach call, then to
the callback or state transition that starts cleanup. A stored observer is not
an active observer until the code actually connects it.

Separate product-owned lifecycle edges from optional application behavior. If a
manager needs unload or termination notification to release objects it owns,
the manager must establish that observation independently. A test that adds an
application event handler can accidentally activate the missing connection and
hide the ordinary-path leak. Removing the last application handler must not
disconnect observation that the manager still requires.

## Distinguish borrow, retain, and transfer

- **Borrow:** the callee uses the pointer only during the call. Release any
  caller-owned temporary reference afterward; never release a borrowed input.
- **Retain:** on success the callee acquires an independent reference. The
  caller still releases its temporary reference. `Advise` and `SetClientSite`
  commonly have this shape.
- **Transfer:** a documented result and flag move the caller's existing
  ownership to the callee. After that predicate is true, the caller must not
  read, copy back, release, or otherwise inspect a value the callee may already
  have destroyed.

`IDataObject::SetData` is the important transfer example. A successful call with
`fRelease=TRUE` transfers the whole `STGMEDIUM`; the recipient may call
`ReleaseStgMedium` before returning. Do not convert the native structure back or
release `pUnkForRelease` after that call. A managed-to-native conversion can
itself acquire a temporary `pUnkForRelease` reference. Before the call that
reference is caller-owned; successful transfer moves it with the medium, while
failure or `fRelease=FALSE` leaves the conversion reference for the adapter to
release. Keep the caller's managed value unchanged after successful transfer.

For every transfer-capable call, test the full predicate rather than success
alone: success and failure, transfer flag true and false, release owner present
and absent, recipient retains and recipient destroys during the call, and any
failure that occurs after conversion but before the native call.

## Represent native registration identity

Managed delegate equality is not native registration identity. Every successful
attach can create a distinct proxy, CCW, or cookie even when the event name and
delegate compare equal. The owner must retain enough information to detach each
successful registration exactly once.

- Track a registration only after native attach succeeds. If attach reenters
  disposal, roll it back before returning.
- Include the native discriminator: source, event name or IID, proxy identity,
  and cookie where applicable.
- Detach one exact matching registration. An unmatched removal is a no-op and
  must not decrement a guessed count or disconnect other registrations.
- If detach fails, retain or restore ownership metadata so final cleanup can
  retry unless the API contract proves no registration remains; do not create
  an untracked native sink.
- Keep ordinary connection-point handlers separate from individually attached
  dispatch proxies when they have independent native lifetimes.

Exercise duplicate delegates, the same delegate under different names,
multicast delegates, unmatched removal, repeated removal, and mixed event APIs.
Tests with one delegate and one name cannot validate the representation.

## Make teardown reentrant

Native disconnect and release calls can invoke managed callbacks. Establish a
terminal state before making them:

1. mark the owner disposed or unloading;
2. remove it from manager lookups or clear the lookup collections;
3. move each owned reference or registration to local cleanup state;
4. attempt every independent disconnect and release;
5. report failures after cleanup, preserving one original exception or
   aggregating independent failures according to the API contract.

Removal after teardown must be non-creating. An event `remove` or detach method
must not use a lazy property that recreates the native owner it is trying to
clean up. Test callbacks that dispose the owner, throw, remove themselves, or
trigger another detach. Also inject one detach failure and prove unrelated
owners and the outer native object are still released.

## Design tests from product invariants

Write the cheapest test that can falsify the controlling path before building a
large reference-count suite:

1. Exercise the ordinary public workflow without optional application hooks.
2. Assert that the internal native observation or registration was actually
   established, not merely allocated.
3. Trigger the real lifecycle transition and verify both release and continued
   usability of unaffected owners.
4. Add the ownership, multiplicity, failure, and reentrancy matrix only after
   the controlling path passes.

Keep the oracle independent of the proposed representation. Prefer externally
observable lifetime, native reference counts, live-handle checks, callback
delivery, and sibling-owner behavior over asserting only fields introduced by
the patch. Cross-apply a competing fix's tests when alternatives exist; shared
blind spots become visible when one implementation's adversarial cases run
against the other.

For apartment or process teardown, verify a clean process exit in addition to a
test-framework pass. A test can report success before final COM cleanup crashes
or strands a native owner.
