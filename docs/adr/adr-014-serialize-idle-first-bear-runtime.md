# ADR-014: Serialize an idle-first Bear runtime

- Status: Accepted
- Date: 2026-07-31

## Context

Bear exposes enough macOS Accessibility support for bounded text reads,
exact-range replacement, caret restoration, and range geometry. It does not
offer Typover an atomic edit transaction, a stable note identifier, or a way to
attach native spelling metadata to Bear's text storage.

The first automatic implementation performed some corrections immediately and
gave every visible correction its own Accessibility observer, workspace
observers, fallback timer, and geometry task. Physical-HID testing showed two
production risks:

- a physical key could arrive between selection, replacement, and caret
  restoration; and
- observer, timer, AX, LaunchServices, and WindowServer work grew with the
  number of visible squiggles.

The replacement API can also report a successful write followed by failed
selection restoration or post-write verification. Treating that outcome as a
simple refusal falsely implied that nothing changed and discarded the state
needed for Change Back.

## Decision

The Bear runtime uses these rules:

1. **Idle-first mutation.** A verified completed word is queued. Typover waits
   for a 220-millisecond quiet interval before changing Bear. New physical
   input postpones the whole queue. Corrections are applied from the end of the
   document toward the beginning.
2. **One serialized AX lane.** Recurring context reads, corrections, geometry,
   re-anchoring, Change Back, alternatives, and selection stabilization run
   through one actor-backed lane away from the main actor. The initial session
   baseline remains synchronous so no physical input can race ahead of it.
3. **Bounded IPC.** Bear AX elements use a 750-millisecond messaging timeout.
   Task cancellation is not treated as cancellation of synchronous AX IPC.
4. **Shared annotation lifecycle.** The automatic collection receives events
   from the coordinator's single AX observer and owns one workspace observer
   set, fallback timer, and keyboard monitor. Individual corrections retain
   only their visual, anchor, and interaction state. Closely spaced verified
   edits are re-anchored as one collection batch; self-induced value and
   selection invalidations wait until that batch reaches settled Bear text.
   The last verified panel placement remains visible while serialized
   re-anchoring is in flight and is hidden only when a later result invalidates
   it.
5. **Honest post-write reconciliation.** If Bear accepted a replacement but
   the final verification step was inconclusive, Typover immediately verifies
   the exact replacement range and rebuilds its bounded anchor. A reconciled
   write remains visible and reversible. If reconciliation fails, automatic
   mutation pauses behind a circuit breaker until the user turns it off and
   on again.
6. **One focused-editor session.** A focused editor or focused window change
   discards the current annotation collection. Bear does not expose a stable
   note identity that would justify carrying anchors into another editor.
7. **Main actor for presentation.** AppKit panels, menus, settings state, and
   the event reducer remain main-actor isolated. Blocking recurring AX work
   does not.

## Consequences

- A normal correction appears after a short, deliberate pause instead of while
  the next key may be arriving.
- Rapid input can be caught up after the burst without whole-field replacement.
- AX work is serialized rather than competing across correction controllers.
- Switching notes intentionally removes old squiggles; restoring them would
  require a reliable Bear editor identity or a cooperative Bear integration.
- A correction can be counted as applied only when it has a reversible anchor.
- Severe system load can still delay a bounded operation, but it cannot create
  unbounded concurrent AX work or silently continue after an indeterminate
  mutation.

## Validation

- deterministic automatic-correction coverage includes idle deferral,
  coalesced-boundary catch-up, reverse-order application, new-input
  cancellation, focus cancellation, and the post-write circuit breaker;
- transaction coverage includes post-write anchor reconciliation;
- overlay coverage includes 20 surviving siblings after Change Back and proves
  that collection-managed controllers do not start per-correction AX monitors;
- overlay coverage also proves self-induced Bear invalidations cannot retire a
  correction while its verified-edit batch is still settling;
- the installed 2026-08-01 physical-HID pass corrected 20/20 words, retained
  valid focus and fixture evidence, and recorded 20 visible overlay ranges with
  zero lifecycle hides after settling;
- a fresh installed pass invoked Change Back on the fifth of 20 overlays and
  opened a later sibling menu with a real pointer event. Bear stayed frontmost,
  only the selected range changed, and all unaffected overlays survived.
