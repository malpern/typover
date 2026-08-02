# Bear Phase 7 robustness matrix

- Status: Long-note, scrolling, attachment-adjacent, and Dark appearance interaction passed; spoken VoiceOver navigation pending
- Last updated: 2026-08-01
- Fixtures: dedicated Phase 2 note plus uniquely identified disposable notes
- Current environment: Bear 2.9.1 (14638), macOS 27.0

This ledger separates deterministic safety coverage from evidence collected in
the real, permissioned Typover and Bear apps. A deterministic pass proves the
transaction policy; it does not prove current Bear layout, focus, timing, or
Accessibility behavior.

## Safety rules

- Use only the dedicated disposable fixture or an explicitly created synthetic
  matrix note.
- The launcher must resolve exactly one title and open its stable Bear note ID.
- Never reuse CLI or raw-Markdown offsets for Accessibility edits.
- Record only scenario labels, timings, geometry, statuses, and refusal reasons.
  Do not record note text.
- Any ambiguity, focus change, stale anchor, partial visibility, or unsupported
  geometry must hide the squiggle and perform no write.

## Evidence ledger

| Scenario | Deterministic evidence | Permissioned live evidence | Expected result |
|---|---|---|---|
| Stable fixture selection | 5 launcher tests pass | Passed again on 2026-07-27: one exact title opened by stable note ID with `--edit` | One exact title opens by note ID; every ambiguous or missing state stops |
| Short note baseline | Exact-range, geometry, overlay, menu tests pass | Passed on 2026-07-26 | Correct only `teh`; aligned squiggle; Revert and alternatives work |
| Long note | Bounded-read and earlier-position tests pass | Passed 2026-08-01 with a physical correction at the midpoint of a 23,431-character disposable note | No whole-note read or write; annotation remains aligned |
| Repeated typo | Ambiguous-anchor tests pass | Passed on 2026-07-26 | Act only on the uniquely anchored occurrence or refuse |
| Rapid continued typing | Rapid insertion, alternative, and Revert tests pass | Passed on 2026-07-26, including live Revert with an adjacent synthetic tail | Preserve newly typed text and keep a unique correction anchored |
| Edit before correction | Re-anchoring tests pass | Passed on 2026-07-26 | Shift to the unique anchor without changing intervening text |
| Edit after correction | Re-anchoring tests pass | Passed on 2026-07-26 | Keep the correction anchored; preserve later text |
| Change both context sides | Invalidated-anchor tests pass | Passed with safe invalidation and explicit-preview recovery on 2026-07-26 | Hide and refuse without writing |
| Multiple Bear windows | Secondary-window geometry passed | Passed on 2026-07-26 | Follow only the focused editor; never annotate another window |
| Switch notes while pending | Focus invalidation and stale-anchor policies pass | Passed on 2026-07-26 | Hide immediately; refuse unless the active editor uniquely verifies |
| Manual supersession | Terminal value-change lifecycle tests pass | Passed after fix on 2026-07-26 | Hide, end the old session, and allow a fresh correction |
| Bear relaunch | Bear termination lifecycle tests pass | Passed after fix on 2026-07-26 | Hide old annotation; never reuse a stale interaction |
| Typover relaunch | Correction state is intentionally session-scoped | Passed on 2026-07-26 | No stale annotation returns after relaunch |
| Light appearance | Native menu and gray squiggle manually verified | Passed on 2026-07-26 | Menu remains legible and squiggle remains visibly secondary |
| Accessibility menu surface | Floating-window metadata and retained-action tests pass | AX window, button, menu, and Revert action passed; correction also passed with VoiceOver enabled; full VoiceOver speech navigation pending | Expose one logical correction stop and dispatch the same guarded actions without activating Typover |
| Dark appearance | Native color behavior is deterministic | Passed 2026-08-01 with a live dark-editor squiggle and native menu visual review | Menu remains native; squiggle remains subtle and legible |
| Scroll during refresh | Offscreen and partial-visibility tests pass | Passed 2026-08-01 in the 23,431-character note; the overlay hid offscreen and returned at the same anchored range | Hide before movement and redraw only after verified geometry |
| Markdown constructs | Wrapped and formatted geometry tests pass | Heading, list, link, code, and wrap geometry passed | Accessibility coordinates remain authoritative |
| Attachment-adjacent text | Exact-range policy passes | Passed 2026-08-01 with physical typing after a real image attachment | Never touch attachment data or replace the whole note |
| Previous supported Bear release | Not automatable on current install | Pending availability | Same safety policy; capability failure disables integration cleanly |

## Live pass measurements

For each live row, record:

- Bear and macOS versions;
- result: pass, safe refusal, or failure;
- correction-to-visible-squiggle latency in milliseconds;
- interaction-to-verified-replacement latency in milliseconds;
- annotation alignment: aligned, hidden, or misplaced;
- the content-free refusal status when no correction occurs.

No row is complete if the final text, selection, or annotation position was not
visually or programmatically verified after the interaction.

## Long-note, scrolling, attachment, and Dark pass: 2026-08-01

A disposable 23,431-character note contained 300 synthetic paragraphs and a
unique midpoint marker at paragraph 150. Bear placed a collapsed caret at live
editor location 11,728, with paragraph 151 present in the bounded trailing
context. The ESP32 physically inserted ` teh ` plus Return at that earlier
location. Typover changed only the three-letter typo, leaving exact text
`MIDPOINT-CURSOR the`, a live document length increase of only the six typed
characters, and the caret at 11,734. Bear CLI found no remaining `teh` in the
note, and Typover logged one verified automatic correction.

While that midpoint correction remained tracked, five native Accessibility
scroll actions moved Bear from scroll position 0.495 to 0.544. Typover logged
the correction hidden with `reason=offscreen`. Five reverse scroll actions
returned to 0.495; Typover logged the same correction ID visible again at
range 11,729:3, and a full-resolution capture showed the gray squiggle aligned
under the original word. The surrounding paragraphs and caret remained intact.

A second disposable note contained a real `TypoverAppIcon.png` attachment,
represented by Bear as one live attachment character, followed by a unique text
marker. Physical `teh ` plus Return immediately after that marker became
`the `. All ten HID reports arrived with no late reports and 30 microseconds
maximum deviation. The live editor retained its attachment character, Bear CLI
still listed the exact attachment filename, and its Markdown body still
contained the attachment link. Typover logged one verified automatic
correction rather than a whole-note replacement.

Bear was already using Dark appearance for both checks. A full-resolution
visual pass confirmed that the light-gray squiggle remains legible but quieter
than the text. Invoking the overlay's standard Accessibility press displayed
the native dark correction menu with a clear selected row, readable alternatives,
and a visible separator while Bear remained frontmost. Both disposable notes
were then soft-deleted to Bear's Trash.

## Fixture and observer recovery pass: 2026-07-27

The app-host fixture launcher again resolved exactly one disposable title and
opened that note by stable ID with Bear's `--edit` option. A separate non-edit
open reproduced Bear focusing a title or search surface instead of the native
note body. The installed Typover build now remains safely armed with only
application-level focus notifications in that state and upgrades to full editor
observation after the body receives focus.

The opt-in overlay journey rendered the synthetic correction, hid it while
Finder was frontmost, restored it when Bear returned, applied an alternative,
and restored the original text through Change Back. Repeated runs exposed
timing variance in the test host's panel visibility and caret-settling
assertions, so the complete overlay journey remains an opt-in diagnostic rather
than a release gate. No wrong-range write or fixture loss occurred; the fixture
was restored to `teh` after each run.

## Permissioned app-host pass: 2026-07-26

Typover now owns one shared Bear preview coordinator used by both Settings and a
native **Preview Selected Bear Typo** app-menu command. The command provides a
stable path into the same guarded transaction without requiring automation to
inspect the Settings window.

On Bear 2.8.1 and macOS 27.0, the installed, stable-signed Typover app:

1. changed only the selected synthetic `teh` to `the`;
2. kept the correction tracked after an adjacent synthetic typing tail was
   inserted;
3. hid the annotation when another note became active and retained the session
   when the original uniquely verifying note returned;
4. restored the disposable marker after each experiment;
5. successfully started a second correction after the first correction was
   manually superseded;
6. changed `the` back to `teh` while preserving a synthetic tail typed directly
   after the corrected word;
7. hid the correction when a detached Bear editor became active and resumed it
   only after the original editor returned; and
8. ended the preview when Bear quit, then started a fresh correction after Bear
   relaunched without restarting Typover.

The observed correction was present in the first capture about 1.6 seconds
after the menu action. That number includes Computer Use activation and capture
overhead, so it is an upper-bound interaction observation rather than an engine
latency measurement.

The first supersession pass exposed a lifecycle bug: the annotation hid, but
the coordinator remained active. Bear reported the manually changed text as a
stale anchor. Typover now treats a stale or ambiguous result as terminal only
when it follows a real Accessibility value-change event. The same result after
a temporary focus or note switch remains hidden and resumable. Deterministic
tests cover both branches, and the permissioned two-correction sequence passed
after deployment.

The correction panel is now an explicit Accessibility floating window. Its
primary underline fragment exposes one labeled button with help text and a
stable identifier; wrapped visual fragments remain excluded from the
Accessibility hierarchy. An Accessibility press schedules menu presentation on
the next main-loop turn so the AX request returns before AppKit begins menu
tracking. The menu session retains its action target until AppKit closes the
menu, and its stable Objective-C action selector is covered by a dispatch test.

Computer Use addressed the floating window, opened the native menu, chose
**Revert to “teh”**, and verified the final synthetic marker as
`teh-phase7tail`. The `-phase7tail` text was unchanged. The test fixture was
then restored to `teh`. Computer Use selects one Typover window at a time, so
the ordinary editor window was closed during this check; this did not activate
the correction panel or alter the Bear transaction. Full spoken VoiceOver
navigation remains a separate manual row.

## VoiceOver, relaunch, and dark-appearance pass: 2026-07-26

The Mac began with VoiceOver off. With VoiceOver temporarily enabled, the
installed Typover app still changed only the selected synthetic `teh` to `the`
in Bear and kept Bear active. The synthetic marker was restored, and VoiceOver
was returned to its original off state.

Computer Use cannot forward VoiceOver's global `VO` keyboard commands or
address VoiceOver's Window Chooser directly. Therefore this is evidence that
the correction path coexists with the running screen reader, not evidence of a
completed spoken-navigation journey. A person must still verify Window Chooser
discovery, the announced label and help, menu traversal, dismissal, and focus
return using VoiceOver itself.

The Mac's appearance began on Auto. In temporary Dark appearance, Typover was
quit while the disposable marker was unchanged; no stale annotation returned.
After relaunch, a fresh correction changed the exact marker from `teh` to `the`
and the dark Bear surface retained the secondary gray annotation treatment.
The marker was restored to `teh`, and the appearance setting was returned to
Auto. Native-menu contrast and the annotation's final human legibility remain
manual visual checks, so the dark row is recorded as a functional rather than
complete visual pass.

## Bear relaunch and multiple-window pass: 2026-07-26

The first Bear relaunch pass showed that the old annotation stayed hidden, but
also exposed a lifecycle defect: Typover still considered the invisible preview
active, so the next preview command was ignored. Typover now ends the tracked
interaction when the terminated application's bundle identifier is Bear. An
unrelated application terminating continues to preserve the Bear interaction.
Two deterministic tests cover both branches.

The installed fixed build logged **Preview interaction finished** while Bear
was quit. After Bear relaunched and the disposable note was reopened, the same
Typover process accepted a fresh selected `teh` and changed it to `the`. No old
annotation returned. The fixture was restored to `teh`.

With the corrected Phase 2 marker tracked in Bear's main window, activating the
separate Phase 4 geometry window hid the correction and did not annotate or
change that note. Returning to the main window resumed the still-valid
interaction at its original editor. The full deterministic suite then passed
with 193 tests in 23 suites.

## Repeated typo and edited-anchor pass: 2026-07-26

The disposable repeated-word line was temporarily changed from `the the` to
`teh teh`. Selecting the first occurrence and invoking the installed preview
changed only that occurrence, producing `the teh`. The second typo and the
separate Phase 2 marker were unchanged, and the repeated-word line was restored.

After a fresh marker correction, inserting bounded synthetic text immediately
before or after the corrected word produced `pre-the` and `the-post`. In each
one-sided case the gray annotation remained with the corrected word and no
neighboring text changed. The fixture was reset between independent scenarios.

Changing both sides produced `pre-the-post`. Typover hid the old annotation and
made no corrective write. This live path also exposed a diagnostic-harness
recovery problem: if Bear misses the expected value-change notification, the
hidden preview can remain logically active and a deliberate new preview was
previously ignored. **Preview Selected Bear Typo** now supersedes an existing
active preview while still rejecting a duplicate request during preparation.
After deployment, restoring the marker to `teh` and requesting a new preview
changed it to `the` without restarting Typover. The complete fixture was then
restored.
