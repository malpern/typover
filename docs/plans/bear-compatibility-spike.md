# Bear compatibility spike

- Status: Phase 2 complete — independent restoration is next
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

- [x] automatically replace one narrowly eligible misspelling;
- [x] preserve the original and replacement in `TypoverCore`;
- [x] render a persistent light-gray squiggle;
- [x] select the squiggle and restore the original;
- [x] preserve selection, caret position, and Undo behavior for the initial
      correction transaction;
- [x] stress-test annotation alignment and state while scrolling a long
      controlled document.
- [x] replace the demo rule with Apple’s local spelling engine and ranked
      alternatives;
- [x] support cursor-relative correction, capitalization, Unicode accents, and
      internal apostrophes while leaving surrounding text unchanged;
- [x] complete the correction corpus and editing-robustness gate in the
      [controlled-editor roadmap](controlled-editor-roadmap.md).

The controlled editor is the reference implementation. Bear compatibility is
evaluated against it rather than defining the interaction while platform
uncertainties remain.

The prerequisite gate is complete. Apple remains Typover's default model
because it keeps private writing on device and performed competitively in the
reviewed rewrite benchmark. Phase 1 is intentionally read-only and does not
invoke any model or depend on a Bear API token.

The first controlled-editor milestone was completed on 2026-07-25 with a
deterministic `teh` → `the` rule. The second milestone replaced that demo rule
with `NSSpellChecker`, retained a deliberately narrow binary eligibility
policy, added ranked alternatives and Apple correction feedback, and kept all
processing on device. The initial long-document scrolling test also passes.

The reference editor now uses a TextKit 2-backed `NSTextView` and the macOS 27
viewport-layout callback. This is the baseline for the long-document scrolling
test; the Bear overlay remains a separate Accessibility and screen-geometry
problem.

The initial scrolling test used corrections at opposite ends of a 35-line
document. Each annotation disappeared offscreen, reappeared in alignment after
scrolling back into the viewport, and remained clickable.

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

### Automation and scripting research: 2026-07-25

Bear 2.8's supported external automation surfaces are useful, but none replaces
the live Accessibility path:

- `bearcli` and Bear's official MCP server expose local note-level search,
  read, create, append, and edit operations. `bearcli edit` finds exact strings
  with Bear's in-app search engine; it does not address the active editor by a
  selected character range or preserve its caret as part of the operation.
- The CLI has valuable safety behavior for scripting, including rejecting
  attachment-removing edits unless explicitly forced. Encrypted notes can be
  listed but not read or modified.
- x-callback URLs can open the selected note, place the cursor in its editor,
  return note content, and append, prepend, or replace note-level content. They
  do not expose the current selection range, text-layout geometry, editor
  notifications, or a range-level replacement transaction.
- Bear's Shortcuts actions cover note creation, lookup, search, opening,
  appending, tagging, exporting, and related note-level operations. The app
  advertises no action for replacing the active editor selection.
- The installed Bear 2.8.1 app has no AppleScript scripting dictionary.
- Bear uses the macOS spelling-and-grammar controls in its Edit menu, which
  supports the hypothesis that its editor participates in standard macOS text
  services. This does not provide an extension point for Typover's persistent
  annotation.

The first Phase 2 fixture run also demonstrated that a `bearcli search-in`
offset does not identify the same character in Bear's Accessibility editor.
The guarded transaction rejected the mismatched range before writing. Raw
Markdown, CLI, and Accessibility offsets must therefore never be mixed.

Decision: use Bear's official CLI only for disposable fixture setup, stable
note identity, diagnostics, and possible reconciliation. Use the focused
`AXTextArea` as the sole coordinate system for live correction, caret
restoration, and annotation geometry. Do not add a Bear API token, Shortcuts
dependency, MCP connection, or AppleScript bridge to the live typing path.

Primary references:

- [Bear command-line interface](https://bear.app/faq/command-line-interface/)
- [Bear x-callback URL scheme](https://bear.app/faq/x-callback-url-scheme-documentation/)
- [Bear 2.8 CLI announcement and search-engine clarification](https://community.bear.app/t/bear-2-8-bearcli-claude-connector-and-mcp-server/19072)
- [Bear Shortcuts automation overview](https://blog.bear.app/2022/03/automate-your-notes-with-shortcuts-and-bear/)
- [Bear spelling and grammar controls](https://bear.app/faq/disable-spell-check-and-corrections/)

## Safety and privacy boundaries

- Use a dedicated disposable Bear note during development.
- Never run mutation experiments against an existing user note.
- Keep all Phase 1 probe context on-device; the probe does not invoke the
  optional cloud model path.
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

Owns correction decisions, binary eligibility rules, range-level diffs, and
generic correction records and dispositions. It has no dependency on Bear,
Accessibility, AppKit, or TextKit.

### `TypoverAccessibility`

Finds the active application and focused editable element, reads a bounded
context range, reads and writes selection, performs the smallest possible
replacement, stores Bear-specific content-private context fingerprints,
re-anchors those ranges, and subscribes to relevant Accessibility
notifications.

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

### Live result: 2026-07-25

The first content-free run against Bear 2.8.1 (14428) on macOS 27 found the
current window's sole `AXTextArea` by role traversal. The search deliberately
does not descend through the note-list table, so a large library cannot crowd
the editor out of a bounded traversal. It does not use a UI-element index.

The run confirmed:

- `AXSelectedText`, `AXSelectedTextRange`, `AXVisibleCharacterRange`, and
  `AXValue` are writable; `AXNumberOfCharacters` is readable;
- both string-for-range readers and `AXBoundsForRange` are available;
- a bounded 42-UTF-16-unit context was read and immediately reduced to its
  length; the probe emitted no note text in its structured report;
- caret/selection range, visible range, character count, and range geometry
  were returned;
- registration succeeded for selection, value, layout, focused-element, and
  focused-window notifications.

The note list held keyboard focus during this first run. The report
distinguishes that state from a focused editor instead of treating the
window's only text area as focused.

A second content-free run used the dedicated
`Typover Disposable Lab — 2026-07-25` note with Bear's editor focused. Bear
accepted registrations for selection, value, layout, focused-element,
focused-window, moved-window, and resized-window notifications. Six
navigation-key actions changed only the caret and produced four
`AXSelectedTextChanged` notifications. The monitor recorded notification names
and counts only.

`AXValueChanged` was registered but deliberately not triggered: doing so would
require a text mutation, which belongs to Phase 2. Window, focus, and layout
registrations are available for later overlay tracking; Phase 1 does not need
to force every notification merely to prove that caret-relative work can begin.

Decision: **go** for exact selected-range replacement and external overlay
geometry. The first mutation test must remain in the dedicated disposable note
and must not fall back to whole-value replacement.

### Acceptance criteria

- Typover can reliably locate one focused Bear editor without depending on a
  fragile UI-element index.
- It can read the caret range and a bounded context around it.
- The probe reports a structured capability result when an attribute is
  missing or unsupported.
- With the editor focused, caret movement produces a content-free selection
  notification that Typover can use to invalidate or refresh scoped state.

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

### Live result: 2026-07-25

The first live attempt deliberately supplied a `bearcli search-in` offset. The
transaction found that `teh` did not occupy that Accessibility range and
returned `preconditionFailed` without selecting or changing text. A second
attempt inferred the range from the caret in a tagged fixture, but Bear had
placed the caret after the bottom tag rather than after the CLI-appended marker;
that attempt also failed safely without a write.

The successful run used the tag-free
`Typover Bear Phase 2 — 2026-07-25` disposable note, with the caret immediately
after `teh `. Typover:

- verified the three-unit target at Accessibility location 145;
- wrote only `AXSelectedText`;
- changed exactly `teh` to `the`;
- restored the zero-length caret to its original location 149;
- verified the bounded surrounding context and unchanged document length;
- created a correction record only after those checks passed;
- treated the repeated transaction as already applied without another write.

Bear's native Command-Z restored `teh`. After Undo, Bear selected the restored
word at range 145–148 instead of leaving the caret after the following space.
That behavior is coherent for native Undo but is more disruptive than Typover's
planned correction-specific Change Back interaction.

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

### Live result: 2026-07-25

Phase 3 now stores a SHA-256 fingerprint of up to 40 UTF-16 units immediately
before and after each verified replacement. It retains the correction range
and note length but does not retain or serialize the surrounding prose.

Change Back searches two bounded Accessibility neighborhoods: the original
location and the location adjusted by the note's net length change. It restores
only one candidate whose leading and trailing fingerprints both match. This
supports later typing before or after the correction without scanning or
rewriting the whole note.

Deterministic tests verify restoration after edits on either side, recognition
of an already restored word, superseding after a manual word change, and
refusal after stale or duplicated context. Ambiguous and stale anchors perform
no write. The Bear adapter maps successful, superseded, and invalidated
outcomes to explicit correction-record dispositions.

The opt-in live transaction ran in the retained tag-free
`Typover Bear Phase 2 — 2026-07-25` note. It changed the synthetic marker from
`teh` to `the`, restored it through Typover's independent Change Back path, and
left the final marker as `teh`. This path did not invoke Bear's Undo command.

Decision: **go** for Phase 4 range geometry. Typover's menu action can now be
independent of Bear's global Undo stack.

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

### Live result: 2026-07-25

Phase 4 now exposes a content-free geometry report with explicit available,
offscreen, stale, ambiguous, superseded, unsupported, failed, and invalid
states. It reuses Phase 3's bounded anchor resolver, so edits before a
correction move the geometry range without trusting an old offset. Production
refresh reads at most two bounded Accessibility neighborhoods rather than the
whole note.

The first live run returned an identical usable rectangle for three consecutive
reads of the synthetic corrected word. The expanded matrix used the retained
`Typover Bear Phase 4 Geometry — 2026-07-25` note, which contains only synthetic
text and a Typover icon attachment. It verified markers on top, middle, bottom,
wrapped, heading, list, variable-width, link, inline-code, and attachment-adjacent
content. Selecting each marker to scroll it onscreen produced stable bounds;
querying the top marker while the bottom remained visible returned `offscreen`
without a bounds result.

A second, narrower Bear window exposed an important behavior: a range split by
wrapping returns one stable union rectangle covering unrelated space between
the two lines. Typover now detects that case, queries composed-character bounds,
and returns one fragment per rendered line. The narrow-window heading and
variable-width markers each resolved to two precise fragments. The same matrix
passed in separate windows with different origins and widths.

Two levels of Bear zoom changed body-line height from 27 to 33 points and
heading-line height from about 31 to 39 points. Geometry refreshed correctly at
the new scale, including wrapped fragments, and Bear was returned to Actual
Size afterward.

The live fixture test may read its complete synthetic note solely to locate
known markers. Shipping geometry uses only bounded context. Deterministic tests
also verify long-note bounded reads, edits before the correction, offscreen and
partially visible ranges, stale and duplicated anchors, manual supersession,
unsupported queries, invalid rectangles, wrapped fragmentation, adapter
gating, and content-free reports.

Decision: **go** for Phase 5. Bear's geometry is sufficient for a guarded
annotation overlay when Typover uses line fragments and hides every nonavailable
state.

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
- alternative corrections, when available.

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
