# Bear compatibility spike

- Status: Planned
- Created: 2026-07-25
- Initial target: Bear 2.8.1 on macOS 27

## Goal

Determine whether Typover can provide automatic, incremental, reversible
corrections while someone writes in Bear for macOS.

The spike should prove or disprove three capabilities independently:

1. replace one exact word through Bear’s active editor without rewriting the
   note;
2. preserve a reliable record that can restore the original word after later
   typing;
3. place a clickable light-gray squiggle beneath the corrected word and keep it
   aligned while the editor moves.

Success does not require Bear to render Typover’s annotation natively. An
external AppKit overlay is acceptable for the spike if its limitations are
measured explicitly.

## Prerequisite

First demonstrate the complete interaction in Typover’s controlled AppKit and
TextKit editor:

- [x] automatically replace one high-confidence misspelling;
- [x] preserve the original and replacement in `TypoverCore`;
- [x] render a persistent light-gray squiggle;
- [x] select the squiggle and restore the original;
- [x] preserve selection, caret position, and Undo behavior for the initial
      correction transaction;
- [ ] stress-test annotation alignment and state while scrolling a long
      controlled document.

The controlled editor is the reference implementation. Bear compatibility is
evaluated against it rather than defining the interaction while platform
uncertainties remain.

The first controlled-editor milestone was completed on 2026-07-25 with a
deterministic `teh` → `the` rule. It remains intentionally narrow. Before the
Bear probe, stress-test long-document scrolling; then replace the demo rule
with an on-device spelling candidate source without weakening the confidence
or range-safety policy.

## Known Bear surfaces

Bear 2.8.1 exposes its editor as an Accessibility `AXTextArea`. Local inspection
found these relevant attributes:

- `AXSelectedText`;
- `AXSelectedTextRange`;
- `AXVisibleCharacterRange`;
- `AXNumberOfCharacters`;
- `AXValue`.

`AXSelectedText`, `AXSelectedTextRange`, and `AXValue` currently report
themselves as writable. Typover must use selected-range replacement and must
not write the whole `AXValue`.

Bear also ships an official `bearcli` that can read notes and perform exact
string replacements. The CLI is useful for controlled tests, reconciliation,
and diagnostics. It is not the preferred live-typing path because database
edits may not preserve editor selection, onscreen state, or native Undo
grouping.

Bear’s x-callback URL API can identify and retrieve the selected note with an
API token. It may help associate an Accessibility editor with a stable Bear
note ID, but it is too coarse and expensive for per-word correction.

## Safety and privacy boundaries

- Use a dedicated disposable Bear note during development.
- Never run mutation experiments against an existing user note.
- Keep correction context on-device.
- Read only the smallest useful range around the insertion point.
- Never log note text, selected text, or correction context.
- Logs may contain application identity, attribute availability, ranges,
  lengths, timings, error codes, and hashes that cannot reconstruct the text.
- Do not request a Bear API token until a test specifically requires stable
  note identity.
- Do not read Bear’s database directly. Use the active editor, Bear’s documented
  CLI, or its documented URL API.
- Exclude encrypted or locked notes unless Bear provides a supported,
  user-visible integration path for them.

## Proposed components

### `TypoverCore`

Owns correction decisions, confidence thresholds, range-level diffs,
correction records, context fingerprints, and re-anchoring logic. It has no
dependency on Bear, Accessibility, AppKit, or TextKit.

### `TypoverAccessibility`

Finds the active application and focused editable element, reads a bounded
context range, reads and writes selection, performs the smallest possible
replacement, and subscribes to relevant Accessibility notifications.

### `TypoverBearAdapter`

Recognizes Bear’s editor, normalizes Bear-specific behavior, associates windows
with note identity when possible, and exposes explicit capability results
rather than assuming every Bear version behaves the same.

### `TypoverOverlay`

Requests screen geometry for a corrected range, renders a nonactivating
clickable annotation, tracks window and scroll changes, and opens the
correction menu without stealing the writer’s insertion point.

## Phase 1: Accessibility capability probe

Build a read-only diagnostic for the focused Bear editor.

Record:

- editor role and identifier;
- whether required attributes are present and writable;
- insertion-point and selected-range behavior;
- visible character range;
- supported parameterized attributes, especially bounds for a character range;
- notifications emitted for selection, value, focus, window, and layout
  changes.

Do not print or persist the editor’s text.

### Acceptance criteria

- Typover can reliably locate one focused Bear editor without depending on a
  fragile UI-element index.
- It can read the caret range and a bounded context around it.
- The probe reports a structured capability result when an attribute is
  missing or unsupported.

## Phase 2: Exact range replacement

In the disposable note, type a known misspelling followed by Space. Replace only
the misspelled word through the active `AXTextArea`.

The replacement transaction should:

1. capture the current selection;
2. verify the expected typo still occupies the target range;
3. select only that range;
4. set `AXSelectedText` to the replacement;
5. restore the caret relative to the inserted text;
6. verify the resulting local context;
7. create a correction record only after verification succeeds.

Do not fall back to writing the complete `AXValue`.

### Acceptance criteria

- The surrounding note remains byte-for-byte equivalent except for the target
  word.
- Bear’s Markdown styling and attachments are unaffected.
- The caret returns to the expected position.
- A failed precondition makes no edit.
- Repeating the transaction is idempotent.

## Phase 3: Undo and restoration

Measure Bear’s native Undo behavior after an Accessibility replacement. In
parallel, implement Typover’s independent Change Back transaction using the
correction ledger.

Restoration must re-anchor the correction from nearby context rather than trust
an old absolute offset after later typing.

### Acceptance criteria

- Command-Z produces a documented, understandable result.
- Typover can restore the original word without undoing later user edits.
- Restoration refuses to edit when the replacement can no longer be uniquely
  identified.
- A correction record transitions through explicit applied, restored,
  superseded, or invalidated states.

## Phase 4: Range geometry

Query Bear for the screen bounds of the corrected character range. Test:

- the word on the first, middle, and last visible line;
- wrapped lines;
- variable-width text;
- headings, lists, links, and inline code;
- the word near attachments;
- editor zoom and typography changes;
- separate Bear windows.

### Acceptance criteria

- Visible corrected ranges produce stable screen-space rectangles.
- Offscreen ranges are recognized as offscreen rather than placed at stale
  coordinates.
- Geometry can be refreshed without reading the whole note.
- Unsupported geometry produces a clear capability failure.

## Phase 5: Annotation overlay

Render the light-gray squiggle in a borderless, nonactivating AppKit panel. The
overlay must not intercept typing or activate Typover when the writer is merely
moving the caret.

Reposition or hide the annotation when Bear:

- scrolls;
- moves or resizes its window;
- changes the note;
- changes editor width or typography;
- loses focus;
- removes or edits the anchored text.

### Acceptance criteria

- The mark remains visually aligned during ordinary typing and scrolling.
- No stale mark is shown over unrelated text.
- The overlay does not appear in screenshots of other spaces or windows.
- Typing latency remains imperceptible.

## Phase 6: Correction interaction

Make the annotation clickable without losing the correction target. Present:

- Change Back to the original;
- alternative corrections, when available;
- Keep Correction, which removes the annotation.

### Acceptance criteria

- Opening the menu does not corrupt Bear’s caret or selection.
- Change Back performs the verified restoration transaction.
- Choosing an alternative updates the existing correction record.
- Dismissing the menu leaves the document unchanged.
- Keyboard and VoiceOver users can reach equivalent actions.

## Phase 7: Robustness matrix

Run the full interaction against:

- short and long notes;
- repeated occurrences of the same typo;
- rapid typing immediately after correction;
- edits before and after an anchored correction;
- multiple Bear windows;
- switching notes while a correction is pending;
- Bear relaunch and Typover relaunch;
- light and dark appearances;
- scrolling while a correction request is in flight;
- Markdown constructs and attachments;
- at least one previous supported Bear release, if available.

Track correctness, annotation alignment, replacement latency, and reasons for
every refused correction.

## Bear CLI fallback evaluation

Separately test Bear’s official CLI in the disposable note:

- exact single-word replacement;
- repeated-word ambiguity;
- open-note refresh behavior;
- selection and caret preservation;
- native Undo behavior;
- modification date and sync behavior;
- attachment safety rejection.

The CLI may become a recovery or post-writing backend only if these tests show
that it preserves Bear’s application invariants. It must not silently replace
the Accessibility path for live typing.

## Risks and fallbacks

| Risk | Preferred response |
|---|---|
| Selected-range replacement is unreliable | Stop the live integration; do not use whole-note replacement |
| Character-range bounds are unavailable | Offer correction without an inline mark, or limit Bear support to a recent-correction control |
| Overlay drifts during layout changes | Hide immediately and recompute; never leave a confidently misplaced mark |
| Markdown presentation offsets differ from accessible offsets | Keep all live ranges in Bear’s Accessibility coordinate space |
| Earlier edits invalidate stored offsets | Re-anchor from bounded surrounding context and require a unique match |
| Native Undo is confusing | Keep Change Back independent and document the native Undo limitation |
| Duplicate text makes the target ambiguous | Refuse the edit rather than choose an occurrence |
| Typing outruns correction | Cancel stale work using a generation or context fingerprint |
| Bear changes its Accessibility tree | Fail capability detection cleanly and disable Bear integration for that version |

## Exit criteria

Classify the result as one of:

### Full compatibility candidate

Range replacement, restoration, geometry, and the clickable overlay all pass.
Proceed toward a supported Bear integration.

### Correction-only candidate

Range replacement and restoration pass, but annotation geometry or overlay
tracking is not reliable. Consider an explicitly limited Bear mode without the
inline squiggle.

### Cooperative integration required

Correction works, but the defining visible and reversible interaction cannot be
delivered externally. Prepare a concrete integration proposal for the Bear
team using evidence from the controlled editor and failed overlay tests.

### Unsupported

Exact range replacement or safe restoration cannot be made reliable. Do not
ship Bear support and do not fall back to whole-note replacement.

## Deliverables

- A reusable Accessibility capability report.
- Automated tests for correction transactions and re-anchoring.
- A disposable-note Bear test procedure.
- Screen recordings of the controlled editor and Bear experiments.
- A compatibility matrix with failure reasons.
- A short decision record selecting one of the exit classifications above.
