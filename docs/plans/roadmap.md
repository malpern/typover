# Typover roadmap

- Status: Active
- Updated: 2026-07-26
- Current milestone: 1 — Bear word-correction beta

## Goal

Deliver automatic corrections that remain visible, understandable, and
individually reversible while someone writes naturally. Typover should begin
with a trustworthy Bear integration, then reuse the proven interaction in a
carefully tested subset of other macOS editors.

## Product contract

Every milestone preserves the same invariants:

- replace the smallest verified text range, never an entire field or document;
- retain the original for every automatic correction;
- leave a quiet light-gray squiggle until the correction is resolved;
- make Change Back and alternatives immediate;
- fail without writing when focus, text, selection, or geometry is ambiguous;
- keep Apple processing on device by default;
- transmit text only after an explicit cloud-model choice; and
- never claim compatibility from deterministic tests alone.

## Current state

The controlled AppKit and TextKit editor is the complete reference
implementation. It proves Apple Spelling, local contextual intelligence,
Careful and Comprehensive correction scopes, optional sentence rewriting,
multiple independently reversible corrections, preference learning,
statistics, Undo and Redo, and long-document annotation behavior.

Bear now supports guarded exact-range replacement, independent Change Back,
ranked alternatives, bounded context re-anchoring, wrapped-range geometry, a
nonactivating clickable overlay, continued typing, and automatic word-level
Apple Spelling. Up to 24 recent Bear corrections can remain independently
reversible. The feature remains opt-in because most automatic-writing scenarios
still need permissioned installed-app validation.

Detailed implementation history remains in the
[controlled-editor milestone record](controlled-editor-roadmap.md) and
[Bear compatibility spike](bear-compatibility-spike.md). Those documents are
evidence, not competing roadmaps.

## Milestone 1: Bear word-correction beta

### Outcome

A writer can enable Typover, write normally in a supported Bear version, and
receive safe word-level corrections without selecting text or invoking the
manual preview command. Each correction keeps its own gray squiggle, Change
Back action, and alternatives.

### Work

- Complete the permissioned installed-app scenarios in the
  [Phase 8 matrix](../testing/bear-phase-8-matrix.md):
  - punctuation;
  - paste and boundary-only paste refusal;
  - active selections and bounded-context drift;
  - Change Back and alternatives;
  - rapid continued typing;
  - note and window switching;
  - disabling and re-enabling Typover;
  - marked-text composition and Undo/Redo;
  - multiple recent corrections.
- Absorb the remaining relevant
  [Phase 7 robustness rows](../testing/bear-phase-7-matrix.md):
  - long-note interaction;
  - scrolling during refresh;
  - attachment-adjacent correction;
  - final Dark appearance review; and
  - full spoken VoiceOver navigation.
- [ ] Measure correction-to-squiggle latency, interaction latency, safe misses,
  refusals, false changes, memory, energy, and recovery behavior without
  logging writing. Session-only applied, safe-skip, refusal, and
  correction-to-annotation measurements are implemented; installed latency,
  interaction latency, active memory and energy, and recovery samples remain.
  A locked/waiting idle sanity check is recorded in
  [Bear performance samples](../testing/bear-performance-samples.md).
- [x] Add capability and version gating so an unknown Bear Accessibility
  contract disables mutation rather than attempting a best guess.
- [x] Define the initial support claim narrowly as Bear 2.8.1 on macOS 27.0,
  the environment currently under installed-app validation.
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

### Outcome

A new tester can install Typover, understand its permissions and privacy
boundary, enable Bear support, diagnose an unavailable state, and recover from
ordinary app or Accessibility lifecycle changes.

### Work

- Create a benefit-led first-run explanation for Accessibility and Input
  Monitoring, with a clear path to System Settings and an option to explore
  later.
- Show whether Bear correction is disabled, waiting, observing, paused,
  unsupported, or missing permission.
- Explain capability and version gating in the interface, including why an
  installed Bear version is unsupported.
- Decide and document background launch and launch-at-login behavior.
- Provide a privacy summary and a content-free diagnostic export.
- Produce a signed beta build and a repeatable clean-machine install and
  permission test.

### Exit criteria

- A clean Mac can reach a working Bear correction without developer tools.
- Revoked permission, Bear relaunch, Typover relaunch, and unsupported versions
  produce understandable recovery states.
- Beta privacy and supported-version claims match observed behavior.

## Parallel track: Release operations

This track may proceed after the minimum beta shell is stable. It does not
block local contextual-correction development, but it must pass before Typover
is offered as a public beta.

- Test update and uninstall behavior on a clean Mac.
- Define versioning, release notes, rollback, and the beta support channel.
- Select and document the license.
- Produce the intended public distribution artifact and verify its signing,
  notarization, installation, update, and removal behavior.
- Confirm that public privacy, support, and compatibility claims match the
  shipped build.

## Milestone 3: Contextual correction in Bear

### Outcome

Typover can apply bounded sentence-context spelling, punctuation, and grammar
corrections in Bear without blocking typing or weakening the word-level safety
contract.

### Work

- Detect a verified completed sentence after punctuation.
- Capture only the most recent sentence, capped at 400 UTF-16 units.
- Run the selected contextual engine asynchronously while continued typing
  remains responsive.
- Discard a proposal if the captured sentence changes, focus moves, or the
  target is no longer unique.
- Preserve Careful as the default and keep Comprehensive plus sentence rewriting
  as separate explicit choices.
- Use Apple Intelligence locally by default. Use OpenAI or Anthropic only after
  an explicit provider choice, with no automatic cloud fallback.
- Reuse the same exact-range transactions, individual annotations, Change Back,
  alternatives, statistics, and bounded restoration rules.

### Exit criteria

- Contextual inference never blocks Bear typing or applies to stale text.
- Every accepted change is visible and independently reversible.
- The installed Bear corpus preserves the controlled editor's false-positive
  and meaning-preservation gates.
- Cloud behavior matches the disclosure in Preferences exactly.

## Milestone 4: Application-neutral editor integration

### Outcome

Bear becomes one adapter for a generic Accessibility correction system rather
than the architecture itself.

### Work

- Extract an application-neutral target profile containing:
  - bundle identity and supported versions;
  - focused-editor discovery;
  - required Accessibility attributes and notifications;
  - range replacement and caret behavior;
  - geometry and coordinate conversion; and
  - application-specific lifecycle quirks.
- Keep correction engines, range verification, re-anchoring, overlays, learning,
  and statistics shared.
- Implement TextEdit as the second adapter and genericity proof.
- Build a content-free compatibility probe that classifies an editor as full,
  correction-only, cooperative-integration-required, or unsupported.
- Exclude secure text fields, password editors, and any target whose text or
  selection contract cannot be inspected safely.
- Add applications only after their own permissioned matrix passes. Native
  implementation alone is not evidence of compatibility.

### Exit criteria

- Bear and TextEdit use the same generic correction pipeline with only target
  profiles and documented quirks differing.
- An unsupported editor fails closed without showing a misplaced annotation or
  changing text.
- Product language names supported applications instead of claiming universal
  system-wide compatibility.

## Milestone 5: Quality scale and model evaluation

### Outcome

Typover's model and policy decisions are supported by representative writing,
cross-version results, and repeatable local benchmarks.

### Work

- Grow the rewrite benchmark from 35 to at least 500 cases, including at least
  300 diverse unchanged controls.
- Add consented, de-identified natural-writing examples containing no private
  text.
- Test correction and rewrite corpora against every supported macOS system-model
  version.
- Benchmark selected open-source models running locally through the existing
  engine boundary.
- Revisit confidence only if calibrated evidence improves the binary automatic
  decision without making the interaction harder to understand.
- Keep false-positive and meaning-preservation performance ahead of raw
  correction coverage.

### Exit criteria

- Model comparisons use the same safety filters, corpus, metrics, and hardware
  disclosure.
- Default-model and support decisions are based on reviewed evidence rather
  than a small development corpus.
- No model-specific requirement distorts the editor interaction or privacy
  contract.

## Sequencing decisions

- Milestone 1 is the only active implementation milestone.
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

Run and record the installed Phase 8 word-correction matrix against the signed
app in the disposable Bear fixture. Fix only defects exposed by that pass, add
deterministic regression coverage for each defect, and keep sentence-level Bear
work out of scope until the word-level exit criteria are satisfied.
