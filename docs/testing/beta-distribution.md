# Beta distribution

- Status: Developer ID build and clean-bundle onboarding check pass;
  clean-machine permission gate pending
- Updated: 2026-08-01

Typover's beta artifact is a release-built `.app` signed with the Developer ID
Application identity. Notarization uses the existing App Store Connect API key;
the script does not read or place a password in argv.

## Local signed artifact

```bash
Scripts/build-beta-app.sh 0.1
```

This produces `.build/beta/Typover-0.1.zip`, verifies the strict code signature,
strips local extended attributes, excludes AppleDouble metadata from the zip,
and does not contact Apple. Versions must contain two or three numeric
components; build numbers must contain 1-18 digits. Invalid values are rejected
before a build or output-path mutation occurs.

The local, read-only package verifier checks the expected bundle identity,
version fields, executable, strict signature, system-only dynamic dependencies,
and archive metadata. It also expands the zip into a temporary directory,
rejects unsafe or unexpected archive paths, proves its bundle is byte-for-byte
identical to the signed build output, and verifies the extracted signature. The
build script runs this verifier automatically, so a zip that does not contain
the exact reviewed app cannot be reported as a successful beta build. The
verifier also rejects embedded launch agents, daemons, privileged helpers, XPC
services, login items, and background-only bundle declarations, matching the
initial beta's manually launched architecture:

```bash
Scripts/verify-beta-app.sh
```

The rejection suite proves the verifier fails closed when an archive contains
an extra top-level path, a bundle whose bytes differ from the signed build, or
unsafe version/build inputs:

```bash
Scripts/test-beta-verifier.sh
```

The 2026-08-01 local beta artifact was signed successfully with the configured
Developer ID identity. A fresh temporary bundle identifier simulated a clean
preferences domain: the onboarding sheet appeared, both permissions showed
`Not yet allowed`, and Continue opened the controlled editor. This verifies the
first-launch presentation without changing the installed app's existing TCC
grants. It is not a substitute for the clean-machine permission and Gatekeeper
gate below.

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

The build is not beta-ready until a clean macOS 27 machine verifies:

1. Gatekeeper opens the downloaded and expanded app without bypasses.
2. First run clearly explains Accessibility and Input Monitoring.
3. The tester can defer permission setup and use the controlled editor.
4. After granting permissions, Bear status becomes observing without developer
   tools or manual defaults changes.
5. Revoking either permission produces an understandable unavailable state.
6. Typover and Bear relaunch recover from a fresh baseline.
7. Removing the app leaves no helper, daemon, login item, or uploaded trace.

The initial beta is manually launched per ADR-015. Update and rollback behavior
remain part of the parallel release-operations track.
