# Controlled-editor acceptance

- Status: Exact notarized candidate accepted; one pointer-only menu rerun pending
- Updated: 2026-08-04

This is the human-facing acceptance gate for Typover's owned AppKit/TextKit
editor. Automated tests remain the safety backstop, but they do not replace
inspection of the installed interaction.

## Installed development-build evidence

The installed Apple Development-signed app from revision
`3ee319cc4424faae3d28abd05787860e39095ce5` passed the following checks on
macOS 27.0:

| Interaction | Observed result |
|---|---|
| Continued typing | Typing `teh teh teh ` in one uninterrupted action produced `the the the `. |
| Independent annotations | All three corrections retained separate light-gray squiggles. |
| Change Back | Reverting the first correction restored only its original `teh`; both later annotations remained. |
| One-step Undo | Command-Z restored the first correction and all three annotations. |
| Contextual correction | Typing `We should of left earlier.` produced `We should have left earlier.`. |
| Earlier caret | Completing that sentence inside surrounding earlier text corrected only the sentence and preserved text before and after it. |

A follow-up development build added content-free transaction timing. Three
consecutive local spelling corrections completed in 0.397, 0.350, and 0.461
milliseconds respectively. The log records only elapsed time and document
UTF-16 length; it never records typed or corrected text.

## Automated safety evidence

`EditorStressTests` covers the cases that are difficult to inspect reliably in
a live acceptance pass, including active marked-text composition refusal,
stale contextual-result refusal, large-document earlier-caret correction,
punctuation and paragraph boundaries, paste refusal, multiple annotations, and
Undo/Redo. The focused 32-test suite passed after the timing instrumentation
was added.

## Exact notarized-candidate evidence

Candidate `0.1.0 (20260804072103)` from clean revision
`e38f535ee2715ff52a8247a9e19e7b882996e13e` passed the installed interaction
gate on macOS 27.0:

| Interaction | Observed result |
|---|---|
| Continued typing | One uninterrupted `teh teh teh ` action produced `the the the `. |
| Independent annotations | All three words retained distinct light-gray squiggles. |
| Contextual correction | A separately typed final period started the on-device request and `We should of left earlier.` became `We should have left earlier.`. |
| Earlier caret | Inserting and completing that sentence between `Earlier text.` and `Later text.` corrected only the inserted sentence and preserved both neighbors. |
| Build identity | About showed version `0.1.0`, build `20260804072103`, and source `e38f535ee2`. |
| Settings automation | The installed Writing Model, scope, rewrite, Bear, permission, and pane controls exposed their documented Accessibility identifiers. |

This pass found and fixed a release-only sentence-boundary defect. The former
method-reference expression classified ordinary characters as terminators in
the optimized binary even though the debug suite passed. The implementation
now uses an explicit scalar predicate, the regression table includes ordinary
letters, digits, whitespace, and punctuation, and the beta build runs that
test in `release` configuration before signing. See
[the bug record](../bugs/2026-08-04-release-sentence-boundary-optimization.md).

The exact candidate's pointer-only Change Back menu could not be re-opened by
the automation driver because its coordinate click could not target the
restored Space. The immediately preceding notarized candidate passed Change
Back, sibling retention, and Undo, and the final revision did not change those
paths. That is useful regression evidence, but it is not substituted for the
remaining exact-candidate pointer click.

## Release-candidate gate

The exact candidate has passed continued typing, independent annotations,
contextual correction, and earlier-caret rows. Repeat the pointer-only Change
Back and its one-step Undo once the window is on the active Space. The full
338-test debug suite and the safety-critical optimized test pass at the
candidate revision. The release gate fails if any
correction replaces more than the intended range, loses a sibling annotation,
interrupts marked-text composition, or cannot be undone as one transaction.
