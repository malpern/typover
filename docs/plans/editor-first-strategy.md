# Typover: editor-first strategy

- Date: 2026-10-15
- Status: Accepted direction; implementation pending
- Baseline reviewed: `f26a8217478454acedee6cb250f7969bf9b9f09d`
- Delivery: [implementation plan](editor-first-implementation.md)
- Execution: [Mac development prompt](../development/mac-development-prompt.md)

## Outcome

Let the writer type at full speed, with little attention spent repairing typos,
mistypes, spelling, grammar, or basic formatting. The result should be clean and
recognizably theirs. Typover should improve its decisions as more context
arrives and as the writer explicitly teaches it preferences.

Build this experience first inside Typover's own native editor. The existing
AppKit/TextKit implementation and reversible correction machinery are the
foundation. A Bear-like quiet writing surface is a useful interaction reference;
cloning Bear's full library, sync, or feature set is not the first objective.

## Priority and scope

This strategy and its implementation plan supersede the Bear-first sequencing
in the previous roadmap and product brief. Previous implementation evidence,
safety invariants, and release records remain valid historical records.
Planned behavior here is not a claim about the current build.

Freeze expansion of the Bear/Accessibility adapter. Preserve its code and tests
where practical, isolate it from ordinary startup, and exclude its permission,
overlay, and physical-HID qualification work from editor milestone gates.
The custom editor must work without Accessibility or Input Monitoring grants.
Its own keyboard navigation and VoiceOver support remain essential.

The first daily-use release includes local drafts, recovery, plain text and
Markdown interchange, excellent editing, reversible corrections, bounded
contextual reconsideration, and inspectable local preferences. Defer universal
cross-app correction, collaboration, sync, plugins, a full notes database,
keyboard firmware changes, and online model training.

## Product contract

1. Typing and navigation remain responsive even when inference or storage is slow.
2. Every automatic change has a bounded target, verified original text, and
   durable provenance. Never replace a document as a correction.
3. New context may justify reconsidering recent text. It must never license
   overwriting subsequent user edits or an active composition.
4. Restoring an original, choosing an alternative, and reviewing changes work
   by keyboard as well as pointer. Fading a mark never deletes its history.
5. Explicit edits and rejections outrank a model. Do not repeatedly reapply a
   rejected correction to the same passage.
6. Mechanical correction, grammar correction, and stylistic rewriting have
   distinct policies. Keep stylistic rewriting separately opt-in.
7. Preserve meaning, voice, names, numbers, negation, and modality. Structural
   validity alone does not establish that a model edit is desirable.
8. Prefer local processing. Changing the amount of context sent to a cloud
   provider changes the privacy contract and must be disclosed before use.

## Experience

Open directly into a useful draft, with a quiet native writing surface,
comfortable typography, find, normal text shortcuts, and unobtrusive save state.
No seeded demo paragraph or always-present testing instructions in daily use.
Keep diagnostic controls available in a development surface.

Use three correction timescales:
- At word boundaries, apply high-precision spelling and explicit replacement rules.
- After sentence/paragraph completion or a short pause, examine the active passage.
- As following text resolves ambiguity, reconsider a bounded recent passage.

Use a configurable, bounded context window, initially the active paragraph and
up to two neighboring paragraphs subject to a character/token cap. The writable
region is smaller than the readable context. Default reconsideration is confined
to the active and immediately preceding paragraph; older text requires an
explicit review action. Tune these starting limits with evidence.

Do not change marked text, the token being composed, or a selected range.
Defer affected proposals until a safe boundary and revalidate them then. Idle
correction should not make the caret jump. Do not continually oscillate between
two plausible outputs. Uncertain or meaning-sensitive edits should be left
alone or offered for review.

Basic formatting starts with deterministic, reversible behavior: list continuation,
indentation, and Markdown-aware presentation. Protect code, URLs, and explicitly
literal regions. Do not introduce automatic paragraph restructuring under the
label of typo correction.

## Reuse and architecture

Keep TypoverCore, Apple spelling, model adapters, exact-range transactions,
selection adjustment, learning controls, and the existing AppKit stress harness.
Extract responsibilities from TypoverTextView incrementally rather than replacing
the editor in one rewrite.

Introduce boundaries for document storage, correction transactions/history,
scheduling/context assembly, policy/learning, and annotation presentation.
TextKit remains the editing authority; a document revision and stable document
identity accompany asynchronous work. Models propose structured edits; the
transaction layer validates and applies them.

The static review found synchronous full learning-store serialization on the
main actor, repeated annotation scans, sentence-only contextual requests, and
an in-memory demo editor without document lifecycle. These are priorities to
measure and address, not measured performance claims.

Use background persistence with ordered revisions, bounded/coalesced scheduling,
indexed correction anchors, and viewport-limited rendering. Retain a simple
implementation where profiling shows it adequate. Avoid building a generalized
editing platform before the first useful draft experience.

## Personalization

Retain explicit replacement mappings, vocabulary, exclusions, and inspectable
preference provenance. Support importing a static replacement list through a
preview that reports duplicates, conflicts, invalid entries, and scope; never
silently bulk-enable questionable rules.

Add explicit language, terminology, punctuation, and optional style preferences.
Start with retrieval of relevant approved preferences, not model fine-tuning.
Treat a contextual rejection as passage-specific unless the user chooses a
broader rule; rejecting one homophone correction must not ban that word globally.
Silence is not proof of acceptance. Implicit learning needs separate evidence
and must not turn accidental edits into permanent preferences.

Writing examples and private session traces are local and opt-in. Provide
inspect, edit, export, and reset controls. Exporting a clean draft must not export
private original text or learning history. Deleting a document must explain
whether any separate, deliberately learned preferences remain.

## Evidence of value

Optimize useful words produced per minute, including time spent reviewing and
repairing output. Raw typing speed and correction count are secondary.

Compare the existing editor baseline, new correction policies, and correction-off
sessions using matched tasks and counterbalanced ordering where feasible.
Measure final residual errors, unwanted changes, repair actions/time, review
burden, preserved voice, and input latency. Report denominators and variation.
Start with the owner's real writing and opt-in sanitized examples, then test
other writers before claiming general superiority.

Separate deterministic transaction correctness from model quality and physical
typing responsiveness. Frozen held-out examples must not become the prompt
tuning set. Include already-correct informal writing and legitimate unusual
wording, not just easily corrected mistakes.

## Release decision

Ship a useful editor before pursuing a universal correction service. Release
only when document recovery, correction reversibility, keyboard interaction,
and latency gates pass on the target Mac. Expand automatic coverage only when
held-out quality and real writing demonstrate less repair without meaning loss.
The release plan must state unsupported languages, document sizes, model
availability, and behavior when contextual intelligence is unavailable.
