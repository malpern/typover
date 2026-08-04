# Shared overlay fallback did work while Bear was inactive

- Status: Fixed, covered, deployed, and physically verified
- Observed: 2026-08-01
- Surface: Bear annotation lifecycle and background energy

## Diagnostic boundary

Computer Use can inspect and operate background windows without activating
their applications. Early Finder clicks therefore did not establish that Bear
had lost frontmost ownership, and their CPU traces are not credited as
inactive-app evidence.

The source audit still exposed a real scaling risk: the collection's shared
two-second fallback task continued to fan out to every tracked controller after
a workspace activation. Each inactive controller would call its presenter hide
path, including panel visibility checks, even though no geometry could be
shown. That work scaled to the 24-annotation session cap.

## Fix

- Pause the collection fallback task when a workspace activation identifies a
  non-Bear app or Bear is hidden.
- Restart the single task when Bear activates again.
- Before every fallback fan-out, make one collection-level frontmost-app check.
  This protects against a delayed or missed workspace notification without
  returning to one synchronous lookup per overlay.
- Leave correction, anchor, and geometry safety rules unchanged.

## Regression coverage

One collection test proves that hide work stops while Bear is inactive and
that fallback presentation resumes when Bear returns. A second test changes
the collection's frontmost-app source without sending a workspace notification
and proves no per-overlay refresh work occurs until Bear is frontmost again.

## Installed result

After an 8/8 physical Bear correction burst, the ESP32 sent a real
Command-Tab keypress and release. Both HID reports arrived with zero late
reports. Ten consecutive one-second samples then held Typover at 0.0% CPU with
no increase in accumulated CPU time. A later physical Command-F focus change
retired a 24-annotation Bear session and produced the same 0.0% CPU result.

The complete deterministic gate passes 287 tests in 29 suites. See
[Bear performance samples](../testing/bear-performance-samples.md) for the
memory measurements from the same installed build.
