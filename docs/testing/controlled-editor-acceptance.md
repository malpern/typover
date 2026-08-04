# Controlled-editor acceptance

- Status: Development build accepted; exact release-candidate rerun pending
- Updated: 2026-08-03

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

## Release-candidate gate

Repeat the visible continued-typing, Change Back, Undo, contextual, and
earlier-caret rows against the exact notarized candidate. Repeat the focused
automated suite against the candidate revision. The release gate fails if any
correction replaces more than the intended range, loses a sibling annotation,
interrupts marked-text composition, or cannot be undone as one transaction.
