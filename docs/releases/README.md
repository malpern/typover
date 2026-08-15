# Typover release notes

Create one Markdown file for every distributed beta candidate. Use the
marketing version and build number in the filename, for example
`0.1-20260802010101.md`.

## Candidates

Newest first. The binary is not published for any of these.

- [`0.1.0 (20260815055632)`](0.1.0-20260815055632.md) — **current candidate.**
  Adds the VoiceOver safety pause and drops post-write re-anchoring. Notarized
  and stapled; the physical Bear rows and the quiet correction-review
  interaction pass still need re-running on this build.
- [`0.1.0 (20260808224257)`](0.1.0-20260808224257.md) — superseded. Presented
  Input Monitoring as included with Accessibility; passed the clean-machine
  permission journey and the artifact-to-claim audit.
- [`0.1.0 (20260806051920)`](0.1.0-20260806051920.md) — superseded. Carried the
  80/80 physical Bear matrix and the installed owned-editor review.
- [`0.1.0 (20260804072103)`](0.1.0-20260804072103.md) — superseded. First
  notarized clean-revision public-beta candidate.

## Template

```text
# Typover VERSION (BUILD)

- Source revision: 40-CHARACTER GIT SHA
- Source dirty: false
- Distribution: private beta
- Supported macOS: 27.0
- Supported Bear: 2.8.1, 2.9.1

## What changed

## Privacy or permission changes

## Persisted-data changes and rollback compatibility

## Known limitations

## Verification evidence

## Support channel
```

Do not call an artifact a release candidate when the revision is dirty, the
support channel or license is unresolved, or the clean-machine matrix is
incomplete.
