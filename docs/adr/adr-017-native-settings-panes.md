# ADR-017: Use native toolbar panes for Settings

## Status

Accepted — August 3, 2026

## Context

Typover's Settings window grew as the controlled editor, Bear integration,
local learning, remote models, and diagnostic tools were added. The resulting
single scrolling page exposed every control at once, repeated explanations,
and made ordinary correction choices compete with engineering diagnostics.

The redesign must preserve all existing behavior while feeling like a native
macOS 27 Settings window. It must also keep local and remote privacy boundaries
clear and retain stable accessibility identifiers for automation.

## Decision

Use SwiftUI's modern customizable-toolbar API to present one fixed,
noncustomizable pane control with four destinations:

- **General** contains correction scope, sentence rewrites, and model choice.
- **Bear** contains the automatic-correction switch, current status, and
  permission state. Compatibility probes, event observation, session metrics,
  and the squiggle preview are grouped under one disclosure control.
- **Learning** contains correction statistics, source detail, remembered
  choices, manual mapping creation, and removal controls.
- **Privacy** explains local and remote processing, manages the bounded Bear
  trace, and provides the full learning reset.

The selected pane and Bear's advanced disclosure state are stored in the app's
standard preferences. The Settings toolbar is always visible; its pane control
uses disabled customization behavior so destinations cannot be reordered or
removed. Each pane uses native `Form`, `Section`, `Toggle`, `Picker`,
`DisclosureGroup`, and destructive button styles rather than bespoke cards.

Explanatory text is used only where it changes a decision, explains a privacy
boundary, or describes the consequence of a destructive action. Existing
settings keys, actions, and accessibility identifiers remain intact.

Manual mappings use the same local learning store and correction pipeline as
learned choices. A mapping can supply a proposal even when Apple Spelling has
none, supports phrase replacements, and may apply to one spelling language or
all languages. It remains visible and removable with the other remembered
corrections.

## Consequences

- Common choices are visible without exposing diagnostic complexity.
- The window title and selected toolbar item identify the current pane, and the
  most recently used pane returns on the next launch.
- Native controls inherit current macOS appearance and accessibility behavior.
- Adding a new setting requires choosing an existing responsibility-based pane;
  a new pane should be rare.
- Snapshot coverage renders every pane, while installed-app QA verifies the
  real toolbar, persistence, scrolling, and accessibility tree.
