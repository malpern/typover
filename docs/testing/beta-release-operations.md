# Beta release operations

- Status: Signed lifecycle matrix and uninstall passed; permissioned UI pending
- Updated: 2026-08-04

This document defines how the manually launched Typover beta is identified,
updated, rolled back, removed, and supported. It does not authorize publishing
an artifact. Notarization, external upload, and public distribution remain
separate explicit actions.

## Version and provenance

- `CFBundleShortVersionString` uses two or three numeric components, beginning
  with `0` during beta development, such as `0.1` or `0.1.1`.
- `CFBundleVersion` defaults to a 14-digit UTC build timestamp with seconds.
  A release operator may provide another 1-18 digit monotonic value through
  `TYPOVER_BUILD_NUMBER`.
- The bundle records the exact 40-character Git revision and a source-dirty
  marker. A local Developer ID build may record `dirty=true` for development
  testing. A notarized candidate must record `dirty=false`; the build script
  refuses a dirty worktree before compiling or contacting Apple.
- The About window shows the marketing version, build number, and a short
  source revision. Development builds with uncommitted changes are explicitly
  labeled **Modified**. The full revision and dirty marker remain available in
  the bundle metadata for exact support correlation.
- Release notes identify the marketing version, build number, revision,
  supported macOS and Bear versions, known limitations, privacy changes, data
  migrations, and rollback compatibility.
- Keep the generated JSON receipt beside every accepted zip. Its checksum and
  independently verified bundle metadata identify the exact artifact used for
  installation, update, or rollback; a filename alone is not release evidence.

## Initial beta update policy

The initial beta has no automatic updater and no launch-at-login item. An
update is an explicit replacement:

1. Export any diagnostic trace needed for an open investigation, then quit
   Typover.
2. Verify the new notarized zip, expanded app, and matching JSON receipt.
3. Keep the previous notarized zip until the new build passes its installed
   smoke test.
4. Replace `Typover.app` in `/Applications`; do not run two copies.
5. Launch the new app and confirm the version, build, and source revision shown
   in **About Typover** match the accepted artifact.
6. Confirm its permission state, Bear status, and one controlled-editor
   correction before enabling Bear automation.

The stable bundle identifier and Developer ID requirement preserve the app's
identity across replacement. The second-machine update/rollback matrix proved
that application preferences and the learning file survive. Permission
retention still needs a permissioned UI pass; the lifecycle result alone does
not make that stronger promise.

## Rollback policy

Rollback uses the same explicit replacement procedure with the last accepted
notarized artifact. Before any persisted-data schema change ships, tests must
prove that the previous supported build can read or safely ignore the newer
learning and settings data. If it cannot, release notes must require an in-app
learning reset before rollback; silently discarding user choices is not
acceptable.

A rollback pass records:

- the two versions, build numbers, and source revisions;
- whether Accessibility and Input Monitoring remained granted;
- whether Bear returned to observing from a fresh baseline;
- whether learning preferences and statistics remained readable; and
- whether any background process from the replaced build survived.

## Uninstall policy

Typover is manually launched and the verified beta bundle is forbidden from
containing launch agents, daemons, XPC services, privileged helpers, login
items, or background-only declarations. Ordinary removal is therefore:

1. Turn off Bear automation and quit Typover.
2. Move `/Applications/Typover.app` to Trash.
3. Confirm no Typover process or correction overlay remains.

Preferences and local learning are user data, not hidden services. A tester who
wants a clean data removal should first use **Delete local Bear trace** and
**Reset all Typover learning**, then remove the app. A forensic clean-machine
pass may additionally remove the `com.malpern.typover` preferences domain and
`~/Library/Application Support/Typover` after recording what existed. macOS
owns TCC permission records; Typover must not edit the TCC database.

## Required lifecycle matrix

| Row | Current evidence | Required result |
|---|---|---|
| Fresh install | **Passed on second Mac**: checksum, signature, stapling, Gatekeeper, `/Applications` install, and one fresh GUI process | Complete the visible first-run permission flow on an unlocked session |
| In-place update | **Passed**: notarized 0.0.9 to 0.1.0 left one process and preserved model, scope, rewrite, Bear enablement, and learning checksum | Confirm TCC grants and Bear observation survive on the permissioned Mac |
| Rollback | **Passed**: 0.1.0 to notarized 0.0.9 and back to 0.1.0 preserved the same state | Confirm no stale Bear observer in the permissioned UI pass |
| App-only removal | **Passed on second Mac** after an 11-minute final-candidate soak: app and process were absent while preferences and learning remained intact | No process, overlay, helper, daemon, XPC service, or login item remains |
| Full local-data removal | **Passed on second Mac** using a recoverable state folder: the preferences domain, Application Support directory, app, process, and Typover launch-item footprint were absent | Documented files/defaults are absent after explicit user-directed cleanup |

## Release notes and support

Use [`docs/releases/README.md`](../releases/README.md) for every distributed
candidate. Public beta support uses the repository's GitHub Issues tracker and
the report contract in
[`docs/public-beta-claims.md`](../public-beta-claims.md). The repository must be
public before inviting ordinary testers; a private repository does not make
Issues available to them.

## Public-distribution blockers

- Make the MIT-licensed repository public before inviting testers.
- Candidate `0.1.0 (20260804072103)` from clean revision `e38f535` is accepted,
  stapled, Gatekeeper-approved, and receipt-verified.
- Finish local and second-machine permission UI, revocation, and Bear
  reattachment rows above. The second-machine soak and uninstall rows pass.
- Review the public privacy and compatibility statements against the shipped
  build.
