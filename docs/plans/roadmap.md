# Typover roadmap

- Status: Active
- Updated: 2026-08-05
- Current focus: Build the replacement notarized candidate with the permission
  fix, finish the clean-machine permission journey, then audit the shipped
  claims and publish the beta

## Goal

Deliver automatic corrections that remain visible, understandable, and
individually reversible while someone writes naturally. Typover should begin
with a trustworthy Bear integration, then reuse the proven interaction in a
carefully tested subset of other macOS editors.

## Product contract

Every milestone preserves the same invariants:

- replace the smallest verified text range, never an entire field or document;
- retain the original for every automatic correction;
- retain a retriggerable light-gray correction mark until the correction is
  resolved, even when the default presentation fades between review moments;
- make Change Back and alternatives immediate;
- fail without writing when focus, text, selection, or geometry is ambiguous;
- keep Apple processing on device by default;
- transmit text only after an explicit cloud-model choice; and
- never claim compatibility from deterministic tests alone.

## Target correction-review interaction

The marketing prototype is now the shared interaction target rather than an
editor-only illustration:

1. Apply an eligible correction without interrupting typing.
2. Draw its light-gray mark immediately, keep it fully visible for 1.5
   seconds, then fade it over 120 milliseconds.
3. Keep the correction record after the mark disappears.
4. Reveal nearby marks after a 100-millisecond review dwell. The controlled
   editor uses exact sentence geometry; Bear uses a bounded same-line proximity
   corridor around already-verified overlay geometry so review does not add
   repeated Accessibility text reads.
5. Open the native correction menu only after a deliberate 350-millisecond
   dwell directly over a visible mark. A click, right-click, keyboard shortcut,
   or accessibility action remains immediate.
6. Keep the mark visible while its menu is open, dismiss without changing text,
   and require the pointer to leave before hover can reopen that menu.
7. Make **Always Visible** apply consistently to the controlled editor and
   Bear.

This is implemented in source in both lanes. Deterministic validation is not a
substitute for the remaining installed-app visual and physical Bear pass.

## Roadmap dashboard

Status meanings:

- **Done** — implemented and validated at the level required for that item.
- **In progress** — useful implementation exists, but a listed acceptance or
  release gate is still open.
- **Not started** — planned work has not entered implementation.
- **Deferred** — intentionally begins only after the Bear word-level beta is
  trustworthy.

| Workstream | Status | Done | Still required |
|---|---|---|---|
| Controlled AppKit editor | **Exact candidate accepted; quiet review implemented in source** | Notarized 0.1.0 passes uninterrupted three-word correction, three annotations, pointer-only Change Back, one-step Undo, contextual correction, earlier-caret correction, About provenance, Settings Accessibility, 352 debug tests, and an optimized boundary gate. Source adds sentence review and deliberate hover-to-menu | Build the replacement candidate and visually accept the final fade, review, hover-menu, dismissal, and Reduced Motion behavior |
| Brief contextual marks | **In progress — both lanes implemented in source** | 1.5-second visibility, 120 ms fade, delayed review reveal, menu pinning, one-menu-per-hover, shared Always Visible preference, deterministic locality/lifecycle tests, and the interactive marketing prototype. The editor uses exact sentence geometry; Bear uses one collection-level pointer monitor and bounded line proximity | Validate the installed editor visually, then run Bear geometry, focus, scrolling, wrapped-line, load, VoiceOver, and physical-typing acceptance before enabling the behavior in a beta candidate |
| Bear lower-latency spike | **Qualified research candidate; beta policy decided** | Active session event tap, invalidation-only AX reauthorization, explicit fast/fallback lane ownership, tap-proxy posting before physical Space, exact adoption, strict 5/5 rows at 160/100 ms, strict 5/5 at 100 ms under combined load, and fresh mouse/Return recovery evidence | Keep disabled for the first beta; broaden beyond the 100 ms lowercase-word-plus-Space research envelope before productizing |
| Milestone 1: Bear word correction | **Beta envelope qualified** | Automatic exact-range correction, independent squiggles, Change Back, alternatives, rapid-typing catch-up, Accessibility, diagnostics, physical load coverage, post-pause product decision, and fresh-process notarized-candidate qualification through 60 ms per key | Treat the single safe 40 ms stress miss as a documented extreme-speed limit; do not expand the beta claim |
| Milestone 2: Beta shell | **In progress — permission UI remains** | Notarized clean-revision candidate, onboarding, status, privacy, About provenance, strict receipts, second-Mac install, and fresh-process launch | Complete the authenticated permission/revocation journey on an unlocked session |
| Public-beta operations | **In progress — source published** | MIT license, public repository and roadmap, GitHub waitlist and Issues, reviewed claims, exact release notes, notarized 0.0.9/0.1.0 update and rollback with preserved state, 11-minute clean-Mac soak, and recoverable app-only/full-data uninstall | Finish permissioned artifact-to-claim verification before publishing the beta binary |
| Milestone 3: Contextual correction in Bear | **Deferred** | Controlled-editor engines and bounded capture primitives exist | Activate and validate bounded sentence correction in Bear after the word-level beta |
| Milestone 4: Application-neutral integration | **Not started** | Shared engine boundaries are already designed for adapters | Extract target profiles, add TextEdit, then investigate the macOS ChatGPT and Claude composers with a content-free compatibility probe |
| Milestone 5: Quality and model scale | **Early groundwork only** | Small corpus and provider benchmark infrastructure | Grow to 500+ cases, add consented natural-writing data, cross-version testing, and local open-model benchmarks |

## Completed foundations

- [x] Build the controlled-editor reference implementation.
- [x] Implement brief contextual correction marks in the controlled editor
  without discarding correction history or reversibility.
- [x] Keep local word correction inside the native boundary edit, preserve
  selections when contextual results return behind the caret, refuse results
  during IME composition, and retain consecutive contextual requests instead
  of cancelling the earlier sentence.
- [x] Implement safe automatic word correction in supported Bear versions.
- [x] Keep multiple corrections visible and independently reversible.
- [x] Validate exact-range behavior, continued typing, Undo/Redo, IME,
  long notes, attachments, scrolling, alternatives, and Change Back.
- [x] Validate rapid typing and controlled system load with the physical ESP32
  fixture and content-free evidence.
- [x] Complete the Settings visual, native Accessibility, and spoken VoiceOver
  acceptance passes.
- [x] Add privacy controls, bounded local diagnostics, learning, statistics,
  capability gating, and explicit supported Bear versions.
- [x] Implement signed-build, receipt, archive-integrity, and negative package
  verification tooling.

## Open gates

### Required before a signed beta candidate is accepted

- [x] Decide how to treat measured post-pause correction behavior. Keep the
  idle-first AX lane as the safe Bear control/fallback and pursue a separate,
  disabled-by-default text-expander-style experiment. Do not hold Typover's
  own editor to Bear's mutation limitations.
- [x] Decide the active-tap burst policy. ADR-018 keeps the first beta on the
  idle-first lane and limits the disabled research claim to lowercase ASCII
  words completed with Space at 100 milliseconds per key or slower.
- [x] Build and notarize candidate `0.1.0 (20260804072103)` from clean
  revision `e38f535ee2715ff52a8247a9e19e7b882996e13e`; verify its receipt,
  checksum, stapled ticket, Gatekeeper result, and optimized regression gate.
  Its correction evidence remains valid, but the clean first-run pass
  superseded it for distribution after finding the permission-pane misroute.
- [ ] Build and notarize a replacement 0.1.0 candidate from the clean
  permission-flow revision; repeat receipts, Gatekeeper, optimized tests,
  owned-editor smoke, both permission links, and one fresh Bear physical row.
- [ ] Finish the clean-machine permission checklist. Artifact verification,
  installation, and fresh GUI launch pass on the second Mac; visible permission
  grant/revocation needs an unlocked authenticated session. The 2026-08-05
  first-run pass verified the explanation, both denied states, and deferred
  controlled-editor access, but found that the permission button opened
  System Settings at General. Source now guides Accessibility first and Input
  Monitoring second; the replacement notarized candidate must repeat this row.
- [ ] Accept the quiet correction-review interaction on the replacement
  candidate. Verify the 1.5-second hold and 120 ms fade, exact sentence review in the owned
  editor, bounded proximity review in Bear, hover-menu intent and dismissal,
  scrolling/wrapped lines, continued typing, Always Visible, VoiceOver, and no
  focus theft or elevated idle CPU.
- [x] Qualify that exact candidate with fresh Bear and Typover processes and
  release-config memory retirement. Two 2026-08-05 physical runs observed
  159/160 corrections across 160/100/60/40 ms rows, including 20/20 through
  60 ms with both processes fresh. The lone 40 ms result was an exact safe
  `teh` miss with no corruption; the newest-24 retention cap behaved exactly
  as configured. The bounded second-machine soak also passed.

### Required before a public beta

- [x] Close the lifecycle matrix. Notarized update and rollback pass across
  0.0.9 and 0.1.0 with one process and preserved preferences/learning. An
  11-minute clean-Mac soak stayed at 0% CPU with flat RSS, app-only removal
  preserved local state, and explicit full-data removal left no app, process,
  preference domain, Application Support directory, or Typover launch item.
- [x] Select a license and support channel: MIT license and public GitHub
  Issues, with a content-free report contract.
- [x] Finalize release-note and rollback instructions; instantiate them with
  the exact candidate metadata after notarization.
- [ ] Verify that the published privacy, compatibility, and support claims
  match the shipped artifact after the permissioned Bear row.

Future contextual correction, additional applications, and larger model
benchmarks are explicitly **not** blockers for the first word-level Bear beta.

## Parallel experience lanes

ADR-016 now separates the two product environments instead of forcing them
through one compromise.

The controlled editor owns `NSTextView`, `NSTextStorage`, selection, marked
text, Undo, and drawing. Local word correction therefore completes
synchronously during the boundary edit, before the next key is processed.
Contextual work stays asynchronous and can apply behind continued typing or a
moved selection only when its exact captured sentence is unchanged. Multiple
sentences now keep independent in-flight requests, and earlier accepted edits
rebase the ranges of later requests. A result that arrives during marked-text
composition is refused.

Bear keeps ADR-014's installed idle-first AX path as its production control.
The lower-latency spike now has two clearly separated transports behind
`TYPOVER_EXPERIMENTAL_BEAR_TEXT_EXPANSION=1`. The disqualified first transport
observed Space after dispatch and then posted deletion/insertion events. The
replacement candidate installs an active session event tap at the head of the
stream, advances a bounded physical-letter model, posts a fully prepared
`teh -> the` sequence at the callback proxy, and only then returns the original
physical Space. It is off by default and supports only the ordering experiment's
lowercase US-layout letters and Space.

Each fresh AX baseline authorizes at most one destructive transaction. The tap
disarms before it posts and can rearm only after exact bounded verification
adopts a normal reversible Bear anchor. Synthetic events carry Typover's marker
and cannot recurse. Secure Input, learned suppression, modifiers, repeats,
unsupported input, mouse interaction, tap disablement, proposal mismatch, or
startup failure deauthorize the path. An emitted write that cannot be matched
opens the existing mutation circuit without learning, statistics, or a
squiggle. Deterministic gates pass: 17 ordering tests, 45 coordinator tests, a
    clean build, and the full 338-test suite. Physical qualification now proves
the active path at 160/100 ms and 100 ms under combined load; repeat 60/40 ms
rows establish a safe but variable mixed-lane burst envelope rather than an
active-only guarantee.

The first active-tap physical admission attempt stopped before any HID input:
the ESP32 was absent from USB, `keypath-hid-fixture.local` did not resolve, and
its last known home-network address was unreachable. No Bear text was mutated.
This is an infrastructure blocker, not a Typover result; the one-word 160 ms row
remains the first physical gate when the fixture returns.

The first installed physical admission attempt on 2026-08-03 passed three quiet
host samples and found the ESP32, USB keyboard, jig, private diagnostics, and
Typover healthy. It was rejected before any fixture input because Bear remained
windowless after CLI targeting. A later forced Bear restart plus display wake
confirmed that the Mac was at the locked login screen, where macOS correctly
prevents Bear from becoming frontmost. The harness therefore could not prove a
frontmost editor with a collapsed terminal caret. No Bear text was mutated and
this is infrastructure-blocked evidence, not a synthetic-path result. The
unused disposable notes were moved to Bear Trash and Typover was relaunched with
the experimental environment gate off.

After unlock, the installed physical spike passed 1/1 at 160 ms with the exact
`the ` text and 1/1 retained overlay. A five-word matrix then passed 5/5 at both
160 and 100 ms. At 60 ms it produced `the the the teh tthe ` and corrected only
3/5. Focus stayed valid, the fixture completed with no late reports, and the host
remained quiet. The fourth boundary callback was delayed while later physical
input continued, so the post-dispatch deletion targeted stale caret timing.
Verification opened the mutation circuit, but could not prevent the already
emitted keystrokes from damaging text. The 40 ms row was deliberately skipped.
Evidence is stored in `~/.local/state/typover/bear-hid/` under runs
`typover-hid-2026-08-04T02-14-50Z` and
`typover-hid-2026-08-04T02-15-41Z`. The global-monitor/backspace transport is
disqualified for production; Typover was restored to the default safe path and
the evidence note was moved to Bear Trash.

Independent verification repeated the result from fresh notes and fresh Typover
processes. Run `typover-hid-2026-08-04T02-22-44Z` again passed 5/5 at 160 and
100 ms, then corrected only 4/5 at 60 ms with one safe `teh` miss. Run
`typover-hid-2026-08-04T02-24-34Z` tested twenty words at 60 ms: six visibly
changed and fourteen remained `teh`, but Typover verified only five before a
delayed boundary produced another post-write verification failure and opened the
circuit. Overlay sampling found 0/6 retained markers, so that row was rejected as
invalid evidence. Both runs kept Bear focused, used quiet-host admission, and had
no late fixture reports. The exact `tthe` corruption was not reproduced, but the
60 ms unreliability, delayed callback, and unverified-write circuit failure were.
This strengthens rather than weakens the decision to replace the transport.

The active event-tap replacement was physically qualified on 2026-08-03. Run
`typover-hid-2026-08-04T03-58-52Z` passed consecutive 5/5 rows at 160 and
100 milliseconds with ten pre-dispatch emissions, ten verified applications,
zero tap disables, valid focus, zero late fixture reports, and ten retained
overlays. Callback work stayed between 0.041 and 0.110 milliseconds and verified
application latency stayed between 29 and 52 milliseconds.

The first full matrix exposed two lifecycle bugs without text corruption.
Return invalidated the tap between rows but the coordinator did not initially
republish a fresh settled authorization. A first repair then overcorrected by
resetting the word model after every letter. The final contract rearms only
after an explicit invalidating input and a fresh AX snapshot; ordinary letter
updates preserve the tap's bounded predictor. At 40 milliseconds, the matrix
also exposed competing ownership between a coalesced AX fallback scan and a
still-authorized tap. The fallback now explicitly disarms pre-dispatch before
claiming a range or scan, and only post-fallback rebaseline may reauthorize it.

Run `typover-hid-2026-08-04T04-03-46Z` verified that handoff: Bear reached 5/5
at 60 milliseconds using four active corrections and one idle fallback, with
five overlays, no circuit break, and no tap disable. The strict active-only
flag correctly classified the mixed-path row as invalid evidence. The separate
resilience run `typover-hid-2026-08-04T04-04-50Z` continued through both burst
rows: 60 milliseconds safely corrected 4/5, while 40 milliseconds converged
5/5 using one active correction and four bounded catch-up corrections. It kept
focus, received every fixture report on time, refused no replacement, and
retained all nine applied overlays. These repeat results make 60/40 millisecond
coverage a burst-resilience measurement, not an active-only support claim.

Finally, `typover-hid-2026-08-04T04-06-03Z` passed 5/5 at 100 milliseconds
under combined CPU, WindowServer, and Accessibility contention. All five words
used pre-dispatch, the tap never disabled, callbacks took 0.034–0.091
milliseconds, application latency stayed at 34–39 milliseconds, all five
overlays remained, and sampled CPU idle fell as low as 23.5 percent. The
candidate remains disabled by default under ADR-018.

Fresh release-regression rows on 2026-08-03 closed the product-policy slice.
`typover-hid-2026-08-04T06-34-56Z` passed a strict 100 millisecond row 5/5 with
five pre-dispatch emissions. After an explicit mouse click invalidated the
authorization, `typover-hid-2026-08-04T06-36-36Z` recovered a fresh baseline
and again passed 5/5. `typover-hid-2026-08-04T06-37-13Z` exercised the 60
millisecond handoff and safely produced 4/5 with one exact `teh` miss and no
unexpected text. The punctuation row
`typover-hid-2026-08-04T06-38-04Z` safely preserved all five inputs, confirming
that punctuation is not part of the qualified fast-path envelope. Every row
kept focus, complete fixture evidence, and zero late reports.

## Detailed current state

The controlled AppKit and TextKit editor is the complete reference
implementation. It proves Apple Spelling, local contextual intelligence,
Careful and Comprehensive correction scopes, optional sentence rewriting,
multiple independently reversible corrections, preference learning,
statistics, Undo and Redo, and long-document annotation behavior.

The installed acceptance pass in
[`controlled-editor-acceptance.md`](../testing/controlled-editor-acceptance.md)
now covers uninterrupted multi-word correction, independent light-gray
squiggles, contextual correction, and an earlier caret inside surrounding text
on exact notarized candidate `0.1.0 (20260804072103)`. About reports the exact
build and source, and Settings exposes the intended automation identifiers.
The pass found a release-only sentence-boundary misclassification that debug
tests had missed; revision `e38f535` fixes it and makes an optimized regression
test a pre-signing gate. Content-free instrumentation previously measured three
local correction transactions at 0.350–0.461 milliseconds. The full suite now
passes 352 tests in 30 suites. The exact candidate's pointer-only Change Back
and one-step Undo now pass as well: reverting the first of three corrections
preserved both sibling annotations, and Command-Z restored all three.

Bear now supports guarded exact-range replacement, independent Change Back,
ranked alternatives, bounded context re-anchoring, wrapped-range geometry, a
nonactivating clickable overlay, continued typing, and automatic word-level
Apple Spelling. Up to 24 recent Bear corrections can remain independently
reversible. Each primary squiggle exposes direct Accessibility actions for
Change Back and safe alternatives. A scoped Control–Option–Command–M global
shortcut is wired to change back the newest tracked correction without
activating Typover or opening an inactive menu. Its original Carbon registration
accepted the physical chord but did not deliver a callback in the installed
app. The shortcut now uses the same AppKit global key-event path already proven
by automatic Bear correction. Deterministic coverage and an installed physical
one-chord retest pass: one key-down plus release restored exactly the newest
remaining correction while preserving Bear focus, the caret, and all other
text. The feature remains opt-in because final-candidate and clean-machine
acceptance gates are still open.

Bear focus recovery now has a safe two-stage observer. Typover can wait on
content-free application focus notifications when Bear has not exposed an
unambiguous note body, then attach value and selection observation only after a
native editor is available. This closes the gap where entering the note after a
title or search field had been focused could otherwise leave automatic
correction dormant.

The exact notarized `0.1.0 (20260804072103)` candidate completed its final
fresh-process physical qualification on 2026-08-05. A first fresh-Typover run
corrected 80/80 words across 160/100/60/40 ms. After Bear was restarted, the
second run corrected 20/20 at 160, 100, and 60 ms and 19/20 at 40 ms. The
remaining token stayed exactly `teh`; there was no unexpected text, circuit
break, lost focus, refused replacement, or late ESP32 report. Overlay history
grew to the configured 24-item cap and then retired older corrections without
dropping the newest tracked set. Evidence is stored under runs
`typover-hid-2026-08-05T21-47-41Z` and
`typover-hid-2026-08-05T21-50-26Z`.

Bear's keyboard and Accessibility notifications are independent asynchronous
streams, and exact-range replacement is a comparatively slow Accessibility
transaction. Typover now uses one idle-first rule for every mutation. After
220 milliseconds without physical input it scans only the bounded text
observed since the current burst began, queues eligible completed words, and
applies exact-verified ranges from end to beginning. Focus changes, Undo/Redo,
an unavailable burst start, or text outside the 96-unit live window still fail
closed.

The quiet physical HID baseline now passes 20/20 corrections at 160, 100, 60,
and 40 milliseconds per character. The 60 and 40 millisecond rows deliberately
exercise post-burst recovery after Bear coalesces Accessibility notifications.
Every row preserved exact expected text and had matching Typover application
logs; the ESP32 delivered all 162 reports per row with no late reports.

The first controlled-load envelope is also installed and physical. Isolated
CPU, WindowServer, and Accessibility rows each pass 20/20 at 160 milliseconds
per key. A schema-4 combined matrix passes 80/80 across 160, 100, 60, and 40
milliseconds, with machine CPU idle reaching 9.6% and all rows converging
within 1.59–3.79 seconds. The physical punctuation row passes 5/5 across `.`,
`?`, `!`, `;`, and `:` boundaries.

Installed lifecycle controls now cover paste and boundary-only paste refusal,
matched disabled/enabled physical controls, closing and reopening Typover's
main window in the same process, active-selection boundary refusal, bounded
caret/context drift, physical Undo/Redo cancellation, note switching during a
queued correction, and repeated 24-annotation memory cycles. A real
ESP32 Command-Tab and Command-F establish the inactive and retired energy
boundaries: Typover remains at 0.0% CPU after either transition. The current
debug build plateaus below a provisional 200 MiB RSS budget after two complete
24-annotation cycles. A clean release-config development build now passes
three more 24/24 physical cycles and settles at 191,456 KiB after both the
second and third retirement, with 0.0% CPU across every retired sample. This
sets the same provisional 200 MiB local budget for the release configuration
without evidence of linear per-session growth.

An installed Space, Left, and adjacent-`x` control found that a deferred
correction retained only its exact range and could therefore write after its
authorizing caret context had drifted. Deferred corrections now retain a
transient bounded snapshot and require append-only document growth at the same
caret immediately before mutation. The exact physical failure sequence now
preserves `tehx ` with an explicit `deferredContextChanged` skip, while a
separate normal 5/5 append burst still corrects. See
[Deferred correction context drift](../bugs/2026-08-01-deferred-correction-context-drift.md).

An earlier quiet-machine rapid-typing pass corrected every completed typo,
including 21 consecutive `teh ` insertions. All 21 corrections retained
their overlays. Changing back the fifth word then exposed a collection-level
anchor dependency: its verified edit changed the long leading fingerprint of
every later correction. Typover now broadcasts its own verified edits across
the active collection, transforms nonoverlapping ranges, and rebuilds their
anchors from Bear's current text. Automated coverage reverts correction five
of 21 while retaining the other 20 and separately covers length-changing and
overlapping edits. The post-fix installed interaction pass now also succeeds:
an early direct Accessibility action changed only its word and retained all 19
siblings, and a later sibling's pointer menu opened without moving focus or
changing text.

The installed alternative path now passes independently as well. An external
Accessibility client found the primary squiggle's public custom actions while
Bear remained frontmost and chose `ten` for a synthetic `teh -> the`
correction. Bear changed only that anchored word, Typover logged the verified
alternative interaction, and the refreshed squiggle offered `the` as a sibling
choice. The next physical `teh ` became `ten `, proving that the remembered
preference was used. The deliberately bad test preference was then removed
without clearing the existing statistics history.

The first installed visible-latency acceptance point is now recorded against a
clean revision. A one-word physical correction showed its gray squiggle in
444.355 milliseconds, and the real nonactivating menu verified Change Back in
62.441 milliseconds while Bear stayed frontmost. In an uninterrupted
five-word sequence, all five corrections and overlays passed, but the
idle-first safety policy delayed the earlier words until the burst ended:
visible samples ranged from 474.904 to 3,206.381 milliseconds with a
1,824.610-millisecond median. This is a deliberate reliability tradeoff rather
than overlay drawing lag. Beta acceptance must explicitly decide whether
post-pause correction is the intended experience before shortening the idle
gate or allowing Accessibility writes during active input.

The remaining Phase 7 interaction gaps narrowed as well. A physical correction
at paragraph 150 of a 23,431-character disposable note changed only the bounded
midpoint word. Scrolling it offscreen hid the overlay and scrolling back made
the same correction ID and range visible again. A separate physical correction
after a real Bear image attachment retained both the live attachment character
and Bear's attachment record. A full-resolution Dark appearance pass confirmed
the gray squiggle and native menu remain legible while Bear stays frontmost.
Both synthetic notes were soft-deleted after verification.

The spoken VoiceOver journey now passes on the installed release-configuration
development build. Physical VoiceOver navigation reaches Typover's combined
permission rows, discovers a correction through Window Chooser, announces the
correction button, traverses Revert and an alternative, dismisses the Actions
menu, and invokes exact Change Back. The first pass exposed that Window Chooser
activation hid the overlay; Typover now preserves it only for a VoiceOver-driven
host activation and returns both application focus and the VoiceOver cursor to
Bear after the action. Ordinary Typover activation still hides the overlay.

Detailed implementation history remains in the
[controlled-editor milestone record](controlled-editor-roadmap.md) and
[Bear compatibility spike](bear-compatibility-spike.md). Those documents are
evidence, not competing roadmaps.

## Remaining beta sequence

The dashboard above is the summary source of truth. The remaining work is
ordered by what blocks a trustworthy beta:

1. Finish the human-facing quiet-review acceptance pass in the owned editor and
   Bear. The post-pause correction policy is already decided; this pass is now
   about fade/reveal timing, intentional menu activation, focus retention,
   accessibility, and Bear geometry/performance under real typing.
2. Produce the signed and notarized beta candidate, then run the clean-machine
   installation, permission, recovery, update, and uninstall checklist.
3. Qualify that final candidate—not every development build—with fresh Bear
   and Typover processes, the release-config memory envelope, and a bounded
   second-machine soak.
4. Finish public-beta operations: the MIT-licensed source, roadmap, waitlist,
   support channel, release notes, and rollback guidance are public; the
   artifact-to-claim audit remains before publishing the beta binary.
5. After the word-level beta is trustworthy, begin the deferred milestones:
   bounded local contextual correction, then a TextEdit adapter, and finally
   broader model benchmarking.

## Proportionate testing strategy

Use the smallest test that can establish the behavior being changed:

- During ordinary development, run targeted deterministic tests for the
  touched policy, transaction, adapter, or UI behavior.
- Run a focused 1–5 word physical Bear row only when a change touches physical
  input observation, Bear Accessibility, exact-range mutation, overlays, or
  interaction handling.
- Run the full physical matrix only for a release candidate, a supported
  Bear/macOS version change, a material observer/transaction/overlay
  architecture change, or an unexplained installed-app regression.
- Keep specialized rows such as IME composition, 20-word overlay retention,
  severe load, and multi-cycle memory as release regression coverage rather
  than routine per-change checks.
- Preserve fail-closed admission: a shared desktop, lost Bear focus, a busy
  host, incomplete fixture reports, or missing log evidence invalidates the
  run. It is infrastructure evidence, not a Typover pass or failure.
- Do not collect more evidence merely because the harness can. Add or repeat a
  row only when it protects a product claim or answers a live uncertainty.

## Milestone 1: Bear word-correction beta

**Status: In progress — core behavior is complete; 14 of 16 work items are
done. Two beta-acceptance gates remain.**

### Outcome

A writer can enable Typover, write normally in a supported Bear version, and
receive safe word-level corrections without selecting text or invoking the
manual preview command. Each correction keeps its own gray squiggle, Change
Back action, and alternatives.

### Work

- [x] Complete the word-level permissioned installed-app scenarios in the
  [Phase 8 matrix](../testing/bear-phase-8-matrix.md): punctuation, paste and
  boundary-only refusal, selections and context drift, Change Back and
  alternatives, continued typing, note switching, enable/disable lifecycle,
  Undo/Redo, full IME marked text, and multiple recent corrections. Sentence
  correction belongs to Milestone 3 and is not a Milestone 1 gap.
- [x] Complete the relevant visual and robustness rows from
  [Phase 7](../testing/bear-phase-7-matrix.md): long-note interaction,
  scrolling and overlay return, attachment-adjacent correction, and Dark
  appearance.
- [x] Diagnose the Typover Settings accessibility-tree transport failure and
  complete an independent native AX pass. `SkyComputerUseService` crashes with
  `EXC_BREAKPOINT` while Typover remains alive; the native Settings tree returns
  55 descendants and the expected stable control identifiers. Decorative
  status and statistic images are now hidden, statistic cards expose one
  labeled value, and the installed native tree reports zero standalone image
  stops. Computer Use still crashes identically, confirming the external
  boundary documented in
  [Computer Use Settings-tree crash](../bugs/2026-08-03-computer-use-settings-tree-crash.md).
- [x] Complete spoken VoiceOver navigation through Settings, a correction,
  Change Back, an alternative, dismissal, and Bear focus return. Physical
  VoiceOver caption evidence found and verified a host-activation lifecycle
  bug; the installed fix preserves the overlay only for VoiceOver interaction
  and returns the VoiceOver cursor to Bear after exact restoration. Keep the
  evidence in [Bear Phase 7](../testing/bear-phase-7-matrix.md).
  The lifecycle boundary is documented in
  [VoiceOver overlay activation](../bugs/2026-08-03-voiceover-overlay-activation.md).
- [x] Complete an independent unlocked-desktop visual review of Typover
  Settings. Native full-resolution captures covered the installed Settings
  surface from permissions through the final learning controls. The review
  found and fixed the provider-count label `1 corrections`; localized zero,
  singular, and plural coverage now passes, and the installed UI reads
  `1 correction`. Keep the evidence in
  [Bear Phase 7](../testing/bear-phase-7-matrix.md).
- [x] Record the first clean installed correction-to-visible-squiggle and
  menu-to-verified-change timing points without logging writing. A one-word
  correction became visible in 444.355 milliseconds and its real menu verified
  Change Back in 62.441 milliseconds while Bear remained frontmost. A focused
  uninterrupted five-word row passed 5/5 corrections and 5/5 overlays, with
  visible timing from 474.904 to 3,206.381 milliseconds because the idle-first
  policy waits for the burst to stop. Keep the evidence in
  [Bear performance samples](../testing/bear-performance-samples.md).
- [x] Decide whether post-pause correction is the intended beta experience.
  Retain it as the safe AX control/fallback while ADR-016's separately gated
  text-expander-style spike investigates lower latency. Do not enable the new
  transport by default without physical evidence that it preserves exact text,
  selection, focus, Undo, continued typing, and overlay retention.
- [x] Complete a bounded second-machine beta soak. Content-free safe-skip,
  refusal, load, recovery, memory, and energy evidence is already recorded;
  both debug and release-config runs support a provisional 200 MiB RSS budget.
  The final notarized candidate also remained flat at about 160 MiB RSS and
  0% CPU for an 11-minute clean-machine observation. Keep the evidence in
  [Bear performance samples](../testing/bear-performance-samples.md).
- [x] Add capability and version gating so an unknown Bear Accessibility
  contract disables mutation rather than attempting a best guess.
- [x] Define and enforce an explicit support allowlist. Bear 2.8.1 and 2.9.1
  have passed the live Accessibility capability and exact-range transaction
  checks on macOS 27.0.
- [x] Make temporary observer and typed-boundary monitoring failures explicit
  and recover from a fresh baseline on the next application lifecycle event.
- [x] Replace the temporary single-user private Bear trace before broader beta
  testing. Unified logs now contain only content-free event names. The optional
  file-backed trace defaults off; its default enabled mode redacts writing, and
  including bounded context is a separate explicit choice. Settings explains
  the 24-hour/1 MB local retention cap and no-upload boundary and provides
  export and delete controls. Focused store and settings-render tests pass.
- [x] Add a bounded post-burst catch-up pass for rapid physical typing. It may
  inspect only the verified insertion since a recent caret baseline, must wait
  for a short idle
  interval, and must refuse any selection, focus, deletion, replacement, or
  ambiguous-context transition. Do not use whole-note or Bear-database writes.
- [x] Establish a reproducible severe-load recovery envelope. The
  board-independent host harness is implemented and documented in
  [Bear physical HID harness](../testing/bear-physical-hid-harness.md). It
  reuses the existing Waveshare ESP32-S3 fixture, requires a quiet-machine
  baseline, an explicit disposable Bear note, and exclusive Bear focus. It
  captures exact inserted-range, fixture, content-free log, CPU, memory, power,
  and convergence evidence and fails closed on focus, range, log, or resource
  ambiguity. The installed CPU, WindowServer, and Accessibility profiles pass
  20/20 at 160 milliseconds per key. The canonical combined profile passes
  80/80 at 160, 100, 60, and 40 milliseconds with no late HID reports while
  machine CPU idle falls to 9.6%. All four combined rows recover within the
  10-second bound, converging in 1.59–3.79 seconds with no refusal, context loss,
  unexpected text, or circuit-breaker event. Focus changes, ambiguous context,
  an unavailable bounded burst start, a non-append edit, or expiry of the
  10-second observation bound remain explainable safe-refusal boundaries.
  Schema 4 also fixes explicit-note targeting, PID-based power sampling, bounded
  convergence observation, and locale-stable latency evidence. Rejected earlier
  artifacts remain diagnostic-only.
- [x] Populate schema-5 arrival and overlay-retention evidence under controlled
  combined load. Three consecutive fresh-Typover rows pass 60/60 physical
  corrections at 160 milliseconds per key. A separate fresh-note row passes
  20/20 with 20/20 visible correction windows, all 162 fixture reports, zero
  late reports, 21.4% minimum host CPU idle, 40.7% peak Typover CPU, and
  165,264 KiB peak Typover RSS. Completion-boundary-to-AX-value samples span
  1.19-12.58 milliseconds with no reverse callback ordering. A fourth
  fresh-process row also passes 20/20 exact text but is not credited for
  overlays because only four current-line windows remained on screen after
  Bear scrolled the accumulated note. One preceding first-token `eth` artifact
  remains invalid and unexplained; it did not recur in the next 100 physical
  tokens. See
  [Combined-load first token transposition](../bugs/2026-08-03-combined-load-first-token-transposition.md).
- [ ] Qualify the final release candidate once with fresh Bear and Typover
  processes, a fresh disposable note, the release-config memory-retirement
  envelope, and the bounded second-machine soak. Capture per-character
  USB-to-screen-paint timing only if it can be measured without perturbing
  Bear. The fixed churn, anchor, and settling failures remain documented in
  [Bear overlay main-thread churn](../bugs/2026-07-31-bear-overlay-main-thread-churn.md),
  [Empty-note repeated anchors](../bugs/2026-07-31-empty-note-repeated-anchor-ambiguity.md),
  and
  [Bear post-burst overlay retirement](../bugs/2026-07-31-bear-post-burst-overlay-retirement.md).
- Keep automatic Bear correction off by default until the exit criteria pass.

### Exit criteria

- Every listed installed-app scenario passes or produces an intentional safe
  refusal that is explainable through content-free diagnostics.
- No tested failure changes the wrong range, moves the writer to another
  editor, loses newly typed text, or leaves a stale squiggle visible.
- Change Back and alternatives work independently across several recent
  corrections.
- Typover records enough content-free diagnostics to explain why a correction
  was applied, missed, or refused.
- The supported Bear and macOS versions are stated explicitly.

### Not required for this milestone

- sentence-level AI in Bear;
- support for an older Bear release that is not part of the initial support
  claim;
- support for another writing application; or
- enabling automatic Bear correction by default.

## Milestone 2: Minimum beta shell

**Status: In progress — the signed/notarized and clean-install halves pass;
the authenticated permission UI half remains.**

### Outcome

A new tester can install Typover, understand its permissions and privacy
boundary, enable Bear support, diagnose an unavailable state, and recover from
ordinary app or Accessibility lifecycle changes.

### Work

- [x] Create a benefit-led first-run explanation for Accessibility and Input
  Monitoring, with a clear path to System Settings and an option to explore
  later. The reusable permission rows refresh whenever Typover becomes active;
  the installed Settings visual review now passes.
- [x] Show whether Bear correction is disabled, waiting, observing, paused,
  unsupported, or missing permission.
- [x] Explain capability and version gating in the interface, including why an
  installed Bear version is unsupported.
- [x] Decide and document background launch and launch-at-login behavior.
  ADR-015 keeps the initial beta manually launched until energy, recovery,
  update, and uninstall evidence passes.
- [x] Provide a privacy summary and a content-free diagnostic export. The
  optional local trace now has explicit consent, bounded retention, export,
  delete, and a separately gated bounded-writing mode.
- [x] Expose beta build identity in the About window. It shows the marketing
  version, build number, short source revision, and a visible **Modified**
  marker for dirty development builds while retaining exact provenance in the
  bundle metadata.
- [x] Declare reviewable Accessibility and Input Monitoring purpose text in the
  signed bundle, and reject beta artifacts that omit either privacy
  description.
- [ ] Complete the signed beta and repeatable clean-machine permission test.
  The Developer ID/notarization script and clean-machine
  checklist are implemented in
  [Beta distribution](../testing/beta-distribution.md). The local Developer ID
  archive now passes strict signature, expected-team, hardened-runtime, secure
  timestamp, bundle metadata, system-dependency, and clean-zip verification.
  Every package now also emits a machine-readable receipt tying the archive's
  SHA-256 to its version, build, source provenance, signing team, deployment
  floor, and notarization claim; positive and adversarial receipt verification
  remain part of the package gate.
  Every build now extracts the archive, rejects unsafe
  or unexpected paths, compares the distributed bundle byte-for-byte with the
  signed build output, and verifies the extracted signature; adversarial extra-
  path and mismatched-bundle tests pass. The bundle and executable now both
  declare the supported macOS 27.0 deployment floor, and the verifier requires
  them to match. Building and validating the notarized
  candidate and executing the clean-machine permission checklist were the
  original remaining steps. Candidate `0.1.0 (20260804072103)` from clean
  revision `e38f535` is now Apple-notarized, stapled, Gatekeeper-approved, and
  receipt-verified. A second Mac passed checksum verification, clean
  `/Applications` install, and fresh GUI launch. The candidate's first-run
  permission UI still needs an unlocked authenticated pass through grant,
  revocation, recovery, and Bear observation.

### Exit criteria

- A clean Mac can reach a working Bear correction without developer tools.
- Revoked permission, Bear relaunch, Typover relaunch, and unsupported versions
  produce understandable recovery states.
- Beta privacy and supported-version claims match observed behavior.

## Parallel track: Release operations

**Status: In progress — the full signed lifecycle matrix passes and the source
repository, roadmap, waitlist, and support channel are public; the permissioned
artifact-to-claim audit remains.**

This track may proceed after the minimum beta shell is stable. It does not
block local contextual-correction development, but it must pass before Typover
is offered as a public beta.

- [x] Define the local release-operations contract. The
  [beta release-operations contract](../testing/beta-release-operations.md)
  defines numeric versions/builds, exact source provenance, manual update,
  rollback, uninstall footprint, and a release-note template.
- [x] Finish clean-Mac lifecycle testing. Notarized 0.0.9-to-0.1.0 update,
  rollback, and final restore pass with one process and preserved settings and
  learning data. The final candidate completed an 11-minute flat-resource soak;
  recoverable app-only removal preserved state, and explicit full-data removal
  cleared the app, process, preferences, Application Support, and launch-item
  footprint without touching macOS-owned TCC records.
- [x] Publish the MIT-licensed repository, visual roadmap, privacy-conscious
  waitlist issue form, and GitHub Issues support channel.
- [x] Select and document the MIT license.
- [ ] Accept the intended public distribution artifact. Candidate 0.1.0 passes
  signing, notarization, receipt, installation, update, rollback, soak, and
  removal; the permissioned Bear row remains before publication.
- [ ] Confirm that public privacy, support, and compatibility claims match the
  shipped build.

## Milestone 3: Contextual correction in Bear

**Status: Deferred — supporting primitives exist, but no item is complete for
the installed Bear integration.**

### Outcome

Typover can apply bounded sentence-context spelling, punctuation, and grammar
corrections in Bear without blocking typing or weakening the word-level safety
contract.

### Work

- [ ] Detect a verified completed sentence after punctuation. The dormant Bear
  capture primitive now requires the observed terminator to match the bounded
  Accessibility text exactly.
- [ ] Capture only the most recent sentence, capped at 400 UTF-16 units. Bounded
  reads now resolve document coordinates only when the sentence begins at the
  document start or an earlier terminator is visible; truncated beginnings
  fail closed. Runtime scheduling remains gated on Milestone 1 evidence.
- [ ] Run the selected contextual engine asynchronously while continued typing
  remains responsive.
- [ ] Discard a proposal if the captured sentence changes, focus moves, or the
  target is no longer unique.
- [ ] Preserve Careful as the default and keep Comprehensive plus sentence
  rewriting as separate explicit choices.
- [ ] Use Apple Intelligence locally by default. Use OpenAI or Anthropic only
  after an explicit provider choice, with no automatic cloud fallback.
- [ ] Reuse the same exact-range transactions, individual annotations, Change
  Back, alternatives, statistics, and bounded restoration rules.

### Exit criteria

- Contextual inference never blocks Bear typing or applies to stale text.
- Every accepted change is visible and independently reversible.
- The installed Bear corpus preserves the controlled editor's false-positive
  and meaning-preservation gates.
- Cloud behavior matches the disclosure in Preferences exactly.

## Milestone 4: Application-neutral editor integration

**Status: Not started.**

### Outcome

Bear becomes one adapter for a generic Accessibility correction system rather
than the architecture itself.

### Work

- [ ] Extract an application-neutral target profile containing:
  - bundle identity and supported versions;
  - focused-editor discovery;
  - required Accessibility attributes and notifications;
  - range replacement and caret behavior;
  - geometry and coordinate conversion; and
  - application-specific lifecycle quirks.
- [ ] Keep correction engines, range verification, re-anchoring, overlays,
  learning, and statistics shared.
- [ ] Implement TextEdit as the second adapter and genericity proof.
- [ ] Build a content-free compatibility probe that classifies an editor as
  full, correction-only, cooperative-integration-required, or unsupported.
- [ ] Run that probe against the macOS ChatGPT and Claude message composers.
  Treat them as separate targets even if they share an implementation
  technology or expose similar Accessibility trees.
- [ ] For each chat app, document focused-composer discovery, bounded text and
  selection reads, value/selection notifications, exact-range replacement,
  caret behavior, geometry, rich-text or attachment behavior, IME behavior,
  and changes across supported app versions.
- [ ] Restrict inspection to bounded text in the active composer. Do not read
  conversation history, sidebars, past messages, or application databases.
- [ ] Prove that correction handling cannot activate Send, submit on Return,
  change the selected conversation, disturb an attachment, or move focus out
  of the composer. If the app cannot expose a safe transaction boundary,
  classify it as cooperative-integration-required or unsupported.
- [ ] Exclude secure text fields, password editors, and any target whose text or
  selection contract cannot be inspected safely.
- [ ] Add applications only after their own permissioned matrix passes. Native
  implementation alone is not evidence of compatibility.

### Exit criteria

- Bear and TextEdit use the same generic correction pipeline with only target
  profiles and documented quirks differing.
- Any supported ChatGPT or Claude adapter changes only the verified active
  composer range and never submits a message. Support is app- and
  version-specific; passing one chat app does not qualify the other.
- An unsupported editor fails closed without showing a misplaced annotation or
  changing text.
- Product language names supported applications instead of claiming universal
  system-wide compatibility.

## Milestone 5: Quality scale and model evaluation

**Status: Early groundwork only — the target corpus and cross-version evidence
are not complete.**

### Outcome

Typover's model and policy decisions are supported by representative writing,
cross-version results, and repeatable local benchmarks.

### Work

- [ ] Grow the rewrite benchmark from 35 to at least 500 cases, including at
  least 300 diverse unchanged controls.
- [ ] Add consented, de-identified natural-writing examples containing no private
  text.
- [ ] Test correction and rewrite corpora against every supported macOS
  system-model version.
- [ ] Benchmark selected open-source models running locally through the existing
  engine boundary.
- [ ] Revisit confidence only if calibrated evidence improves the binary
  automatic decision without making the interaction harder to understand.
- [ ] Keep false-positive and meaning-preservation performance ahead of raw
  correction coverage.

### Exit criteria

- Model comparisons use the same safety filters, corpus, metrics, and hardware
  disclosure.
- Default-model and support decisions are based on reviewed evidence rather
  than a small development corpus.
- No model-specific requirement distorts the editor interaction or privacy
  contract.

## Sequencing decisions

- Milestone 1 qualification, the bounded Bear lower-latency spike, and
  controlled-editor hardening are the active implementation lanes.
- Remaining Phase 7 evidence is part of Milestone 1; Phase 7 is no longer a
  separate implementation stream.
- The minimum beta shell in Milestone 2 follows the word-level Bear gate before
  more correction scope is added.
- Sentence-level Bear intelligence follows the minimum beta shell. Release
  operations may continue in parallel and do not block local contextual
  development.
- Release operations must pass before public beta distribution.
- Application generalization begins only after Bear is a trustworthy reference
  integration.
- Corpus expansion and local-model benchmarking may proceed in parallel when
  they do not distract from the active milestone.

## Deferred or explicitly out of scope

- whole-field, paragraph, selection, note, or document replacement;
- automatic cloud fallback;
- silently reading Bear's database;
- converting raw Markdown or Bear CLI offsets into live editor offsets;
- universal compatibility claims based only on an app being native;
- native persistent formatting inside an external editor without cooperation
  from that editor or Apple; and
- changing the default correction policy based on an uncalibrated confidence
  score.

## Immediate next slice

1. Build and notarize the final beta candidate from the accepted clean
   revision.
2. Repeat the focused controlled-editor acceptance rows against that exact
   candidate.
3. Keep the current idle-first AX lane as the Bear beta behavior; the active
   lane remains a disabled research experiment under ADR-018.
4. Run the clean-machine
   install, permission, fresh-process, release-memory, and second-machine soak
   checklist against that exact artifact.
5. Qualify in-place update, rollback, app-only removal, and full local-data
   removal; then bind exact artifact metadata into the release notes.

Do not routinely repeat the full 20-word, severe-load, circuit-breaker, or IME
rows. They are release regression coverage and should be rerun only when the
testing strategy above calls for them.
