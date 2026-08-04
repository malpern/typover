# ADR-018: Keep Bear's fast lane experimental for the first beta

- Status: Accepted
- Date: 2026-08-03

## Context

The active event-tap candidate can place a verified correction before Bear
receives the physical Space. Repeated physical rows pass 5/5 at 100 and 160
milliseconds per key, including combined system load. At 60 milliseconds, the
coordinated idle fallback prevents text corruption but the result varies: the
latest release-regression row corrected 4/5 and safely left one `teh`.

The fast planner is intentionally narrower than Typover's correction engine.
It accepts lowercase ASCII words and Space only. A 100 millisecond punctuation
row safely left all five words unchanged because the surrounding transition no
longer matched the preauthorized fast transaction. These are safe misses, not
evidence of a general punctuation fast path.

## Decision

1. Typover's controlled editor has no artificial typing-rate policy. Local word
   corrections stay inside its owned AppKit edit transaction.
2. The first Bear beta keeps the serialized 220 millisecond idle-first
   Accessibility lane as its default production path.
3. The Bear active event-tap lane remains behind
   `TYPOVER_EXPERIMENTAL_BEAR_TEXT_EXPANSION=1`; it is not presented as a beta
   preference or public compatibility promise.
4. The qualified experimental envelope is lowercase ASCII word correction on
   Space at 100 milliseconds per key or slower. Faster bursts may use the
   coordinated fallback and may safely miss a word; they must never corrupt,
   merge, or replace unrelated text.
5. Punctuation, marked-text composition, Secure Input, selection changes,
   modifiers, unsupported layouts, and ambiguous focus remain refusal or
   fallback cases until separately qualified.

## Consequences

- The beta has one conservative Bear behavior rather than exposing a partially
  qualified speed control.
- Product claims can distinguish immediate Typover-editor correction from
  safe post-pause Bear correction.
- The fast lane remains testable without silently becoming a supported user
  setting.
- A later ADR may enable it after a larger rate, punctuation, layout, load,
  update, and cross-machine matrix proves a production envelope.

## Validation evidence

Fresh release-regression runs on 2026-08-03 produced:

- strict 100 ms Space row: 5/5, five pre-dispatch emissions, 33.9–40.9 ms
  verified application latency, no tap disablement or late fixture reports;
- mouse invalidation followed by a strict 100 ms row: 5/5, fresh authorization
  recovered, no focus or fixture failure;
- 60 ms handoff row: 4/5 with one exact safe miss and no unexpected text; and
- strict 100 ms punctuation row: 0/5, all five exact inputs preserved and no
  unexpected text.

Evidence is retained in the local content-free harness summaries named in
`docs/testing/bear-physical-hid-harness.md`.
