# ADR-010: Use fail-closed nonactivating panels for Bear annotations

- Status: Accepted
- Date: 2026-07-25

## Context

Bear does not expose an API for attaching Typover's persistent correction mark
to its text layout. Phase 4 established that Bear does expose guarded
screen-space fragments through Accessibility, including separate fragments for
a range that crosses a rendered line wrap.

An external window can draw those fragments, but an ordinary application
window would create three unacceptable behaviors: it could activate Typover,
intercept typing or pointer input intended for Bear, and remain visible after
its geometry became stale or the user moved to another application or Space.

## Decision

Typover will render each Bear geometry fragment in its own AppKit panel. During
Phase 5, every panel is:

- borderless, transparent, and shadowless;
- nonactivating and unable to become key or main;
- ignored by pointer hit testing;
- omitted from normal window cycling;
- scoped to the active Space rather than joined to every Space.

The panel contains only the light-gray wave. Accessibility rectangles are
converted per display from top-left coordinates into AppKit's bottom-left
coordinate space before the glyph rectangle is reduced to a narrow underline
strip. If any fragment cannot be placed on exactly one known display, Typover
rejects the complete annotation.

The overlay controller is fail-closed:

1. Bear must be the frontmost application.
2. The correction record must still be applied.
3. Anchor resolution and bounded geometry must return `available`.
4. Every returned fragment must produce a valid placement.

Text, layout, focus, window-move, and window-resize notifications hide the old
geometry before an asynchronous refresh. A 125-millisecond fallback refresh
covers missed scroll and layout events. Generation checks prevent an older
Accessibility response from restoring an obsolete mark.

Selection-only notifications may refresh without pre-hiding because moving the
caret does not change text layout. Application activation, hiding, and
termination always hide synchronously.

## Consequences

### Benefits

- Bear remains the active writing application while the mark is visible.
- Typing and caret movement pass directly to Bear.
- Wrapped corrections preserve their Phase 4 line fragments.
- Background, offscreen, stale, ambiguous, superseded, unsupported, and invalid
  states all converge on the same safe result: no mark.
- Multi-display conversion is explicit and deterministically tested.

### Costs and limits

- Phase 5's panels are intentionally not clickable. Phase 6 must introduce a
  narrow hit target without weakening nonactivation or caret preservation.
- The overlay is external to Bear, so transient hiding during recomputation is
  preferable to visually smooth but potentially stale placement.
- Accessibility notifications are not treated as perfectly reliable; the
  fallback refresh adds a small amount of bounded polling.
- Continuous rapid scrolling, typing-load measurement, and older Bear versions
  remain in the Phase 7 robustness matrix.

Phase 6's intentionally narrow exception for pointer and accessibility input is
defined in [ADR-011](adr-011-nonactivating-bear-correction-menu.md).
