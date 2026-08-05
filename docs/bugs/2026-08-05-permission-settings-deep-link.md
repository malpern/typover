# Permission setup opened the wrong System Settings pane

- Status: Fixed in source; Accessibility link verified in a development build;
  clean candidate verification pending
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

Unit coverage fixes the ordering, button labels, and exact pane URLs. A signed
development build opened the visible macOS 27 Accessibility list directly.
The clean Mac test must still verify both links in the replacement notarized
candidate before this bug and the permission journey are accepted.
