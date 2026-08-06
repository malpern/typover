# Bear physical HID harness

- Status: Quiet and controlled-load board-backed matrices pass
- Fixture: Waveshare ESP32-S3 Touch-LCD-1.69 KeyPath HID fixture
- Scope: Synthetic text in a disposable Bear note

This harness measures whether Typover corrects every completed word when a
physical USB keyboard produces the same burst at repeatable timings. The ESP32
schedules every HID report locally, so Wi-Fi and host load cannot change the
input cadence after a case starts.

The Typover repository does not copy or modify the fixture firmware. It invokes
the existing authenticated client from the KeyPath fixture worktree through
`TYPOVER_HID_FIXTURE_CLIENT`. The fixture token is decrypted by the wrapper from
the existing sops store and is never passed in argv or printed.

The harness also opens the existing native AppKit HID Capture Jig in a dedicated
`Typover · Bear Physical HID` mode. The floating monitor stays visible while
Bear owns keyboard focus. It presents the ESP32's known rapid-key schedule as an
animated keycap stack, then replaces the pending state with correction and miss
counts verified from Bear text and Typover logs. The UI explicitly labels the
animation as scheduled input because a background window cannot capture the
events delivered to Bear.

Both test surfaces are deliberately Bear-branded. The AppKit monitor uses the
installed Bear app icon and a prominent Bear wordmark. The harness also sends an
explicit `brand: bear` presentation to the ESP32 for every phase, producing a
coral Bear face and Bear-specific preparation, typing, verification, and result
labels on the board. This is presentation state only; it does not change the HID
schedule or count as correction evidence.

## Build and offline check

```bash
swift build --configuration release --product TypoverBearHIDHarness
Scripts/typover-hid-harness plan
Scripts/typover-hid-harness doctor
```

`plan` does not require the board or its secret. The default matrix types 20
continuous instances of `teh ` followed by Return at 160, 100, 60, and 40 ms
per character. This covers ordinary deliberate typing through a fast burst.

`doctor` checks all of the following without emitting HID input:

- the existing fixture client is executable;
- the AppKit Jig launcher and monitor client are executable;
- the fixture is reachable and its USB keyboard is mounted;
- Typover is running; optional private diagnostics are reported but are not a
  run prerequisite;
- Bear exposes the supported focused text editor contract; and
- Bear is frontmost.

An unplugged board appears as `fixtureReachable: false`; that is an expected
waiting state, not a Typover failure.

Create a uniquely named disposable note with Bear's official CLI and retain
the returned UUID. The title and note are test data; never target an ordinary
note.

```bash
/Applications/Bear.app/Contents/MacOS/bearcli create \
  "Typover Physical Test" --content '\n' --format json --fields id,title
```

## Physical run

Do not use the Mac while the matrix runs. Supply the disposable note UUID so
the harness can restore that exact target after Jig setup:

```bash
Scripts/typover-hid-harness run --exclusive-desktop-confirmed \
  --bear-note-id <UUID>

# Active-tap candidate only: require one pre-dispatch emission per correction
# and invalidate the row on any event-tap disablement.
Scripts/typover-hid-harness run --exclusive-desktop-confirmed \
  --bear-note-id <UUID> --require-pre-dispatch-evidence
```

After a quiet baseline, controlled contention can be selected explicitly:

```bash
Scripts/typover-hid-harness run --exclusive-desktop-confirmed \
  --bear-note-id <UUID> --load-profile cpu
Scripts/typover-hid-harness run --exclusive-desktop-confirmed \
  --bear-note-id <UUID> --load-profile window-server
Scripts/typover-hid-harness run --exclusive-desktop-confirmed \
  --bear-note-id <UUID> --load-profile accessibility
Scripts/typover-hid-harness run --exclusive-desktop-confirmed \
  --bear-note-id <UUID> --load-profile combined
```

The focused punctuation row uses the same physical and exact-text contract:

```bash
Scripts/typover-hid-harness run --exclusive-desktop-confirmed \
  --bear-note-id <UUID> --scenario punctuation --intervals 100 --words 5
```

It cycles through `.`, `?`, `!`, `;`, and `:` completion boundaries, preserving
the punctuation and following spaces while distinguishing each `teh` safe miss
from an exact `the` correction.

The runner waits for three host samples with at least 60% CPU idle and no
active Swift compiler. It refuses to start unless Typover is running, the
fixture reports a mounted USB keyboard, and the operator supplied a valid Bear
note UUID. Before the quiet-host wait it opens the Jig monitor and shows a
focus gate. After the host becomes quiet, the harness uses Bear's official CLI
to reopen that exact note at its current terminal UTF-8 byte offset, activates
Bear, and waits up to two minutes for Accessibility to prove a focused
collapsed caret at the end of the editor. It holds explicit macOS display,
system, and one-hour-bounded user-active wake assertions until the run ends,
and every generated load source is terminated on normal completion or failure.
The explicit timeout matters because macOS gives an otherwise unbounded
`caffeinate -u` assertion only five seconds. It rechecks the caret after load,
arm, and monitor setup, watches the frontmost application throughout the
delayed start and HID burst, and aborts the fixture if Bear loses focus. After
the fixture completes,
the harness keeps the selected load active and observes the exact inserted
range for at least 1.5 seconds and at most 10 seconds. It records the time to
full convergence; if the range never converges, the final exact text is still
classified as a safe miss, unexpected text, or invalid evidence. The monitor
remains visible on the final verified result.

The wrapper incrementally rebuilds the release harness before every command.
This happens before quiet admission and prevents a checked-in schema or safety
change from being masked by a stale `.build/release` executable. Do not set
`TYPOVER_HID_HARNESS_SKIP_BUILD=1` for credited evidence.

Each case is classified as:

- `passed`: all 20 words became `the`;
- `safe-misses-observed`: the exact input was preserved, but one or more words
  remained `teh`;
- `unexpected-text`: a chunk was neither the input nor the expected correction;
  or
- `invalid-evidence`: focus, range, length, or capture evidence was incomplete.

A visually corrected word counts as Typover evidence only when the same case's
unified log contains a matching `Automatic correction applied` event. This
prevents Bear's own autocorrection or another text service from being credited
to Typover.

Schema 5 adds a host-side input-arrival measurement. Typover timestamps the
global physical completion-boundary callback before its MainActor hop, then
records the first Bear `AXValueChanged` callback paired with that boundary.
Each case stores those content-free `boundaryToValueMilliseconds` samples and
counts `valueBeforeBoundaryCallback` orderings that cannot yield a valid
non-negative sample. This measures the observable path from Typover's input
monitor to Bear's Accessibility notification; it does not claim to measure
ESP32 USB submission-to-screen-paint latency.

Schema 6 adds active-tap qualification evidence. With
`--require-pre-dispatch-evidence`, every corrected word must have one matching
pre-dispatch emission log, every callback-duration value is retained, and any
tap-disable notification makes the case invalid. Use the flag only when the
installed Typover process was launched with
`TYPOVER_EXPERIMENTAL_BEAR_TEXT_EXPANSION=1`. The log predicate includes only
Typover's content-free automatic-correction and pre-dispatch-tap categories.
This does not infer proxy ordering from logging; the fixture schedule, exact
Bear text, verified application, retained overlay, and absence of tap
disablement remain jointly required.

The same schema records the visible Typover correction-window count before and
after each case while the selected load remains active. A final count is exact
retention evidence only when the baseline count was zero; otherwise it is kept
as diagnostic context because old and new correction windows cannot be
distinguished by count alone. For release evidence, relaunch Typover and run
one timing case so `fullyRetainedFromEmptyBaseline` can be `true`.

## Schema-6 active-tap result: 2026-08-03

The fresh-process run ending `03-58-52Z` passed consecutive five-word rows at
160 and 100 milliseconds per character. It recorded ten exact corrections, ten
matching pre-dispatch emissions, ten verified applications, zero tap disables,
valid Bear focus, zero late fixture reports, and ten retained overlays. Event
tap callback duration was 0.041–0.110 milliseconds and verified application
latency was 29–52 milliseconds.

The full quiet matrix then exposed lifecycle and lane-ownership races. Return
correctly invalidated the tap but initially left it unarmed for the next row;
the coordinator now reauthorizes only after an explicit invalidating event and
a fresh settled AX snapshot. At 40 milliseconds, a coalesced fallback scan and
an authorized tap briefly competed for ownership, correctly opening the
mutation circuit. The fallback now explicitly disarms pre-dispatch before it
claims any range or scan.

The post-fix strict run ending `04-03-46Z` reached 5/5 at 60 milliseconds with
four pre-dispatch corrections and one verified idle fallback. It had no tap
disable or circuit break, but `--require-pre-dispatch-evidence` correctly kept
the mixed-path row invalid because that flag requires one active emission per
corrected word. The resilience run ending `04-04-50Z`, without the active-only
requirement, safely completed both burst rows: 4/5 at 60 milliseconds and 5/5
at 40 milliseconds. The latter used one active correction and four bounded
catch-up corrections. Focus remained valid, every fixture report arrived on
time, no replacement was refused, the tap did not disable, and all nine applied
corrections retained overlays.

The combined-load run ending `04-06-03Z` passed 5/5 at 100 milliseconds with
strict pre-dispatch evidence. All five corrections used the event tap, callback
duration stayed at 0.034–0.091 milliseconds, verified application latency stayed
at 34–39 milliseconds, all five overlays remained, and sampled CPU idle fell as
low as 23.5 percent. This qualifies the active path at normal rapid typing
rates. The 60/40 millisecond rows remain mixed-lane burst-resilience evidence,
not an active-only guarantee.

The default evidence directory is
`~/.local/state/typover/bear-hid/<run-id>/`. Each JSON file is mode `0600` and
contains the synthetic inserted range, fixture status and trace, quiet-machine
samples, controlled-load process samples, per-correction timing, and
content-free Typover unified-log events for the case. Optional bounded-writing
diagnostics live in a separate capped local file and are never copied into the
harness artifact. The harness files stay local.

## What this establishes

The matrix separates three layers that manual typing mixes together:

1. the ESP32 trace proves what physical keyboard reports were scheduled;
2. the exact Bear range proves what text arrived and what Typover changed; and
3. the Typover trace explains applied corrections and safe skips such as
   `contextChanged`.

The first quiet run is a baseline. Schema version 4 includes named scenarios,
requires complete CPU-idle, CPU, resident-memory, and power evidence for every
controlled CPU, WindowServer, Accessibility, or combined contention case, and
records bounded post-fixture observation and convergence times. Process power
rows are joined to the `ps` sample by PID rather than the presentation-only
command name. The same exact-text and fail-closed evidence contract still
applies.

The first two CPU attempts were safely rejected after `loginwindow` became
frontmost. They exposed an expired user-active assertion in the harness, not a
Typover correction result. The wake contract is fixed, covered, and verified by
the later credited load matrix. See
[HID harness wake assertion timeout](../bugs/2026-08-01-hid-harness-user-active-timeout.md).

The same rejected artifact revealed that macOS 27 refuses fractional `top`
sample delays. The sampler now uses a supported one-second interval and tests
the complete argument and PID parser contract. A valid load artifact must contain
CPU-idle, CPU, resident-memory, and power fields for Typover, Bear, and
WindowServer in every sample; a contention case with missing resource evidence
is now classified `invalid-evidence`. See
[HID harness top delay](../bugs/2026-08-01-hid-harness-top-delay.md).

A later CPU row observed exact 20/20 correction behavior but was also rejected:
the wrapper had silently executed a stale schema-2 release binary, so no power
fields were present. The wrapper now rebuilds incrementally before execution;
the affected row remains diagnostic-only, while later current-schema runs are
credited. See
[Stale physical-harness release binary](../bugs/2026-08-01-stale-hid-harness-binary.md).

The next CPU attempt passed quiet admission but stopped before HID input because
generic Bear activation could not restore the previously prepared disposable
note and terminal caret after Jig setup. Runs now require a note UUID and reopen
that exact note through Bear's CLI immediately before the Accessibility gate.
See [Explicit Bear note targeting](../bugs/2026-08-01-hid-harness-explicit-note-target.md).

The first combined 40 millisecond row sampled Bear after 1.5 seconds while the
bounded catch-up pass was still applying corrections. The artifact correctly
rejected the mismatch between 7 visible corrections and 11 application logs;
a read-only check moments later showed 20/20. Schema 4 now observes for a
bounded 10 seconds while load remains active. It also parses grouped latency
values such as `4,774.841` without truncating them to `4`. See
[Post-burst convergence observation](../bugs/2026-08-01-hid-harness-convergence-window.md).

## Controlled-load result: 2026-08-01

The installed development build passed each isolated 160 millisecond load row
and a consolidated schema-4 combined matrix:

| Profile | Intervals | Corrected | Minimum CPU idle | Peak Typover CPU | Peak WindowServer CPU | Late reports |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| CPU | 160 ms | 20/20 | 19.6% | 11.8% | 25.4% | 0 |
| WindowServer | 160 ms | 20/20 | 65.4% | 15.6% | 52.6% | 0 |
| Accessibility | 160 ms | 20/20 | 57.1% | 27.8% | 44.1% | 0 |
| Combined | 160/100/60/40 ms | 80/80 | 9.6% | 130.3% | 72.1% | 0 |

Every row retained Bear focus, contained only exact corrected text and its
trailing newline, had matching Typover application logs, captured all required
resource fields, and received all 162 scheduled fixture reports. Maximum HID
lateness was 65 microseconds. Under combined contention the four rows converged
within 1.59, 3.02, 3.26, and 3.79 seconds after fixture completion. Process CPU
can exceed 100% on macOS because the value spans multiple cores.

The evidence is local in the runs ending `01-39-14Z`, `01-40-39Z`,
`01-41-27Z`, and the canonical combined run `01-49-31Z`. These runs establish
a tested recovery envelope, not a universal guarantee for arbitrary system
load or future Bear versions.

## Schema-5 repeat and overlay result: 2026-08-03

Four consecutive fresh-Typover combined-load rows passed 80/80 physical text
corrections at 160 milliseconds per character. All runs retained valid Bear
focus, complete load evidence, all 162 fixture reports, and zero late reports.
The local artifacts end in `19-01-02Z`, `19-04-26Z`, `19-05-19Z`, and
`19-06-11Z`.

The first row populated 21 completion-boundary-to-AX-value samples between
1.19 and 12.58 milliseconds and recorded no reverse callback ordering. Its
bounded-writing trace contains 20 distinct exact deferred applications, and
its overlay sample remained 20/20 while combined contention was active.

A newly created disposable-note control ending `19-08-14Z` also passed 20/20
with 20/20 visible correction windows. It is the canonical exact-retention
artifact because the installed app began with no old correction windows and
all newly corrected text remained in the visible Bear viewport.

Do not infer lost annotations from a lower visible-window count after a long
disposable note scrolls. The accumulated-note row ending `19-06-11Z` corrected
20/20 but sampled only four on-screen overlays; it is recorded as viewport
evidence rather than the retention control. Use a fresh disposable note for an
exact overlay row.

One preceding combined-load artifact ending `18-58-31Z` produced a first token
of `eth` despite ordered fixture input and is retained as invalid evidence. It
did not recur in the next 100 physical tokens. See
[Combined-load first token transposition](../bugs/2026-08-03-combined-load-first-token-transposition.md).

## Installed circuit-breaker sequence: 2026-08-03

The debug-only `post-write-unreconciled` seam passed its complete physical
sequence. The first one-word run changed `teh` to `the`, retained valid focus,
received all ten fixture reports with zero late reports, exposed no overlay,
and logged both the injected verification failure and the mutation-circuit
pause. The generic harness correctly labels this artifact invalid because its
ordinary success contract requires a normal application event and overlay.

Without relaunching Typover, a second one-word run preserved `teh` as a safe
miss with no overlay, proving the open circuit refused further mutation. After
a normal relaunch with no fault environment, a third run corrected 1/1 and
retained 1/1 visible overlay. The local artifacts end in `19-38-15Z`,
`19-39-09Z`, and `19-40-43Z`.

## Punctuation result: 2026-08-01

The schema-4 run ending `01-48-30Z` corrected all five physical segments to
`the. the? the! the; the: `, preserved every boundary and the trailing newline,
logged five Typover applications, and received all 52 fixture reports with no
late reports.

## Quiet baseline result: 2026-07-31

The installed development build passed every 20-word row:

| Interval per character | Corrected | Missed | Unexpected text |
| --- | ---: | ---: | ---: |
| 160 ms | 20 | 0 | 0 |
| 100 ms | 20 | 0 | 0 |
| 60 ms | 20 | 0 | 0 |
| 40 ms | 20 | 0 | 0 |

The valid 160 and 100 millisecond case artifacts are in the local run ending
`02-17-52Z`; an unrelated frontmost-app interruption stopped that matrix before
the faster rows. The final 60 and 40 millisecond evidence is in the run ending
`02-27-12Z`, classified `all-corrections-observed`. Each row submitted all 162
fixture reports with zero late reports, preserved exactly 20 `the` words plus
the trailing newline, and contained 20 matching Typover application logs.

This baseline exposed two distinct issues before passing. First,
selection-based replacement could overlap the next physical key and corrupt
`teh ` into a joined token. Typover now defers fast boundaries until idle.
Second, Bear coalesced multiple character changes at 40 milliseconds, so
per-boundary reads could not recover every word. The idle pass now scans only
the bounded text observed since the rapid burst began and exact-verifies
reverse-ordered ranges. If that burst start is unavailable or has fallen
outside the bounded live window, Typover leaves the text unchanged.

The harness proves physical input delivery, final Bear text, and matching
Typover writes. It does not count visible overlay panels or exercise Change
Back; those remain separate automated collection tests and an installed manual
interaction row.

## First-beta fast-lane policy regression: 2026-08-03

Four fresh physical rows closed the burst-policy decision without expanding
the public beta claim:

| Run | Scenario | Result | Evidence |
|---|---|---|---|
| `typover-hid-2026-08-04T06-34-56Z` | Strict pre-dispatch, 100 ms, five Space-completed words | 5/5 corrected | Five pre-dispatch emissions; 33.9–40.9 ms application latency; five retained overlays |
| `typover-hid-2026-08-04T06-36-36Z` | Mouse invalidation, fresh authorization, strict 100 ms | 5/5 corrected | Focus and fixture evidence complete; all five corrections used pre-dispatch |
| `typover-hid-2026-08-04T06-37-13Z` | Fast-to-fallback handoff, 60 ms | 4/5 corrected | One exact safe `teh` miss; no unexpected text, tap disablement, or late fixture report |
| `typover-hid-2026-08-04T06-38-04Z` | Punctuation, 100 ms | 0/5 corrected | All five exact inputs preserved; punctuation is outside the qualified fast-path envelope |

All rows passed quiet-host admission, retained Bear focus, and captured complete
load and ESP32 trace evidence. ADR-018 therefore keeps the event-tap path behind
its environment gate for the first beta. The beta continues to use the
serialized 220 millisecond idle-first AX lane; the research fast-path claim is
limited to lowercase ASCII words completed with Space at 100 milliseconds per
key or slower.

## Exact notarized-candidate qualification: 2026-08-05

Candidate `0.1.0 (20260804072103)` from clean revision `e38f535` completed two
quiet-host physical matrices with the experimental event-tap gate disabled.

| Run | Process state | 160 ms | 100 ms | 60 ms | 40 ms | Unexpected text | Late reports |
|---|---|---:|---:|---:|---:|---:|---:|
| `typover-hid-2026-08-05T21-47-41Z` | Fresh installed Typover; existing Bear | 20/20 | 20/20 | 20/20 | 20/20 | 0 | 0 |
| `typover-hid-2026-08-05T21-50-26Z` | Fresh installed Typover and fresh Bear | 20/20 | 20/20 | 20/20 | 19/20 | 0 | 0 |

The lone second-run miss stayed exactly `teh`; no joined token, stale-caret
write, circuit break, replacement refusal, or unexpected chunk appeared. Focus
and load evidence remained valid in all eight rows. Maximum ESP32 lateness was
221 microseconds in the first matrix and 48 microseconds in the second.

The first row in each matrix retained 20/20 visible correction windows from an
empty baseline. Later rows reached and held the release configuration's newest-
24 correction cap. Their CLI summary says overlay evidence is unavailable
because the baseline was already populated, but the structured evidence records
the expected 24-to-24 retirement behavior; it is not an overlay-loss failure.

This closes fresh-process candidate qualification for the beta envelope. The
40 ms row is retained as an extreme-speed resilience stress case, not a claim
that every token is corrected. Its acceptance contract is fail-safe unchanged
text, never corruption.

## Quiet-review replacement candidate: 2026-08-06

Replacement candidate `0.1.0 (20260806051920)` from clean revision
`329e92bdc21a2dd7651e2b252c014f228e439576` completed the full quiet physical
matrix with the first-beta event-tap experiment disabled.

| Run | 160 ms | 100 ms | 60 ms | 40 ms | Unexpected text | Late reports |
|---|---:|---:|---:|---:|---:|---:|
| `typover-hid-2026-08-06T05-58-02Z` | 20/20 | 20/20 | 20/20 | 20/20 | 0 | 0 |

Every row retained valid Bear focus and complete load evidence. Convergence
after the fixture completed was 2.75 ms or less, and maximum ESP32 lateness was
43 microseconds. The first row began from the candidate's existing 20 visible
corrections and retained all 20; subsequent rows reached and held the intended
newest-24 correction cap.

An immediately preceding attempt, `typover-hid-2026-08-06T05-52-14Z`, was
correctly rejected as invalid evidence. The owned-editor acceptance pass had
temporarily taught `teh -> ten` by choosing an alternative, so Bear contained
twenty exact `ten` results while the release oracle expected `the`. Removing
only that synthetic learned preference restored `teh -> the` in the installed
editor before the credited retry. This demonstrates that the harness does not
silently count a valid but different learned correction as release evidence.
