# SwiftUI main-window restoration identity

- Status: Fixed for new installs; existing development preference residue can
  require one manual window open
- Found: 2026-08-01
- Affected surface: Typover app launch and first-run onboarding

## Symptom

After onboarding was added around the root view, an existing development
install could launch with no visible main window. A clean temporary bundle
identifier opened onboarding normally, proving that construction and launch
were healthy.

## Cause

The original scene used SwiftUI's synthesized restoration identity. That
identity included the root view's generic type, so changing the root hierarchy
changed the identifier while AppKit still retained restoration data for the old
identifier. The process launched, but the stale restored window was not
recreated.

## Fix

The editor now uses a singleton `Window` scene with the explicit stable ID
`main` and a presented default launch behavior. Future root-view refactors no
longer alter the restoration identity, and a fresh bundle continues to present
onboarding on launch.

The stale preference domain belongs only to local development builds that ran
before this fix. It is not evidence of a first-install beta failure. The current
singleton scene still needs one unlocked installed visual check before the
main-window row is closed.
