# Empty-note repeated anchors became ambiguous

- Status: Fixed; installed repeated-empty-note retest passed
- Observed: 2026-07-31
- Surface: Bear automatic correction and gray-squiggle collection

## Symptom

Typing eight identical `teh ` entries into an empty Bear note corrected every
word to `the`, but only the first and final gray squiggles remained visible.

## Cause

Each correction originally captured only the text that existed at that moment.
As more identical words were appended, a middle correction's stored one-sided
context matched several `the` occurrences. The resolver correctly failed
closed and hid the ambiguous overlay. The first correction stayed anchored to
the document start and the final correction still had current context, which
explains the exact first-and-last pattern.

The earlier repeated-word regression began after a unique heading. That prefix
made every bounded anchor distinguishable and did not reproduce an empty note.

## Fix

The automatic-correction coordinator now reports every successful exact-range
replacement to the overlay collection before adding its new annotation. The
collection snapshots the already-existing controllers at that moment and
serializes those verified edits rather than cancelling an in-flight update.
Existing controllers transform their known ranges and re-anchor from Bear's
current text. This gives them fresh two-sided context without guessing from
repeated words and prevents the new correction from processing its own edit as
an overlap.

Only Typover-verified edits use this path. Manual edits with indistinguishable
context remain ambiguous and fail closed.

## Regression coverage

- Sixteen identical corrections now start in a truly empty document. After
  each verified edit coordinates older anchors, all sixteen resolve to their
  original ranges.
- An identical manual prefix insertion remains ambiguous.
- Two rapidly queued verified edits both reach every tracked controller and
  re-anchor serially.
- An annotation added immediately after a verified edit is excluded from that
  edit's target snapshot.
- Consecutive automatic corrections assert that their exact edit ranges are
  reported to the annotation tracker.

The deterministic suite covers the empty-note range transforms. A fresh
installed run then retained all 20 repeated-word overlays; changing back the
fifth correction removed only that overlay and preserved the other 19.
