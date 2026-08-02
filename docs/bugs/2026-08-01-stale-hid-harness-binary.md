# Stale physical-harness release binary

- Status: Fixed
- Found: 2026-08-01
- Affected evidence: CPU-contention run at `23:47:36Z`

## Symptom

The controlled CPU run produced exact Bear text and 20 matching Typover
applications, but the harness classified the row `invalid-evidence`. Its
summary unexpectedly used schema version 2 and omitted every process power
field even though the checked-in harness source used schema version 3 and
required complete load evidence.

## Cause

`Scripts/typover-hid-harness` executed an existing release binary whenever it
was present. It did not determine whether the package sources were newer. The
binary therefore encoded an older artifact contract while the developer
reasonably believed the current source was running.

## Fix

The wrapper now invokes SwiftPM's incremental product build before every
command, including `doctor`, `snapshot`, and `run`. An unchanged build is fast;
a source change can no longer silently reuse an old harness. The build occurs
before quiet-host admission, so compiler activity cannot contaminate the
physical timing row.

`TYPOVER_HID_HARNESS_SKIP_BUILD=1` remains an explicit diagnostic escape hatch.
It must not be used for credited physical evidence.

The rejected schema-2 run remains rejected. Its 20/20 text and log result is
diagnostic information, not a credited controlled-load pass.
