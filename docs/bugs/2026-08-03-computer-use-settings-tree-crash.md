# Computer Use Settings-tree crash

- Status: External automation transport failure; Typover native AX tree passes
- Observed: 2026-08-03
- Environment: macOS 27.0 (26A5388g), Sky Computer Use 26.727.1000550

## Symptom

Computer Use can inspect Typover's main editor window. After it sends
Command–Comma, Typover opens its SwiftUI Settings window, but the following
app-state request fails with `Sky Computer Use native pipe closed before
response`.

Typover remains alive and responsive. The corresponding diagnostic report is
for `SkyComputerUseService`, not Typover, and records `EXC_BREAKPOINT` /
`SIGTRAP`. The failure reproduced after a fresh Computer Use service launch.

## Independent native Accessibility result

A separate app-scoped `AXUIElement` walk found the **Typover Settings** window,
55 accessible descendants, and the expected stable identifiers for the visible
Bear, diagnostics, statistics, learning, and remembered-rule controls. The
native query completed normally before and after the Computer Use crash.

The same pass exposed decorative SF Symbols as extra image stops. Typover now
hides those status, statistic, empty-state, and direction icons from
Accessibility and combines each statistic card into one labeled value. The
rebuilt installed app reports zero standalone `AXImage` descendants in the
visible Settings tree while retaining every expected control identifier.
Computer Use still crashes with the same exception, ruling those image nodes
out as its cause.

## Boundary

Do not change Typover's native accessibility hierarchy merely to satisfy this
Computer Use build. Treat its Settings serialization as an external transport
bug until a later Computer Use version can read the same valid native AX tree.
Use the native AX audit for structural evidence and a separate unlocked-desktop
visual or VoiceOver pass for human-facing acceptance.

The local crash reports remain in `~/Library/Logs/DiagnosticReports/`; they are
not repository artifacts.
