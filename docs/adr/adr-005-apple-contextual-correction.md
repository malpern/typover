# ADR-005: Use Apple’s on-device model for bounded contextual correction

- Status: Accepted
- Date: 2026-07-25
- Scope: Apple engine; optional user-selected providers are defined by ADR-007

## Context

`NSSpellChecker` is fast and accurate for ordinary misspellings, but it cannot
reliably detect a valid word used in the wrong context, such as `it's` where
`its` is required. Typover needs a contextual path that remains private, works
without a network, and cannot rewrite broad passages while the writer is
typing.

The macOS 27 Foundation Models framework exposes the Apple Intelligence system
language model, its device and locale availability, and guided structured
generation. Apple may update that model in OS releases, so its quality and
latency must be measured separately from the deterministic editor transaction.

## Decision

Typover will use `SystemLanguageModel.default` behind the replaceable
`ContextualCorrectionEngine` protocol.

- The engine runs only when Apple reports the on-device model and current
  spelling locale as available.
- Typover has no Private Cloud Compute, server, or other network fallback.
- A request contains only the most recently completed sentence and is capped at
  400 UTF-16 code units.
- The default Careful scope may propose at most one objective correction and
  must return structured original and replacement text.
- Typover deterministically reduces every returned original/replacement pair
  to the smallest changed whole word or phrase.
- The proposal must identify one unique exact substring in the captured
  sentence. Broad, punctuated, ambiguous, empty, or stale targets are rejected.
- Single-word substitutions must remain within a small lexical edit distance.
  A narrow reviewed exception permits `of` to `have` for the common
  `should of` error. This rejects unrelated model output even when its target
  happens to be an exact substring.
- Typing may continue after the sentence while inference runs. Any change
  inside the captured sentence invalidates the result.
- Accepted contextual corrections use the same light-gray squiggle,
  restoration menu, statistics, and Undo transaction as spelling corrections.
- Contextual reversions do not create a global word preference. A valid word
  can be right in another sentence, so learning requires future context-aware
  keys.

## Consequences

### Benefits

- Sentence-context mistakes can be corrected without sending writing off the
  Mac.
- Model output cannot directly replace a document. Sentence replacement is
  permitted only through the separate, explicit, bounded opt-in defined by
  [ADR-006](adr-006-separate-correction-scope-from-sentence-rewrites.md).
- The editor remains responsive because inference is asynchronous.
- The protocol and contextual corpus can benchmark open-source local engines
  later without changing the interaction.

### Costs

- The current model adds roughly seconds rather than milliseconds of latency.
- Model updates can change results, so the contextual corpus is a benchmark,
  not a permanently deterministic gate.
- Conservative rejection and no confidence score mean some contextual errors
  remain unchanged.
- Prompt profiles are benchmark inputs, not product settings. A more explicit
  focused-grammar prompt was slower and less accurate than the conservative
  prompt on the 48-case corpus, so the conservative profile remains the
  default.
- Context-aware preference learning is deferred rather than applying unsafe
  global rules to otherwise valid words.
