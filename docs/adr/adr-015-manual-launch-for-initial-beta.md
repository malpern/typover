# ADR-015: Keep launch at login out of the initial beta

- Status: Accepted
- Date: 2026-08-01

## Context

Typover must be running to observe completed-word input and maintain reversible
Bear annotations. A login item could make that feel automatic, but it also
creates a persistent background process before the permission, privacy,
recovery, and energy behavior has completed installed and clean-machine
validation.

## Decision

The initial beta uses explicit manual launch:

- first run and Settings state that Typover must remain open while writing;
- Typover does not register itself as a login item;
- closing Typover ends observation and removes its session-only annotations;
- no helper, daemon, or hidden relaunch mechanism is added for this milestone.

Launch at login can be reconsidered only after active and idle energy samples,
revoked-permission recovery, update/uninstall behavior, and clean-machine beta
installation pass.

## Consequences

- testers always know when Typover is running;
- uninstall and permission recovery stay simple during the beta;
- a tester must launch Typover after logging in or restarting the Mac;
- the onboarding and Settings copy must make this requirement explicit.
