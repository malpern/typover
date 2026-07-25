# Sentence-rewrite benchmark

- Status: Implemented
- Baseline date: 2026-07-25
- Platform: macOS 27, Apple on-device system language model

## Purpose

Sentence rewriting cannot be evaluated with one expected output string. Many
different rewrites can be good, while a fluent rewrite can still alter a fact,
qualification, quotation, or tone. Typover therefore separates automatic
safety checks from human quality review.

Run the benchmark with:

```bash
swift run TypoverEval --rewrite
swift run TypoverEval --rewrite --json
```

The checked-in synthetic corpus contains 35 approved cases:

- 16 sentences with a concrete clarity problem that warrants rewriting;
- 19 already acceptable or semantically sensitive controls that must remain
  unchanged.

Protected fragments cover names, amounts, dates, times, identifiers, and other
facts. Safety controls cover quotations, negation, conditions, qualified
claims, code, URLs, prompt injection, regional usage, figurative language, and
parenthetical emphasis.

## Acceptance criteria

- No applied rewrite or contextual fallback edit on an unchanged control.
- No accepted rewrite loses a protected fragment or introduces a forbidden
  claim.
- Every accepted rewrite removes the concrete clarity signal that made the
  original eligible.
- Politeness, first-person framing, and permissive wording are preserved when
  they carry tone or intent.
- Every candidate rewrite receives human review for meaning, factual fidelity,
  tone, and material improvement.
- Coverage is reported but does not outrank false-positive avoidance.

## Deterministic safety policy

The model's preference is not sufficient permission to rewrite. Typover also
requires a concrete signal such as known filler, conspicuous repetition, or an
indirect construction. It rejects rewrites of quoted, conditional, negative,
qualified, prompt-like, code, URL, and parenthetical-emphasis contexts. Numeric
and symbolic tokens must remain exact. A rewrite must remove its triggering
clarity defect and preserve explicit tone markers.

The Comprehensive fallback separately rejects code identifiers, quoted
commands, prompt-like text, adjacent duplicate words, adjacent gerunds, and
changes from British collective-noun agreement to American agreement.

## Baseline result

The final validation run produced:

- 19 of 19 unchanged controls passed;
- 0 applied false positives;
- 14 of 16 intended cases produced candidate rewrites;
- 0 protected-fragment failures;
- 0 model errors;
- 5 model proposals were rejected by deterministic safety checks;
- all 14 candidate rewrites passed human review.

The two safe misses removed explicit politeness or first-person framing. They
were correctly rejected rather than applied.

## Operating-cost snapshot

The same 35-case run measured:

- first-request latency proxy: 4.68 seconds;
- warm median latency: 1.71 seconds;
- p95 latency: 2.88 seconds;
- process-attributed energy: 617.78 mJ for the complete run;
- TypoverEval physical footprint: 9.77 MB, 9.88 MB lifetime peak;
- reported neural footprint: 0 MB.

The first request is a proxy, not a controlled cold boot measurement. The
process resource counters cover TypoverEval and energy billed to it; Apple's
system model executes in system services, so the memory and neural-footprint
figures do not represent the full system inference cost. Treat these numbers as
a reproducible application-side baseline, not total device energy or memory.

Apple can update the system model independently of Typover. Re-run the corpus,
retain the complete candidate review, and compare operating-cost distributions
for every supported macOS model version.
