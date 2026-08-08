# Input Monitoring is not a separately grantable permission

- Status: Settled 2026-08-08 by controlled experiment, not inference. Not a
  defect in the permission code. The onboarding presents Input Monitoring as a
  second independent choice, which it is not, and one ordering branch is
  unreachable.
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

## Why: there is no Input Monitoring grant to hold

Tested directly on a second clean macOS 27 guest, because the first run only
established a correlation and the published accounts of this API relationship
disagree with each other.

With Accessibility granted and both rows reading **Allowed**:

| action | Accessibility | Input Monitoring |
| --- | --- | --- |
| grant Accessibility only | Allowed | Allowed |
| `tccutil reset ListenEvent com.malpern.typover` | Allowed | **Allowed** — unchanged |
| `tccutil reset Accessibility com.malpern.typover` | Not yet allowed | **Not yet allowed** — both clear |

Resetting Input Monitoring changes nothing; resetting Accessibility clears both.
The second row is the control, and it matters: `tccutil` prints
`Successfully reset …` either way, so without it the first row would only show
that the command ran, not that it did anything. Because the control does move
state with the same tool against the same bundle, the no-op on `ListenEvent` is
a real result: **there is no Input Monitoring approval stored for Typover to
reset.** `CGPreflightListenEventAccess()` is reporting access implied by
Accessibility trust.

Had an independent grant existed, resetting it would have produced exactly the
combination this defect is about — Accessibility allowed, Input Monitoring
denied. It did not.

Typover requires Accessibility for its exact-range Bear writes, so it is always
in the state where Input Monitoring comes along with it, for a permission the
user was never asked for and cannot see.

### What this evidence does and does not establish

It establishes the behaviour for **this app, on macOS 27, in a VM guest**:
`CGPreflightListenEventAccess()` tracks `AXIsProcessTrusted()`, and no separate
approval exists.

It does not establish a documented platform contract. Apple's reference for
`CGPreflightListenEventAccess()` does not mention Accessibility at all. A 2021
developer-forum account describes Accessibility as subsuming the Input
Monitoring request — consistent with what is measured here — but community
sources also state flatly that the two are independent, so the corroboration is
weak and the experiment is what the conclusion rests on. Two caveats worth
keeping: the runs were in a virtual machine, and nothing here was tested on
another macOS version.

## Consequences

**The `.inputMonitoring` ordering branch is unreachable.**
`nextSystemSettingsDestination` returns it only when
`accessibilityAllowed == true && inputMonitoringAllowed == false`. Every
attempt to produce that combination failed, including deliberately resetting
the Input Monitoring approval while Accessibility stayed granted.
**Set Up Input Monitoring…** was never displayed.

Granting Input Monitoring first does not reach it either — that yields
`accessibilityAllowed == false`, which returns `.accessibility`, correctly.

**The unit test that covers it proves nothing about the running app.**
`Permission setup opens the next missing macOS pane` builds
`TypoverPermissionSnapshot(accessibilityAllowed: true, inputMonitoringAllowed: false)`
by hand, bypassing the preflight calls, so it passes against a state the system
cannot produce. That test is why the ordering looked verified when only two of
its three states had ever existed.

**The onboarding overstates the user's choice.** It presents Accessibility and
Input Monitoring as separate grants, with separate explanations and separate
allowed/denied rows. In practice a user who grants Accessibility has granted
both without being shown that, and the second row can never be acted on.

`public-beta-claims.md` does *not* contain a "separately granted" claim — that
framing lives only in the app. What it did contain was a candidate-audit line
stating the installed app "visibly has Accessibility and Input Monitoring
allowed", which is not true of Input Monitoring: it is visible nowhere. That
line has been narrowed.

## Recommended changes

These are product decisions, not fixes to make silently:

1. Present Input Monitoring as **implied by Accessibility** rather than as a
   second grantable row — or drop the row and explain the combined capability
   once, accurately.
2. Reword the onboarding explanation so it does not imply a separate,
   deliberate Input Monitoring choice.
3. Either delete the `.inputMonitoring` destination and its title as dead code,
   or keep it only as defence against a future macOS that separates the two —
   and if kept, say so at the test, which currently reads as coverage of a live
   path.

Keeping the runtime `.inputMonitoringUnavailable` safety check is still
reasonable: it costs nothing and fails closed if the relationship ever changes.
