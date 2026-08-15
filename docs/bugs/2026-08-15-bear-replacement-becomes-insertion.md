# A corrupt learned preference replaced every `teh` with `theteh`

- Status: **Root cause found, fixed, and verified.** One defect remains open:
  a corrupted correction still reports success
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

## Provenance — resolved by the activity trail

An earlier revision of this record guessed that the 2026-08-15 agent session
created the entry, reading `updatedAt` as the creation time. That was wrong.
`setPreference` refreshes `updatedAt` on every write, and the store's 1,874
timestamped activities date the preference nine hours earlier:

```
21:41:33–21:43:23   45 x src=appleSpelling, outcomes=[]        the 45/45 passing rows
21:45:20            src=appleSpelling         [manuallyEdited]
21:46:30            src=rememberedPreference  [manuallyEdited]  preference now in effect
21:46:45 onward     every correction src=rememberedPreference
```

The preference was created between 21:43:23 and 21:46:30 on 2026-08-14 —
during interactive acceptance work, immediately after the passing rows — and
by a **manual edit**, not an alternative choice. Every correction from 21:46:45
onward, including all nine physical rows the next morning, used it.

## How a manual edit produced `theteh`

`recordManualEdit` stored any replacement that passed
`isSafeImplicitReplacement`, which rejects only empty strings, strings over 64
characters, and strings containing whitespace or control characters. `theteh`
passes all three. The existing ambiguity guard catches a multi-word edit such
as `"Start Finish remains."` but not a single concatenated token.

The reachable sequence is ordinary typing: a correction lands, the writer keeps
typing, and the new characters join the corrected word. `teh` becomes `the`,
typing continues, the word now reads `theteh`, and Typover infers that the
writer edited its correction to `theteh` and remembers it permanently. Fast
typing is Typover's own audience, so this is not an artifact of the harness.

## Fix

`recordManualEdit` now requires an inferred replacement to be within two edits
of the original. `theteh` is three and is refused; `dont -> don't`,
`resume -> résumé`, and `teh -> "the,"` are all within two and still learn.

The bound applies **only** to the inferred path. An explicit choice may still
expand to an arbitrary phrase (`addr -> 123 Main Street`), as may a manual
mapping (`brb -> be right back`); both are stated intent. An earlier attempt
applied the same bound to explicit choices and was withdrawn when the suite
caught it breaking phrase expansion — the distinction is between honouring a
stated intent and guessing at an unstated one.

## Open defects

1. ~~Learned preferences are applied without validation.~~ Fixed at the source:
   the inferred-edit path no longer stores a replacement more than two edits
   from the original. Stores already holding such an entry are not repaired
   automatically — Settings → Learning lists remembered rules with a remove
   action, which is the recovery path.
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
