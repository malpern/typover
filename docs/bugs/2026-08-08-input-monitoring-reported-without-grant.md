# Input Monitoring is not a separately grantable permission

- Status: Settled 2026-08-08. Not a defect in the permission code; the
  onboarding and privacy copy that present Input Monitoring as a second
  independent choice are inaccurate, and one ordering branch is unreachable.
- Date: 2026-08-08

## What was observed

On a disposable macOS 27 guest that had never seen Typover, granting **only**
Accessibility flipped the onboarding view's Input Monitoring row from
**Not yet allowed** to **Allowed**. Revoking Accessibility flipped it back. The
two never moved independently.

While Typover reported Input Monitoring as allowed, the System Settings
**Input Monitoring pane was entirely empty** — no Typover row, and no rows at
all. The Accessibility pane meanwhile listed Typover alongside Peekaboo,
`prltoolsd` and `sshd-keygen-wrapper`.

Observed with candidate `0.1.0 (20260806051920)`, source revision
`329e92bdc21a2dd7651e2b252c014f228e439576`. Full run in
[the clean permission cycle record](../testing/clean-permission-cycle-2026-08-08.md).

## Why

**Accessibility is a superset of Input Monitoring.** An app holding
Accessibility already has the capability Input Monitoring governs, so macOS
never raises the Input Monitoring request and never adds the app to that pane.
Which permission a `CGEventTap` demands depends on its options — `listenOnly`
asks for Input Monitoring, `defaultTap` asks for Accessibility — but the
Input Monitoring request is bypassed entirely when Accessibility is already
granted. The relationship is one-way: Input Monitoring alone does not confer
Accessibility, and an app granted only Input Monitoring still sees
`AXIsProcessTrusted()` return false.

Typover requires Accessibility for its exact-range Bear writes, so it is always
on the side of that relationship where Input Monitoring is implied.
`CGPreflightListenEventAccess()` therefore returns true for a permission the
user was never asked for and cannot see.

This is expected macOS behaviour rather than a fault in Typover's permission
code. The conclusion rests on the live observation above plus the documented
community account of the API relationship; it is not stated in Apple's own
reference for `CGPreflightListenEventAccess()`, which does not mention
Accessibility at all.

## Consequences

**The `.inputMonitoring` ordering branch is unreachable.**
`nextSystemSettingsDestination` returns it only when
`accessibilityAllowed == true && inputMonitoringAllowed == false`, and the
superset relationship makes that combination impossible: whenever the first is
true the second is too. **Set Up Input Monitoring…** can never be displayed.

Granting Input Monitoring first does not reach it either — that yields
`accessibilityAllowed == false`, which returns `.accessibility`, correctly.

**The unit test that covers it proves nothing about the running app.**
`Permission setup opens the next missing macOS pane` builds
`TypoverPermissionSnapshot(accessibilityAllowed: true, inputMonitoringAllowed: false)`
by hand, bypassing the preflight calls, so it passes against a state the system
cannot produce. That test is why the ordering looked verified when only two of
its three states had ever existed.

**Two user-facing claims overstate the user's choice.** The onboarding view
presents Accessibility and Input Monitoring as separate grants with separate
explanations and separate allowed/denied rows. The privacy copy describes Input
Monitoring as a capability the user deliberately grants. In practice a user who
grants Accessibility has granted both, without being shown that.

## Recommended changes

These are product decisions, not fixes to make silently:

1. Present Input Monitoring as **implied by Accessibility** rather than as a
   second grantable row — or drop the row and explain the combined capability
   once, accurately.
2. Reword the privacy claim so it does not imply a separate, deliberate Input
   Monitoring choice.
3. Either delete the `.inputMonitoring` destination and its title as dead code,
   or keep it only as defence against a future macOS that separates the two —
   and if kept, say so at the test, which currently reads as coverage of a live
   path.

Keeping the runtime `.inputMonitoringUnavailable` safety check is still
reasonable: it costs nothing and fails closed if the relationship ever changes.
