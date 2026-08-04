# Cursor-relative correction behavior

- Status: Implemented in the controlled editor
- Updated: 2026-07-25

## Active writing location

Typover treats the current insertion point as the active writing location. The
end of the document has no special behavior. If the writer moves to an earlier
page or paragraph and starts typing, newly completed words at that caret follow
the same correction path as words typed at the end.

## Eligible target

Only the word immediately before a completion boundary is eligible for an
automatic edit. Completion boundaries currently include:

- Space, Return, and other whitespace;
- `.`, `,`, `!`, `?`, `;`, `:`, and `…`.

Typover does not correct the word while it is being composed or while AppKit has
active marked text from an input method.

Pasted text is treated as existing text rather than newly typed text, so a paste
never triggers automatic correction. Replacing a selection by typing still
uses the normal newly completed-word rule.

The initial word policy:

- accepts Unicode letters and combining accent marks;
- accepts internal straight (`'`) and curly (`’`) apostrophes;
- preserves lowercase, Capitalized, and ALL-CAPS patterns;
- leaves mixed-case words unchanged;
- requires the replacement to be exactly one insertion, deletion,
  substitution, or adjacent transposition away;
- rejects apostrophes at the beginning or end of a word.

Apple’s spell checker must first identify the word as misspelled. Typover does
not independently add accents to words Apple considers correctly spelled.

## Surrounding text

For the fast spelling path, existing text before and after the caret is
context-only. Moving the caret does not make surrounding prose eligible for
automatic replacement.

- A newly typed and completed word may change.
- Existing words before it remain unchanged.
- Existing words after it remain unchanged.
- Text elsewhere in the document remains untouched.

After the writer types `.`, `!`, `?`, or `…`, Typover may also analyze the most
recently completed sentence with the selected contextual model. Apple’s
on-device system language model is the default. The writer may explicitly
choose GPT-5.6 Terra or Claude Sonnet 5 in Settings after configuring that
provider through Add Secret. There is no automatic cloud fallback. The sentence
is capped at 400 UTF-16 code units. A contextual proposal may target a word or
short phrase earlier in that sentence, which allows valid-word errors to be
corrected after they have already been written.

Contextual work is asynchronous. The writer can continue typing after the
captured sentence while the model runs.

The Settings window separates two decisions:

- **Writing model** chooses Apple, OpenAI, or Anthropic. Apple is the default.
  Choosing a cloud provider displays the sentence-sharing and possible-cost
  boundary before use. Only the model choice is stored in preferences; keys
  remain in Add Secret's encrypted store.
- **Careful** is the default. It may apply one conservative objective
  contextual correction.
- **Comprehensive** may apply up to three non-overlapping objective spelling,
  punctuation, or grammar corrections in the completed sentence.
- **Allow sentence rewrites** is a separate opt-in available only with
  Comprehensive. It permits the model to rephrase one completed sentence for
  clarity while preserving meaning, facts, intent, and tone.

Typover applies a range-level contextual result only when:

- the captured sentence still matches exactly at its original range;
- the model’s original substring occurs exactly once in that sentence;
- the target and replacement are nonempty, bounded, and contain no sentence
  punctuation or newline;
- each model answer can be reduced deterministically to a smallest changed word
  or phrase;
- every target is unique, valid, and non-overlapping;
- the complete proposal contains no more than the number of edits allowed by
  the selected scope;
- in Careful mode, a single-word replacement is lexically related to its
  original, apart from a narrow reviewed grammar exception.

If sentence rewrites are enabled, the model may return one complete replacement
sentence instead of range-level edits. A rewrite is rejected unless it
preserves the exact captured scope, contains no newline, ends in sentence
punctuation, and remains within 600 UTF-16 code units. An accepted rewrite is
underlined across the replacement sentence and can restore the exact original
sentence through Change Back or Undo.

The model must also identify writing with a concrete clarity signal, such as
obvious filler, conspicuous repetition, or an unnecessarily indirect
construction. Typover verifies that the replacement removes that signal and
preserves numeric and symbolic tokens plus explicit politeness, first-person,
and permission markers. It does not automatically rewrite quotations,
conditions, negation, qualified claims, prompt-like text, code, URLs, or
parenthetical emphasis. These rules intentionally turn uncertain proposals
into safe misses.

Comprehensive range edits use related protections: code identifiers, quoted
commands, prompt-like instructions, duplicate neighboring words, and adjacent
gerunds are rejected before application.

Editing inside the captured sentence makes the result stale and it is
discarded. Pasted text and active marked-text composition do not trigger
contextual analysis.

## Correction-mark visibility

The default **Brief + contextual** interaction keeps each new light-gray
squiggle fully visible for four seconds, then fades it over 150 milliseconds.
The correction record, original text, alternatives, Undo transaction, and menu
remain intact after the mark disappears.

Reviewing a sentence reveals every unresolved correction in that sentence:

- pointer review uses the sentence's rendered TextKit line fragments, expanded
  by 12 points horizontally and 6 points vertically;
- a 100-millisecond dwell prevents marks from flashing during incidental
  pointer travel;
- a 250-millisecond exit grace prevents flicker at fragment boundaries;
- clicking or navigating the insertion point into an earlier sentence reveals
  its corrections, but ordinary continued typing clears that caret review so
  the active sentence does not stay permanently decorated; and
- an open correction menu pins its mark until the menu closes.

Sentence locality uses the same explicit punctuation and paragraph boundaries
as Typover's contextual correction detector. Multiple corrections in the
reviewed sentence return together; corrections in other sentences remain
hidden. **Always Visible** keeps every unresolved mark drawn. The preference is
stored in the standard macOS application-preferences domain.

This interaction is implemented only in Typover's controlled editor. Bear
continues using persistent overlay marks until the dedicated geometry,
performance, and interaction spike establishes a reliable approximation.

## Transaction safety

Immediately before replacement, Typover verifies that the expected original
word still occupies the proposed range. It replaces only that range and adjusts
the current selection by the replacement-length difference.

Inserting text before an existing correction lets TextKit move its annotation
with the attributed text. Editing through an annotated correction invalidates
that correction, removes its mark, and records the user response as an edit.

Every successful automatic correction retains the original text and exposes
Change Back, alternatives where applicable, and normal Undo. Multiple
Comprehensive corrections from one result share one Undo transaction but keep
separate visible annotations and menus. A sentence rewrite is one visible,
reversible transaction.

Rejected transactions and invalidated annotations produce structured,
text-free diagnostics containing only a reason, correction identifier, numeric
range, document length, and timestamp. Successful transactions record a
text-free duration sample. Both in-memory buffers are capped at 200 entries.

## Remembered preferences

Typover remembers explicit correction choices locally for the same original
word and spelling language:

- choosing an alternative makes that replacement the preferred correction next
  time;
- directly editing an annotated correction makes the resulting token preferred
  only when Typover observed the edit inside that marked range;
- Change Back suppresses automatic correction of that exact original word;
- Undo and Redo of menu-driven correction changes restore the corresponding
  preference state.

Preferences use the exact original casing and language. A choice for `teh` in
English does not silently become a preference for another language or a
differently cased token.

Statistics and remembered choices are visible in Typover’s standard Settings
window. Removing one choice affects the shared editor immediately. The writer
can reset statistics independently or clear all local learning after a
confirmation.

User-selectable behavior settings—including correction scope, sentence rewrite
permission, model choice, correction-mark visibility, Bear automatic
correction, and diagnostic toggles—are stored in Typover’s standard macOS
application-preferences domain
(`com.malpern.typover`). They survive relaunch and remain local to this Mac.
Structured correction preferences and statistics stay in Typover’s Application
Support data file, and provider API keys remain encrypted in Add Secret; neither
belongs in the preferences plist.

Settings identifies whether a remembered rule came from a chosen correction, a
local edit, Change Back, or an earlier Typover version. Accents, apostrophes,
capitalization, and punctuation can remain part of an implicit local edit.
Explicitly chosen rules may intentionally expand to a phrase.

If an edit removes the entire annotation before Typover can identify a local
replacement—or if a broader document mutation only leaves the annotation on
unrelated text—the interaction still counts as a manual override but does not
create an uncertain mapping.

## Local statistics

Typover records one activity entry for each successfully applied correction and
tracks whether that correction was:

- changed back;
- changed to an alternative;
- manually edited;
- left unresolved.

The override rate is the number of unique applied corrections that were ever
changed back, given an alternative, or manually edited, divided by all applied
corrections. Repeated clicks on the same correction do not inflate that rate.

Activity entries contain a correction ID, timestamp, and outcome flags—not the
document text. Remembered preferences necessarily contain the original typo and
preferred replacement, but remain only in Typover’s local Application Support
file. Typover does not upload or synchronize either dataset.

## Deferred behavior

Typover does not autonomously revisit an entire page or document while the
writer is typing. Explicit review of older prose is a separate future behavior
with stricter staleness, context, and user-attention requirements.
