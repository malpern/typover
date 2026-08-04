# HID harness could not restore the prepared Bear note

- Status: Fixed, covered, and physically verified
- Discovered: 2026-08-01
- Scope: Physical Bear evidence admission, not Typover correction behavior

## Symptom

A controlled CPU run passed quiet-host admission and opened the nonactivating
Jig, but Bear never exposed a collapsed caret at the end of the disposable note.
The harness timed out before arming or starting the ESP32, so no HID input or
Typover product result was credited.

## Cause

The note and caret were prepared before the run. After Jig setup and quiet
admission, the harness activated Bear generically. App activation did not prove
which Bear window or note became key, so the final fail-closed Accessibility
gate could reject a correctly prepared note—or, without that gate, physical
input could have reached the wrong note.

## Fix

Every run now requires an explicit disposable Bear note UUID. Immediately
before the terminal caret gate, the harness uses Bear's official CLI to read the
note, calculate its terminal UTF-8 byte offset, and reopen that exact note with
a collapsed selection. Accessibility remains authoritative: HID cannot start
unless Bear is frontmost and reports the selection at the document end.

Pure tests cover trailing-newline handling, multibyte content, invalid IDs, and
the exact CLI argument contract. Command-line rejection checks cover missing and
malformed note IDs without contacting the fixture.

The first implementation retained an older assumption that the CLI caret
should precede Bear's terminal newline. Live comparison proved that byte offset
mapped to Accessibility location 41 in a 42-unit editor. The full CLI content
byte count maps to location 42 and is therefore the only offset admitted by the
existing end-of-document gate. The helper and regression now preserve that
mapping.

## Evidence boundary

The later CPU, WindowServer, Accessibility, combined, and punctuation runs all
reopened the explicit note, passed the terminal-caret Accessibility gate, and
completed without focus loss. The canonical combined run corrected 80/80 words
with complete fixture, text, log, and resource evidence.
