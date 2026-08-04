# HID harness sampled Bear before post-burst convergence

- Status: Fixed, covered, and physically verified
- Observed: 2026-08-01
- Surface: Combined-load physical evidence and correction-latency telemetry

## Symptom

At 40 milliseconds per key under combined CPU, WindowServer, and Accessibility
contention, the harness captured 7 corrected and 13 preserved `teh` segments
after its fixed 1.5-second settle delay. Typover had already logged 11 verified
applications, so the harness correctly classified the evidence as invalid. A
read-only Bear CLI check moments later showed the full segment at 20/20.

The same artifact exposed implausibly small correction latencies. Unified logs
formatted values with locale grouping—for example `4,774.841`—but the parser
accepted only digits through the first comma and recorded `4`.

## Cause

The post-burst catch-up pass is deliberately bounded and serialized. Severe AX
contention delayed its scan and exact-range transactions beyond the harness's
fixed observation point. A single snapshot could therefore land in the middle
of safe convergence even though the selected load was still active.

Telemetry used a localized number formatter while the evidence parser assumed
an ungrouped decimal representation.

## Fix

Schema 4 keeps the controlled load active while it observes the exact inserted
range for at least 1.5 seconds and at most 10 seconds. It records both total
post-fixture observation time and time to full correction. Focus loss still
invalidates the case, and reaching the deadline still preserves the existing
safe-miss, unexpected-text, and log-matching rules; the harness never waits
without a bound or turns incomplete evidence into a pass.

The producer now emits POSIX, ungrouped millisecond values. The parser also
accepts historical grouped values so older local artifacts remain interpretable.

## Evidence

Focused tests cover grouped, ungrouped, and absent latency values and pin the
10-second convergence bound in the default matrix. The isolated schema-4 40
millisecond combined row passed 20/20. A fresh consolidated combined matrix
then passed 80/80 across 160, 100, 60, and 40 milliseconds per key, converging
within 1.59–3.79 seconds with complete load evidence and zero late HID reports.
