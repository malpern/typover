# Public beta claims

- Status: Approved wording; exact candidate audit pending permissioned Bear row
- Updated: 2026-08-04

## Compatibility

- Typover requires macOS 27.0.
- The controlled Typover editor is the reference experience and corrects local
  spelling inside its own AppKit edit transaction while typing continues.
- Bear integration is limited to Bear 2.8.1 and 2.9.1 on macOS 27.0. Unknown
  Bear or macOS versions fail closed without editing.
- The first Bear beta corrects verified eligible words after a short safe pause
  in typing. Immediate pre-dispatch Bear correction is research-only and is not
  a public beta feature.
- Support for another app, another Bear release, or native AppKit text editing
  in general must be measured separately; Typover does not claim system-wide
  compatibility.

## Privacy

- Apple Spelling and Apple Intelligence run on device. Remembered choices and
  aggregate correction statistics stay on the Mac.
- OpenAI or Anthropic is used only after the user explicitly selects that
  provider. Only the newly completed sentence is sent for contextual checking;
  there is no silent cloud fallback.
- Normal Bear operation reads bounded text near the active caret, mutates only
  an exact verified range, and does not save note text.
- The optional Bear diagnostic trace is off by default, content-free by
  default, local-only, and bounded to 24 hours or 1 MB. A separate explicit
  switch can include bounded writing context for a diagnostic session; Typover
  warns before that content is retained and provides export and delete controls.
- Typover contains no telemetry uploader, launch daemon, privileged helper,
  login item, or automatic updater in the first beta.

## Support

Public beta support uses the repository's GitHub Issues tracker. Reports should
include Typover version, build, source revision from About, macOS and Bear
versions, exact reproduction steps using disposable text, and the content-free
diagnostic export when available. Writers should not paste private note content
into an issue.

Security or privacy reports that require non-public disclosure must not be
filed with ordinary reproduction text in a public issue. Testers should use
GitHub's private **Report a vulnerability** form described in `SECURITY.md`.

## Candidate audit

Candidate `0.1.0 (20260804072103)` matches the claims that can be verified
without granting system permissions:

- the bundle requires macOS 27.0 and identifies clean source `e38f535`;
- Apple Spelling and Apple Intelligence are the defaults shown in Settings;
- the OpenAI and Anthropic choices remain explicit;
- the app contains no launch agent, daemon, privileged helper, XPC service,
  login item, telemetry uploader, or updater;
- its notarized update and rollback preserve local preferences and learning;
  and
- the lower-latency Bear event-tap lane is not exposed as the default product
  path.

The Bear compatibility, post-pause behavior, permission-state recovery, and
bounded diagnostic claims need one final run with the exact candidate after
the notarized app receives Input Monitoring approval. Until that row passes,
the wording is approved but the artifact is not beta-ready.

## Known limitations

- Bear correction depends on macOS Accessibility and Input Monitoring and may
  safely skip a correction when focus, selection, geometry, or timing is
  ambiguous.
- Light-gray Bear squiggles are non-native overlay controls. They disappear
  when Bear is backgrounded or the anchor becomes stale and reappear only after
  the exact bounded range can be verified.
- The controlled editor can correct punctuation and contextual grammar. The
  first Bear beta is limited to word-level Apple Spelling.
- The beta is manually installed, launched, updated, rolled back, and removed.
