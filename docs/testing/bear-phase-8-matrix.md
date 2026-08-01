# Bear Phase 8 automatic-correction matrix

- Status: Bear 2.9.1 compatibility and rapid correction passed; repeated-overlay retest pending
- Updated: 2026-07-30
- Default: Off
- Engine: Apple Spelling, on device

The focused automatic-correction gate passes 23 tests, including the current
rapid-typing regressions. The quiet-machine broad gate now passes 223 tests in
24 suites. The signed development build is deployed to
`/Applications/Typover.app`, and automatic Bear correction is enabled locally
for the live pass.

Mutation is now gated to the environments actually validated: Bear 2.8.1 and
2.9.1 on macOS 27.0. An unknown Bear version, an unvalidated macOS minor
version, missing Bear bundle metadata, or any missing required Accessibility
notification disables automatic mutation and produces an explicit status.
The support claim will widen only after another version passes this matrix.
If typed-boundary monitoring is temporarily unavailable, Typover stops its
Bear observer, reports the unavailable state, and retries from a fresh baseline
on the next application activation.

The automatic coordinator also keeps session-only, content-free counts for
boundary inputs, Bear value changes, applied corrections, safe skips, and
refusals. It samples correction-to-visible-annotation latency and successful
menu-action-to-verified-change latency without retaining the original word,
replacement, surrounding text, note identity, or document content. Settings
exposes only the content-free totals and timing summaries.

A completion key authorizes a Bear value change for at most 750 milliseconds.
If the matching Accessibility change arrives later, Typover records a safe
skip and does not write. This prevents an old keypress from authorizing an
unrelated later edit. The exact inserted boundary must also equal the observed
key, so a Space cannot authorize a period transition or vice versa.

This matrix covers the transition from the manual Bear preview harness to
automatic correction during ordinary typing. Deterministic checks establish
policy and transaction behavior. A row is not complete until the installed app
also passes in Bear.

| Scenario | Deterministic status | Installed Bear status | Expected result |
|---|---|---|---|
| Type `teh` and Space | Passed | Passed 2026-07-26 | Only `teh` becomes `the`; caret stays after the Space; gray squiggle appears |
| Type `teh` and punctuation | Passed for period, question mark, and newline with exact key-to-transition matching | Pending | Exact word changes; punctuation and caret remain untouched |
| Paste `teh ` | Passed for bulk/coalesced change | Pending | No correction and no squiggle |
| Paste only a boundary after `teh` | Passed through missing-keystroke refusal | Pending | No correction |
| Active selection | Passed, including fresh-baseline resume | Pending | Observation pauses; no write |
| Bounded context changes | Passed | Pending | Refuse without writing |
| Change Back | Passed with learning and collection-wide sibling re-anchoring | Single correction passed; post-fix repeated-collection retest pending | Restore only the word and suppress the same learned correction |
| Choose an alternative | Overlay callback passed | Pending | Replace only the anchored word and remember the choice |
| Continue typing rapidly | Passed, including boundary preservation, a fixed boundary deadline, coalesced-change refusal, debounced overlay geometry, and 21 repeated correction interactions | Quiet-machine run corrected and annotated 21 of 21 completed typos | Preserve all later input; existing squiggles may briefly hide while typing and return after idle; safe miss if events truly coalesce |
| Switch notes or windows | Passed; focus changes disarm in-flight input before reattachment | Pending | Reattach only to the newly focused Bear editor |
| Typover disabled | Passed; stop and fresh re-enable lifecycle covered | Pending | Stop observation and hide the active Typover annotation |
| Marked-text composition | Composition-changing transitions are rejected | Pending | Never correct while composition is active |
| Undo/Redo | Command-Z and Shift-Command-Z explicitly disarm correction | Pending | Do not treat Undo/Redo as new typing |
| Multiple recent corrections | Passed; reverting correction five of 21 retains the other 20, length-changing alternatives shift later ranges, and overlaps alone invalidate | All 21 overlays appeared; post-fix early Change Back retest pending | Keep each valid correction independently reversible |
| Sentence correction | Not yet implemented | Pending | Run selected local model asynchronously after a verified terminator |

## Bear 2.9.1 compatibility pass: 2026-07-29

Bear updated locally from 2.8.1 (14428) to 2.9.1 (14638). Typover's exact
version gate correctly refused mutation until the new release was checked. A
content-free live probe against the focused 2.9.1 editor passed with one
`AXTextArea`, writable selection and value attributes, bounded range reads,
range geometry, and all required selection, value, layout, focus, and window
notifications.

The guarded live geometry harness then applied `teh` to `the` in the dedicated
fixture, resolved the same anchored range and bounds across three samples, and
restored `teh` through Change Back. Bear CLI 2.9.1's `app open` command uses
UTF-8 byte offsets and an appended line includes a terminal newline; the
fixture caret must therefore be placed before that newline. This CLI setup
detail does not change Typover's live Accessibility coordinate space.

Decision: add Bear 2.9.1 to the explicit validated-version allowlist while
retaining Bear 2.8.1. The rapid physical-keyboard row still needs to be rerun
against the newly deployed 2.9.1-compatible build.

## Input-safety pass: 2026-07-26

The signed development app containing the input-intent safety changes is
deployed to `/Applications/Typover.app`. The deterministic gate passes 217
tests. It now distinguishes a literal typed boundary from Command-Z and
Shift-Command-Z, and any later Undo/Redo key disarms an earlier boundary before
Bear's value change is considered. Shifted punctuation uses the actual typed
character, so `?` and `:` remain eligible completion boundaries.

Marked-text state is not assumed from a keyboard event. Instead, the observer
requires Bear's settled text to differ by exactly one literal boundary
character, with the preceding and following bounded text unchanged. Candidate
selection, composition updates, and composition commits that alter the marked
word therefore fail closed. A normal boundary typed after composition has
ended can still be corrected.

No installed rows were advanced in this pass: Computer Use disconnected while
opening Typover Settings, and the fallback UI driver was unavailable. Typover
and Bear remained running, and the installed Typover process logged that its
automatic observer was ready after Bear became frontmost. Deterministic
evidence is not recorded as a permissioned live-app pass. Composition,
Undo/Redo, shifted punctuation, and the multi-annotation path still require
observation in the installed apps.

## Editor-focus recovery pass: 2026-07-27

The installed app now distinguishes “Bear is frontmost” from “Bear's note body
is focused.” Bear's official CLI and ordinary navigation can initially leave
focus in a title or search field, and in that state Bear may expose either one
inactive text area or no safely identifiable text area. Previously Typover
retried for a short period and then had no observer left to notice a later click
into the note body.

Typover now installs a content-free, application-level waiting observer when no
editor can be identified unambiguously. That observer registers only Bear focus
and window notifications. It does not read text and cannot authorize a
correction. When the native note body becomes focused, Typover restarts from a
fresh baseline, registers the editor value and selection notifications, and
then begins boundary monitoring. Stage-specific logs now distinguish missing
Accessibility trust, Bear absence, observer creation failure, notification
registration failure, and the safe waiting-for-editor state.

The signed build was deployed to `/Applications/Typover.app`. In Bear 2.8.1 on
macOS 27.0 it logged the waiting state after a non-edit fixture open, then
upgraded to **Bear automatic observation ready** after the same fixture was
opened for editing. The content-free live capability probe then passed with one
focused `AXTextArea`, bounded range access, exact-range write support, geometry,
and every required notification. Computer Use continued to time out while
enumerating Bear's complete accessibility tree, so this pass does not advance
the remaining ordinary-keystroke rows.

## Rapid repeated-word diagnosis: 2026-07-27

A permissioned manual run typed seven consecutive `teh` entries quickly. Bear
contained `the teh the teh the teh teh`, and Typover's local log recorded three
verified applications. The coordinator was overwriting an armed Space with the
ordinary first key of the next word before Bear delivered the delayed
Accessibility value-change notification. The earlier consecutive-word test
waited for each correction and did not model this ordering.

Ordinary key-down events now preserve a pending completion boundary. Undo/Redo,
focus changes, selection changes, expiry, and evaluation still disarm it. Exact
transition verification remains authoritative: if Bear coalesces the Space and
next letter into one change, Typover records a safe context-change skip rather
than guessing. Two deterministic regressions cover both the recoverable delayed
notification and the fail-closed coalesced case; the fixed-deadline regression
below covers timer rescheduling. The fixed installed build
still requires the same rapid manual sequence before this row can pass.

A second private-trace pass identified another recoverable synchronization
problem. Once a Space and Bear value change were paired, later selection and
value notifications from the next word repeatedly reset the 35-millisecond
settling timer. Several completed words could therefore collapse into one
snapshot and fail exact-transition validation. A paired boundary now keeps its
first fixed evaluation deadline; subsequent notification noise cannot debounce
it away. The focused 23-test suite passes, including a timing regression that
would fail under the old rescheduling behavior.

Computer Use cannot substitute for this installed row. Its bulk text action is
delivered to Bear as one coalesced edit, while its individual key action does
not appear in Typover's global `NSEvent` monitor. Both paths correctly produce
no automatic correction, but neither reproduces physical keyboard input. The
fixed build therefore still requires a manual repeated-`teh` pass.

The physical fixed-deadline retest applied 4 of 14 rapid entries. The trace
showed the first three corrections completing normally, followed by bounded
context reads delayed by 200–885 milliseconds. Each tracked squiggle owned an
independent Bear observer and a 125-millisecond fallback geometry poll, so the
Accessibility workload grew with every successful correction and competed with
the automatic-correction reader.

Production overlay sessions now debounce geometry work for 180 milliseconds
after Bear text changes and use a two-second fallback interval. A value change
hides the potentially stale squiggle immediately; after typing pauses, each
still-valid correction re-anchors and reappears. Correction detection remains
independent and continues during the debounce. The focused overlay suite passes
21 tests, including a rapid-notification regression, and the focused automatic
suite passes all 23 tests. The deployed build needs the same physical sequence
before deciding whether bounded idle catch-up is still required.

## Quiet-machine rapid correction and repeated-anchor pass: 2026-07-30

After the machine reached three consecutive samples above 60% CPU idle, the
complete deterministic gate passed 222 tests in 24 suites. A physical Bear
2.9.1 run then produced 17 Space key-down boundaries. Sixteen Spaces entered
Bear and every corresponding `teh ` became `the `; the remaining Space never
entered Bear's document and therefore was not a Typover miss. The 16 verified
applications took 92–207 ms from boundary to completion, averaging 117 ms.
Bear's final note contained 16 `the` words and no `teh`.

The screenshot nevertheless retained only ten gray squiggles. This was a
separate reversibility defect: production anchors kept 40 UTF-16 units of
leading context, exactly ten repetitions of `the `. Starting with the eleventh
correction, later identical words could reproduce the same bounded
fingerprints, so the geometry resolver correctly failed closed and discarded
the ambiguous annotations.

Production anchors now retain 256 UTF-16 units on each available side. This
remains a bounded local read and distinguishes 64 consecutive `the ` sequences,
well beyond the 24-overlay session limit for this case. A regression creates 16
corrections through the real exact-range transaction and confirms that every
anchor resolves to its own range. The true duplicated-context test was expanded
to collide with the complete production anchor and still refuses without
writing. The broad gate now passes 223 tests in 24 suites. The installed build
still needs one physical pass confirming all 16 squiggles and Change Back on an
early word.

## Collection re-anchoring pass: 2026-07-31

A later quiet-machine run produced 21 completion boundaries, 21 verified
applications, no context-change refusals, and 21 visible overlays. Application
latency ranged from 82 to 166 ms and averaged 109.3 ms. Changing back the fifth
correction restored only that word, but removed every later overlay. Those
later anchors all included the edited word in their 256-unit leading
fingerprint, so they became stale together even though their own text and
ranges remained valid.

Typover now treats a successful Change Back or alternative as a verified
collection edit. Every non-source overlay transforms its last resolved range:
earlier ranges remain fixed, later ranges shift by the UTF-16 length delta, and
only overlapping ranges are invalidated. Each survivor then verifies its exact
replacement against Bear's current text and captures fresh bounded,
content-private fingerprints before drawing again.

Five regressions cover the new behavior: exact re-anchoring, superseded and
out-of-bounds refusal, reverting correction five of 21 while preserving the
other 20, length-changing range shifts, and overlap invalidation. The focused
gate passes 62 tests across four relevant suites; the complete gate passes 228
tests in 24 suites. The installed build still needs the same early Change Back
interaction to confirm all 20 sibling squiggles remain visible in Bear.

## Physical cadence and bounded catch-up pass: 2026-07-31

The ESP32-S3 physical fixture reproduced 20 continuous `teh ` words plus Return
at 160, 100, 60, and 40 milliseconds per character. Immediate selection-based
replacement passed the two slower rows but could overlap the next key at 60
milliseconds, producing an unexpected joined token. Deferring rapid
corrections removed that corruption. A first valid deferred run preserved every
missed word but corrected only 16/20 at 60 milliseconds and 3/20 at 40
milliseconds because Bear coalesced several Accessibility changes before the
35-millisecond read.

Typover now retains the earliest observed word start for a rapid burst. After
220 milliseconds without physical input, it reads only the available bounded
leading context, enumerates completed words from that start, applies learning
preferences, and exact-verifies replacements from the highest range to the
lowest. It never scans the whole note. Focus changes and Undo/Redo clear the
queue; an unobserved or truncated start remains a safe miss. The catch-up task
yields between writes and requeues untouched ranges if new physical input is
observed.

The final installed physical evidence passes 20/20 at both 60 and 40
milliseconds. Combined with the earlier valid cases, all four timing rows pass
with exact expected Bear text, 20 matching Typover application logs per row,
all 162 fixture reports submitted, zero late reports, and no unexpected text.
Focused coverage now includes 30 coordinator tests, nine completed-word tests,
and seven HID-plan/evidence tests; the complete gate passes 244 tests in 25
suites. The physical harness does not count gray squiggles or click Change Back,
so the early-correction interaction remains the next installed row.

For this single-user development phase, an opt-in local private trace can log
the actual bounded Bear context, input intents, Accessibility event order,
pairing latency, proposals, ranges, and outcomes through unified logging. It is
enabled with the `bear-private-diagnostics-enabled` app default, stays on this
Mac, and does not upload text. Disable it and restart Typover when a diagnostic
run is complete.

## Privacy and safety boundary

The observer keeps only bounded, session-only text around the caret: at most 96
UTF-16 units before it and 24 after it. It never reads a whole note, never saves
the bounded text, and never requires a Bear API token. Normal diagnostics do
not log words. Anchor creation captures up to 256 UTF-16 units on each
available side of a correction, hashes that context immediately, and retains
only the fingerprints. Re-resolution searches only bounded neighborhoods
around the original and length-adjusted locations. The explicitly enabled
single-user private trace and opt-in live test harness may print bounded
context locally during development. A correction proceeds only when a real
unmodified completion key and Bear's one-character text transition agree;
either signal alone is insufficient.
