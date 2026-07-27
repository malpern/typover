# Bear Phase 8 automatic-correction matrix

- Status: First opt-in word-correction slice implemented
- Updated: 2026-07-26
- Default: Off
- Engine: Apple Spelling, on device

The deterministic gate passes with 201 tests in 24 suites. The signed
development build is deployed to `/Applications/Typover.app`, and automatic
Bear correction is enabled locally for the live pass. The installed interaction
rows remain pending until ordinary Bear keystrokes can be exercised and
observed end to end.

This matrix covers the transition from the manual Bear preview harness to
automatic correction during ordinary typing. Deterministic checks establish
policy and transaction behavior. A row is not complete until the installed app
also passes in Bear.

| Scenario | Deterministic status | Installed Bear status | Expected result |
|---|---|---|---|
| Type `teh` and Space | Passed | Pending manual unlock | Only `teh` becomes `the`; caret stays after the Space; gray squiggle appears |
| Type `teh` and punctuation | Boundary classification passed | Pending | Exact word changes; punctuation and caret remain untouched |
| Paste `teh ` | Passed for bulk/coalesced change | Pending | No correction and no squiggle |
| Paste only a boundary after `teh` | Passed through missing-keystroke refusal | Pending | No correction |
| Active selection | Passed | Pending | Observation pauses; no write |
| Bounded context changes | Passed | Pending | Refuse without writing |
| Change Back | Passed with learning | Pending | Restore only the word and suppress the same learned correction |
| Choose an alternative | Overlay callback passed | Pending | Replace only the anchored word and remember the choice |
| Continue typing rapidly | Exact-range and anchor suites pass | Pending | Preserve all later input; safe miss if events coalesce |
| Switch notes or windows | Existing Phase 7 lifecycle tests pass | Pending | Reattach only to the newly focused Bear editor |
| Typover disabled | Coordinator policy implemented | Pending | Stop observation and hide the active Typover annotation |
| Marked-text composition | Not yet implemented | Pending | Never correct while composition is active |
| Undo/Redo | Existing transaction tests pass; input classification pending | Pending | Do not treat Undo/Redo as new typing |
| Multiple recent corrections | Not yet implemented | Pending | Keep each valid correction independently reversible |
| Sentence correction | Not yet implemented | Pending | Run selected local model asynchronously after a verified terminator |

## Privacy and safety boundary

The observer keeps only bounded, session-only text around the caret: at most 96
UTF-16 units before it and 24 after it. It never reads a whole note, never saves
the bounded text, never logs words, and never requires a Bear API token. A
correction proceeds only when a real unmodified completion key and Bear's
one-character text transition agree; either signal alone is insufficient.
