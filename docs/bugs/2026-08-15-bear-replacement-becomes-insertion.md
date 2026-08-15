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

## Untested, in priority order

1. **Reboot.** The single most discriminating test. If a reboot restores correct
   replacement, the "persists until the next boot" claim in the VoiceOver record
   is real but its trigger is broader than VoiceOver — sleep/resume being the
   obvious candidate given the overnight gap.
2. **`AquaVoiceHook`.** Aqua Voice is an Electron dictation app with a hook
   process, an `AquaMacOSBridge`, and Accessibility helpers. Quitting the main
   app did not stop the hook, which respawned (PID 66044) and was live during
   run `14-12-25Z`. Eliminating it needs its launch agent disabled, which was not
   done. The harness contract explicitly warns about another text service being
   credited to Typover.
3. **Raycast Beta's `Accessibility.xpc`**, live throughout.
4. **macOS `26A5406e`**, a beta build. Whether it changed since the passing runs
   was not established.

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
