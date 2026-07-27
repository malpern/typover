# Bear Phase 8 automatic-correction matrix

- Status: Automatic multi-correction safety slice implemented
- Updated: 2026-07-27
- Default: Off
- Engine: Apple Spelling, on device

The deterministic gate passes with 217 tests in 24 suites. The signed
development build is deployed to `/Applications/Typover.app`, and automatic
Bear correction is enabled locally for the live pass. The installed interaction
rows remain pending until ordinary Bear keystrokes can be exercised and
observed end to end.

Mutation is now gated to the environment actually under validation: Bear
2.8.1 on macOS 27.0. An unknown Bear version, an unvalidated macOS minor
version, missing Bear bundle metadata, or any missing required Accessibility
notification disables automatic mutation and produces an explicit status.
The support claim will widen only after another version passes this matrix.
If typed-boundary monitoring is temporarily unavailable, Typover stops its
Bear observer, reports the unavailable state, and retries from a fresh baseline
on the next application activation.

The automatic coordinator also keeps session-only, content-free counts for
boundary inputs, Bear value changes, applied corrections, safe skips, and
refusals. It samples correction-to-visible-annotation latency and successful
menu-action-to-verified-change latency without retaining the original word,
replacement, surrounding text, note identity, or document content. Settings
exposes only the content-free totals and timing summaries.

A completion key authorizes a Bear value change for at most 750 milliseconds.
If the matching Accessibility change arrives later, Typover records a safe
skip and does not write. This prevents an old keypress from authorizing an
unrelated later edit. The exact inserted boundary must also equal the observed
key, so a Space cannot authorize a period transition or vice versa.

This matrix covers the transition from the manual Bear preview harness to
automatic correction during ordinary typing. Deterministic checks establish
policy and transaction behavior. A row is not complete until the installed app
also passes in Bear.

| Scenario | Deterministic status | Installed Bear status | Expected result |
|---|---|---|---|
| Type `teh` and Space | Passed | Passed 2026-07-26 | Only `teh` becomes `the`; caret stays after the Space; gray squiggle appears |
| Type `teh` and punctuation | Passed for period, question mark, and newline with exact key-to-transition matching | Pending | Exact word changes; punctuation and caret remain untouched |
| Paste `teh ` | Passed for bulk/coalesced change | Pending | No correction and no squiggle |
| Paste only a boundary after `teh` | Passed through missing-keystroke refusal | Pending | No correction |
| Active selection | Passed, including fresh-baseline resume | Pending | Observation pauses; no write |
| Bounded context changes | Passed | Pending | Refuse without writing |
| Change Back | Passed with learning | Pending | Restore only the word and suppress the same learned correction |
| Choose an alternative | Overlay callback passed | Pending | Replace only the anchored word and remember the choice |
| Continue typing rapidly | Exact-range and anchor suites pass | Pending | Preserve all later input; safe miss if events coalesce |
| Switch notes or windows | Passed; focus changes disarm in-flight input before reattachment | Pending | Reattach only to the newly focused Bear editor |
| Typover disabled | Passed; stop and fresh re-enable lifecycle covered | Pending | Stop observation and hide the active Typover annotation |
| Marked-text composition | Composition-changing transitions are rejected | Pending | Never correct while composition is active |
| Undo/Redo | Command-Z and Shift-Command-Z explicitly disarm correction | Pending | Do not treat Undo/Redo as new typing |
| Multiple recent corrections | Passed; independent actions and 24-session bound | Pending | Keep each valid correction independently reversible |
| Sentence correction | Not yet implemented | Pending | Run selected local model asynchronously after a verified terminator |

## Input-safety pass: 2026-07-26

The signed development app containing the input-intent safety changes is
deployed to `/Applications/Typover.app`. The deterministic gate passes 217
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

## Editor-focus recovery pass: 2026-07-27

The installed app now distinguishes “Bear is frontmost” from “Bear's note body
is focused.” Bear's official CLI and ordinary navigation can initially leave
focus in a title or search field, and in that state Bear may expose either one
inactive text area or no safely identifiable text area. Previously Typover
retried for a short period and then had no observer left to notice a later click
into the note body.

Typover now installs a content-free, application-level waiting observer when no
editor can be identified unambiguously. That observer registers only Bear focus
and window notifications. It does not read text and cannot authorize a
correction. When the native note body becomes focused, Typover restarts from a
fresh baseline, registers the editor value and selection notifications, and
then begins boundary monitoring. Stage-specific logs now distinguish missing
Accessibility trust, Bear absence, observer creation failure, notification
registration failure, and the safe waiting-for-editor state.

The signed build was deployed to `/Applications/Typover.app`. In Bear 2.8.1 on
macOS 27.0 it logged the waiting state after a non-edit fixture open, then
upgraded to **Bear automatic observation ready** after the same fixture was
opened for editing. The content-free live capability probe then passed with one
focused `AXTextArea`, bounded range access, exact-range write support, geometry,
and every required notification. Computer Use continued to time out while
enumerating Bear's complete accessibility tree, so this pass does not advance
the remaining ordinary-keystroke rows.

## Privacy and safety boundary

The observer keeps only bounded, session-only text around the caret: at most 96
UTF-16 units before it and 24 after it. It never reads a whole note, never saves
the bounded text, never logs words, and never requires a Bear API token. A
correction proceeds only when a real unmodified completion key and Bear's
one-character text transition agree; either signal alone is insufficient.
