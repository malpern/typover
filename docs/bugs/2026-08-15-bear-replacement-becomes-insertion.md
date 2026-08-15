# Bear replacement became an insertion mid-boot, and Typover reported success

- Status: **Open and blocking.** Reproduced on two builds; root cause unknown
- Date: 2026-08-15
- Scope: Bear exact-range mutation; candidate qualification
- Environment: macOS 27.0 `26A5406e`, Bear 2.9.1, fixture `keypath-hid-fixture.local`

## Symptom

Every physically typed `teh ` produced `theteh` in Bear. The correction text was
inserted in front of the original instead of replacing it, and the original was
never removed.

Typover did not detect this. Its own telemetry for the run reports
`applied: 5`, `replacementRefused: 0`, `contextChanged: 0`,
`learnedSuppression: 0`, and `finalVisibleCorrections: 5` from an empty
baseline. It drew five squiggles over five corruptions and offered them as
reversible.

Document arithmetic confirms a pure insertion rather than a failed replacement:
baseline length 34, final length 70. Five typed `teh ` is 20 characters, five
inserted `the` is 15, plus the trailing newline — exactly 70. Nothing was
deleted.

## What makes this urgent

It is the same signature as
[VoiceOver changes Bear's replacement semantics](2026-08-15-voiceover-bear-replacement-semantics.md),
but **VoiceOver was off and its latch was never armed** — the
`bear-voiceover-safety-pause-boot` key is absent, so VoiceOver has not been seen
this boot. The mitigation shipped in `0.1.0 (20260815055632)` therefore does not
cover this, and the VoiceOver attribution in that record may be wrong or
incomplete.

## Timeline within a single boot

The Mac booted 2026-08-14 18:54 local and has not rebooted since.

| Run | Boot age | Result | Text |
|---|---|---|---|
| `typover-hid-2026-08-15T04-41-23Z` | ~2h47m | passed 5/5 | `the the the the the` |
| `typover-hid-2026-08-15T04-42-11Z` | ~2h48m | passed 20/20 | `the the …` |
| `typover-hid-2026-08-15T04-43-05Z` | ~2h49m | passed 20/20 | `the the …` |
| `typover-hid-2026-08-15T14-08-33Z` | ~12h14m | **0/5 invalid** | `theteh …` |
| `typover-hid-2026-08-15T14-10-39Z` | ~12h16m | **0/5 invalid** | `theteh …` |
| `typover-hid-2026-08-15T14-12-25Z` | ~12h18m | **0/5 invalid** | `theteh …` |
| `typover-hid-2026-08-15T14-15-25Z` | ~12h21m | **0/5 invalid** | `theteh …` |

It worked and then stopped working **inside one boot**, with an overnight sleep
between. That rules out the boot-scoped framing: this is not state that was
already set at boot, and it is not cleared by anything short of a reboot tried
so far.

## Not the cause

- **Not the VoiceOver latch commits.** Run `14-10-39Z` used the pre-latch
  development build `d77f902` and failed identically: `theteh`, `applied: 5`,
  five overlays.
- **Not VoiceOver.** Off throughout; latch never armed.
- **Not input delivery.** All four failing runs submitted 42 fixture reports
  with 0 late reports and maximum lateness 30 µs. The typed text arrived intact.
- **Not focus or load.** `focusRemainedValid: true` and complete load evidence
  in every run.
- **Not learned state.** `correction-learning.json` contains no `teh` entry, and
  the `com.malpern.typover` preferences domain has no correction entries.
- **Not Bear's process state alone.** A full Bear quit and relaunch before
  `14-15-25Z` did not clear it.
- **Not synthetic input.** First observed through injected `CGEvent` typing, then
  reproduced identically through real USB HID from the ESP32.

## Ruled out on 2026-08-15, after four further rows

- **A reboot does not clear it.** Run `15-06-59Z` followed a clean restart and a
  fixture reset: `theteh` again, lengths 37 → 73. This kills the boot-scoped
  framing entirely, and with it the "persists until the next boot" wording in
  the VoiceOver record.
- **Not the ESP32's transport state.** The board was reset between runs.
- **Not Cotypist.** Run `15-10-02Z` had Cotypist stopped and verified dead
  through the row. Still `theteh`.
- **Not any third-party text agent.** Run `15-12-15Z` ran with Aqua Voice,
  Cotypist, fixkey, Hammerspoon, VoxClaw, CodexBar, Granola, FigmaAgent and
  Raycast all stopped, and `com.aqua-voice-hook.app` booted out of launchd so it
  could not respawn. Still `theteh`.

## The decisive comparison

Typover's own decision log is identical between the passing morning run and the
failing afternoon run — same outcomes, same counts, same telemetry, same test
case:

```
unarmedValueChange: 15   idleDeferred: 5   rapidTypingCoalesced: 1
deferredApplied: 5       redundantAutomaticValueChange: 1
applied: 5               replacementRefused: 0
```

`04-41-23Z` produced `the the the the the`. `15-12-15Z` produced
`theteh theteh …`. Typover made the same decisions and issued the same write in
both. The divergence is therefore **not in Typover's correction logic** — it is
in what the write does to the host once issued.

Note also that the same `theteh` result appeared in Typover's **own controlled
AppKit editor**, which does not go through the Accessibility path at all. A
defect that spans both the in-process editor and the Bear AX adapter points at
something shared and below both, not at the Bear integration.

## Corrected mechanism (second pass, 2026-08-15)

Three earlier framings are now disproven by reading the code and probing the
layers directly:

- **The engine supplies no range.** `AppleSpellCheckerEngine.proposal(for:)`
  takes a single word and returns strings only. The caller computes the range.
  A "degenerate engine range" cannot occur.
- **The write layer is honest.** A headless `NSTextView` probe shows
  `insertText(_:replacementRange:)` honoring range lengths correctly.
- **The write verification is not blind, and it passed.**
  `BearExactRangeReplacement` reads the selection back after setting it,
  precomputes the expected surrounding context, and verifies both the context
  window and the total character count after the write. For `teh→the` an
  insertion-without-deletion grows the count by 3 and fails both checks. All
  five corrections in the failing runs reported `.applied` — the replacement
  **really was in the document, verified, at write time**.

Therefore the original `teh` **re-materialized after a verified successful
replacement**. The adjacency pins down where: the final text is `theteh ` with
`teh` immediately after `the`, *before* the space. Keystroke replay would land
at the caret (after the space, producing `the teh `). Re-materialization at the
original offset is the signature of Bear re-rendering from a second text model
that still contains the typed original — Bear 2 is CRDT-based — merged with the
AX edit.

Also ruled out in this pass: Bear was **not** silently updated (bundle dated
Jul 27, build 14638, no install-log entries), and no macOS update landed (last:
Jul 16). The spell checker's adaptive state was probed and reset with no effect;
`kern`-level and OS-update triggers are dead.

The synthetic-input `theteh` in Typover's own controlled editor cannot share
this mechanism (no Bear model involved) and is provisionally re-classified as a
separate CGEvent-injection artifact. The physical Bear evidence is the load-
bearing defect.

## Open hypothesis and discriminating data

**Hypothesis:** Bear's editor holds the typed original in a canonical model
that AX selected-text writes do not fully reach; a reconciliation pass re-
inserts the original beside the verified replacement. Something in Bear's
persistent state flipped this behaviour on between 21:43 and 06:45 local and it
survives Bear restarts and a macOS reboot. Candidate trigger: the burst of
`bearcli`-created disposable notes and any resulting sync backlog. This would
also retroactively explain the "VoiceOver changes Bear's semantics" finding —
that session interacted with the same reconciliation layer, and the boot-scoped
framing was coincidence.

Data that would settle it:

1. **A delayed re-read after one correction.** Enable the content-bearing
   diagnostic (`Include bounded writing context`), run one row, and read the
   trace: it should show `the ` verified at write time and `theteh ` on a later
   read, timestamped. That converts the re-materialization from deduction to
   observation.
2. **Bear sync state.** Check Bear's sync/iCloud status; quiesce or clear the
   backlog of disposable notes and re-run one row.
3. **A fresh Bear database.** A clean macOS user account with Bear installed
   (Bear is not in the VM lab base) separates note-store state from app.
4. **Write-strategy cross-check.** The research fast lane edits via synthetic
   key events, which enter Bear's model as ordinary typing. If a key-event
   write of the same correction does not exhibit re-materialization, the
   dual-model theory is confirmed and a viable alternate write path exists.

## Solvability

Two independent layers, both actionable:

- **Fail-closed detection (Typover, certain).** The current verification is
  immediate and was satisfied honestly. Add a delayed re-verification — re-read
  the context window a few hundred milliseconds after `.applied`; if the
  original resurfaced, open the mutation circuit, retire the mark, and surface
  the pause. This turns silent corruption into a refusal regardless of root
  cause, and also retires the silent-success defect recorded above.
- **Correct-by-construction writes (contingent).** If the dual-model theory
  holds, replacement via synthetic key events (select-then-type, as the fast
  lane already does) enters Bear's canonical model directly and cannot be
  reconciled away. That is a measured, existing code path — research-gated
  today, but a candidate write strategy for exactly this host state.

## Consequences

- Candidate `0.1.0 (20260815055632)` **cannot be qualified** until this is
  understood. The physical Bear matrix cannot be re-run to a pass.
- The quiet correction-review interaction pass is blocked upstream: there is no
  valid correction to hover over, so the pointer rows could not begin.
- Typover reporting `applied` for a write that did not replace is a defect in
  its own right, independent of the trigger. Whatever caused the host behaviour,
  Typover should have detected a non-replacement and refused rather than drawing
  a reversible mark over corrupted text. The removal of post-write re-anchoring
  hardened the Bear adapter, but this path still reported success.

## Evidence

Artifacts in `~/.local/state/typover/bear-hid/`, run IDs as tabled above. Each
contains the fixture trace, exact Bear text, load samples, overlay retention,
and content-free Typover log events.
