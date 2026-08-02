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
