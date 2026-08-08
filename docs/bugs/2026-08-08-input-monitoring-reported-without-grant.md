# Input Monitoring reports Allowed without its own grant

- Status: Open; observed on a clean macOS 27 guest, cause not yet confirmed
- Date: 2026-08-08

## Symptom

On a disposable macOS 27 VM that had never seen Typover, granting **only**
Accessibility flipped the onboarding view's Input Monitoring row from
**Not yet allowed** to **Allowed**. Revoking Accessibility flipped it back.
The two permissions never moved independently.

While Typover reported Input Monitoring as allowed, the System Settings
**Input Monitoring pane was entirely empty** — no Typover row, and no rows at
all. The Accessibility pane meanwhile listed Typover alongside Peekaboo,
`prltoolsd` and `sshd-keygen-wrapper`.

So the permission Typover reports as granted has no entry in the list that
governs it, and nothing there to revoke.

Observed with candidate `0.1.0 (20260806051920)`, source revision
`329e92bdc21a2dd7651e2b252c014f228e439576`. Full run in
[the clean permission cycle record](../testing/clean-permission-cycle-2026-08-08.md).

## Why it matters

Two claims in the beta material depend on these being distinct permissions.

The onboarding UI presents Accessibility and Input Monitoring as separate
grants with separate explanations, and `TypoverPermissionModel` derives its
setup button from whichever is *next missing*: Accessibility, then Input
Monitoring, then the Privacy & Security root. On a clean machine the middle
state is unreachable — the button goes straight from **Set Up Accessibility…**
to **Open Privacy & Security…**, and **Set Up Input Monitoring…** never
appears. That ordering branch has unit coverage but has never been observed
against a running build.

The privacy copy also describes Input Monitoring as a deliberate, separately
granted capability. If it is in practice implied by Accessibility, the
description overstates how much a user is choosing.

## Likely cause, not yet confirmed

`TypoverOnboardingView` reads the state with:

- `AXIsProcessTrusted()` for Accessibility
- `CGPreflightListenEventAccess()` for Input Monitoring

The most plausible explanation is that `CGPreflightListenEventAccess()` reports
the access an Accessibility-trusted process already has, and that Typover does
not appear in the Input Monitoring list because it has never *requested*
`ListenEvent` — that request would come when it installs its event tap, which
this run never reached because it never started a Bear session.

This is a hypothesis. The run that would settle it drives an actual Bear
correction on a clean guest with Accessibility granted, and then re-reads both
the pane and the reported state.

## Open questions

1. Does Typover appear in the Input Monitoring pane once a Bear session has
   installed the event tap?
2. If Input Monitoring is genuinely implied by Accessibility for this app, is
   showing it as a second grantable permission accurate?
3. Can the **Set Up Input Monitoring…** state be reached on a real machine at
   all? If not, its ordering logic is unreachable code and the claim it
   supports should be re-worded rather than kept.
