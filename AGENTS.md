# Typover agent guide

Typover is a native macOS experiment in automatic, visible, reversible
spell correction.

## Product invariants

- Apply only corrections that pass the current explicit eligibility policy.
- Replace the smallest safe text range; never rewrite an entire document.
- Preserve the original text for every automatic correction.
- Keep automatic corrections visibly distinguishable until the user resolves
  them.
- Make restoring the original or choosing another suggestion immediate.
- Treat typed text as private. Prefer on-device processing and document every
  boundary where text could leave the Mac.

## Development

```bash
swift build
swift test
swift run Typover
```

Keep experiments isolated behind protocols so spell engines, Accessibility
clients, and rendering approaches can be evaluated independently.
