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
   smallest possible character range. An explicitly enabled sentence rewrite
   is the bounded exception.
4. The corrected text retains a subtle, persistent mark.
5. Clicking the mark offers the original text and alternative corrections.

Typover must not replace an entire text field or document. Whole-field
replacement disrupts selection, formatting, Undo, collaboration, and long-form
writing. An optional rewrite is limited to one newly completed sentence and
remains visible and reversible as one transaction.

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
corrections, then applies only those that pass explicit deterministic rules.
After a sentence is completed, Apple’s on-device system language model can
also detect contextual mistakes. Settings provide a conservative `Careful`
scope, a broader `Comprehensive` scope for objective spelling, punctuation, and
grammar, and a separate Comprehensive-only opt-in for one-sentence rewrites.
Apple Intelligence is the default contextual model. An advanced model picker
can instead use GPT-5.6 Terra or Claude Sonnet 5 after an API key is configured
through Add Secret. Cloud selection is explicit and sends only the newly
completed sentence to that provider; it is never an automatic fallback.
Type a typo followed by Space or sentence punctuation, then click its
light-gray squiggle to change it back or choose another spelling. Corrections
follow the active caret even when editing an earlier part of the document.

```bash
swift build
swift test
swift run Typover
```

Bear Accessibility development must use the stable signed app bundle rather
than `swift run` or an ad-hoc signature:

```bash
./Scripts/build-development-app.sh
open .build/Typover.app
```

The script uses the installed Apple Development identity so macOS can retain
Typover’s Accessibility approval across rebuilds. Ad-hoc signing identifies
each new executable by its changing code hash and silently invalidates the
previous approval.

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
swift run TypoverEval --contextual --scope comprehensive
swift run TypoverEval --contextual --all-prompt-profiles
swift run TypoverEval --rewrite
swift run TypoverEval --rewrite --json
swift run TypoverEval --remote-rewrite --provider anthropic
swift run TypoverEval --remote-rewrite --provider openai
swift run TypoverEval --remote-rewrite --provider all --smarter-models
```

Reviewed spelling cases gate the test suite. Provisional names, technical
vocabulary, and multilingual examples are reported separately until their
expectations receive human review. The contextual corpus is a benchmark rather
than a deterministic gate because Apple can update the system model with macOS.
The rewrite corpus separately measures unwarranted rewrites, fact preservation,
human-reviewed quality, latency, and process-attributed operating cost.
Remote-model commands send only the checked-in synthetic rewrite corpus to the
selected provider and require that provider's API credential in the process
environment. The app can also resolve those same named credentials from Add
Secret's encrypted store without copying them into Typover preferences.

## Architecture

Architecture decisions are recorded in [docs/adr](docs/adr/README.md). Typover
uses an AppKit-first hybrid architecture: AppKit and TextKit own the defining
correction interaction, while SwiftUI remains available for conventional
product surfaces.

Active research work is described in [docs/plans](docs/plans/README.md),
including the completed controlled-editor milestones and the active Bear
compatibility spike. Bear Phase 6 now combines guarded exact-range replacement,
independent Change Back, content-free range geometry, and a clickable
nonactivating light-gray annotation with Apple Spelling alternatives. Phase 7
now preserves a unique correction while the writer continues typing on one
side, while ambiguous or two-sided changes still fail closed. Phase 8 now
automatically corrects verified word completions and keeps up to 24 recent Bear
corrections independently annotated and reversible.

The controlled editor’s correction rules are captured in
[docs/correction-behavior.md](docs/correction-behavior.md).

## Status

Controlled-editor interaction prototype with Apple spelling candidates,
bounded user-selectable contextual sentence analysis, user-selectable
correction scope, optional sentence rewriting, ranked spelling alternatives,
Change Back, and Undo. Apple Intelligence remains the default; OpenAI and
Anthropic are explicit cloud options. Explicit
spelling alternatives, manual edits, and Change Back choices are learned
locally, and aggregate correction outcomes are retained without document text.
Contextual overrides are measured but do not create unsafe global rules for
otherwise valid words. Bear observation and exact-range replacement now exist
as explicit test transactions. Change Back re-anchors from bounded,
content-private context fingerprints and refuses stale or ambiguous targets;
visible Bear corrections now produce guarded screen-space fragments and a
narrow interactive AppKit squiggle while offscreen, background, or stale
corrections produce no visible overlay. The concise Bear menu offers Revert
followed by verified alternatives, with no inert “Keep Existing” row. A
guarded delayed caret repair handles Bear's asynchronous selection update
without overriding a newer user selection. A conservative one-sided anchor
keeps the menu available during continued typing without allowing newly typed
text into the replacement range. The Phase 7 live harness now opens one exact
disposable note by stable Bear note ID instead of inheriting search-result
selection state. Settings and the native **Preview Selected Bear Typo** app-menu
command share one guarded preview coordinator. The permissioned app has passed
baseline correction, adjacent continued typing, note switching, safe return,
manual supersession, a fresh second correction, and accessible Revert while
preserving newly typed adjacent text. Automatic Bear correction now passes the
first ordinary `teh` plus Space live check. Installed multi-correction,
composition, Undo/Redo behavior, and the remaining robustness matrix still need
permissioned live checks; their deterministic safety coverage passes.

## License

Not yet selected.
