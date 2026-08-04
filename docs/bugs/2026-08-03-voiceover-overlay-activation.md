# VoiceOver Window Chooser retired the correction overlay

- Status: Fixed and physically verified
- Date: 2026-08-03
- Scope: Bear correction overlay accessibility lifecycle

## Symptom

VoiceOver could discover `Correction options for the` in Window Chooser, but
selecting that window made the correction disappear before its button or
actions could be used.

## Root cause

Typover correctly hides Bear annotations whenever another application becomes
frontmost. VoiceOver's Window Chooser necessarily activates the application
that owns the selected accessibility window. The correction panel is owned by
Typover even though it is visually nonactivating, so the ordinary Typover
activation notification ran the inactive-app path and ordered out the panel.

This was not a VoiceOver labeling problem. The live element exposed `AXButton`,
`AXPress`, and custom actions for Revert and every safe alternative. The panel
lifecycle removed that valid element before VoiceOver could act on it.

## Fix

While VoiceOver is running, activation of Typover itself may preserve the
existing correction long enough for accessibility interaction. Geometry and
fallback refresh work remain paused because Bear is not frontmost. Activating
Typover without VoiceOver still hides the overlay, as does activating any
unrelated application.

After a VoiceOver custom action finishes, Typover closes the transient overlay
and activates Bear after a short main-loop delay. Waiting until the VoiceOver
Actions menu has dismissed is necessary for the VoiceOver cursor to follow the
application focus back to Bear's editor instead of falling through to
Typover's ordinary editor window.

## Evidence

- Deterministic Bear annotation overlay suite: 38/38 passed.
- Physical run `typover-hid-2026-08-03T21-37-56Z`: 1/1 correction and 1/1
  retained overlay at 160 milliseconds per key.
- VoiceOver announced the correction window, correction button, Revert action,
  and the `ten` alternative.
- Revert restored exact `teh `, `net.shinyfrog.bear` became frontmost, and the
  VoiceOver caption returned to the same Bear editor.
- Escape dismissed the Actions menu back to the correction button without
  changing the note.

## Regression boundary

Do not generalize this exception to arbitrary host activation. It is limited to
the Typover bundle while `NSWorkspace.isVoiceOverEnabled` is true. Correction
transactions still require an existing verified Bear anchor, and every
unrelated focus change keeps the normal fail-closed behavior.
