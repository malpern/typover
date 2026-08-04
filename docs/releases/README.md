# Typover release notes

Create one Markdown file for every distributed beta candidate. Use the
marketing version and build number in the filename, for example
`0.1-20260802010101.md`.

## Candidates

- [`0.1.0 (20260804072103)`](0.1.0-20260804072103.md) — notarized
  clean-revision public-beta candidate; permissioned Bear acceptance remains
  open and the binary is not published.

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
