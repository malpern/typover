# ADR-004: Keep preference learning and correction statistics local

- Status: Accepted
- Date: 2026-07-25

## Context

Writers should not have to repeat the same correction choice. Typover also
needs evidence about how often it changes text and how frequently writers
override those changes before broadening automatic behavior.

Apple’s spell checker accepts response feedback, but its learning is opaque.
Typover needs deterministic product behavior and measurable outcomes that do
not depend on undocumented system learning.

## Decision

Typover will maintain a local correction-learning store.

- A chosen alternative becomes the preferred replacement for the same exact
  original token and spelling language.
- An identifiable direct edit becomes the preferred replacement only when the
  editor observed that edit inside the marked correction range.
- Broader or otherwise ambiguous document mutations count as manual overrides
  but do not create a reusable preference.
- Remembered preferences retain their provenance: an explicit choice, an
  implicit local edit, Change Back, or a migrated earlier-version choice.
- Explicit choices may intentionally contain a phrase. Implicit local edits
  must remain a bounded single token; accents, apostrophes, capitalization, and
  punctuation are preserved.
- Change Back suppresses the same exact token and language.
- Remembered choices override the Apple candidate but still use the normal
  exact-range, annotation, and restoration transaction.
- Menu-driven preference changes participate in Undo and Redo.

The store also records one activity per successfully applied correction.
Outcome flags distinguish Keep, Change Back, alternative selection, and direct
manual editing. A correction is counted as overridden at most once even if it
receives several override actions.

Overall override rate is:

`unique overridden corrections / successfully applied corrections`

Unresolved corrections are applied corrections with no explicit recorded
outcome.

## Privacy

Statistics contain correction IDs, timestamps, and outcome flags. They do not
contain document text.

Preference entries necessarily contain an original token, language, and
preferred replacement or suppression. They are stored only in:

`~/Library/Application Support/Typover/correction-learning.json`

Typover does not upload or synchronize this file. Persistence failures never
interrupt typing.

## Consequences

### Benefits

- Repeated choices produce predictable behavior.
- Typover can measure override rates before expanding automatic correction.
- Apple spelling remains useful without making its opaque learning the product
  source of truth.
- Statistics do not retain surrounding prose.

### Costs

- Preference mappings contain isolated user-entered tokens and therefore need
  clear local-data controls.
- Exact-token and exact-language matching intentionally learns slowly.
- Direct edits that destroy the complete annotation may be counted without
  yielding a reliable replacement mapping.
- Learning must distinguish a direct local edit from text that merely inherited
  an annotation attribute during a broader document mutation.
- A user-facing way to inspect, remove, and reset preferences and statistics is
  still required.

## Revisit when

Revisit the keying and synchronization policy only after the local behavior is
measured. Any broader matching, cross-device sync, or shared learning must be
an explicit product and privacy decision.
