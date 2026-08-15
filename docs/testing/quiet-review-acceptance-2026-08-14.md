# Quiet correction-review acceptance: 2026-08-14

- Status: **Blocked as of 2026-08-15.** Physical Bear correction now fails on
  this machine, producing `theteh` instead of `the` while Typover reports
  success. The pointer rows cannot begin because no valid correction exists to
  hover over. See
  [Bear replacement became an insertion mid-boot](../bugs/2026-08-15-bear-replacement-becomes-insertion.md).
  The observations recorded below stand as of 2026-08-14 but no longer
  reproduce
- Candidate: Typover `0.1.0 (20260808224257)`
- Bear: `2.9.1`
- Fixture: `0.3.2-esp32s3`, build `fc98a5acc0a5`
- Presentation restored after testing: **Brief + contextual**

## Accepted observations

The exact notarized candidate completed three fresh physical-input rows in the
same disposable Bear note after the ESP32 was reset:

| Row | Result | Focus | Fixture timing |
|---|---:|---|---|
| Integrity probe, 100 ms/key | 5/5 corrected | Valid | 0 late reports |
| Wrapped row, 100 ms/key | 20/20 corrected | Valid | 0 late reports |
| Bottom-of-note scroll row, 100 ms/key | 20/20 corrected | Valid | 0 late reports |

All 45 words became the exact expected `the` tokens. The runs recorded no
learned suppression, replacement refusal, or context change. Their evidence is
stored in the local content-free harness artifacts:

- `typover-hid-2026-08-15T04-41-23Z`
- `typover-hid-2026-08-15T04-42-11Z`
- `typover-hid-2026-08-15T04-43-05Z`

For the scroll row, 28 synthetic filler lines placed the fresh corrections at
the bottom of the note. Bear scrolled one page away and back through its native
Accessibility scroll actions. The corrected text remained exact, the editor
retained focus, and Typover's bounded correction collection retained the fresh
20-record row.

The controlled AppKit editor also passed the intended quiet sequence on the
installed candidate: a new correction drew its light-gray mark immediately,
the mark disappeared after the brief interval, and moving the insertion point
back into the sentence revealed it again.

The focused `BearAnnotationOverlayTests` suite passed 42 tests. It covers
wrapped placement, faded hit-testing, Bear proximity reveal, one-menu-per-hover,
Always Visible, independent overlays, scroll/lifecycle refresh, VoiceOver host
activation, focus return, and ordinary inactive-app hiding. Its permissioned
live-Bear test remains intentionally skipped outside the dedicated harness.

Three post-run samples, three seconds apart, measured both Typover and Bear at
0.0% CPU with unchanged resident memory in each process.

## Evidence limits

Computer Use captures one application's window at a time. Bear's capture does
not include Typover's separate nonactivating overlay windows, so it cannot
visually certify Bear squiggle drawing or pointer-only hover. The harness still
observed the correction collection and exact text, but those signals are not a
substitute for the remaining visual interaction row.

**Amended 2026-08-15.** The capture half of that limit is narrower than stated:
with *both* Typover and Bear in the Computer Use allowlist, the screenshot
compositor includes both applications' windows, and Typover's in-window marks
are legible. The original limit looks like a grant-scope artifact of capturing
Bear alone. This does **not** establish that the nonactivating overlay above
Bear composites — that was never reached, for the reason below.

The binding limit is input fidelity, not capture. Synthetic keystrokes injected
through Computer Use do not produce a valid correction: typing `teh` then space
into the controlled editor yields `theteh`, with the replacement inserted beside
the original rather than replacing it, and a squiggle drawn over the whole
thing. This reproduces identically on notarized candidate
`0.1.0 (20260815055632)` and on the pre-latch development build `d77f902`, so it
is not a property of the VoiceOver latch changes.

Whether that is a genuine controlled-editor defect under injected `CGEvent`
input or an artifact of injection is unresolved. The physical HID evidence
shows correct replacement in this same editor, so injection fidelity is the
leading explanation, and it is the reason the matrix uses the ESP32 fixture.
The consequence for acceptance is direct: the pointer rows cannot be driven by
synthetic typing, because no valid correction exists to hover over. Steps 1–4
still need physical input.

The Reduced Motion system setting was safely enabled and restored to its
original off state. The app window became unavailable to the UI driver after a
required Typover restart, so the live Reduced Motion visual row is not counted
as passed. Source has an explicit no-animation branch and deterministic
behavior remains covered, but a clean visual observation is still required.

## VoiceOver finding and mitigation

VoiceOver is no longer an open verification row. It is a known limitation with
a shipped mitigation, and the change is user-visible.

With VoiceOver enabled, Bear stops replacing selected text and instead inserts
the replacement *beside* the selected original. That breaks the first product
invariant — replace the smallest safe range — and it is not reversible by
changing the replacement range back, because the original is still present.
The altered semantics persist for the remainder of the macOS boot; turning
VoiceOver off does not restore them.

Typover's response is `BearVoiceOverSafetyLatch`. Once VoiceOver is observed
enabled, every Bear mutation path is refused until the next boot: automatic
correction, the overlay preview, Change Back, and alternatives. The Bear status
row reads *Paused after VoiceOver use; restart your Mac to resume Bear
correction. Typover's editor remains available*, and the controlled AppKit
editor is unaffected. `BearCorrectionAdapter` no longer re-anchors a write whose
verification failed, so a beside-insertion can never be promoted into a
"reversible" correction that cannot actually be reversed.

Four deterministic tests cover this: boot-scoped persistence across latch
instances, that the real boot identifier is a `kern.bootsessionuuid` that
cannot drift inside one boot, that a queued correction is cancelled, and that
the pause engages before any Accessibility write.

**Provenance gap:** the originating observation is not recorded in this file or
any other testing record — it exists only as the rationale in the source. The
session that observed the beside-insertion should be written up before
publication, since it is the sole evidence for a shipped user-facing
limitation.

## Excluded infrastructure incident

One earlier 20-word attempt after a Mac sleep/resume produced doubled physical
HID input (`tteehh.`). The fixture trace contained one report per intended key,
while macOS received each report twice after USB resume. Typover correctly made
no correction. Resetting the ESP32 cleared the transport state, after which all
three accepted rows above passed. The invalid run
`typover-hid-2026-08-15T04-36-26Z` is retained as fixture-resilience evidence,
not as a Typover result.

## Remaining release observation

One short, user-observed pass should now cover the remaining inseparable
interaction surface:

1. let a fresh Bear mark fade;
2. move the pointer near the corrected line and verify proximity reveal;
3. dwell directly over the mark for 350 ms and verify the menu opens once;
4. move away or press Escape and verify dismissal without text or focus change;
5. repeat steps 1–4 once with Reduced Motion enabled; and
6. confirm Bear remains the writing destination throughout.

Then, last and separately, because it cannot be undone without a reboot:

7. enable VoiceOver and confirm Bear correction refuses rather than
   mis-replaces — the Bear status row reads the paused-after-VoiceOver copy,
   automatic correction makes no write, and the overlay preview, Change Back,
   and alternatives all decline;
8. turn VoiceOver back off and confirm the pause *persists*, which is the
   intended behavior; and
9. confirm the controlled AppKit editor still corrects normally while Bear is
   paused.

Run step 7 only after steps 1–6 have passed, and expect to restart the Mac
before any further Bear testing.

