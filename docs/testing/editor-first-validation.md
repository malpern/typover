# Editor-first validation protocol

- Updated: 2026-10-15
- Status: Required future evidence, not executed results
- Plan: [implementation milestones](../plans/editor-first-implementation.md)

## Three independent kinds of evidence

1. Deterministic tests establish storage, scheduling, transaction, and UI-state
   correctness using fake engines/clocks/storage.
2. Live-model evaluations measure correction quality and latency on an explicitly
   identified OS/model configuration. Model output is not a stable unit-test oracle.
3. Interactive Mac sessions establish real editing, input-to-display behavior,
   keyboard/VoiceOver/IME usability, and writing benefit.

A headless test run cannot stand in for physical typing or a GUI qualification.
Missing Apple Intelligence must degrade gracefully and be reported separately
from an engine failure. No cloud fallback without explicit selection.

## Test matrix

| Area | Essential assertions | Evidence |
| --- | --- | --- |
| Transactions | Exact target, expected original, bounds, all-or-nothing multi-edit; no whole-document correction | Unit + AppKit integration |
| Text coordinates | Emoji, surrogate pairs, combining marks, bidirectional text, CRLF, apostrophes; no split graphemes | Unit + seeded edit traces |
| Concurrent typing | Before/inside/after target; stale revision; out-of-order result; close/switch document | Fake asynchronous engine |
| Composition | Marked text and selection untouched; safe reconsideration after composition ends | Integration + real IME |
| Undo/review | Typing, automatic edit, alternative, Change Back, subsequent edit, undo/redo; no repeated rejection loop | Integration + keyboard session |
| Provenance | Multiple/overlapping corrections; reloaded anchors; invalid historical target cannot write | Unit + recovery |
| Storage | Ordered snapshots, atomic text/history, failed write, crash, migration, unknown schema | Fault injection + force quit |
| Scheduler | Bounded work, debounce, cancellation ignored, retry limits, no model backlog | Fake clock + engine |
| Privacy | Local-only mode makes no provider requests; logs omit text; clean export omits history; disclosure matches context | Provider spy + inspection |
| Learning | Explicit/implicit provenance, accidental edits, suppression scope, conflicts, reset and migration | Unit + held-out evaluation |
| Presentation | Wrap, resize, scroll, large file, faded marks still reviewable, keyboard focus and VoiceOver | AppKit + GUI |
| Formatting | Markdown/code/literal protection; reversible operations; export fidelity | Unit + GUI |

Use generated event traces with fixed seeds and persist failing seeds. State
properties should include: a rejected transaction leaves text unchanged; edits
cannot affect another document; restore never overwrites intervening user text;
save completion cannot move the durable revision backwards.

## Performance protocol

Run optimized builds on the actual Mac mini. Record chip/RAM, OS/SDK, model,
display refresh, power mode, thermal/background load, app revision, document
size, correction count, and measurement method. Warm and cold inference runs
must be reported separately.

Measure 10k and 100k UTF-16-unit documents with 0, 100, and 1,000 historical
corrections, typing both at the end and in the middle, while scrolling, saving,
and running slow fake inference. Include a 1M-unit stress case to identify
scaling limits. Use at least 1,000 synthetic input events per measured cell,
three repetitions, and report p50/p95/p99/max plus dropped/stalled events.

Initial engineering budgets, to validate in M0:
- Synchronous editor input handling: p95 <= 8 ms, p99 <= 16 ms on 100k-unit
  documents; no application-attributed stall over 50 ms in the measured run.
- Physical input-to-visible-update: target p95 <= 33 ms on a 60 Hz display,
  measured separately with a documented method. Software transaction timings
  must never be described as physical end-to-end latency.
- Persistence and model waits: no blocking file write or awaited inference on
  the input path. Task/queue counts remain bounded under a five-minute burst.
- Autosave: target durable completion within one second of quiescence under
  normal local storage. Faults are surfaced and do not freeze typing.
- Contextual turnaround: report completion time after the chosen boundary,
  including debounce/queue/model/apply phases. Aim for <= 2 seconds warm p95 on
  the target model, but do not weaken safety or substitute cloud inference to
  hit it. If hardware cannot meet this, narrow context or change interaction
  and document the decision.

These are proposed budgets, not measurements. M0 may revise them with explicit
rationale before implementation; later regressions require evidence. Measure
scaling and compare to correction-off to locate Typover's overhead.

## Streaming quality corpus

Each case contains synthetic or explicitly consented text, timed edit events,
caret/selection and composition events, engine response ordering, allowed final
outputs, protected spans, and expected review/restore behavior. Include:
- mechanical errors, missing/extra words, spacing and punctuation;
- valid-word errors resolved by later context, and ambiguity that should remain;
- already-correct informal voice, unusual grammar, dialect, names, technical
  terms, numbers, negation, modality, quotations, code, and URLs;
- edits to previous paragraphs, overlapping proposals, explicit rejection,
  and a later context update that must not reapply the rejected edit.

Split tuning, validation, and frozen holdout cases. Label acceptable alternatives
and expected unchanged spans before scoring. Score the final text and edit
sequence, not whether one exact candidate was returned.

Report correction precision, residual-error rate, unwanted changes per 1,000
words, meaning-changing edits, rejection/reapplication rate, and correction
latency. Distinguish spelling, grammar, formatting, and optional style.
Publish denominators, case provenance, model/OS version, and repeated-run
variation. Retain the existing corpus as regression coverage, not the entire
quality specification.

## Real writing sessions

Use matched tasks across correction-off, current baseline, and new policy;
counterbalance ordering to reduce learning/fatigue effects. Include free writing
as well as transcription. Keep raw personal text local unless explicitly approved.

Record elapsed time through final review, final usable words, repair keystrokes,
undo/revert actions, review time, residual errors, unwanted edits, and the
writer's voice/trust rating. Define useful words/minute as final usable words
divided by total writing-plus-review minutes. Do not interpret an unreverted
change as approval.

Start with at least three 20-minute owner sessions per condition as a pilot,
not a statistically conclusive community benchmark. Examine individual failures
before averages. Add other writers and languages before generalizing.

## Milestone evidence record

For each gate record:
- revision, clean/dirty worktree, environment and configuration;
- exact command or manual procedure and dataset/seed;
- expected result, actual result, artifact path, and pass/fail/blocked;
- known limitations and whether the evidence is automated, live-model, or manual.

Keep raw personal documents, secrets, and private recovery bundles out of Git.
Commit synthetic fixtures, aggregate results, and sanitized failure descriptions.
A milestone with missing required manual evidence remains pending qualification.
