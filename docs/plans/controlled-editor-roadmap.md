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
- [x] Provide Change Back, alternatives, and Undo.
- [x] Preserve the caret and selection through replacement.

### 2. Modern TextKit reference editor

- [x] Use a TextKit 2-backed `NSTextView`.
- [x] Track viewport layout with the macOS 27 callback.
- [x] Keep annotations aligned while scrolling a long document.
- [x] Keep corrections clickable after leaving and returning to the viewport.

### 3. Local Apple spelling engine

- [x] Replace the deterministic demo rule with `NSSpellChecker`.
- [x] Use Apple’s ranked guesses when no separate automatic candidate exists.
- [x] Feed reverted and edited responses back to Apple.
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
- [x] Count applied, reverted, alternative, manual-edit, overridden, and
      unresolved corrections without storing document text in statistics.
- [x] Add a user-facing statistics and preference-management surface.

## Completed milestone: evaluation and editing robustness

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

- [x] Exercise rapid typing across many consecutive corrections.
- [x] Exercise multiple corrections before and after the caret.
- [x] Verify Undo and Redo through correction, alternative, and Change Back
      sequences.
- [x] Verify edits immediately before, inside, and after an annotated
      correction.
- [x] Verify paste, selection replacement, and marked-text input do not cause
      stale or duplicate corrections.
- [x] Verify punctuation, paragraph boundaries, scrolling, wrapping, and large
      documents.
- [x] Add structured diagnostics for rejected or stale proposals without
      recording document content.

The AppKit stress harness now drives the production `TypoverTextView` with a
deterministic correction engine. It covers 10 rapid correction triplets,
stale-text rejection during lookup, cursor moves, annotation shifting and
invalidation, selection replacement, paste suppression, marked-text
composition, punctuation and paragraph triggers, narrow wrapping, viewport
movement, a 600-paragraph document, and Undo/Redo for every correction action.
Diagnostics retain only a reason, correction identifier, numeric range,
document length, and timestamp; their in-memory buffer is capped at 200
entries. Successful correction transactions also retain a capped, text-free
duration sample so editing latency can be measured before adding a model.

### Acceptance criteria

- The corpus is deterministic on the supported macOS and language baseline.
- No expected-unchanged example is automatically modified.
- Rapid typing never applies a proposal to stale text.
- Undo and Redo preserve understandable correction state.
- Existing annotations remain aligned or are explicitly invalidated.
- Lookup and editing latency are measured before an AI model is introduced.

The first two criteria and lookup-latency measurement are enforced for the
approved corpus. Transaction behavior and editing-latency sampling are covered
by the AppKit stress harness.

## Completed milestone: contextual local intelligence

Apple’s on-device model now handles mistakes that require sentence context,
such as valid-word substitutions.

- [x] Operate on only the most recently completed sentence, capped at 400 UTF-16
      code units.
- [x] Request structured output from `SystemLanguageModel.default`.
- [x] Reduce full-sentence model output to the smallest changed word or phrase,
      then require a unique exact match in the captured sentence.
- [x] Run asynchronously and discard proposals when the captured sentence
      changed, while allowing typing to continue after it.
- [x] Apply the same light-gray annotation, Change Back, and Undo transaction.
- [x] Check model and locale availability and never use a network or Private
      Cloud Compute fallback.
- [x] Add a separate balanced contextual corpus and benchmark command.
- [x] Expand the corpus to 48 reviewed cases: 24 corrections and 24 unchanged
      controls.
- [x] Compare conservative and focused-grammar prompt profiles.
- [x] Surface current on-device model availability and per-source private
      activity statistics.
- [x] Verify contextual Undo/Redo and correction at an earlier cursor position
      in a long document.

Run `swift run TypoverEval --contextual` for the contextual benchmark. On the
macOS 27 development machine, the conservative prompt passed 40 of 48 cases
with no false positives, wrong applied corrections, or model errors. It
produced eight safe misses. Median lookup latency was about 1.39 seconds and
p95 was about 3.31 seconds. An intermediate raw-model run proposed one
unrelated substitution; the deterministic lexical-safety gate rejected it, and
the evaluator now reports the same effective behavior the editor would apply.

The focused-grammar prompt was less accurate and slower in the comparison, so
it is retained only as a benchmark profile. Run
`swift run TypoverEval --contextual --all-prompt-profiles` to compare both.
These results are development snapshots rather than permanent quality
guarantees because Apple can update the system model with OS releases.

### Correction scope and sentence rewrites

- [x] Keep Careful as the default single-edit contextual behavior.
- [x] Add a persisted Comprehensive scope for up to three objective spelling,
      punctuation, or grammar changes.
- [x] Apply a multi-edit result atomically while preserving a separate visible
      annotation and restoration menu for each change.
- [x] Add a separate Comprehensive-only setting that permits one completed
      sentence to be rewritten for clarity.
- [x] Preserve the original sentence, annotate the rewrite, and support Change
      Back plus one-step Undo and Redo.
- [x] Keep the Apple model path entirely on device with no automatic network
      fallback.

On the macOS 27 development machine, the Careful scope passed 40 of 48 cases
with eight safe misses. After the rewrite-safety work, Comprehensive passed 43
of 48 with five safe misses and no false positives, wrong applied corrections,
or model errors. Its final median latency was about 1.93 seconds and p95 was
about 3.05 seconds.

### Rewrite quality and operating cost

- [x] Add a separate safety-weighted sentence-rewrite corpus.
- [x] Define automatic acceptance criteria for unwarranted changes, protected
      facts, concrete clarity signals, and tone markers.
- [x] Keep variable but structurally valid rewrites in a human-review queue.
- [x] Measure first-request and warm latency, process-attributed energy,
      memory, neural footprint, and wakeups.
- [x] Reject unsafe comprehensive fallbacks involving code identifiers,
      quoted commands, prompt-like text, duplicate words, adjacent gerunds,
      and regional collective-noun agreement.

The 35-case baseline has 16 intended rewrite cases and 19 unchanged controls.
All controls remained unchanged, 14 intended cases produced candidates, both
misses were safe tone-preservation rejections, and all 14 candidates passed
human review. The final run had no preservation failures or model errors.
Warm median latency was 1.71 seconds and p95 was 2.88 seconds. Detailed scope,
results, and operating-cost caveats are in the
[sentence-rewrite benchmark](../testing/sentence-rewrite-benchmark.md).

## Model decision checkpoint

- [x] Benchmark inexpensive OpenAI and Anthropic models against the same rewrite
      corpus.
- [x] Benchmark stronger OpenAI and Anthropic models against the same rewrite
      corpus.
- [x] Keep Apple's on-device system model as Typover's default product model.
- [x] Add an explicit Preferences switch for Apple, GPT-5.6 Terra, and Claude
      Sonnet 5 without introducing automatic cloud fallback.
- [x] Keep cloud credentials in Add Secret's encrypted store rather than
      Typover preferences.

Apple remains the default product choice. GPT-5.6 Terra matched the Apple
baseline on the small reviewed corpus, which shows that stronger cloud models
are useful evaluation references. A writer can now explicitly select Terra or
Claude Sonnet 5 in Preferences, with a clear network and cost disclosure. That
choice is never an automatic fallback, and API keys remain in Add Secret's
encrypted store rather than Typover settings.

## Parallel validation track: natural-writing and cross-version validation

- [ ] Grow the rewrite benchmark from 35 to at least 500 cases, including at
      least 300 diverse unchanged controls.
- [ ] Add consented, de-identified natural writing samples that contain no
      private text.
- [ ] Test the correction and rewrite corpora against every macOS system-model
      version Typover supports.
- [ ] Keep false-positive avoidance ahead of raw correction coverage.

The first cloud reference run used a deliberately shorter prompt. Claude Haiku
4.5 was faster than the Apple baseline but introduced one regional false
positive and one meaning-preservation failure. Typover's rules removed the
false positive but did not catch the meaning change. Two GPT-5 nano runs
preserved every control but produced only zero or one candidate out of 16
intended rewrites; its sole proposal also lost a protected fact. The cheap
OpenAI model is therefore not useful for this rewrite path under the shared
minimal prompt. The smarter tier was materially better: GPT-5.6 Terra matched
the Apple baseline's 14 accepted rewrites with no detected safety failure, and
Claude Sonnet 5 produced 13 accepted rewrites with no detected safety failure.
Terra is now the strongest cloud reference, while Apple remains the product
default because it is local and the corpus is still too small to justify a
model-stack decision. See the
[remote-model comparison](../testing/remote-model-comparison.md).

## Later comparison: open-source local models

Use the same corpus, metrics, and engine boundary to benchmark selected
open-source models running locally. Do not change the editor interaction to
accommodate a particular model. This comparison is useful before committing to
a long-term model stack, but it does not block the initial Bear compatibility
spike.

## Bear gate

Begin the Bear compatibility spike after:

- the evaluation corpus and editor stress matrix pass;
- the correction transaction has stable diagnostics;
- the reference behavior is documented well enough to identify which
  compromises come from Accessibility or Bear rather than from Typover itself.

The local-model foundation, operating-cost snapshot, expanded corpus, and
candidate review now satisfy this gate. The Bear compatibility spike is the
next implementation milestone. Natural-writing expansion, cross-version
validation, and open-source comparison can continue without blocking it.

## Completed implementation milestone: Bear Phase 1

Build the read-only Accessibility capability probe described in the
[Bear compatibility spike](bear-compatibility-spike.md).

- [x] Add the `TypoverAccessibility` boundary and structured capability model.
- [x] Locate the current Bear window's sole `AXTextArea` by role traversal,
      without a fragile element index, and report whether it actually holds
      keyboard focus.
- [x] Report required attributes, writability, parameterized range geometry,
      and relevant Accessibility notification registrations.
- [x] Read the caret and a tightly bounded context without printing or
      persisting document text.
- [x] Record a provisional go decision for exact-range replacement and overlay
      geometry.
- [x] Register selection, value, focus, window, and layout observers while the
      Bear editor actually holds focus in a disposable note.
- [x] Confirm that read-only caret movement emits `AXSelectedTextChanged`
      without capturing note text.

Phase 1 is diagnostic only: it does not modify a Bear note, draw an overlay, or
request a Bear API token.

## Completed implementation milestone: Bear Phase 2

Implement and verify one exact selected-range replacement in the dedicated
disposable note:

- capture and verify the expected target range;
- replace only `AXSelectedText`, never the complete `AXValue`;
- restore the caret relative to the inserted text;
- verify a tightly bounded local result;
- create a correction record only after verification succeeds;
- measure Bear's native Undo result before expanding the experiment.

The exact-range transaction now passes deterministic stale-target,
idempotency, caret-delta, selection-failure, surrounding-context, and
correction-record tests. A live Accessibility transaction in the tag-free
disposable note changed only `teh` to `the`, restored the original caret, and
verified its local postconditions. Native Command-Z restored and selected the
original word.

## Completed implementation milestone: Bear Phase 3

Typover now has an independent Change Back transaction and correction-anchor
state that:

- preserves bounded context fingerprints with the verified correction record;
- re-anchors after edits before or after the corrected range;
- restores only when the replacement remains uniquely identifiable;
- refuses ambiguous or stale restoration without editing;
- keeps native Undo behavior documented but does not depend on the Undo stack for
  Typover's menu action.

The deterministic restoration suite passes, and an opt-in live Bear test
applied and independently restored the synthetic typo without invoking native
Undo.

## Completed implementation milestone: Bear Phase 4

Typover now resolves `AXBoundsForRange` through the correction anchor, returns
precise line fragments for wrapped targets, hides offscreen or stale ranges,
and distinguishes unsupported, failed, and invalid geometry. The live matrix
passed across formatting, wrapping, scrolling, zoom, attachment-adjacent text,
and separate Bear windows.

## Completed implementation milestone: Bear Phase 5

Typover now renders each verified Bear geometry fragment in a borderless,
nonactivating, click-through AppKit panel. Accessibility invalidations hide and
recompute the mark, a bounded fallback refresh covers missed layout events, and
frontmost-app gating prevents the overlay from following the user into another
application or Space. The live synthetic correction stayed aligned, hid across
an application switch and manual supersession, returned only after fresh
verification, and restored the fixture afterward.

## Completed implementation milestone: Bear Phase 6

The squiggle is a narrow nonactivating hit target with a native menu, Change
Back, verified alternatives, one Accessibility button, and a Bear-only keyboard
shortcut. Guarded delayed selection stabilization handles Bear's post-edit
caret update without overriding a newer user selection.

## Next implementation milestone: Bear Phase 7

Run the complete interaction robustness matrix across long notes, repeated
typos, rapid typing, note and window switches, relaunches, appearance changes,
Markdown constructs, attachments, and the previous supported Bear release.
The opt-in fixture now resolves one exact disposable-note title through Bear's
local CLI and opens its stable note ID directly before waiting for the focused
Accessibility editor. Missing, fuzzy, duplicate, malformed, and failed-open
results fail closed. This removes the transient search-results dependency; a
permissioned live app-host pass and the remaining matrix rows are still needed
before treating the interaction as an unattended gate.

The continued-typing slice is implemented deterministically. A unique expected
correction remains anchored when either its leading or trailing context changes,
so typing beside the word does not remove Change Back or alternatives. Both
sides changed and duplicate one-sided matches fail closed. The real-Bear
overlay harness contains the same sequence. The permissioned app host has now
passed baseline correction, adjacent continued typing, note switching, safe
return, manual supersession, a fresh second correction, and Revert while
preserving an adjacent synthetic typing tail. Multiple-window interaction and
Bear relaunch now pass as well. Bear termination explicitly ends the old
interaction, and a fresh correction succeeds after relaunch without restarting
Typover. Full dark visual review, full VoiceOver navigation, and the previous
Bear release remain. Typover relaunch and functional correction with VoiceOver
enabled and in Dark appearance have passed.
