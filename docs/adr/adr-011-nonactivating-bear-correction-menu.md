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
stops. The primary panel is also exposed as an Accessibility floating window
with a stable identifier, label, and help text. A Bear-only
Control–Option–Command–M global hotkey directly invokes Change Back for the
newest tracked correction. It does not activate Typover or open an AppKit menu.

The hotkey uses the system global-hotkey registry, with one process-wide
registration and newest-owner arbitration. It is installed only while at least
one correction is tracked. A global `NSEvent` monitor is not used: Apple
documents that such a monitor only observes a copy of an event and cannot stop
delivery to Bear. Likewise, an ordinary Return key cannot reliably confirm a
menu owned by inactive Typover while Bear remains the key application.

The primary squiggle exposes the same bounded actions directly to Accessibility:
Change Back plus each safe alternative. Assistive technology and deterministic
automation can therefore invoke an exact action without activating Typover,
opening a menu, or routing a follow-up key through Bear. The default
Accessibility press still opens the visible menu.

Accessibility presses schedule menu presentation on the next main-loop turn so
the press response does not remain blocked inside AppKit's menu-tracking loop.
The presentation session owns the menu action target until `menuDidClose` and
uses a stable Objective-C action selector. Pointer presentation remains direct.

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
  correction is tracked in frontmost Bear. It performs Change Back directly;
  it is not menu navigation.
- The process owns one registered hotkey even if the automatic tracker and a
  manual preview briefly overlap. The newest active owner receives the action.
- Accessibility clients can invoke Change Back or a named alternative directly
  from the primary squiggle while wrapped fragments remain nonduplicative.
- Settings and the app-menu preview command share one coordinator and one
  overlay controller; the menu command does not create a second correction
  implementation.
- A stale or ambiguous anchor after a real text-value change ends the preview
  session. The same unavailable geometry after a temporary focus or note switch
  stays hidden and may resume only after fresh verification.
- The live Accessibility Revert-with-tail transaction has passed while
  preserving adjacent typed text.
- Full spoken VoiceOver navigation, menu-dismissal, and cross-version behavior
  remain explicit Phase 7 matrix items rather than assumptions.

## References

- [Apple: global event monitors can only observe events](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents%28matching%3Ahandler%3A%29)
- [Apple: perform an Accessibility action](https://developer.apple.com/documentation/applicationservices/1462091-axuielementperformaction)
- [TextWarden's independent global-shortcut action routing](https://github.com/PhilipSchmid/textwarden/blob/85311ca22ae0d3ea7c80753ab75f7020931ffdae/Sources/App/TextWardenApp.swift#L647-L682)
