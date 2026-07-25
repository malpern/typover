# ADR-003: Use local correction engines behind a binary policy

- Status: Accepted
- Date: 2026-07-25

## Context

Typover needs a correction source that is fast enough to run while someone is
typing, private enough for long-form writing, and replaceable so different
approaches can be measured fairly.

Apple’s spelling system is already local and provides ranked guesses, and in
some cases a separate automatic-correction candidate. It does not provide a
calibrated probability that a candidate is correct. Adding a made-up numeric
confidence value would make the prototype appear more certain than its evidence
supports.

Future engines may use Apple-provided on-device language models or open-source
models running locally. Those engines should not require changes to the editor,
annotation, restoration, or Undo behavior.

## Decision

Typover will separate candidate generation from the decision to edit text.

- `CorrectionEngine` returns a primary correction, alternatives, its source,
  language, and lookup duration.
- `AutomaticCorrectionPolicy` makes a transparent yes-or-no decision about
  whether a proposal is eligible for automatic replacement.
- The first policy accepts only lowercase ASCII words of a bounded length whose
  primary correction is one insertion, deletion, substitution, or adjacent
  transposition away.
- `NSSpellChecker` is the first production candidate source. It runs on device,
  uses the writer’s Apple spelling resources, and receives accepted, reverted,
  and edited feedback.
- The correction model and UI contain no numeric confidence score.
- Typover will not send writing to a network service or silently fall back to a
  cloud model.

## Future model evaluation

After the controlled editor is reliable, Typover may benchmark an
Apple-provided on-device model and selected open-source local models through the
same engine boundary. The harness should measure:

- correction accuracy and false-positive rate on a representative typo corpus;
- median and tail latency, including cold start;
- memory, energy, and model-size cost;
- quality of ranked alternatives;
- behavior with names, domain language, capitalization, and multilingual text.

Numeric confidence scoring is explicitly deferred. It should be considered only
after benchmark data exists and only if a calibrated score improves decisions
over the binary policy. It is a future feature, not part of the first
prototype.

## Consequences

### Benefits

- The initial behavior is simple to understand, test, and tune.
- Apple spelling provides a fast local baseline without coupling Typover to one
  future model.
- The editor can compare candidate sources without changing its reversible
  interaction.
- Typover avoids presenting an unvalidated score as meaningful certainty.

### Costs

- The first policy intentionally misses corrections that require more context
  or more than one edit.
- Capitalized, non-ASCII, and multilingual words remain unchanged in the
  initial prototype.
- Model benchmarking and any useful calibration require a curated evaluation
  corpus.

## Revisit when

Revisit the policy after the controlled editor has collected a representative
offline test corpus and the Apple spelling baseline has measured false-positive
and missed-correction rates.
