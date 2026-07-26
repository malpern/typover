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
| Stable fixture selection | 5 launcher tests pass | Pending rerun | One exact title opens by note ID; every ambiguous or missing state stops |
| Short note baseline | Exact-range, geometry, overlay, menu tests pass | Manually verified on 2026-07-26 | Correct only `teh`; aligned squiggle; Revert and alternatives work |
| Long note | Bounded-read and earlier-position tests pass | Geometry matrix passed on 2026-07-25; interaction pending | No whole-note read or write; annotation remains aligned |
| Repeated typo | Ambiguous-anchor tests pass | Pending | Act only on the uniquely anchored occurrence or refuse |
| Rapid continued typing | Rapid insertion, alternative, and Revert tests pass | Pending permissioned harness rerun | Preserve newly typed text and keep a unique correction anchored |
| Edit before correction | Re-anchoring tests pass | Pending | Shift to the unique anchor without changing intervening text |
| Edit after correction | Re-anchoring tests pass | Pending | Keep the correction anchored; preserve later text |
| Change both context sides | Invalidated-anchor tests pass | Pending | Hide and refuse without writing |
| Multiple Bear windows | Secondary-window geometry passed | Interaction pending | Follow only the focused editor; never annotate another window |
| Switch notes while pending | Focus invalidation and stale-anchor policies pass | Pending | Hide immediately; refuse unless the active editor uniquely verifies |
| Bear relaunch | Bear-not-running and focus-unavailable states pass | Pending | Hide old annotation; never reuse a stale interaction |
| Typover relaunch | Correction state is intentionally session-scoped | Pending | No stale annotation returns after relaunch |
| Light appearance | Native menu and gray squiggle manually verified | Passed on 2026-07-26 | Menu remains legible and squiggle remains visibly secondary |
| Dark appearance | Native color behavior is deterministic | Pending | Menu remains native; squiggle remains subtle and legible |
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
