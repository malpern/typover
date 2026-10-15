# Mac development prompt

Paste the block below into a coding agent opened in the Typover repository on
the target Mac (likely the Mac mini). Fetch the latest master first without
discarding local work. This prompt authorizes implementation and local commits;
it does not authorize a public release, uploads of private writing, or new paid
provider usage.

---

Lead implementation of Typover's editor-first strategy. I want to type very
quickly without worrying about typos, mistypes, spelling, grammar, or basic
formatting, and get clean writing that still sounds like me. Build on Typover's
existing native editor and reversible corrections. The custom editor is the
product priority; universal macOS Accessibility/Bear integration is deferred.

Read AGENTS.md and these documents before editing:
- docs/plans/editor-first-strategy.md
- docs/plans/editor-first-implementation.md
- docs/testing/editor-first-validation.md
- docs/correction-behavior.md
- applicable ADRs and the existing build/test scripts.

The new editor-first documents supersede older Bear-first sequencing. Preserve
the existing safety invariants and useful shared tests. Historical release
qualification is not evidence that the new editor milestones are complete.

Start by inspecting the working tree and current implementation. Preserve
unrelated changes; use an isolated branch/worktree if needed. Verify the actual
Mac's hardware, macOS, Swift/Xcode/SDK versions, GUI access, and Apple Intelligence
availability. The reviewed project required macOS 27 and Swift 6.4: inspect the
current package and APIs, and do not silently lower requirements. Run the
documented build and tests and establish M0 evidence before changing behavior.
Do not print credentials or collect private writing automatically.

Then implement M1 through M5 in dependency order, as tested vertical slices.
Make routine architecture and UI decisions yourself. Keep the app runnable,
prefer small refactors over a wholesale rewrite, and commit each coherent,
validated increment locally with a clear message. Continue through available
work rather than stopping after producing another plan or skeleton. If the
full program exceeds one session, leave a durable handoff and resume from it.

Priorities:
1. A quiet useful writing surface, dependable drafts/autosave/recovery, clean
   text/Markdown interchange, persisted correction history, and keyboard review.
   Ordinary startup must not require AX or Input Monitoring.
2. Responsive input, background ordered persistence, guarded transactions,
   indexed anchors where profiling warrants them, and bounded rendering work.
3. Bounded rolling-context correction on completion, pauses, and later context,
   with coalesced scheduling, safe stale-result rejection/reconsideration, and
   validated insert/delete/replace edits.
4. Inspectable personal vocabulary/replacements/preferences, carefully scoped
   rejection learning, and deterministic reversible formatting.
5. Held-out streaming evaluation and actual Mac writing evidence showing less
   repair and review burden without damage to meaning or voice.

Preserve original text for every automatic correction and apply only the
smallest safe range. Never apply a whole-document correction, overwrite newer
user edits, or touch active marked text. Keep Undo/Redo understandable, Change
Back immediate, and faded corrections reviewable. Protect numbers, names,
negation, modality, code, and literal regions. Keep style rewriting separately
opt-in; structural checks do not prove an edit preserves meaning.

Use deterministic engines/clocks/storage fault injection for correctness tests;
use live models for separate quality evaluations. Exercise Unicode, IME,
multiple documents, close/switch during inference, out-of-order results,
overlapping corrections, force-quit recovery, and keyboard/VoiceOver behavior.
Measure release-build latency on this Mac and distinguish software timings
from physical input-to-display latency. Never label an unavailable GUI, SDK,
model, or manual test as passed.

Local processing is the default. Do not silently fall back to a cloud model.
The existing remote contract sends a sentence; expanded context requires a
clear new disclosure and explicit user choice. Do not upload private examples
or enable new paid usage as part of testing.

Update the milestone ledger with commit IDs, commands, evidence, failures,
and remaining manual gates. Maintain docs/development/editor-first-handoff.md
with current branch/revision, completed work, design decisions, exact next
steps, and reproducible commands. Keep documentation accurate about implemented
versus planned behavior. Record ADRs for meaningful storage/transaction changes.

Ask me only for a genuinely blocking product decision, required credentials,
or a manual action you cannot perform. If GUI/model qualification is blocked,
complete independent implementation and deterministic testing, record the
blocker precisely, and leave the relevant gate pending. Do not spend time
reviving the Bear release workflow to qualify the custom editor.

At each substantial checkpoint report what now works, tests and measurements,
known limitations, and the next milestone. At handoff, provide the runnable app
location/launch command and a short manual acceptance script. Do not publish,
merge into master, or distribute a release without a separate instruction.
