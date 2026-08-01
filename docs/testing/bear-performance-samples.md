# Bear performance samples

- Status: Active evidence log
- Updated: 2026-08-01
- Privacy: Content-free process and interaction measurements only

This log records reproducible installed-app measurements for the Bear beta
gate. It never includes note titles, words, replacements, surrounding text, or
document identifiers.

## Environment

- Hardware: Apple M5, 24 GiB memory, arm64
- macOS: 27.0 (26A5378n)
- Bear: 2.9.1 (14638)
- Typover: Apple Development-signed debug app in `/Applications/Typover.app`

## Idle waiting baseline — 2026-07-26

Typover was running with automatic Bear correction enabled in preferences while
the Mac was locked, so Bear was not the frontmost editable application. Five
one-second `top` samples reported:

- resident memory: 65 MB in every sample;
- CPU: 0.0% in every sample;
- process power score: 0.0 in every sample;
- threads: 3–4; and
- accumulated CPU time: 0.56 seconds after about one minute of process life.

The machine-wide load average was 47–49 during the sample because unrelated
Swift builds were active. This result is useful only as an idle sanity check:
Typover added no measurable CPU or power activity under that load. It is not a
valid active-typing, correction-latency, or steady-state energy baseline.

## Runtime-v2 locked idle sample — 2026-08-01

After the controlled CPU run was safely aborted on lock-screen focus loss, the
installed runtime-v2 process remained in its ordinary waiting state. Five
consecutive targeted samples reported:

- `ps` resident memory: 117,280 KiB in every sample;
- `ps` CPU: 0.0% in every sample;
- `top` process power score: 0.0 in every sample; and
- `top` CPU: 0.0% in every sample.

The corrected macOS 27 `top` contract used two samples with a one-second delay.
This establishes a second idle point after the beta shell, privacy store, and
runtime redesign. It does not explain the memory increase from the earlier
65 MB build and does not replace an unlocked active-typing or 24-overlay
sample. Those comparisons remain part of the installed load matrix.

## Remaining samples

Typover now records both timing paths in memory for the current session:
completion boundary to tracked annotation, and correction-menu choice to a
verified Change Back or alternative replacement. Settings reports the median
for each path; the diagnostics retain at most 200 samples and no writing.
Installed samples remain pending.

- correction boundary to visible squiggle while typing naturally in Bear;
- squiggle click to verified Change Back and alternative replacement;
- sustained typing with several recent annotations;
- rapid typing and safe-miss behavior;
- note switching, scrolling, and recovery after Bear or Typover relaunch;
- idle and active samples on a quiet machine; and
- memory after the 24-annotation session bound is reached.
