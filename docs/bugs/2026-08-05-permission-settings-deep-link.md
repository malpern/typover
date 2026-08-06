# Permission setup opened the wrong System Settings pane

- Status: Fixed; both destinations and the allowed-state fallback are verified
  with the replacement notarized candidate; clean permission cycle pending
- Found: 2026-08-05

## Symptom

On a clean macOS 27 account, Typover's **Open Privacy & Security…** button
launched System Settings but left the tester on General. The first-run copy was
clear and permission setup could be deferred, but the button did not guide a
new tester to either required permission.

## Cause

`TypoverPermissionModel.openSystemSettings()` opened the System Settings
application bundle without a destination URL. System Settings therefore used
its default or previous pane rather than Typover's intended privacy flow.

## Fix

Permission setup now opens the next missing pane in order:

1. Accessibility;
2. Input Monitoring; then
3. the Privacy & Security root when both permissions are already allowed.

The pane URLs use the legacy privacy anchors that macOS 27's
`SecurityPrivacyExtension` still declares (`Privacy_Accessibility` and
`Privacy_ListenEvent`). The root fallback uses that extension's current bundle
identifier. If macOS cannot open a destination URL, Typover still falls back to
launching System Settings rather than failing silently.

## Verification

Unit coverage fixes the ordering, button labels, and exact pane URLs. Installed
candidate `0.1.0 (20260806051920)` reports both grants allowed and its button
opens the visible Privacy & Security root. The exact Accessibility and Input
Monitoring URLs both open their intended macOS 27 lists, where Typover is
visibly enabled. The clean Mac test must still exercise the candidate's dynamic
next-missing ordering from denied through allowed and revoked states before the
full permission journey is accepted.
