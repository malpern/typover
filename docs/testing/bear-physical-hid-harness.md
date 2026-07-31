# Bear physical HID harness

- Status: Harness and visual monitor complete; first board-backed run pending
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
- Typover is running with local private diagnostics enabled;
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

The runner waits for three host samples with at least 60% CPU idle and no
active Swift compiler. It refuses to start unless Typover is running, the
fixture reports a mounted USB keyboard, and Bear has a focused collapsed caret
at the end of its editor. Before the quiet-host wait it opens the Jig monitor and
shows a focus gate; the runner then waits up to two minutes for the safe Bear
caret instead of requiring perfect setup at command launch. It rechecks that
caret after load, arm, and monitor setup, watches the frontmost application
throughout the delayed start and HID burst, and aborts the fixture if Bear loses
focus. The monitor remains visible on the final verified result.

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
samples, and Typover unified-log lines for the case. Because the development
private trace is enabled, those log lines can include bounded Bear context. The
files stay local and should be deleted or redacted before sharing.

## What this establishes

The matrix separates three layers that manual typing mixes together:

1. the ESP32 trace proves what physical keyboard reports were scheduled;
2. the exact Bear range proves what text arrived and what Typover changed; and
3. the Typover trace explains applied corrections and safe skips such as
   `contextChanged`.

The first quiet run is a baseline. Later work can add controlled CPU and
Accessibility contention using the same artifact schema, then compare current
behavior with the bounded post-burst catch-up design.
