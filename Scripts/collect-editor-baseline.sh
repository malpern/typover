#!/bin/bash
# Collect local M0 evidence. Compatible with macOS's system Bash 3.2.
set -euo pipefail
umask 077

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"

if [[ "${1:-}" == "--help" ]]; then
  echo "Usage: $0 [new-output-directory]"
  echo "Runs local build, tests, release build, and synthetic spelling evaluation."
  echo "Does not run cloud evaluations or qualify manual/GUI gates."
  exit 0
fi
if [[ $# -gt 1 ]]; then
  echo "Expected at most one output directory." >&2
  exit 2
fi
if [[ "$(uname -s)" != Darwin ]]; then
  echo "BLOCKED: baseline requires the target Mac; this host is not macOS." >&2
  exit 2
fi
cd "$repository_root"
revision="$(git rev-parse --verify HEAD)"
dirty=false
if [[ -n "$(git status --porcelain)" ]]; then dirty=true; fi
output="${1:-$repository_root/.build/editor-first-baseline/$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$(dirname "$output")"
# Never overwrite a prior evidence run, even if its timestamp matches.
if ! mkdir "$output"; then
  echo "Refusing to overwrite baseline output: $output" >&2
  exit 2
fi
output="$(cd "$output" && pwd)"
printf 'step\tstatus\texit_code\tseconds\n' > "$output/results.tsv"
failed=0

run_step() {
  local name="$1"
  shift
  local started ended code status
  started="$(date +%s)"
  printf 'Running %s...\n' "$name"
  printf '%q ' "$@" > "$output/$name.command"
  printf '\n' >> "$output/$name.command"
  if "$@" > "$output/$name.log" 2>&1; then
    code=0
    status=PASS
  else
    code=$?
    status=FAIL
    failed=1
  fi
  ended="$(date +%s)"
  printf '%s\t%s\t%s\t%s\n' "$name" "$status" "$code" "$((ended-started))" >> "$output/results.tsv"
}

cat > "$output/README.md" <<EOF
# Typover editor baseline

- UTC start: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Revision: $revision
- Dirty before collection: $dirty
- Automated results: results.tsv (PASS means command exit 0 only)
- Command invocations: *.command; output: *.log

This run does not complete M0. Fill in manual-checks.md on the target Mac.
Inspect logs before sharing: command diagnostics can contain local file paths.
No raw personal writing, credentials, environment dump, or hardware serial
number is intentionally collected. Do not commit this directory wholesale.
EOF
cat > "$output/manual-checks.md" <<'EOF'
# Manual evidence still required

Status: NOT RUN. Replace each item with procedure, result, and limitations.

- Actual Mac model/chip/RAM: see hardware logs; confirm target machine.
- Display refresh rate, power mode, background load, and thermal conditions.
- Interactive GUI session and Apple Intelligence readiness/model availability.
- Baseline writing session and keyboard/VoiceOver/IME behavior.
- Release-build latency matrix and measurement method from validation protocol.
- Classify failed tests as new, reproduced pre-existing, or environment-blocked.

These checks are not implied by passing command-line tests. A missing model
must be recorded; do not substitute a cloud provider automatically.
EOF

run_step os sw_vers
run_step architecture uname -m
run_step hardware-model sysctl -n hw.model
run_step hardware-chip sysctl -n machdep.cpu.brand_string
run_step hardware-memory sysctl -n hw.memsize
run_step swift-version swift --version
run_step developer-directory xcode-select -p
run_step sdk xcrun --sdk macosx --show-sdk-version
run_step build swift build
run_step tests swift test
run_step release-build swift build -c release
# This is the checked-in synthetic LOCAL spelling corpus, not a remote model.
run_step spelling-evaluation swift run TypoverEval --json

printf '\nEvidence: %s\n' "$output"
cat "$output/results.tsv"
echo "Manual gates remain NOT RUN; see manual-checks.md."
exit "$failed"
