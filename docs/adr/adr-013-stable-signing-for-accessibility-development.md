# ADR-013: Use stable signing for Accessibility development builds

- Status: Accepted
- Date: 2026-07-26

## Context

Typover's Bear prototype requires macOS Accessibility permission. The initial
development bundle was signed ad hoc after every build. An ad-hoc app's
designated requirement is its current code hash, so replacing the executable
also changes the identity macOS associates with the permission. A previously
approved Typover build can therefore lose access after an otherwise ordinary
rebuild.

The Bear preview also treated every failed probe as a missing three-character
selection. When permission had expired, it brought Bear forward, performed no
write, and gave the writer no useful explanation.

## Decision

Package Bear-development builds with the installed Apple Development identity
through `Scripts/build-development-app.sh`. The resulting designated
requirement is based on Typover's bundle identifier and signing certificate,
not a changing code hash. The packager starts from a fresh bundle, records the
exact Git revision and worktree cleanliness in its Info.plist, and verifies the
metadata and strict code signature before reporting success.

Before bringing Bear forward, the preview checks Accessibility trust. If it is
missing, Typover requests the standard macOS permission prompt and remains in
Typover. Probe and replacement failures map to distinct visible states for
permission, Bear availability, editor focus, selection mismatch, and rejected
writes.

## Consequences

- Accessibility approval can survive normal development rebuilds at the same
  app path.
- The first stable-signed build requires one fresh approval because it has a
  different identity from the earlier ad-hoc build.
- Developers must not replace the packaged executable and re-sign it ad hoc.
- Installed development builds can be traced to an exact source state through
  the About window and verified bundle metadata.
- Failed Bear previews now explain why nothing changed and never imply that a
  write occurred.
