# Typover roadmap

- Status: Active
- Updated: 2026-08-03
- Current milestone: 1 — Bear word-correction beta final acceptance

## Goal

Deliver automatic corrections that remain visible, understandable, and
individually reversible while someone writes naturally. Typover should begin
with a trustworthy Bear integration, then reuse the proven interaction in a
carefully tested subset of other macOS editors.

## Product contract

Every milestone preserves the same invariants:

- replace the smallest verified text range, never an entire field or document;
- retain the original for every automatic correction;
- leave a quiet light-gray squiggle until the correction is resolved;
- make Change Back and alternatives immediate;
- fail without writing when focus, text, selection, or geometry is ambiguous;
- keep Apple processing on device by default;
- transmit text only after an explicit cloud-model choice; and
- never claim compatibility from deterministic tests alone.

## Current state

The controlled AppKit and TextKit editor is the complete reference
implementation. It proves Apple Spelling, local contextual intelligence,
Careful and Comprehensive correction scopes, optional sentence rewriting,
multiple independently reversible corrections, preference learning,
statistics, Undo and Redo, and long-document annotation behavior.

Bear now supports guarded exact-range replacement, independent Change Back,
ranked alternatives, bounded context re-anchoring, wrapped-range geometry, a
nonactivating clickable overlay, continued typing, and automatic word-level
Apple Spelling. Up to 24 recent Bear corrections can remain independently
reversible. Each primary squiggle exposes direct Accessibility actions for
Change Back and safe alternatives. A scoped Control–Option–Command–M global
shortcut is wired to change back the newest tracked correction without
activating Typover or opening an inactive menu. Its original Carbon registration
accepted the physical chord but did not deliver a callback in the installed
app. The shortcut now uses the same AppKit global key-event path already proven
by automatic Bear correction. Deterministic coverage and an installed physical
one-chord retest pass: one key-down plus release restored exactly the newest
remaining correction while preserving Bear focus, the caret, and all other
text. The feature remains opt-in because most
automatic-writing scenarios still need permissioned installed-app validation.

Bear focus recovery now has a safe two-stage observer. Typover can wait on
content-free application focus notifications when Bear has not exposed an
unambiguous note body, then attach value and selection observation only after a
native editor is available. This closes the gap where entering the note after a
title or search field had been focused could otherwise leave automatic
correction dormant.

Bear's keyboard and Accessibility notifications are independent asynchronous
streams, and exact-range replacement is a comparatively slow Accessibility
transaction. Typover now uses one idle-first rule for every mutation. After
220 milliseconds without physical input it scans only the bounded text
observed since the current burst began, queues eligible completed words, and
applies exact-verified ranges from end to beginning. Focus changes, Undo/Redo,
an unavailable burst start, or text outside the 96-unit live window still fail
closed.

The quiet physical HID baseline now passes 20/20 corrections at 160, 100, 60,
and 40 milliseconds per character. The 60 and 40 millisecond rows deliberately
exercise post-burst recovery after Bear coalesces Accessibility notifications.
Every row preserved exact expected text and had matching Typover application
logs; the ESP32 delivered all 162 reports per row with no late reports.

The first controlled-load envelope is also installed and physical. Isolated
CPU, WindowServer, and Accessibility rows each pass 20/20 at 160 milliseconds
per key. A schema-4 combined matrix passes 80/80 across 160, 100, 60, and 40
milliseconds, with machine CPU idle reaching 9.6% and all rows converging
within 1.59–3.79 seconds. The physical punctuation row passes 5/5 across `.`,
`?`, `!`, `;`, and `:` boundaries.

Installed lifecycle controls now cover paste and boundary-only paste refusal,
matched disabled/enabled physical controls, closing and reopening Typover's
main window in the same process, active-selection boundary refusal, bounded
caret/context drift, physical Undo/Redo cancellation, note switching during a
queued correction, and repeated 24-annotation memory cycles. A real
ESP32 Command-Tab and Command-F establish the inactive and retired energy
boundaries: Typover remains at 0.0% CPU after either transition. The current
debug build plateaus below a provisional 200 MiB RSS budget after two complete
24-annotation cycles. A clean release-config development build now passes
three more 24/24 physical cycles and settles at 191,456 KiB after both the
second and third retirement, with 0.0% CPU across every retired sample. This
sets the same provisional 200 MiB local budget for the release configuration
without evidence of linear per-session growth.

An installed Space, Left, and adjacent-`x` control found that a deferred
correction retained only its exact range and could therefore write after its
authorizing caret context had drifted. Deferred corrections now retain a
transient bounded snapshot and require append-only document growth at the same
caret immediately before mutation. The exact physical failure sequence now
preserves `tehx ` with an explicit `deferredContextChanged` skip, while a
separate normal 5/5 append burst still corrects. See
[Deferred correction context drift](../bugs/2026-08-01-deferred-correction-context-drift.md).

An earlier quiet-machine rapid-typing pass corrected every completed typo,
including 21 consecutive `teh ` insertions. All 21 corrections retained
their overlays. Changing back the fifth word then exposed a collection-level
anchor dependency: its verified edit changed the long leading fingerprint of
every later correction. Typover now broadcasts its own verified edits across
the active collection, transforms nonoverlapping ranges, and rebuilds their
anchors from Bear's current text. Automated coverage reverts correction five
of 21 while retaining the other 20 and separately covers length-changing and
overlapping edits. The post-fix installed interaction pass now also succeeds:
an early direct Accessibility action changed only its word and retained all 19
siblings, and a later sibling's pointer menu opened without moving focus or
changing text.

The installed alternative path now passes independently as well. An external
Accessibility client found the primary squiggle's public custom actions while
Bear remained frontmost and chose `ten` for a synthetic `teh -> the`
correction. Bear changed only that anchored word, Typover logged the verified
alternative interaction, and the refreshed squiggle offered `the` as a sibling
choice. The next physical `teh ` became `ten `, proving that the remembered
preference was used. The deliberately bad test preference was then removed
without clearing the existing statistics history.

The first installed visible-latency acceptance point is now recorded against a
clean revision. A one-word physical correction showed its gray squiggle in
444.355 milliseconds, and the real nonactivating menu verified Change Back in
62.441 milliseconds while Bear stayed frontmost. In an uninterrupted
five-word sequence, all five corrections and overlays passed, but the
idle-first safety policy delayed the earlier words until the burst ended:
visible samples ranged from 474.904 to 3,206.381 milliseconds with a
1,824.610-millisecond median. This is a deliberate reliability tradeoff rather
than overlay drawing lag. Beta acceptance must explicitly decide whether
post-pause correction is the intended experience before shortening the idle
gate or allowing Accessibility writes during active input.

The remaining Phase 7 interaction gaps narrowed as well. A physical correction
at paragraph 150 of a 23,431-character disposable note changed only the bounded
midpoint word. Scrolling it offscreen hid the overlay and scrolling back made
the same correction ID and range visible again. A separate physical correction
after a real Bear image attachment retained both the live attachment character
and Bear's attachment record. A full-resolution Dark appearance pass confirmed
the gray squiggle and native menu remain legible while Bear stays frontmost.
Both synthetic notes were soft-deleted after verification.

Detailed implementation history remains in the
[controlled-editor milestone record](controlled-editor-roadmap.md) and
[Bear compatibility spike](bear-compatibility-spike.md). Those documents are
evidence, not competing roadmaps.

## Remaining plan at a glance

The word-level Bear behavior is functionally complete. The remaining work is
ordered by what blocks a trustworthy beta rather than by how much additional
test coverage could be collected:

1. Finish the human-facing acceptance pass: complete spoken VoiceOver
   navigation and the unlocked Typover Settings visual review. The native
   Settings AX inspection passes; its Computer Use failure is diagnosed as an
   external transport crash. Review the measured post-pause correction
   behavior as a beta product decision.
2. Produce the signed and notarized beta candidate, then run the clean-machine
   installation, permission, recovery, update, and uninstall checklist.
3. Qualify that final candidate—not every development build—with fresh Bear
   and Typover processes, the release-config memory envelope, and a bounded
   second-machine soak.
4. Resolve public-beta operations: license, support channel, release notes,
   rollback, and public privacy and compatibility claims.
5. After the word-level beta is trustworthy, proceed to bounded local
   contextual correction, then a TextEdit adapter, and finally broader model
   benchmarking.

## Proportionate testing strategy

Use the smallest test that can establish the behavior being changed:

- During ordinary development, run targeted deterministic tests for the
  touched policy, transaction, adapter, or UI behavior.
- Run a focused 1–5 word physical Bear row only when a change touches physical
  input observation, Bear Accessibility, exact-range mutation, overlays, or
  interaction handling.
- Run the full physical matrix only for a release candidate, a supported
  Bear/macOS version change, a material observer/transaction/overlay
  architecture change, or an unexplained installed-app regression.
- Keep specialized rows such as IME composition, 20-word overlay retention,
  severe load, and multi-cycle memory as release regression coverage rather
  than routine per-change checks.
- Preserve fail-closed admission: a shared desktop, lost Bear focus, a busy
  host, incomplete fixture reports, or missing log evidence invalidates the
  run. It is infrastructure evidence, not a Typover pass or failure.
- Do not collect more evidence merely because the harness can. Add or repeat a
  row only when it protects a product claim or answers a live uncertainty.

## Milestone 1: Bear word-correction beta

### Outcome

A writer can enable Typover, write normally in a supported Bear version, and
receive safe word-level corrections without selecting text or invoking the
manual preview command. Each correction keeps its own gray squiggle, Change
Back action, and alternatives.

### Work

- [x] Complete the word-level permissioned installed-app scenarios in the
  [Phase 8 matrix](../testing/bear-phase-8-matrix.md): punctuation, paste and
  boundary-only refusal, selections and context drift, Change Back and
  alternatives, continued typing, note switching, enable/disable lifecycle,
  Undo/Redo, full IME marked text, and multiple recent corrections. Sentence
  correction belongs to Milestone 3 and is not a Milestone 1 gap.
- [x] Complete the relevant visual and robustness rows from
  [Phase 7](../testing/bear-phase-7-matrix.md): long-note interaction,
  scrolling and overlay return, attachment-adjacent correction, and Dark
  appearance.
- [x] Diagnose the Typover Settings accessibility-tree transport failure and
  complete an independent native AX pass. `SkyComputerUseService` crashes with
  `EXC_BREAKPOINT` while Typover remains alive; the native Settings tree returns
  55 descendants and the expected stable control identifiers. Decorative
  status and statistic images are now hidden, statistic cards expose one
  labeled value, and the installed native tree reports zero standalone image
  stops. Computer Use still crashes identically, confirming the external
  boundary documented in
  [Computer Use Settings-tree crash](../bugs/2026-08-03-computer-use-settings-tree-crash.md).
- [ ] Complete the remaining human accessibility acceptance work: spoken
  VoiceOver navigation through status, settings, a correction, Change Back,
  and an alternative, plus an independent unlocked-desktop visual review.
- [x] Record the first clean installed correction-to-visible-squiggle and
  menu-to-verified-change timing points without logging writing. A one-word
  correction became visible in 444.355 milliseconds and its real menu verified
  Change Back in 62.441 milliseconds while Bear remained frontmost. A focused
  uninterrupted five-word row passed 5/5 corrections and 5/5 overlays, with
  visible timing from 474.904 to 3,206.381 milliseconds because the idle-first
  policy waits for the burst to stop. Keep the evidence in
  [Bear performance samples](../testing/bear-performance-samples.md).
- [ ] Decide whether post-pause correction is the intended beta experience.
  Do not shorten the idle gate or write while input is active without new
  physical evidence that the change preserves exact text, selection, focus,
  and overlay retention.
- [ ] Complete a bounded second-machine beta soak. Content-free safe-skip,
  refusal, load, recovery, memory, and energy evidence is already recorded;
  both debug and release-config runs support a provisional 200 MiB RSS budget.
  Keep the evidence in
  [Bear performance samples](../testing/bear-performance-samples.md).
- [x] Add capability and version gating so an unknown Bear Accessibility
  contract disables mutation rather than attempting a best guess.
- [x] Define and enforce an explicit support allowlist. Bear 2.8.1 and 2.9.1
  have passed the live Accessibility capability and exact-range transaction
  checks on macOS 27.0.
- [x] Make temporary observer and typed-boundary monitoring failures explicit
  and recover from a fresh baseline on the next application lifecycle event.
- [x] Replace the temporary single-user private Bear trace before broader beta
  testing. Unified logs now contain only content-free event names. The optional
  file-backed trace defaults off; its default enabled mode redacts writing, and
  including bounded context is a separate explicit choice. Settings explains
  the 24-hour/1 MB local retention cap and no-upload boundary and provides
  export and delete controls. Focused store and settings-render tests pass.
- [x] Add a bounded post-burst catch-up pass for rapid physical typing. It may
  inspect only the verified insertion since a recent caret baseline, must wait
  for a short idle
  interval, and must refuse any selection, focus, deletion, replacement, or
  ambiguous-context transition. Do not use whole-note or Bear-database writes.
- [x] Establish a reproducible severe-load recovery envelope. The
  board-independent host harness is implemented and documented in
  [Bear physical HID harness](../testing/bear-physical-hid-harness.md). It
  reuses the existing Waveshare ESP32-S3 fixture, requires a quiet-machine
  baseline, an explicit disposable Bear note, and exclusive Bear focus. It
  captures exact inserted-range, fixture, content-free log, CPU, memory, power,
  and convergence evidence and fails closed on focus, range, log, or resource
  ambiguity. The installed CPU, WindowServer, and Accessibility profiles pass
  20/20 at 160 milliseconds per key. The canonical combined profile passes
  80/80 at 160, 100, 60, and 40 milliseconds with no late HID reports while
  machine CPU idle falls to 9.6%. All four combined rows recover within the
  10-second bound, converging in 1.59–3.79 seconds with no refusal, context loss,
  unexpected text, or circuit-breaker event. Focus changes, ambiguous context,
  an unavailable bounded burst start, a non-append edit, or expiry of the
  10-second observation bound remain explainable safe-refusal boundaries.
  Schema 4 also fixes explicit-note targeting, PID-based power sampling, bounded
  convergence observation, and locale-stable latency evidence. Rejected earlier
  artifacts remain diagnostic-only.
- [x] Populate schema-5 arrival and overlay-retention evidence under controlled
  combined load. Three consecutive fresh-Typover rows pass 60/60 physical
  corrections at 160 milliseconds per key. A separate fresh-note row passes
  20/20 with 20/20 visible correction windows, all 162 fixture reports, zero
  late reports, 21.4% minimum host CPU idle, 40.7% peak Typover CPU, and
  165,264 KiB peak Typover RSS. Completion-boundary-to-AX-value samples span
  1.19-12.58 milliseconds with no reverse callback ordering. A fourth
  fresh-process row also passes 20/20 exact text but is not credited for
  overlays because only four current-line windows remained on screen after
  Bear scrolled the accumulated note. One preceding first-token `eth` artifact
  remains invalid and unexplained; it did not recur in the next 100 physical
  tokens. See
  [Combined-load first token transposition](../bugs/2026-08-03-combined-load-first-token-transposition.md).
- [ ] Qualify the final release candidate once with fresh Bear and Typover
  processes, a fresh disposable note, the release-config memory-retirement
  envelope, and the bounded second-machine soak. Capture per-character
  USB-to-screen-paint timing only if it can be measured without perturbing
  Bear. The fixed churn, anchor, and settling failures remain documented in
  [Bear overlay main-thread churn](../bugs/2026-07-31-bear-overlay-main-thread-churn.md),
  [Empty-note repeated anchors](../bugs/2026-07-31-empty-note-repeated-anchor-ambiguity.md),
  and
  [Bear post-burst overlay retirement](../bugs/2026-07-31-bear-post-burst-overlay-retirement.md).
- Keep automatic Bear correction off by default until the exit criteria pass.

### Exit criteria

- Every listed installed-app scenario passes or produces an intentional safe
  refusal that is explainable through content-free diagnostics.
- No tested failure changes the wrong range, moves the writer to another
  editor, loses newly typed text, or leaves a stale squiggle visible.
- Change Back and alternatives work independently across several recent
  corrections.
- Typover records enough content-free diagnostics to explain why a correction
  was applied, missed, or refused.
- The supported Bear and macOS versions are stated explicitly.

### Not required for this milestone

- sentence-level AI in Bear;
- support for an older Bear release that is not part of the initial support
  claim;
- support for another writing application; or
- enabling automatic Bear correction by default.

## Milestone 2: Minimum beta shell

### Outcome

A new tester can install Typover, understand its permissions and privacy
boundary, enable Bear support, diagnose an unavailable state, and recover from
ordinary app or Accessibility lifecycle changes.

### Work

- [x] Create a benefit-led first-run explanation for Accessibility and Input
  Monitoring, with a clear path to System Settings and an option to explore
  later. The reusable permission rows refresh whenever Typover becomes active;
  installed visual validation remains.
- [x] Show whether Bear correction is disabled, waiting, observing, paused,
  unsupported, or missing permission.
- [x] Explain capability and version gating in the interface, including why an
  installed Bear version is unsupported.
- [x] Decide and document background launch and launch-at-login behavior.
  ADR-015 keeps the initial beta manually launched until energy, recovery,
  update, and uninstall evidence passes.
- [x] Provide a privacy summary and a content-free diagnostic export. The
  optional local trace now has explicit consent, bounded retention, export,
  delete, and a separately gated bounded-writing mode.
- [x] Expose beta build identity in the About window. It shows the marketing
  version, build number, short source revision, and a visible **Modified**
  marker for dirty development builds while retaining exact provenance in the
  bundle metadata.
- [x] Declare reviewable Accessibility and Input Monitoring purpose text in the
  signed bundle, and reject beta artifacts that omit either privacy
  description.
- [ ] Produce a signed beta build and a repeatable clean-machine install and
  permission test. The Developer ID/notarization script and clean-machine
  checklist are implemented in
  [Beta distribution](../testing/beta-distribution.md). The local Developer ID
  archive now passes strict signature, expected-team, hardened-runtime, secure
  timestamp, bundle metadata, system-dependency, and clean-zip verification.
  Every package now also emits a machine-readable receipt tying the archive's
  SHA-256 to its version, build, source provenance, signing team, deployment
  floor, and notarization claim; positive and adversarial receipt verification
  remain part of the package gate.
  Every build now extracts the archive, rejects unsafe
  or unexpected paths, compares the distributed bundle byte-for-byte with the
  signed build output, and verifies the extracted signature; adversarial extra-
  path and mismatched-bundle tests pass. The bundle and executable now both
  declare the supported macOS 27.0 deployment floor, and the verifier requires
  them to match. Building and validating the notarized
  candidate and executing the clean-machine permission checklist remain.
  A 2026-08-02 clean-revision local build recorded its exact Git SHA with
  `dirty=false`; the integrated verifier and negative distribution tests pass.

### Exit criteria

- A clean Mac can reach a working Bear correction without developer tools.
- Revoked permission, Bear relaunch, Typover relaunch, and unsupported versions
  produce understandable recovery states.
- Beta privacy and supported-version claims match observed behavior.

## Parallel track: Release operations

This track may proceed after the minimum beta shell is stable. It does not
block local contextual-correction development, but it must pass before Typover
is offered as a public beta.

- Test update and uninstall behavior on a clean Mac.
- Define versioning, release notes, rollback, and the beta support channel.
  The local [beta release-operations contract](../testing/beta-release-operations.md)
  now defines numeric versions/builds, exact source provenance, manual update,
  rollback, uninstall footprint, and a release-note template. Installed
  lifecycle evidence remains pending. The repository is private, so a support
  email or public issue tracker still requires an owner decision.
- Select and document the license.
- Produce the intended public distribution artifact and verify its signing,
  notarization, installation, update, and removal behavior.
- Confirm that public privacy, support, and compatibility claims match the
  shipped build.

## Milestone 3: Contextual correction in Bear

### Outcome

Typover can apply bounded sentence-context spelling, punctuation, and grammar
corrections in Bear without blocking typing or weakening the word-level safety
contract.

### Work

- Detect a verified completed sentence after punctuation. The dormant Bear
  capture primitive now requires the observed terminator to match the bounded
  Accessibility text exactly.
- Capture only the most recent sentence, capped at 400 UTF-16 units. Bounded
  reads now resolve document coordinates only when the sentence begins at the
  document start or an earlier terminator is visible; truncated beginnings
  fail closed. Runtime scheduling remains gated on Milestone 1 evidence.
- Run the selected contextual engine asynchronously while continued typing
  remains responsive.
- Discard a proposal if the captured sentence changes, focus moves, or the
  target is no longer unique.
- Preserve Careful as the default and keep Comprehensive plus sentence rewriting
  as separate explicit choices.
- Use Apple Intelligence locally by default. Use OpenAI or Anthropic only after
  an explicit provider choice, with no automatic cloud fallback.
- Reuse the same exact-range transactions, individual annotations, Change Back,
  alternatives, statistics, and bounded restoration rules.

### Exit criteria

- Contextual inference never blocks Bear typing or applies to stale text.
- Every accepted change is visible and independently reversible.
- The installed Bear corpus preserves the controlled editor's false-positive
  and meaning-preservation gates.
- Cloud behavior matches the disclosure in Preferences exactly.

## Milestone 4: Application-neutral editor integration

### Outcome

Bear becomes one adapter for a generic Accessibility correction system rather
than the architecture itself.

### Work

- Extract an application-neutral target profile containing:
  - bundle identity and supported versions;
  - focused-editor discovery;
  - required Accessibility attributes and notifications;
  - range replacement and caret behavior;
  - geometry and coordinate conversion; and
  - application-specific lifecycle quirks.
- Keep correction engines, range verification, re-anchoring, overlays, learning,
  and statistics shared.
- Implement TextEdit as the second adapter and genericity proof.
- Build a content-free compatibility probe that classifies an editor as full,
  correction-only, cooperative-integration-required, or unsupported.
- Exclude secure text fields, password editors, and any target whose text or
  selection contract cannot be inspected safely.
- Add applications only after their own permissioned matrix passes. Native
  implementation alone is not evidence of compatibility.

### Exit criteria

- Bear and TextEdit use the same generic correction pipeline with only target
  profiles and documented quirks differing.
- An unsupported editor fails closed without showing a misplaced annotation or
  changing text.
- Product language names supported applications instead of claiming universal
  system-wide compatibility.

## Milestone 5: Quality scale and model evaluation

### Outcome

Typover's model and policy decisions are supported by representative writing,
cross-version results, and repeatable local benchmarks.

### Work

- Grow the rewrite benchmark from 35 to at least 500 cases, including at least
  300 diverse unchanged controls.
- Add consented, de-identified natural-writing examples containing no private
  text.
- Test correction and rewrite corpora against every supported macOS system-model
  version.
- Benchmark selected open-source models running locally through the existing
  engine boundary.
- Revisit confidence only if calibrated evidence improves the binary automatic
  decision without making the interaction harder to understand.
- Keep false-positive and meaning-preservation performance ahead of raw
  correction coverage.

### Exit criteria

- Model comparisons use the same safety filters, corpus, metrics, and hardware
  disclosure.
- Default-model and support decisions are based on reviewed evidence rather
  than a small development corpus.
- No model-specific requirement distorts the editor interaction or privacy
  contract.

## Sequencing decisions

- Milestone 1 is the only active implementation milestone.
- Remaining Phase 7 evidence is part of Milestone 1; Phase 7 is no longer a
  separate implementation stream.
- The minimum beta shell in Milestone 2 follows the word-level Bear gate before
  more correction scope is added.
- Sentence-level Bear intelligence follows the minimum beta shell. Release
  operations may continue in parallel and do not block local contextual
  development.
- Release operations must pass before public beta distribution.
- Application generalization begins only after Bear is a trustworthy reference
  integration.
- Corpus expansion and local-model benchmarking may proceed in parallel when
  they do not distract from the active milestone.

## Deferred or explicitly out of scope

- whole-field, paragraph, selection, note, or document replacement;
- automatic cloud fallback;
- silently reading Bear's database;
- converting raw Markdown or Bear CLI offsets into live editor offsets;
- universal compatibility claims based only on an app being native;
- native persistent formatting inside an external editor without cooperation
  from that editor or Apple; and
- changing the default correction policy based on an uncalibrated confidence
  score.

## Immediate next slice

1. Complete spoken VoiceOver navigation and the unlocked Typover Settings
   visual review. Native Settings AX structure is already credited; do not
   block this row on the diagnosed Computer Use transport crash.
2. Review the measured post-pause correction behavior and decide whether it is
   the intended beta experience. If it is not, design and physically validate a
   bounded earlier-catch-up policy before release qualification.
3. Build the signed and notarized beta candidate and run the clean-machine
   install and permission checklist.
4. On that final candidate, run one fresh-process qualification: fresh Bear,
   fresh Typover, release-config memory retirement, and the bounded
   second-machine soak.

Do not routinely repeat the full 20-word, severe-load, circuit-breaker, or IME
rows. They are release regression coverage and should be rerun only when the
testing strategy above calls for them.
