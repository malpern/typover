# ADR-019: Use brief contextual correction marks in the owned editor

- Status: Accepted for the controlled-editor beta
- Date: 2026-08-04

## Context

Persistent correction marks make every Typover action inspectable, but many
successful corrections can make finished writing look like an error report.
Hiding marks permanently would remove accountability and create an invisible
target. A word-sized hover target is also too small to rediscover after its mark
has faded.

## Decision

The controlled editor defaults to **Brief + contextual** correction marks:

1. Draw a new mark for four seconds and fade it over 150 milliseconds.
2. Retain the attributed correction ID, original text, alternatives, learning
   state, and Undo transaction after the mark becomes visually quiet.
3. Reveal every unresolved correction in a reviewed sentence when the pointer
   dwells inside the sentence's padded rendered fragments.
4. Reveal the sentence after explicit pointer or keyboard caret navigation, but
   clear that reveal when ordinary typing resumes.
5. Pin a mark while its correction menu is open.
6. Offer **Always Visible** as a persisted preference and accessibility
   fallback.

Sentence boundaries reuse Typover's explicit correction boundaries. Pointer
geometry is derived from TextKit segments and never changes document text.

## Consequences

- Finished writing becomes calmer without losing per-change restoration.
- The reveal target is the sentence being reviewed, not an invisible corrected
  word.
- Multiple corrections in one sentence return as one understandable group.
- The owned editor remains the reference UX.
- Bear keeps its current persistent overlays until a separate spike validates
  cached sentence geometry, shared pointer monitoring, scrolling, edits,
  wrapped lines, energy use, and noninterference with Bear input.
