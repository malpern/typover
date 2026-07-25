# macOS Dictation QA

- Status: Ready for manual validation
- Updated: 2026-07-25
- Scope: Typover’s controlled editor only

## Why this remains manual

AppKit exposes marked-text composition, which Typover tests automatically, but
it does not expose a supported API for starting a genuine macOS Dictation
session with deterministic audio. Injecting text would only retest
`NSTextInputClient`; it would not validate the system Dictation lifecycle,
permissions, cancellation, or final commit behavior.

## Expected behavior

- Dictated text remains exactly as macOS commits it.
- Typover never edits partial or marked Dictation text.
- Dictation creates no duplicate or stale correction annotations.
- Existing light-gray correction annotations remain aligned.
- Typing a misspelled word after Dictation still corrects normally.
- No dictated text appears in Typover diagnostics or statistics.

## Test setup

1. Open Typover’s controlled editor.
2. Use disposable text only.
3. Enable Dictation in System Settings if macOS requests it.
4. Keep Typover’s Statistics & Preferences window available to verify that
   Dictation itself does not create correction activity.

## Manual matrix

| Scenario | Action | Pass condition |
|---|---|---|
| End of document | Dictate one sentence, then stop Dictation. | The final text matches macOS output and has no Typover annotation. |
| Earlier caret | Move into an earlier paragraph and dictate a sentence. | Only macOS inserts text at the caret; surrounding text and annotations remain unchanged. |
| Selection replacement | Select disposable text and dictate a replacement. | macOS replaces only the selection; Typover adds no stale or duplicate annotation. |
| Existing correction nearby | Type `teh ` to create `the` with a light-gray squiggle, then dictate before and after it. | The existing annotation follows its text and remains clickable. |
| Cancellation | Start Dictation, speak briefly, then cancel before commit. | Typover makes no correction and leaves no annotation. |
| Resume typing | Finish Dictation, then type `teh ` normally. | The typed word becomes `the` exactly once and receives one light-gray squiggle. |
| Undo and Redo | Undo and Redo the Dictation insertion, then the next typed correction. | Text and correction state remain understandable with no duplicate mark. |

## Result record

Record the macOS build, input language, microphone route, and pass or failure
for each row. Do not paste dictated content into bug reports. A failure report
may include only scenario name, ranges, lengths, correction identifiers,
timings, and screenshots made with disposable text.
