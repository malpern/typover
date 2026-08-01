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
and does not contact Apple.

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
release.

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
