# Bear performance samples

- Status: Active evidence log
- Updated: 2026-08-03
- Privacy: Content-free process and interaction measurements only

This log records reproducible installed-app measurements for the Bear beta
gate. It never includes private note titles, writing, surrounding text, or
document identifiers. Synthetic fixture tokens may be named when needed to
describe a deterministic interaction.

## Environment

- Hardware: Apple M5, 24 GiB memory, arm64
- macOS: 27.0 (26A5378n)
- Bear: 2.9.1 (14638)
- Current Typover candidate: clean Apple Development-signed release-config app in
  `/Applications/Typover.app`, source revision `88f6555`

Earlier sections name debug or release configuration explicitly where it
differs from the current candidate.

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

## Installed controlled-load matrix — 2026-08-01

The ESP32 physical harness first admitted a quiet host, then kept each selected
load active through typing and post-burst convergence. Exact Bear text,
content-free Typover application logs, the complete fixture trace, and process
CPU/memory/power samples all agreed.

| Profile | Physical timing | Result | Minimum CPU idle | Peak Typover CPU | Peak Typover RSS |
| --- | --- | --- | ---: | ---: | ---: |
| CPU | 160 ms/key | 20/20 | 19.6% | 11.8% | 42,336 KiB |
| WindowServer | 160 ms/key | 20/20 | 65.4% | 15.6% | 42,496 KiB |
| Accessibility | 160 ms/key | 20/20 | 57.1% | 27.8% | 43,024 KiB |
| Combined | 160/100/60/40 ms/key | 80/80 | 9.6% | 130.3% | 152,208 KiB |

The combined rows converged within 1.59–3.79 seconds after the fixture reported
completion. Typover's peak process power score was 89.1, Bear's was 12.3, and
WindowServer's was 66.0. No case recorded a refusal, context loss, unexpected
text, or late HID report; maximum fixture lateness was 65 microseconds.

The combined peak resident memory is materially above the isolated rows and
the earlier idle samples. It was observed after many synthetic corrections and
overlays in a debug build, so it is a beta follow-up rather than proof of a
leak. Repeat the 24-annotation steady-state and post-retirement sample before
setting a memory budget.

The schema-4 artifact is the local run ending `01-49-31Z`. This is a measured
envelope on one Apple M5 system, not a compatibility or worst-case guarantee.

## Twenty-four-annotation memory and inactive energy — 2026-08-01

The installed app passed two additional 24/24 physical correction cycles at
160 milliseconds per key. Both retained exact Bear text, valid focus, complete
resource evidence, and zero late fixture reports. Their local artifacts end in
`02-29-46Z` and `02-33-59Z`.

Using `ps` consistently around the second cycle produced these resident-memory
points:

| Point | Typover RSS |
| --- | ---: |
| Fresh process, stable across five samples | 156,576–156,816 KiB |
| First retired 24-annotation cycle | 191,456 KiB |
| Second retired 24-annotation cycle | 193,680 KiB |

The second retired cycle added about 2.2 MiB rather than repeating the first
roughly 34 MiB warm-up increase. Two cycles do not prove the absence of every
leak, but they do not show linear per-session growth. For the current Apple
Development debug build, use **200 MiB RSS after two 24-annotation cycles** as
a provisional local budget. A release build and longer soak must set the
shipping budget.

App switching and editor-focus retirement were driven by physical ESP32
shortcuts because background UI automation does not prove frontmost ownership.
After a real Command-Tab from an 8-overlay session, all ten one-second samples
reported 0.0% Typover CPU and unchanged accumulated CPU time. After a real
Command-F retired a 24-overlay Bear session, the next ten samples also reported
0.0% CPU. This verifies the inactive-fallback energy fix; it does not claim
that hidden annotations release all allocator pages immediately.

## Clean release-config three-cycle soak — 2026-08-01

A clean release-config development bundle passed provenance verification before
installation: its recorded source revision and clean-worktree state matched the
checkout, and the packaged signed executable matched the installed executable.
The fresh process then passed three consecutive 24/24 physical cycles at 160
milliseconds per key. The local artifacts end in `03-18-05Z`, `03-20-08Z`, and
`03-23-33Z`. All 72 corrections retained exact Bear text and matching Typover
log evidence; all 582 HID reports arrived, none were late, and the largest
fixture deviation was 146 microseconds.

| Point | Typover RSS | Typover CPU |
| --- | ---: | ---: |
| Fresh release-config process, five samples | 157,376–157,552 KiB | 0.0% |
| First retired 24-annotation cycle, ten samples | 191,232–191,296 KiB | 0.0%, except one 1.4% sample |
| Second active cycle, five samples | 192,208 KiB | 0.0–0.2% |
| Second retired cycle, ten samples | 191,456 KiB | 0.0% |
| Third active cycle, five samples | 192,400–192,448 KiB | 0.0–5.6% |
| Third retired cycle, ten samples | 191,456–191,488 KiB, then stable at 191,456 KiB | 0.0% |

The initial release-process warm-up retained allocator pages, but cycles two
and three returned to the same 191,456 KiB plateau. This does not prove the
absence of every long-duration leak or replace a clean-machine beta soak. It
does provide a reproducible local release-config budget of **200 MiB RSS after
three retired 24-annotation cycles**, with no observed linear per-session
growth and no inactive CPU cost.

## Visible correction and menu interaction latency — 2026-08-03

Revision `88f6555` moved the correction-to-squiggle measurement boundary from
verified Bear text replacement to the overlay presenter's first visible frame.
The clean installed build then passed a focused five-word physical row at 160
milliseconds per key with 5/5 exact corrections and 5/5 retained overlays. The
completion-boundary-to-visible-squiggle samples were:

| Correction in post-burst application order | Visible latency |
| ---: | ---: |
| 1 | 474.904 ms |
| 2 | 1,154.540 ms |
| 3 | 1,824.610 ms |
| 4 | 2,522.821 ms |
| 5 | 3,206.381 ms |

The median was 1,824.610 milliseconds. This is not five samples of drawing
cost. Typover's 220-millisecond idle-first safety policy waits until continuous
input stops, then verifies and applies the bounded corrections from the end of
the burst toward its beginning. The most recent word therefore appeared in
under half a second, while earlier words accumulated the duration of the
uninterrupted burst. A separate one-word control measured 444.355 milliseconds
from its completion boundary to a visible squiggle.

The one-word control also supplied the interaction sample. An external native
Accessibility client opened the real nonactivating correction menu and invoked
**Revert to “teh”** while Bear remained frontmost. Bear verified the exact
restoration in **62.441 milliseconds**, retained editor focus, and ended with
the expected original word. An attempted app-scoped Computer Use inspection is
not credited: inspecting Typover's main application surface briefly activated
Typover and correctly retired the Bear overlays.

The credited local artifacts end in `20-58-17Z` for the five-word row and
`21-00-45Z` for the one-word interaction control. This is a focused acceptance
point, not a broad percentile distribution. It closes the instrumentation gap
and exposes a product tradeoff for beta review: Change Back is immediate, but
visible corrections intentionally wait for a typing pause.

## Remaining samples

Typover now records both timing paths in memory for the current session:
completion boundary to tracked annotation, and correction-menu choice to a
verified Change Back or alternative replacement. Settings reports the median
for each path; the diagnostics retain at most 200 samples and no writing.
The first installed visible-squiggle and Change Back timing points are now
recorded. Some broader samples remain pending.

- decide whether the measured post-pause visible-correction behavior is the
  intended beta experience or whether an earlier safe catch-up design is
  required;
- collect a verified alternative-replacement interaction sample if its path
  changes independently of Change Back;
- sustained typing with several recent annotations;
- repeated sustained typing and safe-miss behavior beyond the passing physical
  load matrix;
- note switching, scrolling, and recovery after Bear or Typover relaunch;
- idle and active samples on a quiet machine; and
- an extended second-machine beta soak beyond the passing three-cycle local
  release-config sample.
