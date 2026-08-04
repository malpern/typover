# macOS text-expander implementation survey

- Status: Research complete; deterministic implementation gates passed,
  physical qualification pending
- Date: 2026-08-03
- Scope: System-wide macOS expansion mechanisms that could reduce Bear
  correction latency without weakening Typover's fail-closed contract

## Question

Do established macOS text expanders use a system facility that can make a
Bear correction immediate, ordered, reversible, and safe while the writer
continues typing?

## Findings

### The common implementation is observation followed by synthetic editing

The public evidence does not reveal a hidden atomic cross-application text
replacement API.

- Apple's global `NSEvent` monitor receives events asynchronously, after they
  have been posted to the target. Apple explicitly says it can only observe an
  event and cannot modify or prevent delivery. Espanso's current macOS detector
  uses this API. Its engine compensates for a trigger with synthetic backspaces,
  then injects replacement text with `CGEvent` Unicode keyboard events. It can
  switch between event injection and a clipboard backend, and exposes delays
  because target applications can miss events or paste stale clipboard data.
- TypeIt4Me documents that its default expansion path places the snippet on the
  clipboard and pastes it over the abbreviation. It offers a slower plain-text
  non-clipboard path, a configurable clipboard-restoration delay, and recommends
  increasing that delay on slower or heavily loaded Macs.
- TextExpander likewise documents a clipboard plus synthetic Command-V path for
  some applications, clipboard restoration timing, and application-specific
  compatibility failures.
- TypeIt4Me, TextExpander, Typinator, and Espanso all document that Secure Input
  can prevent them from observing abbreviations. This is a platform boundary,
  not an implementation bug Typover can bypass.

This explains why mature expanders can work well without establishing the
stronger contract Typover needs. A text expander normally performs a known,
explicit, infrequent trigger replacement and can offer per-application
exceptions or timing knobs. Typover may correct every completed word, must not
damage subsequent input, and must subsequently prove and retain an independently
reversible exact range.

### The first Typover transport reproduced the known weak architecture

Typover's disqualified prototype used the same broad family as Espanso:

1. observe the completion boundary through AppKit's asynchronous global monitor;
2. post backspaces at a Core Graphics event-tap location;
3. post replacement text;
4. verify the result later through Bear Accessibility.

The 60 ms physical failures were therefore not evidence that text expansion is
impossible. They showed that a post-dispatch observer cannot safely decide what
stale caret content to delete while newer physical input is already reaching
Bear. Adding sleeps or tuning injection delays may change the failure rate but
cannot create an ordering guarantee.

### An active Core Graphics event tap is materially different

Apple describes an active `CGEventTap` as a filter: its callback can return a
modified or replacement event, or return `NULL` to delete the event. More
importantly, `CGEventTapPostEvent` posts new events at the same point in the
stream as the callback's returned event, and Apple guarantees that those posted
events enter the system before the returned event.

That supports a more precise completion-boundary transaction:

1. physical letters pass through and update a tiny in-memory word tracker;
2. a correction proposal is computed and cached before the boundary arrives;
3. when a supported boundary reaches the active tap, the callback synchronously
   posts exactly the word-length backspaces and replacement at its tap proxy;
4. the callback returns the original boundary, which enters the stream after
   those replacement events;
5. subsequent physical events remain later in the same event stream;
6. asynchronous AX verification either adopts a reversible Bear anchor or opens
   the existing mutation circuit.

Unlike the first prototype, the boundary has not reached Bear yet, so the
transaction deletes only the completed word and does not synthesize the
boundary. No clipboard is involved.

This is still a hypothesis to qualify, not an atomic text API. Apple specifies
the position of tap-posted events relative to the returned boundary, but Bear's
acceptance, multiple posted-event ordering, Undo behavior, and interaction with
other taps require physical evidence. The callback also has a strict latency
budget; macOS can disable a slow event tap. It must therefore perform no AX IPC,
AppKit spell checking, model inference, disk access, logging I/O, waits, or
allocation-heavy work.

### InputMethodKit is the semantically stronger fallback

InputMethodKit gives an active input method an input controller for each client
session and supports a replacement range in the client document. Apple's own
documentation uses a word-to-synonym replacement as its example. This is closer
to cooperative text insertion than deletion and retyping.

It is not the first experiment because it changes the user's active text-input
method and product model, has a much larger installation and compatibility
surface, and still would not give Typover native persistent Bear formatting.
It remains the fallback research direction if an active event tap cannot meet
the ordering gate.

## Decision for the next Bear experiment

Build a second disabled-by-default transport around an active
`.cgSessionEventTap`, placed at the head as a filter, on a dedicated run-loop
thread. Do not modify the shipping idle-first AX lane.

The first version is an ordering experiment, not a spelling feature:

- hard-code or pre-cache only `teh -> the`;
- support only an unmodified Space boundary, lowercase ASCII, Bear frontmost,
  collapsed-selection eligibility cached before the callback, and no marked
  text, repeat, or Secure Input;
- tag every synthetic event and pass tagged events through without tracking;
- use `CGEventTapPostEvent`, not `CGEvent.post`, for the backspaces and Unicode
  replacement;
- return the original physical Space after posting the replacement sequence;
- reset and fail open on focus change, modifiers, unsupported input, stale
  eligibility, `tapDisabledByTimeout`, or `tapDisabledByUserInput`;
- record callback duration and downstream event order outside the callback;
- retain the current bounded AX verification and overlay-adoption gate.

Only after the transport proves ordering should proposal computation be added.
The proposal engine must remain outside the callback and publish immutable
ready-or-not state. If a proposal is not ready when the boundary arrives, the
tap passes the boundary unchanged and the idle-first AX lane may handle it
later.

## Implementation status

The ordering-only candidate is implemented behind
`TYPOVER_EXPERIMENTAL_BEAR_TEXT_EXPANSION=1`; the shipping idle-first AX lane
is unchanged when that gate is absent.

- A main-actor monitor adapter owns a locked event-tap runtime on a dedicated
  user-interactive run-loop thread.
- The callback recognizes only unmodified, non-repeating lowercase US-layout
  letters and Space, and it performs no AX reads, spell checking, model work,
  disk access, waits, or synchronous logging.
- One fresh, verified AX snapshot authorizes at most one destructive
  transaction. The state machine disarms before emitting and can rearm only
  after bounded AX verification adopts the exact replacement.
- The callback creates the entire synthetic sequence before posting any event,
  posts three Backspace down/up pairs and Unicode `the` at the callback proxy,
  then returns the original physical Space.
- Synthetic events carry Typover's marker and never advance the physical word
  model. Unsupported input, mouse input, tap disablement, startup timeout,
  Secure Input, learned suppression, or a proposal mismatch invalidates the
  fast path.
- A write that cannot be matched and adopted opens the mutation circuit; it is
  never counted, learned, or annotated as a correction.

The deterministic gate passes 17 focused ordering/transition tests, 42
coordinator tests, a clean app build, and the full 326-test suite. Those results
prove the internal ordering model and failure policy, not Bear behavior. The
fresh-process physical matrix below remains the acceptance boundary.

## Qualification and stop condition

Before any generalization, run fresh-process ESP32 rows at 160, 100, 60, and
40 ms per key, then repeated 60/40 ms rows under controlled load. Evidence must
include the physical schedule, tap callback sequence, events posted at the
proxy, Bear's exact text, AX verification, overlay adoption, focus, Secure Input,
and tap-disable notifications.

The transport fails qualification if any credited run:

- deletes, duplicates, or reorders a later physical character;
- leaves a partial trigger or replacement;
- applies after focus, selection, composition, or eligibility becomes stale;
- silently loses the boundary;
- produces expected visible text without a verified reversible anchor; or
- disables the event tap without immediately failing open.

If any ordering corruption reproduces after the implementation itself is shown
to match the event-tap contract, stop tuning this family. Retain Bear's safe
post-pause AX behavior, keep immediate correction in Typover's owned editor,
and evaluate InputMethodKit as a separate opt-in product rather than claiming a
zero-compromise transparent Bear integration.

## Sources

Primary platform documentation:

- [Apple: global NSEvent monitors are asynchronous and observation-only](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents%28matching%3Ahandler%3A%29?language=objc)
- [Apple: active CGEvent tap callbacks may modify, replace, or delete events](https://developer.apple.com/documentation/coregraphics/cgeventtapcallback?language=objc)
- [Apple: tap-posted events enter before the callback's returned event](https://developer.apple.com/documentation/coregraphics/cgevent/tappostevent%28_%3A%29?language=objc)
- [Apple: CGEvent tap creation, placement, filters, and permission boundary](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate%28tap%3Aplace%3Aoptions%3Aeventsofinterest%3Acallback%3Auserinfo%3A%29?language=objc)
- [Apple: InputMethodKit input-controller model](https://developer.apple.com/documentation/inputmethodkit/imkinputcontroller?language=objc)
- [Apple: InputMethodKit replacement ranges and synonym example](https://developer.apple.com/documentation/inputmethodkit/imkinputcontroller/replacementrange%28%29?language=objc)

Open-source implementation evidence, inspected at Espanso commit
`375dc9caa1d02ef619a13c0022c46c28d1b99780`:

- [Espanso macOS detector uses an AppKit global monitor](https://github.com/espanso/espanso/blob/375dc9caa1d02ef619a13c0022c46c28d1b99780/espanso-detect/src/mac/native.mm#L60-L94)
- [Espanso macOS injector emits CGEvent Unicode and virtual-key events](https://github.com/espanso/espanso/blob/375dc9caa1d02ef619a13c0022c46c28d1b99780/espanso-inject/src/mac/native.mm#L26-L124)
- [Espanso trigger compensation emits one backspace per trigger character](https://github.com/espanso/espanso/blob/375dc9caa1d02ef619a13c0022c46c28d1b99780/espanso-engine/src/process/middleware/action.rs#L118-L131)
- [Espanso documents event, clipboard, threshold, and delay backends in code](https://github.com/espanso/espanso/blob/375dc9caa1d02ef619a13c0022c46c28d1b99780/espanso-config/src/config/mod.rs#L43-L109)
- [Espanso security policy describes its detector/injector architecture and bounded rolling buffer](https://github.com/espanso/espanso/security/policy)

Vendor implementation and limitation documentation:

- [TypeIt4Me: default clipboard expansion, alternative plain-text path, and restoration delay](https://ettoresoftware.store/mac-apps/typeit4me/help/typeit4me-settings/)
- [TypeIt4Me: Accessibility permission and clipboard replacement](https://ettoresoftware.store/mac-apps/typeit4me/help/installation/)
- [TypeIt4Me: Secure Input prevents abbreviation detection](https://ettoresoftware.store/mac-apps/typeit4me/help/where-does-typeit4me-type/)
- [TextExpander: clipboard plus synthetic paste behavior and compatibility limits](https://textexpander.com/learn/accounts/version/vm-compatibility)
- [TextExpander: expansion and clipboard-restoration timing](https://textexpander.com/learn/using/preferences/expansion-settings)
- [TextExpander: Secure Input prevents expansion](https://textexpander.com/learn/troubleshooting/mac/secure-input-on-macos-why-textexpander-stops-expanding-snippets)
- [Typinator: Accessibility and Input Monitoring troubleshooting](https://help.typinator.ergonis.com/hc/en-us/articles/22645458376092-Typinator-stopped-working)
