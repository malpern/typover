# VoiceOver changes Bear's replacement semantics for the rest of the boot

- Status: Mitigated in `0.1.0 (20260815055632)`; **originating observation not
  recorded** — see Provenance below
- Date: 2026-08-15
- Scope: Bear exact-range mutation under assistive technology

## Symptom

With VoiceOver enabled, a Bear correction does not replace the selected
original. The replacement is inserted *beside* it, leaving both the typo and
its correction in the note.

The altered behaviour is not scoped to the moment VoiceOver is active. It
persists for the remainder of the macOS boot; switching VoiceOver back off does
not restore ordinary replacement.

## Why this is severe

It breaks the first product invariant — replace the smallest safe range, never
more — and it breaks it in the one direction the design cannot absorb. A
beside-insertion is not reversible by changing the replacement range back,
because the original is still present. Change Back on such a write would
either fail or corrupt further.

It is also silent. The write reports as having occurred, so without a specific
guard the correction path treats it as a success and offers it as reversible.

## Fix

Two changes, in `0.1.0 (20260815055632)`.

**Refuse rather than write.** `BearVoiceOverSafetyLatch` records that VoiceOver
has been seen and keeps Bear mutation disabled until the next boot. Every
mutation path consults it: automatic correction, the overlay preview, Change
Back, and alternatives. The Bear status row reads *Paused after VoiceOver use;
restart your Mac to resume Bear correction. Typover's editor remains
available.* The controlled AppKit editor is unaffected.

The latch is keyed to `kern.bootsessionuuid`. `kern.boottime` was rejected:
macOS recomputes it as wall clock minus uptime, so it shifts when the clock is
adjusted or the Mac sleeps and wakes, and a single shifted second would release
the pause while Bear was still unsafe to write to.

**Stop promoting unverified writes.** `BearCorrectionAdapter` no longer
re-anchors a write whose verification failed by re-reading the replacement
range. That recovery existed to preserve reversibility when caret restoration
or a bounded read failed after a good write, but it cannot distinguish that
case from a beside-insertion — the replacement text is findable at the target
either way. Such writes now open the mutation circuit, the existing handling
for an indeterminate write. This changes behaviour for writers who never enable
VoiceOver, which is why the physical Bear rows must be re-run on this candidate
rather than carried forward.

## Evidence

Deterministic, on this candidate:

- the safety pause survives a latch relaunch within one boot and clears on the
  next;
- the real boot identifier is a `kern.bootsessionuuid`, pinned by test so a
  revert to a drifting seconds value fails;
- a queued correction is cancelled when the latch engages;
- the pause engages before any Accessibility write.

Full suite: 358 tests in 30 suites.

## Provenance

**The session that observed the beside-insertion is not recorded anywhere.**
This document reconstructs the defect from the mitigation's rationale, not from
a test record. That is backwards, and it matters here more than usual: the
finding is the sole justification for a shipped, user-visible limitation, and
no artifact currently shows it happening.

Before publication, write up the original observation — macOS and Bear
versions, whether VoiceOver was running or merely had been, the exact note
state, and what the note contained afterward. If it cannot be reproduced,
that is itself worth recording, because the latch is costly to users who rely
on VoiceOver and its justification should be inspectable.

## Regression boundary

The latch is deliberately coarse: it is armed by VoiceOver having been seen at
all, not by VoiceOver being active at the moment of a write, because the host
behaviour outlives the VoiceOver session. Do not narrow it to "while VoiceOver
is running" without evidence that Bear's replacement semantics recover within
the same boot.

Do not restore post-write re-anchoring as a general recovery. If reversibility
after a failed verification is worth recovering, it needs a check that
distinguishes a replaced range from an inserted one, not a search for the
replacement text.
