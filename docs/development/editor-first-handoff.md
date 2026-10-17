# Editor-first development handoff

- Updated: 2026-10-17
- Branch: `editor-first/m0-baseline`
- Base revision: `246648a0531a753d7e1ab0c6ac5e51e572c9eaf5`
- State: M0 tooling implemented; target-Mac baseline still blocked

## Work completed

Added `Scripts/collect-editor-baseline.sh` to capture source revision, dirty
state, selected non-secret hardware/OS/SDK information, build, full tests,
release build, and the local synthetic spelling evaluation. Each command has
a separate log, exact invocation, exit status, and elapsed time. A failed step
does not suppress later evidence; any failure gives a nonzero final exit.

The collector refuses non-macOS hosts and existing output directories, uses
private output permissions, and leaves manual qualification explicitly NOT RUN.
It does not run cloud evaluations or request Accessibility permissions.

Added `Scripts/test-editor-baseline.sh` to exercise orchestration with fake
macOS commands. Covered success, failure exit propagation, continuing after a
test failure, output paths containing spaces, preserving prior evidence,
dirty-worktree identification, and refusing non-macOS execution.

## Evidence from this session

Host: Linux x86_64; no Swift executable available. No configured VPN, TCP
destination, credentials, or remote-Mac connection. GitHub connector access
works; shell clone fails because the configured HTTP proxy is unreachable.
Source was inspected through GitHub; this is not a full local app checkout.

Passed on Linux:

```bash
bash -n Scripts/collect-editor-baseline.sh
bash -n Scripts/test-editor-baseline.sh
bash Scripts/test-editor-baseline.sh
```

The fixture tests validate the collector only. No Swift compilation, AppKit
runtime test, physical-input measurement, or live model evaluation ran. M0 is
not complete, and no editor behavior changed. M1–M5 remain pending.

## Resume on the Mac mini

Preserve unrelated local changes, fetch the development branch, and use an
isolated worktree if needed. Confirm the branch includes the baseline tooling.
From that checkout:

```bash
bash Scripts/test-editor-baseline.sh
bash Scripts/collect-editor-baseline.sh
```

The collector prints its output directory under `.build/editor-first-baseline`.
Read `results.tsv`, inspect any failed step's log, and complete
`manual-checks.md` using the validation protocol. A passing shell test does not
establish Swift 6.4/macOS 27 availability or Apple Intelligence readiness.
Review logs before sharing; do not commit raw local evidence automatically.

Then use [the development prompt](mac-development-prompt.md). Its first work is
to finish M0, record the document-storage/startup ADR, and implement M1 as a
tested vertical slice. Keep text and correction metadata in one atomic revision,
preserve original text and Change Back, and isolate ordinary editor startup from
Bear permission machinery. Do not treat these storage decisions as implemented.

Update this handoff and the milestone ledger after each coherent commit. Record
the exact implementation commit in the next evidence report; this file does not
attempt to embed the hash of its own commit.
