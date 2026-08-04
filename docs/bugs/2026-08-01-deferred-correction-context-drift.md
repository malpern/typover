# Deferred correction could outlive caret and adjacent-text drift

- Status: Fixed and physically verified
- Date: 2026-08-01

## Symptom

In the disposable Bear note, the ESP32 typed Space after `teh`, moved the
caret left, and inserted `x` before Typover's 220-millisecond idle gate. All six
keyboard reports arrived with at most 36 microseconds of lateness. Typover
nevertheless applied the queued `teh` to `the` correction at its old exact
range, producing `thex ` instead of preserving the physical `tehx ` sequence.

This was a wrong-context write. The replacement range still contained `teh`,
but its caret and adjacent text no longer matched the context that had
authorized the correction.

## Cause

A deferred correction retained its proposal and absolute range, but not the
bounded typing context that authorized it. Ordinary input deliberately
rescheduled the idle timer so rapid continued typing could still converge.
That same behavior let navigation and an adjacent edit survive until the exact
range replacer ran. Exact text equality at the target range was necessary but
not sufficient to prove that the queued correction was still current.

## Fix

Each deferred correction now retains its transient bounded context snapshot.
Immediately before any queued Accessibility write, Typover re-reads Bear and
requires an append-only transition:

- document growth must equal forward caret movement;
- the overlapping text before the original caret must be unchanged; and
- bounded trailing text must be unchanged.

This permits normal continued typing at the same caret. Navigation,
replacement, deletion, adjacent insertion, unavailable context, and bounded
fingerprint drift clear the queue and rebaseline without writing.

## Evidence

The deterministic regression reproduces `teh ` becoming `tehx ` before the
idle deadline and verifies that no applicator request is made. A companion
test proves ordinary append-only growth retains authorization. The focused
automatic-correction suite passes 34 tests.

The same installed ESP32 sequence was then repeated with the fixed development
build. Bear ended at exact physical text `tehx `, Typover logged
`deferredContextChanged`, no correction event appeared, and all six fixture
reports arrived with at most 42 microseconds of lateness. A separate normal
append control corrected 5/5 physical `teh ` words at 100 milliseconds per
character with valid Bear focus and fixture evidence in the local run ending
`02-56-15Z`. The clean installed product commit repeated the exact six-report
safety control with maximum lateness of 30 microseconds, then passed a second
5/5 normal append control in the local run ending `03-00-53Z`.
