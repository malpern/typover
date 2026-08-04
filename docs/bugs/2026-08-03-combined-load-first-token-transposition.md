# Combined-load first token transposition

## Summary

A schema-5 physical Bear run under the controlled combined load produced
`eth` for the first fixture token even though the ESP32 trace scheduled the
expected `t`, `e`, `h`, Space sequence. The remaining 19 tokens corrected to
`the`. Focus, fixture delivery, load sampling, and Typover telemetry were all
complete, so the artifact is retained as invalid evidence rather than discarded
or counted as a Typover pass.

## Evidence

The diagnostic artifact is local at
`~/.local/state/typover/bear-hid/typover-hid-2026-08-03T18-58-31Z/summary.json`.
It records:

- valid Bear focus throughout the run;
- all 162 fixture reports submitted, zero late reports, and 47 microseconds
  maximum lateness;
- a fixture trace beginning with HID usages 23, 8, 11, and 44 (`t`, `e`, `h`,
  Space) in the expected order;
- 20 Typover application events and 20 visible correction windows; and
- final inserted text beginning with `eth`, followed by 19 exact `the` words.

The bounded-writing trace was still redacted for that run, so it cannot prove
which exact first range Typover believed it replaced. The discrepancy could be
a transient host/Bear input-order event, an extraction race, or a Typover
reconciliation defect. The artifact does not distinguish those causes.

## Reproduction work

Bounded-writing diagnostics were enabled locally for the follow-up and remain
capped by the existing 24-hour/1 MB retention policy. Four consecutive runs
with a fresh Typover process and the same 160 millisecond combined-load profile
then passed 80/80 exact text corrections. Their local artifacts end in
`19-01-02Z`, `19-04-26Z`, `19-05-19Z`, and `19-06-11Z`. The trace for the first
pass records 20 distinct `teh` to `the` deferred applications.

A fourth run against a newly created disposable Bear note also passed 20/20,
retained 20/20 visible correction windows, received all 162 fixture reports
with zero late reports, and reached 21.4% minimum host CPU idle. Its artifact
ends in `19-08-14Z`.

The fourth accumulated-note run sampled only 4 visible overlay windows after
Bear scrolled the appended line. It is not used as exact overlay-retention
evidence; the fresh-note control establishes the canonical overlay row.

## Status

The transposition has not reproduced in 100 subsequent physical tokens under
the same controlled load. This lowers its observed recurrence but does not
identify a root cause. Keep the artifact and bounded trace path available for a
future reproduction. A second occurrence with ordered fixture input should
stop release qualification until its Bear value-event and Typover write ranges
are classified.
