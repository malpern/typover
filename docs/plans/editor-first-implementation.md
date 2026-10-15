# Editor-first implementation plan

- Updated: 2026-10-15
- Status: Planned; no milestone below is claimed complete
- Authority: [strategy](editor-first-strategy.md)
- Test protocol: [editor-first validation](../testing/editor-first-validation.md)
- Execution: [Mac development prompt](../development/mac-development-prompt.md)

## Working method

Implement vertical slices on a development branch. Keep the app runnable and
commit tested increments. Update this plan with commit IDs, exact commands,
results, limitations, and the next step. Existing controlled-editor milestones
describe prior work; they do not satisfy these new gates automatically.

Suggested responsibility boundaries are DocumentStore, CorrectionCoordinator,
CorrectionTransaction/History, ContextScheduler, and AnnotationIndex. Names and
file splits are implementation choices. Preserve behavior with focused tests
before extracting it from EditorLabView.swift.

Do not change the minimum SDK merely to unblock a machine without first
checking which APIs require it. The reviewed package requires macOS 27 and
Swift 6.4. Inspect the actual Mac mini; hardware, OS, SDK, model availability,
and interactive GUI access are unknown until checked.

## M0 — Establish a reproducible baseline

**Deliver**
- Inspect AGENTS.md, current source, package, scripts, git status, and history.
- Record Mac model/chip/RAM, OS build, Swift/Xcode/SDK versions, power mode,
  display refresh, Apple Intelligence readiness, and GUI session availability.
- Run existing build/tests and local spelling evaluation. Separate unrelated
  Bear permission tests from failures in shared editor code.
- Capture baseline release-build editing timings and a representative manual
  writing session. Add fake engine, fake clock, and storage seams only where needed.
- Write a short ADR for editor-first startup and document storage design.

**Tests/gate**
Existing deterministic tests pass or each pre-existing failure is reproduced
and attributed. No failure is silently removed from the suite. Baseline artifacts
identify revision and environment. Missing hardware/SDK/GUI evidence is reported
as blocked, never passed.

## M1 — A dependable daily writing surface

Depends on M0.

**Deliver**
- Replace the demo shell with a quiet editor and local draft lifecycle:
  new/open, rename, recent drafts, autosave, reopen, find, and plain text/Markdown
  import/export. Retain a separate development lab.
- Use a versioned local document bundle containing canonical UTF-8 text and
  correction metadata. Choose a single atomic envelope initially, or a journal
  with an explicit recovery protocol; never independently save mismatched text
  and history. Record the choice in the ADR.
- Save revision-tagged snapshots off the main actor. Older completions cannot
  overwrite newer revisions. Surface failed saves; offer recovery rather than
  silently discarding a damaged document.
- Persist original/replacement text, correction ID, status, and valid anchors.
  Reloading retains review and Change Back for unchanged passages; invalid
  anchors remain historical records and cannot edit text.
- Keep normal Undo/Redo within the session. Persistent correction history does
  not require serializing the entire native undo stack.
- Add keyboard review/Change Back and clear unavailable-model state.
- Make the default editor independent of Bear coordinators and AX/Input
  Monitoring. Preserve the adapter as an explicit experimental path.

**Tests/gate**
Round-trip Unicode and correction history; empty/large documents; two open
documents with independent tasks/history; clean close/reopen; rapid saves;
out-of-order writes; disk errors; interrupted save and force-quit recovery;
corrupt/unknown schema handling; import/export without metadata leakage.
Verify ordinary launch with AX/Input Monitoring denied, keyboard-only review,
caret preservation, and VoiceOver labels.
Complete a 30-minute writing session and recover the last acknowledged durable
revision after forced termination. Document the possible unsaved interval;
target autosave within one second of quiescence. No acknowledged revision lost.

## M2 — Responsive transactions and durable history

Depends on M1; introduce measurement in M0, not at the end.

**Deliver**
- Move learning persistence and serialization off the main actor with ordered
  writes and flush/recovery semantics. Bound activity retention separately from
  unresolved correction history; avoid unbounded in-memory statistics.
- Isolate guarded transactions from rendering and scheduling.
- Replace repeated per-correction whole-document scans where profiling confirms
  them with an index updated by edit deltas. Limit layout work to visible content.
- Specify overlapping correction behavior: a later correction supersedes or
  links to earlier provenance; Change Back cannot erase intervening user edits.
- Add content-free timing/signpost instrumentation for input processing,
  transaction application, rendering, persistence, and engine waits.

**Tests/gate**
Unicode/UTF-16 anchor transforms, edit before/inside/after correction, selection
replacement, Undo/Redo, multi-edit atomicity, delayed/out-of-order responses,
overlapping corrections, close/switch document during inference, and slow/failing
storage. Seeded randomized edit sequences preserve text/history invariants.
Meet the provisional latency budgets in the validation protocol at 10k and
100k characters with 0/100/1,000 correction records. Report 1M-character stress
behavior separately. Never trade text safety for speed.

## M3 — Corrections that improve with context

Depends on M2.

**Deliver**
- Replace sentence-terminator-only scheduling with bounded, coalesced work
  triggered by completion, paragraph boundaries, idle pause, and edits to recent
  passages. Use a fakeable clock; start with roughly 500 ms debounce and tune.
- One active contextual request and one coalesced pending request per document;
  cap total provider concurrency. Cancel obsolete work when supported and
  always discard invalid responses even if cancellation is ignored.
- Send a context snapshot plus a smaller editable region, language, relevant
  approved preferences, document identity, revision, and stable anchors.
- Revalidate against current text. Unrelated edits may be transformed safely;
  overlapping/ambiguous edits invalidate and schedule fresh work, not a forced
  retry against stale offsets.
- Replace substring-only targeting with validated insert/delete/replace
  operations. Check UTF-16 boundaries, expected originals, insertion anchors,
  allowed regions, conflicts, size/count bounds, and protected syntax.
- Use sentence segmentation that handles abbreviations/decimals; test boundary
  behavior explicitly. Do not assume a simple punctuation scan is sufficient.
- Preserve active composition/selection and suppress repeated corrections
  after a rejection. Separate grammar and opt-in stylistic rewrite policies.
- Keep remote providers on their current sentence-only contract until the
  expanded-context disclosure and explicit user choice are implemented.

**Tests/gate**
Replay typing without punctuation, later disambiguating sentences, edits to an
earlier sentence, rapid bursts, pause/resume, request reordering/timeouts,
model-unavailable/offline behavior, rejection loops, paste, IME composition,
abbreviations, decimals, and multilingual boundaries.
Malformed/out-of-region/injection-like model output cannot bypass transaction
validation. Multi-edit failures apply nothing. Fake-model traces must demonstrate
a correction that becomes justified only by later context.
Live-model quality is a separate evaluation; mark M3 complete only after
held-out results and manual use support enabling the selected policy.

## M4 — Personal vocabulary and faithful formatting

Depends on M3.

**Deliver**
- Preview/import/export static replacement lists; define encoding/schema,
  conflict precedence, case/language behavior, and explicit activation.
- Add inspectable vocabulary, exclusions, language and punctuation preferences;
  retrieve only relevant approved preferences into model requests.
- Keep contextual rejection local by default. Broader preference creation is
  explicit; Undo/Redo and reset remain consistent with learning effects.
- Add lightweight Markdown presentation and reversible list continuation,
  indentation, and basic punctuation behavior with code/literal protection.
- Keep style preferences separate from objective correction. Introduce writing
  examples only with an explicit local consent/storage/deletion design.

**Tests/gate**
Import round-trips and conflicts, malformed/oversized entries, accidental
learning, repeated rejection, ambiguous homophones, mixed-case brands, accented
names, per-language scope, reset/export, and preference migration.
Formatting tests cover code fences, inline code, links, lists, quotes, selection,
Undo/Redo, and exact plain-text/Markdown export.
Held-out personalized cases improve while protected and already-correct cases
remain unchanged. A small development corpus is not evidence of general benefit.

## M5 — Prove the writing benefit and qualify a preview

Depends on M1–M4.

**Deliver**
- Expand evaluation from single expected candidates to streaming edit traces,
  approved alternative final outputs, and multiple independent corrections.
- Conduct matched correction-off/baseline/new-engine writing sessions with
  separate tuning and held-out material. Start with the owner; add willing
  writers before broader product claims.
- Provide a self-contained app build, accurate feature/privacy documentation,
  migration/recovery notes, and a bounded support matrix.
- Update public claims and active roadmap links to match shipped behavior.
  Signing/notarization/distribution follow the applicable release workflow;
  old Bear physical gates are not custom-editor release prerequisites.

**Tests/gate**
All deterministic safety/recovery tests pass. Review latency and held-out quality
reports, keyboard/VoiceOver/IME matrix, and real-session repair burden.
Require no observed data loss or meaning-changing automatic edits in the
qualification set; report sample sizes, not a universal guarantee.
Demonstrate lower repair/review time without worse final quality or perceived
voice. If inconclusive, keep broader correction opt-in and collect more evidence.
No public release or broad claim solely because unit tests passed.

## Milestone ledger

| Milestone | Status | Evidence / commit | Next action |
| --- | --- | --- | --- |
| M0 Baseline | Pending | None | Inspect target Mac |
| M1 Daily editor | Pending | None | Document/storage ADR after M0 |
| M2 Responsiveness | Pending | None | Baseline instrumentation in M0 |
| M3 Rolling context | Pending | None | Scheduler/transaction design after M2 |
| M4 Personalization | Pending | None | Define preference and import semantics |
| M5 Preview evidence | Pending | None | Build held-out evaluation protocol early |

## Scope discipline

Prefer useful incremental changes over a broad editor rewrite. Preserve shared
tests and existing engine interfaces where possible. If a dependency blocks a
milestone, document it and complete independent work; do not silently lower a
gate. Record changes to budgets or policy with rationale and before/after evidence.
