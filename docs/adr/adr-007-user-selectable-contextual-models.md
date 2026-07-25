# ADR-007: Allow explicit contextual-model selection with external secrets

- Status: Accepted
- Date: 2026-07-25

## Context

Typover's Apple Intelligence engine is private, local, and competitive with the
stronger cloud models in the initial rewrite benchmark. OpenAI GPT-5.6 Terra
and Anthropic Claude Sonnet 5 remain useful comparison models, and an explicit
product setting lets the interaction be evaluated without making a cloud
provider the default.

Cloud credentials must not be stored in `UserDefaults`, Typover's learning
file, the app bundle, source control, logs, or command-line arguments. This
development environment already uses Add Secret to write API keys into the
sops-and-age encrypted `~/dotfiles/secrets.env` store.

## Decision

Typover will expose three contextual-model choices:

- Apple Intelligence (On Device), selected by default;
- GPT-5.6 Terra (OpenAI);
- Claude Sonnet 5 (Anthropic).

The setting stores only the selected enum value in `UserDefaults`. Selecting a
cloud model is explicit and never acts as an automatic fallback from Apple.
Preferences states that the completed sentence will be sent to the selected
provider and that provider charges may apply.

For the current unsandboxed research build, Typover integrates with Add Secret
as follows:

- Add or Replace Key opens `/Applications/Add Secret.app` with only the
  approved environment-variable name as an argument;
- Add Secret continues to accept the value in its secure field and writes only
  encrypted secret material to its existing store;
- Typover first accepts an injected process-environment credential for tests
  and command-line development;
- otherwise Typover invokes `sops --decrypt --extract` for exactly the selected
  provider key, with the existing age-key file;
- the decrypted value is held only in memory for the request and is never
  persisted or logged by Typover;
- Preferences displays only available, missing, or checking status and never a
  credential fragment.

Only `OPENAI_API_KEY` and `ANTHROPIC_API_KEY` can be requested through this
adapter. Remote API errors are reduced to typed status information and do not
retain response bodies or submitted text in diagnostics.

Cloud output still passes through the same bounded sentence capture, stale-text
check, deterministic range resolver, rewrite-preservation rules, visible
annotation, Change Back, and Undo transaction as Apple's model.

## Consequences

### Benefits

- Apple remains the safe, zero-configuration product default.
- Model comparisons can happen in the real interaction rather than only in the
  evaluation executable.
- Existing Secrets app workflows remain the credential source of truth.
- Provider attribution is retained in correction statistics and menus.

### Costs and limits

- A selected cloud model sends one completed sentence outside the Mac.
- Cloud use adds latency, cost, network availability, and provider-policy
  dependencies.
- The direct sops integration assumes the current unsandboxed research build.
  A sandboxed distributed app will need a separately reviewed credential
  broker or Keychain design rather than broader file access.
- No automatic provider fallback is provided. A missing key or failed request
  becomes a safe miss.
