# Beta distribution

- Status: Notarized 0.1.0 candidate and second-Mac lifecycle pass; permission UI pending
- Updated: 2026-08-04

Typover's beta artifact is a release-built `.app` signed with the Developer ID
Application identity. Notarization uses the existing App Store Connect API key;
the script does not read or place a password in argv.

## Local signed artifact

```bash
Scripts/build-beta-app.sh 0.1
```

This produces `.build/beta/Typover-0.1.zip` and a matching
`.build/beta/Typover-0.1.json` receipt, verifies the strict code signature,
expected Developer ID team, hardened runtime, and secure signing timestamp,
strips local extended attributes, excludes AppleDouble metadata from the zip,
and does not contact Apple. Versions must contain two or three numeric
components; build numbers must contain 1-18 digits. Invalid values are rejected
before a build or output-path mutation occurs. Every bundle records its exact
40-character Git revision and whether the local tree contained changes. Local
signed artifacts may be dirty for development testing; notarized candidates
fail before submission unless the worktree is clean.

The machine-readable receipt records its schema version, bundle identifier,
version, build, source revision and cleanliness, minimum macOS version, signing
team, archive filename and SHA-256, and notarization claim. Its verifier derives
the same values independently from the signed app and archive. A receipt that
names different app metadata or archive bytes fails closed; a receipt claiming
notarization additionally requires Gatekeeper and stapled-ticket validation.
The beta build runs both the positive verifier and the adversarial receipt suite
before returning an artifact path.

The local, read-only package verifier checks the expected bundle identity,
version fields, executable, strict signature, system-only dynamic dependencies,
source revision and cleanliness marker, and archive metadata. It also expands
the zip into a temporary directory, rejects unsafe or unexpected archive paths,
proves its bundle is byte-for-byte identical to the signed build output, and
verifies the extracted signature. The
build script runs this verifier automatically, so a zip that does not contain
the exact reviewed app cannot be reported as a successful beta build. The
verifier also rejects embedded launch agents, daemons, privileged helpers, XPC
services, login items, and background-only bundle declarations, matching the
initial beta's manually launched architecture.

The signed bundle carries explicit purpose descriptions for Accessibility and
Input Monitoring. Accessibility is used to read and update exact ranges in a
supported editor and place reversible controls. Input Monitoring is used to
detect word-completion keystrokes and safely time corrections, not to record
the user's writing. The verifier rejects an artifact missing either purpose
description.

The bundle declares macOS 27.0 as its minimum system version. Verification
also reads the executable's `LC_BUILD_VERSION` command and requires its `minos`
value to match, preventing the Finder-facing compatibility declaration from
drifting away from the compiled deployment target.

```bash
Scripts/verify-beta-app.sh
```

The rejection suite proves the verifier fails closed when an archive contains
an extra top-level path, a bundle whose bytes differ from the signed build, or
unsafe version/build inputs:

```bash
Scripts/test-beta-verifier.sh
Scripts/test-beta-receipt.sh
```

The 2026-08-01 local beta artifact was signed successfully with the configured
Developer ID identity. A fresh temporary bundle identifier simulated a clean
preferences domain: the onboarding sheet appeared, both permissions showed
`Not yet allowed`, and Continue opened the controlled editor. This verifies the
first-launch presentation without changing the installed app's existing TCC
grants. It is not a substitute for the clean-machine permission and Gatekeeper
gate below.

On 2026-08-02, a clean-revision build from
`635f03421ebce3c0081c539fcbc0264cf4bb38aa` recorded that exact revision with
`dirty=false`. The build-integrated positive verifier and adversarial extra-
path, mismatched-bundle, background-component, permission-purpose, ad hoc
signature, missing-hardened-runtime, version, and build-number rejection tests
all passed. This proves local artifact provenance and archive integrity; it
does not prove notarization or clean-machine behavior.

On 2026-08-04, candidate `0.1.0 (20260804072103)` was built from clean revision
`e38f535ee2715ff52a8247a9e19e7b882996e13e`. Apple accepted notarization
submission `327962e7-f006-4a0e-b4b4-5f81715f256a`; stapling, Gatekeeper,
archive/receipt verification, and the adversarial receipt suite passed. The
archive SHA-256 is
`495473c1ef297d6446cdcbf2a64d3c16c01974149ab9f6ac685f763b4c7aabda`.

The build now runs the sentence-boundary admission regression in optimized
configuration before signing. This gate was added after installed acceptance
found a real release-only failure that debug tests did not reproduce.

## Notarized candidate

```bash
Scripts/build-beta-app.sh 0.1 --notarize
```

This submits the zip to Apple's notary service, waits for the result, staples
the accepted ticket to the app, recreates the zip with the stapled bundle, and
runs Gatekeeper assessment. It does not publish the artifact or create a public
release. Afterward, `Scripts/verify-beta-app.sh` accepts the app and archive
paths followed by `--gatekeeper` to repeat Gatekeeper and stapled-ticket
validation against the extracted distribution copy rather than only the local
build directory.

## Clean-machine gate

The second macOS 27 Mac has verified the artifact checksum, Developer ID
signature, stapled ticket, Gatekeeper acceptance, clean `/Applications`
installation, and fresh process launch. It also completed a notarized
0.0.9-to-0.1.0 update, a rollback to 0.0.9, and a final restore to 0.1.0 with
one process and preserved preferences/learning checksum at every step.

The build is not beta-ready until the remaining visible permission rows verify:

1. First run clearly explains Accessibility and Input Monitoring on the clean
   unlocked session.
2. The tester can defer permission setup and use the controlled editor.
3. After granting permissions, Bear status becomes observing without developer
   tools or manual defaults changes.
4. Revoking either permission produces an understandable unavailable state.
5. Typover and Bear relaunch recover from a fresh baseline.
6. Removing the app leaves no helper, daemon, login item, or uploaded trace.

The final candidate completed an 11-minute second-Mac soak at 0% CPU with flat
RSS near 160 MiB. Recoverable app-only removal left the preferences and learning
file intact; explicit full-data removal then left no app, process, Typover
preferences domain, Application Support directory, or Typover launch item. The
test did not modify macOS-owned TCC records.

The initial beta is manually launched per ADR-015. Update and rollback behavior
remain part of the parallel release-operations track.
