# ADR-009: Fragment wrapped Bear ranges before drawing annotations

- Status: Accepted
- Date: 2026-07-25

## Context

Bear exposes `AXBoundsForRange` for its active `AXTextArea`. A visible word on
one rendered line produces a precise screen-space rectangle. When a requested
range crosses a visual line wrap, however, Accessibility returns one union
rectangle spanning both line fragments. Drawing a squiggle across that union
would underline unrelated space and text.

The Phase 4 live matrix reproduced this in a narrow second Bear window. The
same marker that produced one precise rectangle in the wider window produced a
stable but misleading two-line union rectangle after wrapping. Stability alone
therefore cannot establish that geometry is safe to draw.

## Decision

Typover will resolve geometry in the same Accessibility coordinate space used
for correction and restoration. It will:

1. re-anchor and verify the expected replacement;
2. require the complete corrected range to be inside Bear's visible character
   range;
3. query the complete range plus its first and last composed characters;
4. use the complete rectangle directly when its height is consistent with one
   rendered line;
5. otherwise query each composed character and merge overlapping glyph bounds
   into one rectangle per rendered line.

Offscreen, stale, ambiguous, superseded, unsupported, failed, and invalid
geometry returns an explicit content-free status. Typover must hide the mark in
all of those states rather than reuse an earlier rectangle.

## Consequences

### Benefits

- Ordinary corrected words retain a three-query fast path.
- Wrapped words and bounded sentence rewrites produce drawable line fragments
  instead of a misleading union box.
- Geometry refresh uses the same bounded anchor as Change Back.
- Offscreen ranges never trigger a bounds query, preventing stale overlay
  placement.

### Costs and limits

- Wrapped ranges require one bounds query per composed character.
- Geometry remains dependent on Bear's Accessibility implementation and must be
  revalidated for supported Bear releases.
- Phase 5 must draw every returned fragment and immediately hide all fragments
  whenever refresh no longer returns `available`.
