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

Existing text before and after the caret is context-only. Moving the caret does
not make surrounding prose eligible for automatic replacement.

- A newly typed and completed word may change.
- Existing words before it remain unchanged.
- Existing words after it remain unchanged.
- Text elsewhere in the document remains untouched.

A future contextual engine may read a bounded amount of text on both sides of
the caret, but its editable target must still be an exact, newly completed
range unless the writer explicitly enters a review mode.

## Transaction safety

Immediately before replacement, Typover verifies that the expected original
word still occupies the proposed range. It replaces only that range and adjusts
the current selection by the replacement-length difference.

Inserting text before an existing correction lets TextKit move its annotation
with the attributed text. Editing through an annotated correction invalidates
that correction, removes its mark, and records the user response as an edit.

Every successful automatic correction retains the original word and exposes
Change Back, alternatives, Keep, and normal Undo.

## Remembered preferences

Typover remembers explicit correction choices locally for the same original
word and spelling language:

- choosing an alternative makes that replacement the preferred correction next
  time;
- directly editing an annotated correction makes the resulting word preferred
  when Typover can identify it;
- Change Back suppresses automatic correction of that exact original word;
- Undo and Redo of menu-driven correction changes restore the corresponding
  preference state.

Preferences use the exact original casing and language. A choice for `teh` in
English does not silently become a preference for another language or a
differently cased token.

If a direct edit removes the entire annotation before Typover can identify the
new word, the interaction still counts as a manual override but does not create
an uncertain word mapping.

## Local statistics

Typover records one activity entry for each successfully applied correction and
tracks whether that correction was:

- explicitly kept;
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
writer is typing. Background review of a recently completed sentence and
explicit review of older prose are separate future behaviors with stricter
staleness, context, and user-attention requirements.
