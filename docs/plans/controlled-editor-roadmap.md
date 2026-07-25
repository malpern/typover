# Controlled-editor roadmap

- Status: Active
- Updated: 2026-07-25
- Principle: Make the reference interaction highly functional before investing
  in Bear integration.

## Goal

Build a trustworthy AppKit and TextKit reference editor for automatic, visible,
reversible correction. The editor should establish correction quality,
transaction safety, performance, and interaction behavior before Typover
attempts to reproduce those capabilities through Accessibility in another app.

## Completed milestones

### 1. Reversible correction interaction

- [x] Replace only the exact misspelled range.
- [x] Preserve the original and replacement in `TypoverCore`.
- [x] Render a persistent light-gray squiggle.
- [x] Provide Change Back, alternatives, Keep, and Undo.
- [x] Preserve the caret and selection through replacement.

### 2. Modern TextKit reference editor

- [x] Use a TextKit 2-backed `NSTextView`.
- [x] Track viewport layout with the macOS 27 callback.
- [x] Keep annotations aligned while scrolling a long document.
- [x] Keep corrections clickable after leaving and returning to the viewport.

### 3. Local Apple spelling engine

- [x] Replace the deterministic demo rule with `NSSpellChecker`.
- [x] Use Apple’s ranked guesses when no separate automatic candidate exists.
- [x] Feed accepted, reverted, and edited responses back to Apple.
- [x] Keep spelling lookup entirely on device.
- [x] Keep the candidate source behind a replaceable engine protocol.

### 4. Cursor-relative expanded policy

- [x] Correct a newly completed word at the active caret anywhere in the
      document.
- [x] Leave existing surrounding text unchanged.
- [x] Trigger after whitespace and sentence punctuation.
- [x] Support Unicode letters, combining accents, and internal apostrophes.
- [x] Preserve lowercase, Capitalized, and ALL-CAPS patterns.
- [x] Protect mixed-case names, brands, and identifiers.
- [x] Avoid correction during marked-text composition.
- [x] Verify earlier insertions preserve later correction annotations.

The complete behavior contract is in
[cursor-relative correction behavior](../correction-behavior.md).

### 5. Local preference learning and outcome statistics

- [x] Remember a chosen alternative for the same typo and language.
- [x] Remember an identifiable direct manual edit as the next replacement.
- [x] Treat Change Back as a local suppression preference.
- [x] Apply remembered preferences before the next eligible replacement.
- [x] Keep menu-driven preference changes consistent with Undo and Redo.
- [x] Persist preferences and correction outcomes locally across relaunches.
- [x] Count applied, kept, reverted, alternative, manual-edit, overridden, and
      unresolved corrections without storing document text in statistics.
- [ ] Add a user-facing statistics and preference-management surface.

## Next milestone: evaluation and editing robustness

Before adding a contextual model, build a repeatable local harness around the
Apple spelling baseline.

### Correction corpus

- [x] Create a checked-in corpus of expected corrections and expected
      unchanged words.
- [x] Include insertions, deletions, substitutions, transpositions,
      capitalization, apostrophes, accented words, mixed-case names, technical
      vocabulary, and multilingual examples.
- [x] Record candidate source, selected replacement, alternatives, language,
      and lookup duration without logging private user text.
- [x] Report false-positive rate, missed-correction rate, and median/tail
      latency.
- [x] Keep numeric confidence out of the product unless later calibration
      proves it useful.

Corpus v1 contains 131 synthetic cases. Its 106 reviewed cases gate the test
suite; 25 names, technical terms, and multilingual expectations remain
provisional until human review. Run `swift run TypoverEval` for a readable
report or `swift run TypoverEval --json` for structured per-case output. The
initial macOS 27 baseline has no approved false positives or missed
corrections. Apple leaves the provisional French `cafe` example unchanged.

### Editor stress matrix

- [ ] Exercise rapid typing across many consecutive corrections.
- [ ] Exercise multiple corrections before and after the caret.
- [ ] Verify Undo and Redo through correction, alternative, Change Back, and
      Keep sequences.
- [ ] Verify edits immediately before, inside, and after an annotated
      correction.
- [ ] Verify paste, selection replacement, dictation, and marked-text input do
      not cause stale or duplicate corrections.
- [ ] Verify punctuation, paragraph boundaries, scrolling, wrapping, and large
      documents.
- [ ] Add structured diagnostics for rejected or stale proposals without
      recording document content.

### Acceptance criteria

- The corpus is deterministic on the supported macOS and language baseline.
- No expected-unchanged example is automatically modified.
- Rapid typing never applies a proposal to stale text.
- Undo and Redo preserve understandable correction state.
- Existing annotations remain aligned or are explicitly invalidated.
- Lookup and editing latency are measured before an AI model is introduced.

The first two criteria and lookup-latency measurement are now enforced for the
approved corpus. Editing latency remains part of the editor stress matrix.

## Following milestone: contextual local intelligence

After the spelling baseline is measurable, evaluate Apple’s on-device model
for mistakes that require sentence context, such as valid-word substitutions.

- Operate on a bounded recently completed sentence.
- Return structured exact-range proposals rather than rewritten prose.
- Run asynchronously and discard stale proposals.
- Apply the same visible, reversible transaction and safety policy.
- Never use a network or Private Cloud Compute fallback.
- Benchmark correction quality, false positives, latency, memory, energy, and
  cold start against the Apple spelling baseline.

## Later comparison: open-source local models

Use the same corpus, metrics, and engine boundary to benchmark selected
open-source models running locally. Do not change the editor interaction to
accommodate a particular model.

## Bear gate

Begin the Bear compatibility spike after:

- the evaluation corpus and editor stress matrix pass;
- the correction transaction has stable diagnostics;
- the reference behavior is documented well enough to identify which
  compromises come from Accessibility or Bear rather than from Typover itself.
