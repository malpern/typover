# Clean-machine permission cycle

- Date: 2026-08-08
- Candidate: `0.1.0 (20260806051920)`, source revision
  `329e92bdc21a2dd7651e2b252c014f228e439576`
- Guest: disposable macOS 27.0 VM, lab lease `cbx_564749a6799c`
- Evidence: `/Volumes/KeyPath Lab/CrabBox/KeyPathInstallerLab/artifacts/cbx_564749a6799c/20260808T220801Z`

The denied-to-allowed-to-revoked journey the beta gate has been waiting on, run
on a machine that had never seen Typover. The installed bundle was verified as
the exact qualified candidate before anything else: `CFBundleVersion`
`20260806051920`, identifier `com.malpern.typover`, team `X2RKZ5TG99`.

## Observed

| step | Typover's reported state | setup button |
| --- | --- | --- |
| first launch, nothing granted | Accessibility **Not yet allowed**, Input Monitoring **Not yet allowed** | **Set Up Accessibility…** |
| after granting Accessibility | Accessibility **Allowed**, Input Monitoring **Allowed** | **Open Privacy & Security…** |
| after revoking Accessibility | Accessibility **Not yet allowed**, Input Monitoring **Not yet allowed** | **Set Up Accessibility…** |

The setup button opened **System Settings → Accessibility** directly, confirming
the deep-link fix on a clean account rather than on a machine where System
Settings already had a remembered pane. Granting required authenticating a
password sheet whose confirm button is **Modify Settings**; revoking the same
toggle required no authentication.

The states were read after relaunching Typover each time. The onboarding
snapshot is computed when the view is built, so a grant made while the app is
running is not reflected until it refreshes — worth knowing when reproducing
this, and a plausible source of a "it didn't work" misreading.

## What this does not cover

**The middle ordering state was never reachable.** Typover shows two
permissions, but they did not move independently: granting Accessibility alone
flipped Input Monitoring to Allowed, and revoking Accessibility flipped it back.
The button therefore went straight from *Set Up Accessibility…* to *Open Privacy
& Security…*; **Set Up Input Monitoring…** was never displayed and remains
unverified against a running build.

The cause is visible in the system UI: with Accessibility granted, the
**Input Monitoring pane was completely empty — no Typover row, and no rows at
all**. `CGPreflightListenEventAccess()` nonetheless returned true, which is what
the onboarding view reports. So on this path the second permission is satisfied
without Typover ever appearing in the list that governs it, and there is nothing
there to revoke independently.

This run did not exercise Bear, so a likely explanation is that Typover only
requests `ListenEvent` when it installs its event tap, and the preflight call
reports the access that Accessibility trust already implies. That is a
hypothesis, not an observation — it needs a run that actually starts a Bear
session before the two-permission model can be claimed to behave as the
onboarding UI describes.

## Consequence for the gate

The denied → allowed → revoked cycle itself passed on a clean authenticated
session, which is what the release gate asked for. The gate's stronger wording —
the candidate's *dynamic next-missing ordering* — is two-thirds demonstrated:
two of the three button states were observed, and the third could not be
produced by any sequence available here.
