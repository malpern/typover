# ADR-011: Keep Bear correction menus nonactivating and transaction-backed

- Status: Accepted
- Date: 2026-07-25

## Context

Phase 5 proved that Typover can draw a fail-closed annotation over a verified
Bear range without activating Typover. Phase 6 must make that mark useful: a
writer needs to restore the original or select another correction without
losing Bear's caret, targeting a stale offset, or turning the overlay into a
second editor.

Bear also posts a delayed selection update after some Accessibility text
replacements. A synchronous `AXSelectedTextRange` verification can therefore
succeed before Bear moves the caret back to the edited word.

## Decision

Only the narrow squiggle strip accepts pointer input. Its `NSPanel` remains
nonactivating and cannot become key or main. The primary fragment is exposed as
one Accessibility button; wrapped fragments do not create duplicate VoiceOver
stops. A Bear-only Control–Option–Command–Return shortcut opens the same native
menu.

The menu is intentionally short:

1. Revert to the originally typed text.
2. Up to five safe, unique alternatives shown as bare words.

There is no “Keep Existing” item. Dismissing the menu already performs that
action and must not write.

The visible wording matches Typover's controlled editor: the revert action is
explicit once, while alternatives do not repeat “Change to” on every row. The
standard `NSMenu` styling remains native, accessible, and visually compact.

Menu actions never edit Bear directly from a stored rectangle or range. They
invoke guarded transactions that resolve the content-private correction
anchor, verify a unique current value, write only that exact range, verify the
surrounding context, and preserve the originally typed word in the correction
record. A selected alternative produces a fresh anchor for later Change Back.

After a verified write, Typover performs two delayed selection checks. It
repairs the selection only when all of these remain true:

- the focused Bear editor is still available;
- the anchored text resolves uniquely to the expected value;
- the current selection is exactly one of Bear's known transient edit-end
  carets.

Any other selection is considered a newer user action and is never changed.

## Consequences

- Bear remains the active writing application while the native menu opens.
- Change Back and alternatives share the same bounded-write safety model.
- Clicking a wrapped fragment reaches one logical correction without adding
  duplicate accessibility elements.
- The delayed repair handles Bear's asynchronous caret update while remaining
  fail-closed if the user moves the caret.
- The global shortcut is deliberately specific and active only while a tracked
  correction is visible in frontmost Bear.
- Full VoiceOver, menu-dismissal, rapid-typing, and cross-version behavior
  remain explicit Phase 7 matrix items rather than assumptions.
