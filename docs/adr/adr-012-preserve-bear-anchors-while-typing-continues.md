# ADR-012: Preserve Bear correction anchors while typing continues

- Status: Accepted
- Date: 2026-07-25

## Context

A correction anchor originally required both its leading and trailing context
fingerprints to remain unchanged. That is the strongest possible match, but it
expires as soon as a writer continues the sentence immediately beside the
corrected word. The squiggle can then disappear before the writer has a chance
to inspect it or choose Change Back.

Trusting only the saved offset would keep the mark visible but could target the
wrong occurrence after other edits. Searching for the corrected word alone is
also unsafe when the same word appears more than once.

## Decision

Resolve Bear corrections through a conservative three-step ladder:

1. Prefer one unique candidate whose leading and trailing fingerprints both
   match.
2. If none exists, accept one unique candidate only when its text exactly
   matches an expected correction value and either the leading or trailing
   fingerprint still matches.
3. Use a flexible-length, two-sided search only to recognize that the writer
   manually superseded the corrected word. That path never authorizes a write.

All searches remain inside the existing bounded neighborhoods around the
original and length-adjusted positions. Typover stores only fingerprints, not
surrounding Bear prose. A correction becomes invalid if both sides changed, no
candidate exists, or more than one candidate qualifies at the current step.

Alternative choices create a fresh two-sided anchor after their verified
write. A writer can therefore continue typing on either one side of the latest
correction while the squiggle, alternatives, and Change Back remain available.

Typover-initiated edits are also coordinated across the complete active overlay
collection. After Change Back or an alternative is verified:

1. the interacted correction handles its own result;
2. every nonoverlapping earlier correction keeps its range;
3. every nonoverlapping later correction shifts by the verified UTF-16 length
   delta;
4. only a correction intersecting the edited range is invalidated; and
5. every survivor verifies its exact current text and captures fresh bounded
   fingerprints before its overlay returns.

This coordination applies only to edits Typover has just verified. Arbitrary
user edits continue through the conservative resolver and never gain write
authority from range arithmetic alone.

## Consequences

- Typing immediately after a correction no longer makes the interaction vanish.
- Change Back and alternative choices still target only the corrected word;
  newly typed text remains untouched.
- Repeated expected words with only one matching context side fail closed
  instead of guessing.
- Editing both surrounding sides invalidates the correction until a new
  correction transaction creates a fresh anchor.
- Resolving one correction no longer expires unrelated later corrections just
  because their stored context included the edited word.
- The resolver performs more bounded reads than an exact two-sided match, but
  it never scans or rewrites the whole note.
