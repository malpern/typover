# ADR-006: Separate correction scope from sentence-rewrite permission

- Status: Accepted
- Date: 2026-07-25

## Context

Typover's original contextual model path was deliberately narrow: it could
apply one objective word or short-phrase correction in a completed sentence.
That is appropriate as the default, but it leaves two distinct user choices
unexpressed:

1. whether Typover should fix a broader set of objective spelling,
   punctuation, and grammar problems; and
2. whether Typover may rephrase the writer's sentence for clarity.

Combining those choices into one "more AI" switch would blur the line between
correction and authorship. A writer may want thorough proofreading without
wanting their prose rewritten.

## Decision

Typover will expose two persisted settings:

- **Correction scope** has `Careful` and `Comprehensive` options.
- **Allow sentence rewrites** is a separate opt-in that is available only when
  `Comprehensive` is selected.

`Careful` remains the default. It preserves the original single-edit structured
model contract and the lexical-safety gate used by the existing contextual
benchmark.

`Comprehensive` may propose up to three non-overlapping, objective spelling,
punctuation, or grammar edits in one completed sentence. Typover validates the
captured sentence once, validates every proposed edit, and rejects the entire
result if any edit is stale, ambiguous, overlapping, unsafe, or invalid. The
accepted changes share one Undo transaction, while each changed range retains
its own visible annotation and Change Back menu.

When sentence rewrites are also enabled, the model may instead return one
rewritten version of the completed sentence. A rewrite must:

- preserve the sentence's meaning, facts, intent, and tone;
- add no new information;
- be complete, contain no newline, end in sentence punctuation, and remain
  within 600 UTF-16 code units;
- apply only when the captured original sentence still matches exactly.

An accepted rewrite replaces that sentence as one transaction and annotates
the complete replacement with the light-gray squiggle. Its menu can restore the
exact original sentence, and normal Undo and Redo operate on the rewrite.
Typover will not rewrite paragraphs, selections, or documents through this
automatic path.

Both modes use Apple's on-device system model. There is no network fallback.
Rewrite activity has its own correction source in local statistics and does
not create global word-level learning rules.

## Consequences

### Benefits

- Writers can request broader proofreading without granting permission to
  rewrite their voice.
- The default interaction and benchmark remain conservative.
- Multi-edit results remain atomic, visible, and reversible.
- Sentence rewriting is bounded to the unit the writer just completed rather
  than expanding into whole-field replacement.

### Costs

- Comprehensive mode has a larger model contract and higher latency than
  Careful mode.
- A whole-sentence annotation is visually stronger than a word annotation.
- Rewrite quality cannot be graded fairly with the minimal-edit contextual
  corpus. It requires a separate corpus that evaluates meaning preservation,
  factual fidelity, tone, and whether a rewrite was warranted.
- The model may change across macOS releases, so both comprehensive correction
  and rewrite behavior require continuing benchmarks.
