# Typover roadmap

- Status: Active
- Updated: 2026-08-01
- Current milestone: 1 — Bear word-correction beta

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
caret/context drift, physical Undo/Redo cancellation, and two 24-annotation
memory cycles. A real
ESP32 Command-Tab and Command-F establish the inactive and retired energy
boundaries: Typover remains at 0.0% CPU after either transition. The current
debug build plateaus below a provisional 200 MiB RSS budget after two complete
24-annotation cycles; a release build and longer soak remain required.

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

Detailed implementation history remains in the
[controlled-editor milestone record](controlled-editor-roadmap.md) and
[Bear compatibility spike](bear-compatibility-spike.md). Those documents are
evidence, not competing roadmaps.

## Milestone 1: Bear word-correction beta

### Outcome

A writer can enable Typover, write normally in a supported Bear version, and
receive safe word-level corrections without selecting text or invoking the
manual preview command. Each correction keeps its own gray squiggle, Change
Back action, and alternatives.

### Work

- Complete the permissioned installed-app scenarios in the
  [Phase 8 matrix](../testing/bear-phase-8-matrix.md):
  - punctuation;
  - paste and boundary-only paste refusal;
  - active selections and bounded-context drift;
  - Change Back and alternatives;
  - rapid continued typing;
  - note and window switching;
  - disabling and re-enabling Typover;
  - marked-text composition and Undo/Redo;
  - multiple recent corrections.
- Absorb the remaining relevant
  [Phase 7 robustness rows](../testing/bear-phase-7-matrix.md):
  - long-note interaction;
  - scrolling during refresh;
  - attachment-adjacent correction;
  - final Dark appearance review; and
  - full spoken VoiceOver navigation.
- [ ] Measure correction-to-squiggle latency, interaction latency, safe misses,
  refusals, false changes, memory, energy, and recovery behavior without
  logging writing. Session-only applied, safe-skip, refusal, and
  correction-to-annotation and menu-to-verified-change measurements are
  implemented. Installed load timing, active memory, process power, and
  post-burst recovery samples are recorded. Fresh-process relaunch and a
  two-cycle 24-annotation memory/retirement sample now pass with a provisional
  200 MiB debug budget. Visible-squiggle timing, menu interaction timing, a
  release-build memory budget, and a longer soak remain.
  The evidence log is
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
- [ ] Extend severe-load evidence with repeat runs after fresh app/Bear launches,
  direct keyboard-to-Bear arrival timing, overlay-retention checks during the
  load, and a documented steady-state memory budget. The current ESP32 trace
  proves scheduled reports and final Bear text, but it does not timestamp each
  character's arrival inside Bear.
  The app's main editor scene now has a stable `main` restoration identity and
  presented launch behavior so root-view changes cannot strand future installs
  on stale synthesized SwiftUI restoration identifiers. An AppKit reopen
  delegate now restores that exact scene when the already-running app has no
  visible windows; the installed close/reactivate check passes.
  A reported rainbow wait cursor while opening an early
  squiggle exposed collection-scaled main-thread churn: every overlay fallback
  refresh synchronously queried LaunchServices and reissued unchanged
  WindowServer operations. Frontmost state is now event-cached and panel
  presentation is idempotent. The full 248-test gate passes; the installed
  multi-correction click check now passes against a fresh 20-overlay physical
  run. See
  [Bear overlay main-thread churn](../bugs/2026-07-31-bear-overlay-main-thread-churn.md).
  The same installed pass exposed a separate empty-note ambiguity: repeated
  middle anchors had no unique context while later words were appended. Every
  verified automatic edit is now serialized through the overlay collection so
  older corrections re-anchor from their exact transformed ranges. Queue
  targets are snapshotted before the new annotation is added so a correction
  cannot invalidate itself; unverified ambiguous edits still fail closed. See
  [Empty-note repeated anchors](../bugs/2026-07-31-empty-note-repeated-anchor-ambiguity.md).
  The first idle-first physical burst corrected 20/20 but exposed one remaining
  settling race: all 20 squiggles appeared initially, then older overlays were
  retired while Bear value notifications interleaved with sibling re-anchors.
  Verified edits are now batched to settled text and self-induced invalidations
  are deferred until the batch completes. Existing verified panels remain
  visible while serialized re-anchoring is in flight. A 2026-08-01 installed
  run corrected 20/20 physical words and recorded 20 exact visible overlay
  ranges with zero lifecycle hides after settling. See
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

The physical 20-word Bear burst now passes correction, overlay retention, and
all three independently credited interaction rows. One physical
Control–Option–Command–M chord restored exactly the newest correction. A direct
Accessibility action on correction five changed only that word and retained
the other 19 overlays. A real pointer click on a later sibling opened its
native correction menu while Bear remained frontmost and its text stayed
unchanged.

Next, finish the remaining Phase 8 installed behaviors—active-selection and
bounded-context refusal, note/window switching, alternatives, composition, and
Undo/Redo—then record correction-to-visible-squiggle and menu latency. Diagnose
the Settings accessibility-tree transport failure before crediting a visual
settings pass. Repeat the combined physical matrix after fresh Typover and Bear
launches, extend the two-cycle 24-annotation memory result into a release-build
soak, and add direct keyboard-to-Bear arrival timing rather than inferring it
from the ESP32 schedule.
