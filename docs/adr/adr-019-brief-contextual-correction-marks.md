# ADR-019: Use brief contextual correction marks

- Status: Accepted for the controlled editor; Bear qualification pending
- Date: 2026-08-04

## Context

Persistent correction marks make every Typover action inspectable, but many
successful corrections can make finished writing look like an error report.
Hiding marks permanently would remove accountability and create an invisible
target. A word-sized hover target is also too small to rediscover after its mark
has faded.

## Decision

The controlled editor defaults to **Brief + contextual** correction marks:

1. Draw a new mark for 1.5 seconds and fade it over 180 milliseconds.
2. Retain the attributed correction ID, original text, alternatives, learning
   state, and Undo transaction after the mark becomes visually quiet.
3. In the owned editor, reveal every unresolved correction in a reviewed
   sentence after a 220-millisecond pointer dwell inside the sentence's padded
   rendered fragments.
4. Reveal the sentence after explicit pointer or keyboard caret navigation, but
   clear that reveal when ordinary typing resumes.
5. Pin a mark while its correction menu is open.
6. In Bear, cache only verified correction placements and use one throttled
   global pointer monitor to reveal marks within a bounded 220-point horizontal
   and 14-point vertical corridor. Never place an invisible hit panel over Bear
   and never issue an Accessibility read from pointer movement.
7. Offer **Always Visible** as a persisted preference and accessibility
   fallback.

Sentence boundaries reuse Typover's explicit correction boundaries. Pointer
geometry is derived from TextKit segments and never changes document text.

## Consequences

- Finished writing becomes calmer without losing per-change restoration.
- The reveal target is the sentence being reviewed, not an invisible corrected
  word.
- Multiple corrections in one sentence return as one understandable group.
- The owned editor remains the reference UX.
- Bear now has the bounded-proximity implementation behind the same persisted
  preference. It remains a candidate, not a public promise, until installed-app
  checks validate scrolling, edits, wrapped lines, energy use, focus, and menu
  noninterference.
