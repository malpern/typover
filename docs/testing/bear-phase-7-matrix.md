# Bear Phase 7 robustness matrix

- Status: In progress
- Last updated: 2026-07-26
- Fixture: `Typover Bear Phase 2 — 2026-07-25`
- Current environment: Bear 2.8.1 (14428), macOS 27.0

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
| Stable fixture selection | 5 launcher tests pass | One exact CLI title match verified; app-host launcher rerun pending | One exact title opens by note ID; every ambiguous or missing state stops |
| Short note baseline | Exact-range, geometry, overlay, menu tests pass | Passed on 2026-07-26 | Correct only `teh`; aligned squiggle; Revert and alternatives work |
| Long note | Bounded-read and earlier-position tests pass | Geometry matrix passed on 2026-07-25; interaction pending | No whole-note read or write; annotation remains aligned |
| Repeated typo | Ambiguous-anchor tests pass | Pending | Act only on the uniquely anchored occurrence or refuse |
| Rapid continued typing | Rapid insertion, alternative, and Revert tests pass | Passed on 2026-07-26, including live Revert with an adjacent synthetic tail | Preserve newly typed text and keep a unique correction anchored |
| Edit before correction | Re-anchoring tests pass | Pending | Shift to the unique anchor without changing intervening text |
| Edit after correction | Re-anchoring tests pass | Pending | Keep the correction anchored; preserve later text |
| Change both context sides | Invalidated-anchor tests pass | Pending | Hide and refuse without writing |
| Multiple Bear windows | Secondary-window geometry passed | Interaction pending | Follow only the focused editor; never annotate another window |
| Switch notes while pending | Focus invalidation and stale-anchor policies pass | Passed on 2026-07-26 | Hide immediately; refuse unless the active editor uniquely verifies |
| Manual supersession | Terminal value-change lifecycle tests pass | Passed after fix on 2026-07-26 | Hide, end the old session, and allow a fresh correction |
| Bear relaunch | Bear-not-running and focus-unavailable states pass | Pending | Hide old annotation; never reuse a stale interaction |
| Typover relaunch | Correction state is intentionally session-scoped | Passed on 2026-07-26 | No stale annotation returns after relaunch |
| Light appearance | Native menu and gray squiggle manually verified | Passed on 2026-07-26 | Menu remains legible and squiggle remains visibly secondary |
| Accessibility menu surface | Floating-window metadata and retained-action tests pass | AX window, button, menu, and Revert action passed; correction also passed with VoiceOver enabled; full VoiceOver speech navigation pending | Expose one logical correction stop and dispatch the same guarded actions without activating Typover |
| Dark appearance | Native color behavior is deterministic | Functional correction and relaunch passed on 2026-07-26; final visual/menu contrast review pending | Menu remains native; squiggle remains subtle and legible |
| Scroll during refresh | Offscreen and partial-visibility tests pass | Geometry matrix passed; in-flight interaction pending | Hide before movement and redraw only after verified geometry |
| Markdown constructs | Wrapped and formatted geometry tests pass | Heading, list, link, code, and wrap geometry passed | Accessibility coordinates remain authoritative |
| Attachment-adjacent text | Exact-range policy passes | Geometry passed; interaction pending | Never touch attachment data or replace the whole note |
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
4. restored the disposable marker after each experiment; and
5. successfully started a second correction after the first correction was
   manually superseded; and
6. changed `the` back to `teh` while preserving a synthetic tail typed directly
   after the corrected word.

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
