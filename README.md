# Typover

Typover is a native macOS experiment in confident, reversible autocorrection.

Instead of waiting for someone to click a misspelling, Typover applies a
high-confidence correction automatically, leaves a quiet light-gray mark under
the changed text, and lets the writer restore the original or choose another
suggestion.

> Typover fixes mistakes as you type—and always lets you go back.

## The interaction

1. The writer completes a word or sentence.
2. Typover evaluates only the nearby text needed for context.
3. A high-confidence correction replaces the smallest possible character
   range.
4. The corrected text retains a subtle, persistent mark.
5. Clicking the mark offers the original text and alternative corrections.

Typover must not replace an entire text field or document. Whole-field
replacement disrupts selection, formatting, Undo, collaboration, and long-form
writing.

## Why this is an experiment

macOS Accessibility APIs can read and replace text in many applications, but a
third-party app cannot reliably add a native inline annotation inside every
editor. The first research goal is to establish which parts can be built today
and which require cooperation from AppKit, TextKit, or Apple’s spell-checking
frameworks.

## Research milestones

- Model an individual correction and its reversible history. ✅
- Evaluate word- and sentence-boundary correction without whole-field writes.
- Measure range replacement across native and web-based editors.
- Prototype a light-gray correction mark in a controlled TextKit editor. ✅
- Evaluate an external overlay for applications that do not expose formatting.
- Document the boundary between `NSSpellChecker`, `NSSpellServer`, TextKit, and
  Accessibility.

## Build

Typover currently contains a SwiftUI product shell around a controlled AppKit
and TextKit editor. Type `teh` followed by Space to exercise the first
deterministic correction, then click its light-gray squiggle to change it back
or keep it.

```bash
swift build
swift test
swift run Typover
```

Requires macOS 27 or later and Swift 6.4 or later. The research build uses
TextKit 2 and the viewport-layout hooks introduced for `NSTextView` in macOS
27.

## Architecture

Architecture decisions are recorded in [docs/adr](docs/adr/README.md). Typover
uses an AppKit-first hybrid architecture: AppKit and TextKit own the defining
correction interaction, while SwiftUI remains available for conventional
product surfaces.

Active research work is described in [docs/plans](docs/plans/README.md),
beginning with the Bear compatibility spike.

## Status

Controlled-editor interaction prototype. No system-wide text monitoring or
replacement is implemented yet.

## License

Not yet selected.
