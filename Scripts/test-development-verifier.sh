#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
app_path="${1:-$repository_root/.build/Typover.app}"
expected_revision="${2:-$(git -C "$repository_root" rev-parse --verify HEAD)}"
expected_dirty="${3:-false}"

temporary_directory="$(
  /usr/bin/mktemp -d "${TMPDIR:-/tmp}/typover-development-negative.XXXXXX"
)"
trap '/bin/rm -rf "$temporary_directory"' EXIT HUP INT TERM

"$script_directory/verify-development-app.sh" \
  "$app_path" "$expected_revision" "$expected_dirty" >/dev/null

revision_app="$temporary_directory/revision/Typover.app"
/bin/mkdir -p "$(dirname "$revision_app")"
/bin/cp -R "$app_path" "$revision_app"
/usr/libexec/PlistBuddy \
  -c 'Set :TypoverSourceRevision 0000000000000000000000000000000000000000' \
  "$revision_app/Contents/Info.plist"
if "$script_directory/verify-development-app.sh" \
  "$revision_app" "$expected_revision" "$expected_dirty" \
    >"$temporary_directory/revision.out" 2>&1
then
  echo "Verifier incorrectly accepted a mismatched source revision." >&2
  exit 1
fi
/usr/bin/grep -Fq \
  "The development app source revision does not match the build input." \
  "$temporary_directory/revision.out"

dirty_app="$temporary_directory/dirty/Typover.app"
/bin/mkdir -p "$(dirname "$dirty_app")"
/bin/cp -R "$app_path" "$dirty_app"
opposite_dirty=true
if [[ "$expected_dirty" == "true" ]]; then
  opposite_dirty=false
fi
/usr/libexec/PlistBuddy \
  -c "Set :TypoverSourceDirty $opposite_dirty" \
  "$dirty_app/Contents/Info.plist"
if "$script_directory/verify-development-app.sh" \
  "$dirty_app" "$expected_revision" "$expected_dirty" \
    >"$temporary_directory/dirty.out" 2>&1
then
  echo "Verifier incorrectly accepted a mismatched source dirty state." >&2
  exit 1
fi
/usr/bin/grep -Fq \
  "The development app source dirty state does not match the build input." \
  "$temporary_directory/dirty.out"

echo "Development app provenance rejection tests passed."
