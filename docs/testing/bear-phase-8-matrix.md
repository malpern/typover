# Bear Phase 8 automatic-correction matrix

- Status: Automatic multi-correction safety slice implemented
- Updated: 2026-07-26
- Default: Off
- Engine: Apple Spelling, on device

The deterministic gate passes with 208 tests in 24 suites. The signed
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
| Type `teh` and Space | Passed | Passed 2026-07-26 | Only `teh` becomes `the`; caret stays after the Space; gray squiggle appears |
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
| Marked-text composition | Composition-changing transitions are rejected | Pending | Never correct while composition is active |
| Undo/Redo | Command-Z and Shift-Command-Z explicitly disarm correction | Pending | Do not treat Undo/Redo as new typing |
| Multiple recent corrections | Passed; independent actions and 24-session bound | Pending | Keep each valid correction independently reversible |
| Sentence correction | Not yet implemented | Pending | Run selected local model asynchronously after a verified terminator |

## Input-safety pass: 2026-07-26

The signed development app containing the input-intent safety changes is
deployed to `/Applications/Typover.app`. The deterministic gate passes 208
tests. It now distinguishes a literal typed boundary from Command-Z and
Shift-Command-Z, and any later Undo/Redo key disarms an earlier boundary before
Bear's value change is considered. Shifted punctuation uses the actual typed
character, so `?` and `:` remain eligible completion boundaries.

Marked-text state is not assumed from a keyboard event. Instead, the observer
requires Bear's settled text to differ by exactly one literal boundary
character, with the preceding and following bounded text unchanged. Candidate
selection, composition updates, and composition commits that alter the marked
word therefore fail closed. A normal boundary typed after composition has
ended can still be corrected.

No installed rows were advanced in this pass: Computer Use disconnected while
opening Typover Settings, and the fallback UI driver was unavailable. Typover
and Bear remained running, and the installed Typover process logged that its
automatic observer was ready after Bear became frontmost. Deterministic
evidence is not recorded as a permissioned live-app pass. Composition,
Undo/Redo, shifted punctuation, and the multi-annotation path still require
observation in the installed apps.

## Privacy and safety boundary

The observer keeps only bounded, session-only text around the caret: at most 96
UTF-16 units before it and 24 after it. It never reads a whole note, never saves
the bounded text, never logs words, and never requires a Bear API token. A
correction proceeds only when a real unmodified completion key and Bear's
one-character text transition agree; either signal alone is insufficient.
