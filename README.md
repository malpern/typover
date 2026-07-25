# Typover

Typover is a native macOS experiment in careful, reversible autocorrection.

Instead of waiting for someone to click a misspelling, Typover applies a
small, clearly eligible correction automatically, leaves a quiet light-gray
mark under the changed text, and lets the writer restore the original or choose
another suggestion.

> Typover fixes mistakes as you type—and always lets you go back.

## The interaction

1. The writer completes a word or sentence.
2. Typover evaluates only the nearby text needed for context.
3. A correction that passes Typover’s explicit safety rules replaces the
   smallest possible character range.
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
and TextKit editor. It uses Apple’s on-device spelling service to propose
corrections, then applies only those that pass a deliberately narrow binary
policy. After a sentence is completed, Apple’s on-device system language model
can also detect one contextual valid-word mistake. Type a typo followed by
Space or sentence punctuation, then click its light-gray squiggle to change it
back or choose another spelling. Corrections follow the active caret even when
editing an earlier part of the document.

```bash
swift build
swift test
swift run Typover
```

Requires macOS 27 or later and Swift 6.4 or later. The research build uses
TextKit 2 and the viewport-layout hooks introduced for `NSTextView` in macOS
27.

## Evaluate corrections

The checked-in synthetic corpus measures Typover's Apple spelling baseline
without reading or recording personal document text:

```bash
swift run TypoverEval
swift run TypoverEval --json
swift run TypoverEval --contextual
swift run TypoverEval --contextual --json
```

Reviewed spelling cases gate the test suite. Provisional names, technical
vocabulary, and multilingual examples are reported separately until their
expectations receive human review. The contextual corpus is a benchmark rather
than a deterministic gate because Apple can update the system model with macOS.

## Architecture

Architecture decisions are recorded in [docs/adr](docs/adr/README.md). Typover
uses an AppKit-first hybrid architecture: AppKit and TextKit own the defining
correction interaction, while SwiftUI remains available for conventional
product surfaces.

Active research work is described in [docs/plans](docs/plans/README.md),
beginning with the controlled-editor evaluation and robustness milestone. Bear
compatibility remains documented but deferred until the reference prototype is
highly functional.

The controlled editor’s correction rules are captured in
[docs/correction-behavior.md](docs/correction-behavior.md).

## Status

Controlled-editor interaction prototype with Apple spelling candidates,
bounded Apple Intelligence sentence analysis, binary automatic-correction
policies, ranked spelling alternatives, Change Back, and Undo. Explicit
spelling alternatives, manual edits, and Change Back choices are learned
locally, and aggregate correction outcomes are retained without document text.
Contextual overrides are measured but do not create unsafe global rules for
otherwise valid words. No system-wide text monitoring or replacement is
implemented yet.

## License

Not yet selected.
