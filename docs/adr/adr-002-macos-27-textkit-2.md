# ADR-002: Target macOS 27 and TextKit 2 for the editor lab

- Status: Accepted
- Date: 2026-07-25

## Context

The first controlled editor proved Typover’s correction interaction with an
`NSTextView` embedded in SwiftUI through `NSViewRepresentable`. Its initial
implementation manually assembled `NSTextStorage`, `NSLayoutManager`, and
`NSTextContainer`, which forced the editor onto TextKit 1.

At WWDC26, Apple reaffirmed `NSViewRepresentable` as the supported way to embed
`NSTextView` in a SwiftUI app. Apple also made `NSTextView` conform publicly to
`NSTextViewportLayoutControllerDelegate` in macOS 27. An `NSTextView` subclass
can now observe viewport layout directly while retaining the framework text
view’s editing, selection, accessibility, text-input, and Undo behavior.

The viewport hooks are especially relevant to Typover. A persistent correction
annotation must update after edits, wrapping, scrolling, and other layout
changes without requiring a custom text editor implementation.

## Decision

The controlled editor research target is macOS 27.

- Keep SwiftUI as the application lifecycle and product shell.
- Continue embedding the editor through `NSViewRepresentable`.
- Construct `NSTextView` with `usingTextLayoutManager: true`.
- Use `NSTextLayoutManager` text segments for correction geometry and hit
  testing.
- Use the macOS 27 viewport-layout callbacks to invalidate annotation drawing
  after TextKit lays out or relays out the visible document.
- Do not maintain a TextKit 1 fallback during the research phase.

This decision changes the package minimum from macOS 15 to macOS 27 and the
documented Swift requirement from 6.2 to 6.4.

## Consequences

### Benefits

- The reference editor uses Apple’s current text architecture.
- Typover retains the complete behavior of the framework `NSTextView`.
- Correction geometry follows TextKit 2’s layout rather than glyph indexes from
  the legacy layout manager.
- The viewport callback provides a direct place to respond to scrolling and
  relayout.
- The controlled editor better represents the APIs available to a new macOS 27
  application.

### Costs

- Typover cannot run on macOS 26 or earlier during this research phase.
- TextKit 2 uses abstract text locations and ranges, requiring explicit
  conversion from the UTF-16 ranges used by AppKit editing APIs.
- Back-deployment will require a separate decision and measured fallback rather
  than an accidental dependency on legacy TextKit.

## Revisit when

Reconsider the minimum deployment target when Typover moves from platform
research toward distribution. Any compatibility path must preserve the same
range safety, annotation alignment, accessibility, and Undo behavior before it
is accepted.

## References

- [Use SwiftUI with AppKit and UIKit — WWDC26](https://developer.apple.com/videos/play/wwdc2026/272/)
- [Elevate your app’s text experience with TextKit — WWDC26](https://developer.apple.com/videos/play/wwdc2026/370/)
