# HID harness wake assertion expired during quiet admission

- Status: Fixed, covered, and physically verified
- Observed: 2026-08-01
- Surface: unattended Bear physical HID evidence

## Symptom

Two controlled CPU attempts passed quiet-host admission, focused an empty Bear
note, and began the ESP32 burst. macOS then made `loginwindow` frontmost after
only a few physical reports. The harness aborted the board and classified both
runs `harness-invalid`; neither run is Typover product evidence.

## Cause

The harness launched `caffeinate -dimsu -w <pid>`. The `-u` assertion declares
the user active, but without an explicit timeout it lasts only five seconds.
Quiet admission itself takes longer than five seconds, so the user-active part
expired before the HID burst even though the display and system-sleep
assertions remained alive. The machine's lock policy could therefore activate.

## Fix

The wake plan now supplies a one-hour assertion timeout and still binds the
process lifetime to the harness PID:

```text
-dimsu -t 3600 -w <harness-pid>
```

The harness terminates `caffeinate` during normal cleanup; `-w` also releases
the assertions if the harness exits, and the one-hour timeout is a final bound.
An isolated seven-second check verified that the `UserIsActive` assertion was
still owned by `caffeinate` after the former five-second expiry point.

## Regression coverage

`BearHIDTestingTests.wakeAssertionPlan` fixes the complete argument contract,
including the bounded timeout and parent-process lifetime. The harness target
builds after the change. Later CPU, WindowServer, Accessibility, combined, and
punctuation runs remained unlocked and kept Bear frontmost through completion;
the canonical combined matrix corrected 80/80 physical words.
