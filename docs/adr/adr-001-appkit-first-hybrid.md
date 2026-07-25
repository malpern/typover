# ADR-001: Use an AppKit-first hybrid architecture

- Status: Accepted
- Date: 2026-07-25

## Context

Typover’s defining interaction is not a conventional settings interface. It
must observe nearby text, replace the smallest safe character range, preserve
the original, render a persistent light-gray correction mark, hit-test that
mark, and restore or replace an individual correction without disturbing later
edits.

The interaction requires precise control over:

- TextKit text storage, layout, attributes, and character-range geometry;
- selection, caret, scrolling, and Undo behavior;
- nonactivating overlay windows and coordinate conversion;
- macOS Accessibility APIs and event taps;
- menu-bar and background-agent lifecycle.

SwiftUI is productive for ordinary application surfaces, but these text-system
and window-management requirements sit below its strongest abstraction layer.
The primary reason to prefer AppKit here is control and predictable behavior,
not an assumption that SwiftUI is inherently too slow.

Choosing AppKit does not remove the central platform limitation. Typover cannot
use AppKit to attach native text attributes to content owned and rendered by
another application. AppKit can provide a complete controlled-editor
experience and a more capable external overlay, while a truly native
system-wide annotation may still require a new Apple text-system API.

## Decision

Typover will use an **AppKit-first hybrid architecture**.

- Pure Swift owns correction decisions, confidence policy, range-level diffs,
  and reversible correction history.
- AppKit and TextKit own the defining correction interaction, including the
  controlled-editor research harness, text-range geometry, annotations,
  hit-testing, menus, and Undo integration.
- AppKit owns system integration such as Accessibility observation, event taps,
  nonactivating panels, and overlay positioning.
- SwiftUI remains available for conventional product surfaces such as
  onboarding, permission setup, settings, dictionaries, application
  exclusions, correction history, and diagnostics.
- Framework boundaries will keep the correction engine, Accessibility client,
  annotation renderer, and product UI independently testable.

The SwiftUI shell frames and hosts the controlled editor through
`NSViewRepresentable`. It does not own the correction behavior; the embedded
AppKit and TextKit editor remains the reference implementation for the defining
interaction.

## Initial implementation sequence

1. Keep `TypoverCore` UI-independent.
2. Add a controlled AppKit/TextKit editor.
3. Automatically correct one high-confidence word using a range-level edit.
4. Render a persistent light-gray squiggle on that correction.
5. Let the writer select the mark and restore the original word.
6. Preserve correct selection, caret, scrolling, and Undo behavior.
7. Only then evaluate Accessibility-based replacement and external overlays in
   other applications.

## Consequences

### Benefits

- The central interaction can use TextKit’s native model rather than
  approximating text layout through SwiftUI.
- Overlay windows and background behavior remain under explicit AppKit control.
- SwiftUI can still accelerate lower-risk product surfaces.
- A UI-independent core supports focused tests and alternative spell engines.
- The controlled editor provides a reference implementation against which
  system-wide compromises can be measured.

### Costs

- The project will maintain both AppKit and SwiftUI knowledge and integration
  points.
- AppKit code is generally more explicit and requires more lifecycle and state
  management.
- Some shared design components may need separate AppKit and SwiftUI
  implementations.
- External overlays will remain less reliable than annotations rendered by the
  application that owns the text.

## Revisit when

Reconsider this decision if SwiftUI gains first-class APIs for attributed
editable text, persistent text-range annotations, precise range geometry, and
nonactivating overlay behavior that satisfy the controlled-editor interaction
without AppKit escape hatches.
