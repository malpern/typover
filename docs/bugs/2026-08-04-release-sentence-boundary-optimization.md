# Release-only sentence-boundary misclassification

- Found: 2026-08-04
- Fixed: `e38f535ee2715ff52a8247a9e19e7b882996e13e`
- Affected candidate: `0.1.0 (20260804070201)`
- First fixed candidate: `0.1.0 (20260804072103)`

## Symptom

The controlled editor corrected words normally in an optimized notarized
build, but completing `We should of left earlier.` did not start a contextual
model request. The same interaction succeeded in a debug build.

Content-free lifecycle logging showed that the optimized executable treated
every typed character as a sentence terminator. Each intermediate prefix was
too short to contain a completed sentence, so admission stopped before the
model request.

## Cause

`CompletedSentenceDetector.isSentenceTerminator` passed the instance method
reference `sentenceTerminators.contains` directly to `allSatisfy`. In the
optimized macOS 27 toolchain build used for distribution, that expression
returned true for ordinary characters. The equivalent explicit closure did
not reproduce the behavior.

The existing debug test indirectly covered a nonterminating space but release
tests had never compiled. One unrelated test referenced a `#if DEBUG` fault
injection helper without guarding the test itself, preventing an optimized
test product from building.

## Fix and prevention

- Use an explicit Unicode-scalar closure for `CharacterSet.contains`.
- Directly classify letters, digits, whitespace, commas, semicolons, colons,
  dashes, and the supported terminators.
- Guard the debug-only fault-injection test with `#if DEBUG`.
- Run the boundary regression in `release` configuration inside
  `Scripts/build-beta-app.sh` before signing or notarization.
- Retain content-free admission reason logging so a future failure can be
  placed before availability, proposal, resolution, or application without
  recording document text.

The full debug suite passed 338 tests in 30 suites after the fix. The focused
optimized regression passed, and the optimized installed UI then changed
`We should of left earlier.` to `We should have left earlier.`.
