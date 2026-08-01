# Bear overlay main-thread churn

- Status: Fixed; installed multi-overlay click retest passed
- Observed: 2026-07-31
- Surface: Bear gray-squiggle overlay

## Symptom

With several recent Bear corrections visible, clicking an early gray squiggle
could temporarily produce the macOS rainbow wait cursor. Typover recovered
without a crash or force quit.

## Evidence

Process samples taken after the report did not show a deadlock. They did show
each active correction's main-actor fallback refresh independently doing two
unchanged-state operations:

1. querying `NSWorkspace.frontmostApplication`, which can synchronously enter
   LaunchServices IPC; and
2. setting and ordering its overlay panel, which can synchronously enter
   WindowServer transactions.

Because every tracked correction owns an overlay controller, this work scaled
with the number of visible corrections. The fallback interval limited its
frequency but did not make the repeated synchronous work safe during a click or
under WindowServer contention.

## Fix

- Cache frontmost application state when tracking begins.
- Update that cache from workspace activation and Bear-hide notifications.
- Let fallback geometry refreshes read the cache instead of querying
  LaunchServices.
- Change panel presentation to set an unchanged frame only when it moves and
  order a panel front only when it is hidden.
- Change hiding to order out only panels that are visible.
- Move the automatic annotation collection to one shared workspace observer
  set, one fallback timer, one keyboard monitor, and the coordinator's existing
  Bear AX observer. Individual correction controllers no longer start their
  own lifecycle infrastructure.
- Serialize geometry, re-anchoring, Change Back, alternatives, and selection
  stabilization away from the main actor with a bounded AX messaging timeout.

The correction and geometry safety rules are unchanged. Each refresh still
verifies the Bear anchor and fails closed when focus, text, or geometry is
ambiguous.

## Regression coverage

`BearAnnotationOverlayTests` now verifies that frequent fallback refreshes use
only the initial frontmost-app lookup and that workspace activation events hide
and restore the overlay without another lookup. The AppKit presenter test also
repeats an identical presentation and verifies that it reuses the same visible
panels and frames, then tolerates repeated hiding.

The focused overlay suite includes a regression proving that collection-owned
controllers do not start per-correction AX monitors and that a focused-editor
change discards the session. The redesigned overlay gate passes 28 tests; the
complete deterministic gate passes 251 tests in 25 suites. Installed-app
results are recorded only after rebuilding and observing the real Bear UI. The
redesigned signed build is installed and launches successfully; the original
wait-cursor scenario still needs the real multi-overlay click check.

## Installed result

A fresh 20-overlay physical run changed back the fifth correction through its
direct Accessibility action, then opened a later sibling menu with a real
pointer event. Bear remained frontmost, only the selected word changed, all 19
remaining overlays survived, and no wait cursor appeared.
