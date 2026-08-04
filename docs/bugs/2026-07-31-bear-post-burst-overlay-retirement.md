# Bear overlays retired while verified edits were still settling

- Status: Fixed; installed retention and interaction passes completed
- Observed: 2026-07-31
- Surface: Bear automatic correction and gray-squiggle collection

## Symptom

A physical 20-word `teh ` burst corrected every word and initially displayed
all 20 gray squiggles. After the runtime settled, only the final six squiggles
remained.

## Cause

The overlay collection serialized verified edits, but each controller hid its
panel before entering that serialized re-anchor work. During a 20-correction
burst, the panels therefore disappeared in collection order while one AX
transaction at a time rebuilt its anchor. Bear value and selection
notifications could also request ordinary refreshes while the collection still
represented an intermediate document state, creating additional stale-anchor
windows.

The disappearing-after-settling pattern distinguished this from failure to
correct, missing initial geometry, or a fixed collection limit.

## Fix

The collection debounces closely spaced verified edits into one batch. For each
surviving controller it applies every relevant range transform in order, then
performs one re-anchor against the final Bear text. The last verified panel
placement remains visible while that re-anchor is in flight; a failed re-anchor
still ends tracking and hides it. Bear value and selection invalidations
received while a batch is pending or processing are suppressed; after the full
collection finishes, one shared fallback refresh validates the settled result.

An edit retains the controller-membership snapshot captured when it was
enqueued, so a newly added annotation still cannot process its own edit. Manual
or otherwise unverified ambiguous changes continue to fail closed.

## Regression coverage

- Three repeated corrections receive two closely spaced verified edits as one
  batch and each controller re-anchors once at its final range.
- A Bear value-change notification arriving before the batch finishes does not
  retire or hide the overlays, including while a deliberately slow serialized
  re-anchor remains in flight.
- The existing 20-overlay Change Back regression continues to preserve every
  unaffected sibling.
- The full suite passes 252 tests in 25 suites.

The 2026-08-01 installed physical test corrected 20/20 words at 160
milliseconds per character. Content-free overlay lifecycle telemetry recorded
20 exact visible ranges and zero hides through the settled observation window.
The follow-up installed gate also passed: changing back the fifth correction
retired only that overlay, and a later sibling menu opened immediately while
Bear remained frontmost.
