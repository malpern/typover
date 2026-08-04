# ADR-016: Separate controlled-editor and external-editor mutation lanes

- Status: Accepted
- Date: 2026-08-03

## Context

Typover has two materially different editing environments.

In Typover's own editor, `NSTextView` and TextKit expose the text storage,
selection, marked-text state, Undo manager, and drawing lifecycle in one
process. Typover can correct the completed word synchronously inside the native
edit transaction and can attach a durable, independently reversible
annotation to the exact replacement range.

Bear exposes bounded text, selection, replacement, and geometry through
Accessibility. Those calls are independent synchronous IPC operations rather
than one atomic edit transaction. The current idle-first AX lane is safe and
reliable, but a rapid burst deliberately delays its corrections until physical
typing pauses. Text expanders use a different mechanism: observe a typed
abbreviation, then emit deletion and insertion keystrokes (or paste) at the
active caret. That can feel immediate, but it does not by itself prove which
editor or range received the synthetic input, preserve an annotation, or make
the edit reversible.

Trying to force both environments through one mutation mechanism would either
discard the controlled editor's native guarantees or overstate what Bear's
Accessibility surface can promise.

## Decision

Typover uses two coordinated correction lanes.

### Controlled-editor lane

1. Word-level Apple Spelling runs synchronously after a user-entered completion
   boundary and before the next edit is processed.
2. The smallest exact word range is replaced directly in `NSTextStorage`.
3. Selection adjustment, annotation, learning, Change Back, alternatives, and
   Undo registration are part of the same Typover-owned transaction.
4. Marked-text composition and paste are never auto-corrected.
5. Contextual inference remains asynchronous. A result may apply behind the
   live caret only when the captured sentence is still byte-for-byte exact and
   no marked-text composition is active when the result returns.
6. Continued typing, caret movement, or selection elsewhere does not by itself
   invalidate an unchanged captured sentence. Selection is transformed around
   the accepted replacement.

### External-editor lane

1. ADR-014's serialized idle-first AX replacement remains the default and the
   production control path.
2. A text-expander-style Bear experiment is isolated behind a protocol and is
   disabled by default.
3. The experiment accepts only a collapsed caret, supported single-character
   boundary, non-repeating unmodified lowercase ASCII word, bounded word
   length, supported Bear/macOS version, and known local correction proposal.
4. The first transport prototype emitted synthetic deletion and Unicode
   insertion events without using or exposing the clipboard. Typover-authored
   events carried a private marker so its input observer could reject recursion.
   Physical testing disqualified post-dispatch deletion: a future transport must
   intercept and replace the completion boundary before Bear processes it, or
   provide an equivalently atomic edit contract.
   [Research into current text expanders and macOS input APIs](../research/macos-text-expander-implementation-survey.md)
   selected an active session event tap plus tap-proxy posting as the next
   bounded experiment. Apple guarantees that proxy-posted events enter before
   the callback's returned boundary; physical qualification must still prove
   ordering, Bear acceptance, and reversible adoption.
5. A synthetic mutation is provisional. It is not counted, learned, or shown
   until a bounded AX read verifies the exact replacement and builds a
   reversible correction anchor.
6. Any focus, selection, composition, Secure Input, event-ordering, or
   post-write verification ambiguity rejects the experiment or falls back to
   the idle-first AX lane. An observed but unverified write opens the same
   mutation circuit breaker used for indeterminate AX writes.

## Consequences

- Typover's editor can target an immediate, zero-compromise writing experience
  without inheriting external-app timing limitations.
- Bear can test a lower-latency mutation mechanism without weakening the
  shipping safety contract.
- Synthetic input can improve perceived latency, but it cannot become the
  Bear default until physical tests prove event ordering, continued typing,
  Undo, focus, selection, Secure Input, recursion prevention, verification,
  and overlay adoption under quiet and loaded conditions.
- Failure to qualify the synthetic path does not invalidate Typover's editor or
  the existing post-pause Bear beta. It establishes the honest production
  boundary between cooperative and non-cooperative editors.

## Validation gates

The controlled editor requires deterministic coverage for immediate continued
typing, rapid consecutive corrections, composition, paste, moved selection,
stale contextual results, contextual results returning during continued
typing, independent annotations, and one-step Undo/Redo.

The Bear experiment has deterministic planner, physical-token, transport-gate,
recursion, before/after transition, continued-typing, adoption, coordinator,
Secure Input fallback, and circuit-breaker coverage. Its first physical spike
used the same ESP32 text, timing, focus, fixture, and log evidence as the
idle-first lane. It corrected 1/1 at 160 ms, then 5/5 at both 160 and 100 ms.
At 60 ms it corrected only 3/5 and produced `the the the teh tthe`: the AppKit
global-monitor callback for the fourth boundary arrived after later physical
input, so post-dispatch backspaces mutated stale caret state. Verification opened
the circuit, but only after text damage. The 40 ms row was intentionally not run.
This transport is therefore disqualified for production. No replacement
transport may qualify unless Bear contains the expected text and Typover exposes
a verified reversible anchor at every supported timing row.

An independent fresh-process retest confirmed the boundary. Five-word rows again
passed 5/5 at 160 and 100 ms, while 60 ms corrected 4/5 and safely left one
`teh`. A second fresh-process 60 ms stress row changed 6/20 words, but Typover
verified only five before another delayed boundary caused post-write verification
to fail and opened the mutation circuit; overlay sampling found 0/6 retained
markers, so the harness correctly classified the row as invalid evidence. Bear
focus remained valid, the fixture completed with zero late reports, and the host
was quiet. The exact `tthe` corruption did not recur, which is consistent with a
timing race rather than evidence against it: the unreliable 60 ms behavior and
unverified-write circuit failure both reproduced independently.

The replacement ordering candidate now uses an active session event tap on a
dedicated run-loop thread. A single-use state-machine authorization posts a
fully prepared `teh -> the` deletion/insertion sequence at the tap proxy before
returning the original physical Space. It disarms before posting and rearms only
from a fresh AX baseline after exact adoption. Learned suppression, Secure
Input, unsupported input, tap disablement, or proposal mismatch deauthorizes it;
an unmatched observed write opens the mutation circuit. The focused ordering
suite (17 tests), coordinator suite (45 tests), clean build, and full suite (329
tests across 30 suites) pass.

Physical schema-6 qualification now proves the active path for five consecutive
words at both 160 and 100 milliseconds per character, plus 100 milliseconds
under combined CPU, WindowServer, and Accessibility contention. Every one of
those fifteen corrections had matching pre-dispatch, verified-application, and
overlay evidence with no tap disable or late fixture report. Callback work was
at most 0.126 milliseconds in the quiet matrix and 0.091 milliseconds under
load.

Burst rows at 60/40 milliseconds established a different contract. AX may
coalesce notifications quickly enough that the bounded idle fallback claims a
scan. That claim now explicitly deauthorizes the tap, preventing the two lanes
from owning destructive work concurrently. A post-fix 60 millisecond row
converged 5/5 through four active corrections and one fallback; a separate
resilience run produced one safe miss at 60 milliseconds and then converged 5/5
at 40 milliseconds through one active correction and four fallbacks. There was
no circuit opening, refused replacement, tap disablement, unexpected text, or
late fixture input after the ownership fix. The event tap therefore remains a
disabled-by-default candidate until the product chooses a supported active-path
envelope; the existing idle-first lane remains the production behavior.
