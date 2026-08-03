# Bear Phase 8 automatic-correction matrix

- Status: Bear 2.9.1 rapid correction, schema-5 combined-load repetition, release-config soak, lifecycle control, and repeated-correction interaction passed
- Updated: 2026-08-03
- Default: Off
- Engine: Apple Spelling, on device

The redesigned focused automatic-correction gate passes 34 tests. The focused
overlay gate now includes inactive-fallback suspension and a defensive
frontmost-app check in addition to idle-first catch-up, shared
lifecycle, post-write reconciliation, circuit-breaker regressions, one-owner
global-hotkey arbitration, direct newest-correction Change Back, and per-item
Accessibility actions. The current broad gate passes 289 tests in 29 suites,
including the hardened physical-harness wake, load-sampling, and punctuation
contracts plus dormant bounded-sentence capture and stale-result validation.
Deployment and the
redesigned physical Bear pass are recorded separately below rather than
inferred from deterministic tests.

The Apple Development-signed runtime-v2 build is deployed to
`/Applications/Typover.app` and launches with the stable
`com.malpern.typover` identity. The previous installed build was moved to the
Trash as `Typover-before-runtime-v2-2026-07-31.app`. This advances deployment,
not the physical-HID or visible-overlay rows.

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
| Type `teh` and punctuation | Passed for period, question mark, and newline with exact key-to-transition matching | Passed 5/5 for `.`, `?`, `!`, `;`, and `:` on 2026-08-01 | Exact word changes; punctuation and caret remain untouched |
| Paste `teh ` | Passed for bulk/coalesced change | Passed 2026-08-01; Bear's paste normalization left the exact word unchanged | No correction and no squiggle |
| Paste only a boundary after `teh` | Passed through missing-keystroke refusal | Passed 2026-08-01; a separately pasted boundary did not authorize the earlier word | No correction |
| Active selection | Passed, including fresh-baseline resume | Passed 2026-08-01 with a selected-range boundary control | Observation pauses; a boundary that replaces a selection cannot authorize an older word; normal typing may resume from a fresh collapsed-caret baseline |
| Bounded context changes | Passed, including deferred append-only authorization | Passed 2026-08-01 with physical Space, Left, and adjacent insertion | Refuse without writing; preserve every physical edit |
| Change Back | Passed with learning, collection-wide sibling re-anchoring, direct Accessibility actions, and an exact AppKit global shortcut that targets only the newest correction | AppKit global shortcut and an early correction's direct Accessibility action both passed independently; the direct action retained every unaffected sibling | Restore only the word and suppress the same learned correction without activating Typover |
| Choose an alternative | Overlay callback passed | Passed 2026-08-01 through the installed squiggle's public Accessibility custom action, including a physical learned-preference follow-up | Replace only the anchored word and remember the choice |
| Continue typing rapidly | Passed with idle-first mutation, boundary preservation, a fixed boundary deadline, bounded coalesced-boundary catch-up, serialized AX work, and 21 repeated correction interactions | Redesigned runtime passed 20/20 at 160 ms/character on 2026-08-01 with valid focus and fixture evidence | Preserve all later input; apply queued corrections only after idle; existing squiggles may briefly hide while typing and return after idle |
| Switch notes or windows | Passed; focus changes cancel queued input and discard the old annotation session before reattachment | Passed 2026-08-01 by switching between two disposable notes during the idle window | Reattach only to the newly focused Bear editor; do not carry unidentifiable note anchors across focus |
| Typover disabled | Passed; stop and fresh re-enable lifecycle covered | Passed 2026-08-01 with matched one-word disabled and enabled physical controls | Stop observation and hide the active Typover annotation |
| Marked-text composition | Composition-changing transitions are rejected; collapsing a selection establishes a fresh baseline | Passed 2026-08-03: Japanese Kana exposed an active marked range through physical input and conversion, committed it without a correction or overlay, and a newline-separated U.S. control then corrected 1/1 with its overlay retained | Never correct while composition is active; resume from a fresh collapsed-caret baseline after commit |
| Undo/Redo | Command-Z and Shift-Command-Z explicitly disarm correction | Passed 2026-08-01 with physical Space, Command-Z, and Shift-Command-Z | Cancel the queued correction; do not treat Undo/Redo as new typing |
| Multiple recent corrections | Passed; reverting correction five of 21 retains the other 20, length-changing alternatives shift later ranges, and overlaps alone invalidate | A fresh 20-overlay physical burst retained all overlays; reverting correction five left the other 19, and a later sibling's pointer menu remained interactive without moving focus | Keep each valid correction independently reversible |
| Post-write verification is inconclusive | Passed for anchor recovery and unreconciled-write circuit breaking | Passed 2026-08-03 with the installed debug-only fault seam, a same-process refusal, and a normal-relaunch recovery control | Recover an exact reversible anchor or pause all further automatic mutation; never claim that nothing changed |
| Close and reopen Typover's main window | Passed with an AppKit reopen delegate targeting the stable `main` scene | Passed 2026-08-01 while the existing process remained alive | Reactivating Typover restores its main window without creating a duplicate process |
| Sentence correction | Not yet implemented | Pending | Run selected local model asynchronously after a verified terminator |

## Schema-5 fresh-process combined-load repetition: 2026-08-03

The installed app passed four consecutive one-case combined-load text runs
after a fresh Typover launch for each run. All 80 physical `teh` tokens became
`the`, Bear remained frontmost, every run received all 162 fixture reports with
zero late reports, and the maximum observed HID lateness was 89 microseconds.
The local artifacts end in `19-01-02Z`, `19-04-26Z`, `19-05-19Z`, and
`19-06-11Z`.

Schema 5 populated the host-observable completion-boundary-to-AX-value metric.
The first diagnostic pass recorded 21 paired samples between 1.19 and 12.58
milliseconds, no reverse callback ordering, 20 Typover application events, and
20 distinct bounded `teh` to `the` deferred writes. Controlled contention
reduced machine CPU idle to 26.75% while all 20 visible correction windows
remained present.

A canonical fresh-note control then passed another 20/20 corrections with
20/20 visible correction windows, valid focus, complete load evidence, all 162
fixture reports, zero late reports, and 43 microseconds maximum lateness. Host
CPU idle reached 21.4%, Typover peaked at 40.7% CPU and 165,264 KiB resident
memory, and the local artifact ends in `19-08-14Z`.

An earlier same-load artifact ending `18-58-31Z` is intentionally classified
invalid: its first final token was `eth` even though the fixture trace contains
the ordered `t`, `e`, `h`, Space reports. The next 100 physical tokens did not
reproduce it. See
[Combined-load first token transposition](../bugs/2026-08-03-combined-load-first-token-transposition.md).

An accumulated-note control ending `19-06-11Z` corrected 20/20 text tokens but
sampled only the four overlay windows still visible after Bear scrolled the
wrapped appended line. It is useful viewport-culling evidence, not a failed
annotation-retention row. Exact overlay retention is credited only to the
fresh-note control.

## Installed refusal and lifecycle controls: 2026-08-01

The physical punctuation artifact ending `01-48-30Z` passed all five
boundaries with exact text and no late fixture reports. In a separate installed
paste check, Bear normalized a trailing-space paste to `teh`; pasting the
boundary plus a sentinel separately produced final text ending in `teh x`.
Typover did not correct either bulk/coalesced change. This is credited as a
paste refusal, not as physical-keyboard evidence.

Matched physical one-word controls then exercised the persisted automatic
correction setting across fresh Typover launches. With the setting disabled,
the artifact ending `02-12-50Z` preserved `teh`, recorded zero applications,
and classified the result as a safe miss. With the setting enabled, the
artifact ending `02-14-04Z` produced `the`, recorded one application at 444 ms,
and passed. Both retained valid Bear focus, complete load evidence, and zero
late reports.

Closing Typover's main window while leaving its process alive initially
reproduced a windowless-reactivation defect. The AppKit reopen bridge described
in [Typover could remain running without a reopenable window](../bugs/2026-08-01-windowless-app-reopen.md)
is deployed; the same close/reactivate sequence now restores the main window.

The active-selection control selected a unique sentinel after an already
written `teh`, then used the ESP32 to replace the selection with Space and
Return. Bear retained the older `teh`; Typover recorded
`baselineUnavailable` and `contextChanged` without applying. A preliminary
control that typed a complete new `teh ` into the selected range did correct
after Bear collapsed the selection and established a fresh baseline. That is
the intended resumed-typing behavior, not a selection-authorized change to old
text.

The first bounded-context physical control exposed a genuine deferred-write
bug: Space queued a correction, then Left and `x` changed the caret and adjacent
text before idle, but Typover still changed `teh` to `the`. The fix in
[Deferred correction could outlive caret and adjacent-text drift](../bugs/2026-08-01-deferred-correction-context-drift.md)
binds every queued correction to its transient bounded context and permits only
append-only growth before mutation. Repeating the exact six-report sequence
preserved `tehx ` and logged `deferredContextChanged`; a separate 5/5 physical
append burst proves ordinary continued typing still corrects.

The installed Undo/Redo control began with `teh`, physically typed Space,
issued Command-Z before the idle write, then issued Shift-Command-Z. Bear ended
at exact text `teh `. Typover classified both shortcuts as `undoOrRedo`, cleared
the deferred queue, treated Bear's resulting value changes as unarmed, and
logged no correction. All six fixture reports arrived with at most 27
microseconds of lateness.

The installed note-switch control physically typed Space after `teh` in the
primary disposable note, then opened a second uniquely identified synthetic
note before the idle write. The first note retained `teh `, the second retained
`SAFE TARGET`, and Typover logged focused-editor changes without a correction.
Both fixture reports arrived with no late reports. The second note was then
soft-deleted and Bear was returned to the primary fixture.

The clean release-config development build recorded its source revision and
clean-worktree state in the installed bundle and passed provenance verification
before deployment. Three consecutive 24-word physical cycles then corrected
72/72 words with exact Bear text and zero late reports. Their artifacts end in
`03-18-05Z`, `03-20-08Z`, and `03-23-33Z`; maximum fixture lateness was 46,
146, and 42 microseconds. Physical Command-F retired every cycle. The second
and third retired states both settled at 191,456 KiB and 0.0% CPU, below the
provisional 200 MiB release-config budget and without continuing per-cycle
growth.

The installed alternative control started from a physical one-word `teh `
correction with exact Bear and Typover log evidence. An external Accessibility
client found the primary overlay button by its
`typover.bear.correction-options` identifier and observed the public actions
`Revert to “teh”`, `ten`, `yeh`, `tea`, and `feh`. Performing `ten` returned
success while Bear stayed frontmost, changed only the anchored word, logged
`chooseAlternative`, and refreshed the same overlay with `the` available as an
alternative. A second physical `teh ` then became `ten ` with all ten fixture
reports delivered and 22 microseconds maximum lateness, proving the remembered
preference was applied. The synthetic preference was removed afterward while
retaining the pre-existing statistics history.

The installed composition control physically typed `teh`, held Option while
pressing E, released the dead key, pressed E to commit `é`, and then pressed
Space. Bear retained exact `tehé `, Typover logged the final Space as a
completion boundary but made no correction, and all 13 fixture reports arrived
with no late reports and 29 microseconds maximum deviation. This verifies a
real macOS dead-key composition path.

The full installed marked-text row passed on 2026-08-03 with Apple's Japanese
Kana input source temporarily enabled. Bear's official CLI brought a fresh
disposable note to the foreground at its exact terminal caret before every
physical stage. A physical `T` produced `か`; Bear visibly retained the blue
IME underline and the harness read the exact additional character. Physical
Space kept the range active, and the harness reported `selectionActive`. The
first physical Return left the conversion range active and underlined; a
second physical Return ended composition. Bear then exposed a
collapsed caret after exact committed `か`, with no blue underline and no gray
Typover overlay. The four fixture runs completed with all reports delivered,
zero late reports, and maximum per-run lateness between 14 and 30
microseconds. Typover logged the associated input, value, and selection
changes but no applied correction or overlay action.

After switching back to U.S. English, an intentionally adjacent `かteh` control
produced a content-free `noSuggestion` safe miss; it is recorded as a
mixed-script tokenization control, not a recovery failure. The identical
physical one-word row from the following newline then passed 1/1 with exact
Bear and Typover log evidence and its gray overlay retained 1/1. Its schema-5
artifact is
`~/.local/state/typover/bear-hid/typover-hid-2026-08-03T20-36-18Z/summary.json`.
The temporary Japanese source and keyboard-navigation setting were removed
afterward, restoring the original U.S.-only input configuration.

Opening Settings remains an automation coverage gap. The installed window
appears and Typover remains running, but requesting its full accessibility tree
terminates the Computer Use transport. The resulting diagnostic report names
`SkyComputerUseService`, not Typover: it ends with `EXC_BREAKPOINT`/`SIGTRAP`
while its `AccessibilitySupport` visible-child traversal is building a UI tree.
Typover remained alive after the helper exited. This narrows the observed crash
to the automation helper but does not prove the Settings tree is healthy for a
screen reader, so no settings accessibility or visual pass is credited until
the window is inspected independently on an unlocked desktop. The later
zero-window observation occurred after macOS had locked the session and is not
treated as product evidence.

The development build has a one-shot, debug-only installed-test seam for
the post-write-inconclusive row. Launching it with
`TYPOVER_DEBUG_BEAR_FAULT=post-write-unreconciled` lets the real guarded Bear
write complete, then replaces only that first successful result with a
content-free unreconciled report. The coordinator must pause its mutation
circuit, expose `pausedAfterIndeterminateWrite`, leave the changed text intact,
and create no squiggle. Release builds compile this seam out. The installed row
passed on 2026-08-03. The first physical `teh` became `the` with zero visible
overlays; both required fault logs recorded the injected verification failure
and paused mutation circuit. In the same process a second physical `teh`
remained unchanged with no overlay. After a normal relaunch without the fault
environment, a third physical `teh` became `the` with one visible overlay.
Bear focus remained valid, every fixture report arrived with zero late reports,
and the generic harness artifacts end in `19-38-15Z`, `19-39-09Z`, and
`19-40-43Z`. The first artifact is intentionally `harness-invalid` because the
ordinary harness requires a successful-application log and overlay; those are
exactly the two signals this fault row must withhold.

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

## Overlay interaction contention pass: 2026-07-31

Opening an early squiggle in a repeated-correction collection produced a
transient rainbow wait cursor. Typover remained alive and recovered. Process
samples did not show a deadlock; they showed every overlay controller's
fallback refresh performing a synchronous frontmost-application lookup and
reissuing panel frame and ordering operations even when neither state changed.
That main-actor LaunchServices and WindowServer work scaled with the correction
collection and could contend with menu interaction.

Typover now initializes a cached frontmost bundle identifier once and maintains
it from workspace activation and Bear-hide events. Fallback refreshes use the
cache. The AppKit presenter changes a panel frame only when needed, orders only
hidden panels front, and orders out only visible panels. A fast-fallback
regression proves repeated refreshes do not repeat the synchronous lookup, and
the presenter regression covers identical show and repeated hide calls. The
focused overlay suite passes 27 tests and the complete suite passes 248 tests
in 25 suites. The rebuilt app is installed; the physical early Change Back and
sibling-menu interaction remains pending until the Mac is unlocked.

## Empty-note repeated-anchor pass: 2026-07-31

The next installed pass typed eight identical corrections into a truly empty
note. All eight `teh` words became `the`, but only the first and final gray
squiggles remained. Middle anchors captured short repeated context while the
note was still growing, so later geometry refreshes found several valid
one-sided candidates and hid them as ambiguous. The earlier synthetic repeated
test had begun after a unique heading and therefore missed this exact case.

Automatic correction now reports each successful exact-range replacement to
the annotation collection. The collection snapshots the existing controllers
before the new annotation is added and queues verified edits without dropping
an in-flight update. Each targeted controller transforms its known range and
re-anchors against current Bear text before drawing again. This is proven edit
provenance, not a text-only inference, and the newly added correction cannot
mistake its own edit for an overlap. A manual identical-prefix case remains
ambiguous and hidden.

Regressions now cover sixteen repeated corrections starting in an empty note,
the manual ambiguity refusal, consecutive coordinator edit reports, two queued
edits reaching every overlay serially, and enqueue-time target isolation. The
full gate passes 248 tests in
25 suites. A rebuilt installed pass must still show all eight squiggles before
the first Change Back interaction proceeds.

## Post-burst overlay-settling pass: 2026-07-31

The first physical run of the idle-first runtime typed 20 continuous `teh `
words at 160 milliseconds per character. Bear contained exactly 20 corrected
`the` words, Typover logged 20 verified applications with no context or
replacement failures, and the ESP32 later reported all 162 HID reports with no
late reports or Wi-Fi disconnects. The harness initially marked the evidence
invalid because its eight-second fixture-status request timed out after the
burst; a later status read confirmed the fixture run had completed. The
correction result is therefore 20/20, but the harness evidence row remains
invalid rather than being retroactively upgraded.

All 20 gray squiggles initially appeared. After the runtime settled, only the
final six remained. This isolated a collection race rather than a correction,
HID, or Bear-rendering failure: each Typover replacement generated Bear value
notifications while earlier overlays were still re-anchoring through the
verified-edit queue. A temporarily stale middle anchor could receive its
ordinary invalidation refresh and retire before all sibling edits reached it.

Verified edits are now debounced into a short collection-level batch. Each
surviving controller transforms through every applicable edit and performs one
final re-anchor against Bear's settled text. Value and selection invalidations
caused during that batch are suppressed and followed by one shared fallback
refresh after all controllers finish. New edits arriving during processing are
queued for a later batch.

Regression coverage proves three repeated overlays remain visible when Bear
value notifications arrive before a two-edit batch settles, in addition to the
existing 20-overlay Change Back case. The focused overlay suite passes 29 tests
and the complete suite passes 252 tests in 25 suites. The installed retention
rerun is recorded below. The interaction row still requires an early Change
Back and later sibling-menu click.

## Atomic overlay-retention pass: 2026-08-01

The signed installed runtime typed 20 continuous `teh ` words plus Return at
160 milliseconds per character without any automation focus handoff after the
harness launched. The run passed with exact expected Bear text, 20 matching
Typover applications, a final caret at 81 in an 81-unit document, valid focus,
all 162 ESP32 reports submitted, zero late reports, and a healthy fixture.

The harness artifact is
`~/.local/state/typover/bear-hid/typover-hid-2026-08-01T14-18-22Z/summary.json`.
Content-free overlay lifecycle telemetry independently recorded 20 visible
correction IDs at the exact ranges `0:3` through `76:3` and zero hide events
through the settled observation window. This passes the installed retention
gate without inferring overlay state from corrected text alone. The app-scoped
automation screenshot cannot composite Typover's separate nonactivating panel
windows, so the early Change Back and later sibling-menu interaction remain a
separate visible UI gate.

## AppKit global Change Back shortcut: 2026-08-01

The first installed repeated-correction shortcut attempt submitted the complete
physical Control–Option–Command–M chord through the ESP32 and retained Bear
focus. Carbon had reported successful registration, but its event handler never
ran: Typover logged neither shortcut receipt nor an overlay action, and Bear's
text remained unchanged. This isolated the failure to shortcut delivery rather
than correction restoration or collection ordering.

Typover now observes the shortcut through an AppKit global key-down monitor, the
same permissioned event mechanism that already receives physical Bear typing.
It accepts only the ANSI M virtual key with Control, Option, and Command,
rejects Shift and key repeats, and ignores unrelated state such as Caps Lock.
The collection still chooses by user recency rather than reverse-safe
application order. Content-free logging distinguishes registration from actual
shortcut receipt.

The focused overlay suite passes 33 tests, including exact chord matching,
single shared registration, newest-owner arbitration, newest-correction Change
Back, and user-recency ordering. The signed build is deployed to
`/Applications/Typover.app`.

After USB firmware recovery, a fresh quiet-host physical baseline corrected
20/20 `teh` words at 160 milliseconds per character with valid focus. A uniquely
identified shortcut run then submitted one Control–Option–Command–M key-down and
one release with zero late reports. Bear's bounded text changed at exactly range
`68:3`, from `the` to `teh`; the other 78 UTF-16 units, document length, caret,
and focused editor were unchanged. The local artifacts are
`~/.local/state/typover/bear-hid/typover-hid-2026-08-01T20-16-04Z/summary.json`
and
`~/.local/state/typover/bear-hid/typover-change-back-2026-08-01T20-20-51Z/summary.json`.
This passes the installed global-shortcut row. Direct early Accessibility action
and later pointer-menu interaction are recorded independently below.

## Installed early action and sibling-menu pass: 2026-08-01

A fresh quiet-host physical run passed 20/20 continuous `teh ` corrections at
160 milliseconds per character. Bear remained the frontmost application, the
final caret and document length were both 81 UTF-16 units, and Typover exposed
exactly 20 accessible overlay windows. The baseline artifact is
`~/.local/state/typover/bear-hid/typover-hid-2026-08-01T22-38-27Z/summary.json`.

The fifth visible correction was then invoked through its exported custom
Accessibility action, `Revert to “teh”`. The action returned success, changed
only range `16:3` from `the` to `teh`, preserved Bear as frontmost, and left the
caret and document length unchanged at 81. Typover retired only the resolved
overlay: the exact overlay count changed from 20 to 19, with the other window
positions unchanged.

A real pointer down/up was then posted at a later sibling overlay. Within the
400-millisecond observation window its native menu was present beneath that
specific correction and exposed `Revert to “teh”`, `ten`, `yeh`, `tea`, and
`feh`. Bear remained frontmost, the text and caret were unchanged, and all 19
unresolved overlay windows remained present while the menu was open. Dismissing
the menu with Escape caused Bear to leave editor focus and Typover correctly
ended the annotation session; that cleanup is not credited as part of the
pointer pass.

The test-created `teh` suppression was removed after the run while preserving
all 713 activity records. The pre-cleanup learning file is recoverable from
`~/.Trash/typover-correction-learning-before-ax-pointer-cleanup-2026-08-01-154417.json`.

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
