# ADR-008: Use Accessibility coordinates for live Bear editing

- Status: Accepted
- Date: 2026-07-25

## Context

Bear 2.8 provides several official automation surfaces: `bearcli`, a local MCP
server built on the CLI, x-callback URLs, and Shortcuts actions. They are useful
for note-level creation, search, reading, appending, exact-string editing,
tagging, and navigation.

Typover's live interaction has narrower requirements. It must identify the word
the writer just completed, replace only that onscreen range, restore the active
caret, observe subsequent edits, and position a reversible annotation over the
same rendered characters.

The first Phase 2 fixture run attempted to reuse an offset returned by
`bearcli search-in`. Bear's focused `AXTextArea` exposed a different offset for
the same content. The guarded transaction rejected the range before writing.
This demonstrated that raw Markdown or CLI offsets cannot safely address Bear's
active rendered editor.

The installed Bear app also has no AppleScript scripting dictionary. Its
x-callback URL and Shortcuts actions do not expose selection ranges, layout
geometry, or editor notifications.

## Decision

Typover will use the focused Bear `AXTextArea` as the sole coordinate space for
live correction transactions, caret restoration, re-anchoring, and annotation
geometry.

The live path will:

- derive target ranges from bounded Accessibility text near the current caret;
- verify the expected original at that exact Accessibility range;
- write only `AXSelectedText`, never the complete `AXValue`;
- restore and verify the Accessibility selection;
- verify a bounded surrounding context before creating a correction record;
- retain only fingerprints of that context for later re-anchoring;
- restore through the same verified exact-range transaction only when one
  fingerprinted candidate remains.

Bear's official CLI may be used for disposable test-fixture setup, stable note
identity, content-free diagnostics, bulk maintenance, and later reconciliation
experiments. CLI, raw Markdown, x-callback URL, Shortcuts, and MCP offsets must
never be translated into a live Accessibility edit.

Typover will not require a Bear API token, Shortcuts workflow, MCP connection,
or AppleScript bridge for ordinary live correction.

## Consequences

### Benefits

- The correction, caret, and future squiggle share one coordinate system.
- Markdown source syntax and rendered presentation cannot silently shift an
  edit target.
- The live path remains local and does not require access to the whole Bear
  library.
- Unsupported Bear versions fail their capability checks before mutation.

### Costs and limits

- Typover requires macOS Accessibility permission.
- Bear must be running with its editor focused for a live correction.
- Accessibility behavior must be revalidated against supported Bear releases.
- Stable note identity is separate from the live range and may require an
  optional, carefully scoped reconciliation mechanism later.

## Primary references

- [Bear command-line interface](https://bear.app/faq/command-line-interface/)
- [Bear x-callback URL scheme](https://bear.app/faq/x-callback-url-scheme-documentation/)
- [Bear 2.8 CLI announcement](https://community.bear.app/t/bear-2-8-bearcli-claude-connector-and-mcp-server/19072)
- [Bear Shortcuts automation overview](https://blog.bear.app/2022/03/automate-your-notes-with-shortcuts-and-bear/)
