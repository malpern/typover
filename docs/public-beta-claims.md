# Public beta claims

- Status: Audited against candidate `0.1.0 (20260808224257)` on 2026-08-08; the
  claims below match the artifact. Input Monitoring is settled as included with
  Accessibility rather than separately granted, and this candidate says so. The
  binary stays held pending the quiet correction-review interaction pass. See
  [Input Monitoring is not a separately grantable permission](bugs/2026-08-08-input-monitoring-reported-without-grant.md)
- Updated: 2026-08-08

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

Candidate `0.1.0 (20260808224257)`, audited 2026-08-08. The runtime half was
run on a disposable macOS 27 guest that had never seen Typover, rather than on
the permissioned development Mac, so nothing here depends on state a previous
install left behind.

### Verified against this artifact

**Provenance and compatibility.** The bundle declares
`LSMinimumSystemVersion 27.0`, `CFBundleVersion 20260808224257`, and clean
source `a81645b947a814055da79e06f92cf9b6e3e7e420` with `TypoverSourceDirty 0`.
It is signed by team `X2RKZ5TG99` under the hardened runtime, notarized,
stapled, and Gatekeeper-accepted, and the archive checksum matches its receipt.
Both supported Bear versions, `2.8.1` and `2.9.1`, are present in the binary.

**No background persistence.** The bundle contains only `_CodeSignature`,
`MacOS`, and `Resources` — no launch agent, daemon, privileged helper, XPC
service, or embedded login item — and it carries no entitlements at all. The
binary references none of `SMLoginItemSetEnabled`, `SMAppService`,
`NSBackgroundActivity`, `Sparkle`, or `SUUpdater`. Confirmed at run time on the
clean guest: after launching, `~/Library/LaunchAgents`, `/Library/LaunchAgents`,
`/Library/LaunchDaemons`, and `/Library/PrivilegedHelperTools` contain nothing
matching Typover, and `sfltool dumpbtm` — macOS's own background-item registry —
lists none. The only state created is the `com.malpern.typover` preferences
domain.

**No telemetry.** The only network hosts in the binary are
`https://api.openai.com`, `https://api.anthropic.com`, and `https://github.com`
— the two explicitly selected providers and the support link. There is no
analytics or crash-reporting endpoint.

**Model choice is explicit.** In Settings → Model on the clean guest, the
writing-model control (`typover.settings.contextual-model`) reads
**Apple Intelligence (On Device)**. *GPT-5.6 Terra (OpenAI)* and
*Claude Sonnet 5 (Anthropic)* are unselected menu options.

**Diagnostics are off and content-free by default.** Settings → Privacy shows
*Save a local Bear diagnostic trace* off, with the status line
"Off. Enable it to keep content-free timing for a diagnostic session."
*Include bounded writing context* is a separate switch and is not actionable
while the trace is off, and both **Export…** and **Delete** are present and
likewise inactive with nothing recorded.

**The research lane is not a product path.** The fast event-tap lane appears
only as the environment variable `TYPOVER_EXPERIMENTAL_BEAR_TEXT_EXPANSION`,
with no preference exposing it.

**Permissions.** Accessibility grants and revokes visibly, and its exact pane
URLs route correctly. Input Monitoring is not a separate grant and appears
nowhere in System Settings; this build states that rather than showing it as a
second switch.

### Carried forward from `20260806051920`

The diff between the two candidates is permission-row copy and a status helper
in `TypoverApp`; no engine, Bear-integration, overlay, or preference behaviour
changed, and no preference keys or learning formats moved. On that basis these
keep their prior evidence rather than being re-run:

- physical run `typover-hid-2026-08-06T05-58-02Z`, 80/80 Bear corrections from
  160 through 40 ms per key with valid focus/load evidence;
- the installed owned-editor review;
- notarized update and rollback preserving local preferences and learning;
- Bear post-pause behaviour, exact-range mutation, and the claim that normal
  operation does not save note text.

### Not verifiable in this environment

Apple Intelligence reports **Unavailable on this Mac** in a VM guest, and
Typover correctly falls back to Apple's spelling checker with a stated message.
The on-device Apple Intelligence path therefore could not be exercised here; its
evidence remains the development Mac. Bear itself is not installed in the lab
base, so the version-gating and fail-closed behaviour was confirmed only as far
as both supported versions being present in the binary — the behavioural
evidence is the physical matrix above.

### Status

The claims match the artifact. The binary remains held pending the quiet
correction-review interaction pass: pointer-only dwell, Reduced Motion,
VoiceOver, and Bear proximity/wrapped-line observations.

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
