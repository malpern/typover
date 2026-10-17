#!/bin/bash
# Test orchestration with fake macOS commands; this is not Mac qualification.
set -euo pipefail
script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/typover-baseline-test.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/repo/Scripts" "$fixture/bin"
cp "$script_directory/collect-editor-baseline.sh" "$fixture/repo/Scripts/"
git -C "$fixture/repo" init -q
git -C "$fixture/repo" add Scripts
git -C "$fixture/repo" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm fixture
cat > "$fixture/bin/uname" <<'EOF'
#!/bin/bash
if [[ "$1" == -s ]]; then echo "${TEST_OS:-Darwin}"; else echo arm64; fi
EOF
cat > "$fixture/bin/swift" <<'EOF'
#!/bin/bash
echo "fixture swift $*"
if [[ "$*" == test && "${FAIL_TESTS:-0}" == 1 ]]; then exit 17; fi
if [[ "$*" == 'run TypoverEval --json' ]]; then echo '{"fixture":true}'; fi
EOF
for command in sw_vers sysctl xcode-select xcrun; do
  printf '#!/bin/bash\necho fixture\n' > "$fixture/bin/$command"
done
chmod +x "$fixture/bin/"*
export PATH="$fixture/bin:$PATH"
collector="$fixture/repo/Scripts/collect-editor-baseline.sh"

expect_exit() {
  local expected="$1" actual
  shift
  if "$@" > "$fixture/last.log" 2>&1; then actual=0; else actual=$?; fi
  if [[ "$actual" != "$expected" ]]; then
    cat "$fixture/last.log"
    echo "Expected exit $expected, got $actual" >&2
    exit 1
  fi
}

expect_exit 0 bash "$collector" "$fixture/success with spaces"
grep -q $'tests\tPASS\t0\t' "$fixture/success with spaces/results.tsv"
grep -q 'NOT RUN' "$fixture/success with spaces/manual-checks.md"
grep -q 'Dirty before collection: false' "$fixture/success with spaces/README.md"
[[ "$(wc -l < "$fixture/success with spaces/results.tsv" | tr -d ' ')" == 13 ]]
cp "$fixture/success with spaces/results.tsv" "$fixture/original-results"
expect_exit 2 bash "$collector" "$fixture/success with spaces"
cmp "$fixture/original-results" "$fixture/success with spaces/results.tsv"

export FAIL_TESTS=1
expect_exit 1 bash "$collector" "$fixture/failure"
grep -q $'tests\tFAIL\t17\t' "$fixture/failure/results.tsv"
grep -q $'release-build\tPASS\t0\t' "$fixture/failure/results.tsv"
grep -q $'spelling-evaluation\tPASS\t0\t' "$fixture/failure/results.tsv"
unset FAIL_TESTS

touch "$fixture/repo/untracked"
expect_exit 0 bash "$collector" "$fixture/dirty"
grep -q 'Dirty before collection: true' "$fixture/dirty/README.md"
export TEST_OS=Linux
expect_exit 2 bash "$collector" "$fixture/not-mac"
[[ ! -e "$fixture/not-mac" ]]
expect_exit 0 bash "$collector" --help
echo "Baseline collector orchestration tests passed (fake macOS; no Swift compilation)."
