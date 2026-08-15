# A corrupt learned preference replaced every `teh` with `theteh`

- Status: **Root cause found and verified.** Environment repaired; two code
  defects remain open
- Date: 2026-08-15
- Scope: `CorrectionLearningStore` preference application; correction
  verification
- Environment: macOS 27.0 `26A5406e`, Bear 2.9.1, candidate
  `0.1.0 (20260815055632)`

## Symptom

Every physically typed `teh ` produced `theteh` in Bear, in nine consecutive
harness rows. Typover reported `applied: 5`, `replacementRefused: 0`, and drew
five reversible marks over five corruptions. It reproduced identically in
Typover's own controlled AppKit editor.

## Root cause

`~/Library/Application Support/Typover/correction-learning.json` contained one
learned preference:

```json
{"key": {"language": "en", "original": "teh"},
 "preference": {"preferred": {"_0": "theteh"}},
 "origin": "explicitChoice",
 "updatedAt": 808494982.833607}
```

Typover was not failing to replace. It was **correctly applying a corrupt
learned preference**, writing the literal string `theteh` over the 3-character
range holding `teh`. The instrumented trace shows it plainly:

```
outcome=deferredApplied original="teh" replacement="theteh" range=44:3
```

That explains every observation that made this look like a host problem: the
decision log was identical to a passing run because the logic was identical;
post-write verification passed because Typover verified exactly what it meant
to write; it spanned both editors because the learning store sits beneath both;
and it survived reboots because the store is on disk.

`updatedAt` decodes to **2026-08-15 06:56:22 local** — after the last passing
row (21:43 the previous evening) and before the first failure (07:08). That is
the mid-boot onset.

## The code defect

`AutomaticCorrectionPolicy.proposal(for:)` enforces
`optimalStringAlignmentDistance(from: original, to: replacement) == 1`, so no
engine can propose `teh → theteh` (distance 3). But that guard exists only in
`AutomaticCorrectionPolicy` and `ContextualCorrection`. The learned-preference
path — `CorrectionLearningStore.preference(...)` returning
`.preferred(replacement)` — is applied **without any validation**. A stored
preference therefore bypasses the invariant every engine-produced correction
must satisfy.

There is precedent. The owned-editor acceptance pass previously taught
`teh → ten` by choosing an alternative, and the remedy was likewise to delete
the learned entry. Two incidents of the same class means this is a design
weakness, not an accident.

## Verification

Removing only that one preference, with no code change, restored correct
behaviour on the first attempt:

| | before | after |
|---|---|---|
| text | `theteh theteh theteh theteh theteh` | `the the the the the` |
| classification | invalid-evidence 0/5 | **passed 5/5** |
| lengths | 33 → 69 | 35 → 56 |
| overlays retained | 5/0 | 5/5 |

Run `typover-hid-2026-08-15T15-35-50Z`. The store was backed up to
`correction-learning.json.pre-fix-20260815` first.

## Provenance

The preference was recorded roughly three minutes after this session installed
the candidate and began driving the controlled editor with synthetic
`CGEvent` input. Synthetic input is already documented here as unrepresentative,
and the most likely account is that this session created the entry. The first
`theteh` therefore has an unknown proximate trigger, but every subsequent
occurrence — including all nine physical rows — is fully explained by the
stored preference.

What is not explained: how an `explicitChoice` was recorded when no alternative
was ever chosen, and how a string outside the guess list
(`the, ten, yeh, tea, feh, ted, …`) became the preferred replacement. That path
should be audited, because it is the mechanism that persisted the damage.

## Open defects

1. **Learned preferences are applied without validation.** Re-check the
   invariant at application time and at write time: edit distance ≤ 1, and the
   replacement present in the engine's current guesses. Ideally reject at
   record time too, so the store cannot hold an impossible mapping.
2. **A corrupted correction reports success.** Typover verified its own write
   faithfully but never asked whether the replacement was *plausible*. A
   correction that changes a word's length by +3 for a same-length typo should
   never have been drawn as a reversible mark. The immediate verification is
   necessary but not sufficient.
3. **Diagnostics should surface the replacement string.** The content-free
   trace logs `outcome=deferredApplied` without the replacement, which is why
   nine rows and a reboot were spent chasing the host. Logging the replacement
   length, or the edit distance, would have identified this in one run.

## Ruled out along the way

Recorded so the elimination work is not repeated: the VoiceOver latch commits
(`d77f902` fails identically), VoiceOver itself (latch never armed), boot-scoped
state (survives a reboot), fixture transport (survives a board reset), input
delivery (42 reports, 0 late, 30 µs max lateness), focus and load evidence,
Bear's process state (full restart), a silent Bear update (bundle dated Jul 27,
build 14638), an OS update (last Jul 16), the spell checker's adaptive model
(reset with no effect), and every third-party text agent — Aqua Voice, Cotypist,
fixkey, Hammerspoon, VoxClaw, CodexBar, Granola, FigmaAgent and Raycast all
stopped, with `com.aqua-voice-hook.app` booted out of launchd.

## Consequence for the VoiceOver record

[The VoiceOver finding](2026-08-15-voiceover-bear-replacement-semantics.md)
describes the same `theteh` signature and attributes it to VoiceOver changing
Bear's replacement semantics for the rest of the boot. That attribution is now
doubtful: the identical signature has a fully explained, VoiceOver-independent
cause, and its "until the next boot" persistence matches an on-disk learned
preference better than it ever matched an Accessibility server state. The
shipped `BearVoiceOverSafetyLatch` may be mitigating a misdiagnosis. Before the
beta ships, check whether that session's `correction-learning.json` held a
corrupt entry, and re-test Bear under VoiceOver with a clean store.
