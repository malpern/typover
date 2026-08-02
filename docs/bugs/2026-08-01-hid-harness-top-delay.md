# HID harness used an unsupported `top` sample delay

- Status: Fixed, covered, and physically verified
- Observed: 2026-08-01
- Surface: controlled-load CPU, power, and idle evidence

## Symptom

The first schema-v2 CPU artifact contained per-process CPU and resident memory
from `ps`, but every process power score and load-sample CPU-idle value was
missing.

## Cause

The sampler invoked macOS `top` with `-s 0.2`. macOS 27 requires the sample
delay to be an integer and exits with `invalid argument for sleep interval`.
The harness treated resource sampling as best-effort, so that command failure
produced absent optional fields rather than invalidating the run.

## Fix

The shared sampling plan now uses a one-second delay, requests two samples, and
filters to Typover, Bear, and WindowServer PIDs. Parsers use the final CPU-usage
line and collect the three named power rows. Focused tests pin the exact `top`
arguments and parser output. A direct command on macOS 27 returned all three
process rows plus the final CPU-idle sample.

Current load artifacts contain non-null CPU-idle, CPU, resident-memory, and
power values for Typover, Bear, and WindowServer in every sample. The parser now
joins `top` power rows to the `ps` snapshot by PID, avoiding dependence on a
displayed command name. Focused macOS 27 output coverage and the canonical
combined physical matrix verify the corrected contract.
