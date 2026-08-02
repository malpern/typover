# Typover could remain running without a reopenable window

- Status: Fixed, covered, deployed, and installed-app verified
- Observed: 2026-08-01
- Surface: macOS application lifecycle

## Symptom

Closing Typover's last window left the process running, which is normal macOS
behavior. Activating Typover again from Applications did not restore the main
window. Force quitting and launching a fresh process did show the window, so
the failure was specific to application reopen rather than scene construction.

## Cause

The SwiftUI `Window` scene had a stable `main` identifier and presented-launch
behavior, but no AppKit application-reopen handler. Presented launch behavior
controls a process launch; it does not handle Finder or Dock reactivation of an
already-running app with no visible windows. macOS 27 does not introduce a
newer SwiftUI scene API for this case.

## Fix

`TypoverApp` now uses `NSApplicationDelegateAdaptor`. When AppKit reports an
application reopen with no visible windows, the delegate finds the SwiftUI
window whose identifier is `main` and orders only that window front. It does
not guess between About, Settings, or another scene.

The delegate's window-presenting boundary is a small protocol so tests can
verify selection and presentation without constructing AppKit windows inside
the command-line test host.

## Verification

Two focused tests verify that the hidden main scene is presented and that an
unrelated window is never substituted. In the installed Apple
Development-signed app, the exact close-then-reactivate sequence restored the
same main window while Typover remained one running process. The complete gate
passes 287 tests in 29 suites.
