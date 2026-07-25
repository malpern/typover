# Typover product brief

## Problem

Traditional desktop spell checking identifies probable mistakes but requires
the writer to notice each mark, open a menu, and choose a correction. Existing
automatic correction is inconsistent across applications, briefly annotated,
and difficult to inspect after the moment of replacement.

AI writing tools often take the opposite extreme: they rewrite a selection,
field, paragraph, or document as one opaque operation. That is unsuitable for
long-form writing and makes individual changes hard to trust or reverse.

## Product idea

Typover automatically applies only the most likely corrections and preserves
visible, reversible provenance for each one.

A corrected word receives a persistent light-gray squiggle. Selecting it shows:

- the original typed word;
- other likely corrections;
- an action to keep the current correction and remove the mark.

## Behavioral principles

### Incremental

Observe and replace the smallest safe range. Word-boundary corrections may run
after Space or punctuation. Contextual corrections may reconsider the most
recently completed sentence, but must apply a range-level diff rather than
replace the whole sentence or field.

### Conservative

Automatic replacement must pass a small set of explicit safety rules. The
controlled-editor policy accepts bounded Unicode words whose proposed
replacement is one edit away, preserves lowercase, Capitalized, and ALL-CAPS
patterns, and permits internal apostrophes. Mixed-case words and malformed word
forms remain unchanged.

### Reversible

Every automatic replacement records the original text, replacement, source
range, surrounding context, and time. A writer can restore the original without
searching an undo history.

### Visible

Automatic changes remain quietly visible. The mark should communicate
“Typover changed this” without resembling an unresolved error.

### Private

The preferred design runs on-device. Any prototype that sends text elsewhere
must be opt-in and state exactly what text is transmitted.

## Technical hypotheses

1. A controlled TextKit editor can provide the complete interaction, including
   native inline annotation and per-range menus.
2. Accessibility can support incremental text observation and range
   replacement in a useful subset of macOS applications.
3. A system-wide third-party app cannot reliably attach native formatting to
   arbitrary editors.
4. An overlay can demonstrate the visual concept but will face caret, scrolling,
   wrapping, and coordinate-conversion limitations.
5. A complete system-wide experience may require a new Apple text-system API
   rather than a change to correction quality alone.

## Comparators

- macOS autocorrection: automatic word replacement with a temporary underline
  and Change Back.
- Hush: automatic whole-field replacement after a pause.
- FixKey: shortcut-triggered field or selection rewriting.
- Cotabby: system-wide completion with optional correction at a word boundary.
- Global AutoCorrect: commercial background correction across applications.

None combines automatic incremental correction, a persistent native mark, and
per-change restoration across macOS.

## Future evaluation: correction confidence

Typover does not assign or display a numeric confidence score in the first
prototype. Apple’s spelling APIs provide ranked candidates, not a calibrated
probability, and inventing a score would imply precision we have not measured.

A later benchmark may evaluate confidence scoring or calibration after Typover
has a representative typo corpus and can measure false-positive rates. Any
future score must improve the automatic-correction decision over the simple
binary policy, remain explainable, and be validated separately for each
correction engine. It is not required for the controlled-editor milestone.
