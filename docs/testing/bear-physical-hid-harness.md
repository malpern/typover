# Bear physical HID harness

- Status: Quiet board-backed baseline passes all four timing rows
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

## Physical run

Use a disposable Bear note, place a collapsed caret at the end, and do not use
the Mac while the matrix runs. Then execute:

```bash
Scripts/typover-hid-harness run --exclusive-desktop-confirmed
```

After a quiet baseline, controlled contention can be selected explicitly:

```bash
Scripts/typover-hid-harness run --exclusive-desktop-confirmed --load-profile cpu
Scripts/typover-hid-harness run --exclusive-desktop-confirmed --load-profile window-server
Scripts/typover-hid-harness run --exclusive-desktop-confirmed --load-profile accessibility
Scripts/typover-hid-harness run --exclusive-desktop-confirmed --load-profile combined
```

The runner waits for three host samples with at least 60% CPU idle and no
active Swift compiler. It refuses to start unless Typover is running and the
fixture reports a mounted USB keyboard. Before the quiet-host wait it opens the
Jig monitor and shows a focus gate. After the host becomes quiet, the harness
activates Bear itself and waits up to two minutes for a focused collapsed caret
at the end of the editor. It holds an explicit macOS display/system wake
assertion until the run ends, and every generated load source is terminated on
normal completion or failure. It rechecks the caret after load, arm, and monitor
setup, watches the frontmost application throughout the delayed start and HID
burst, and aborts the fixture if Bear loses focus. The monitor remains visible
on the final verified result.

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

The first quiet run is a baseline. Schema version 2 adds controlled CPU,
WindowServer, Accessibility, and combined contention using the same exact-text
and fail-closed evidence contract.

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
