#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
app_path="${1:-$repository_root/.build/Typover.app}"
expected_revision="${2:-$(git -C "$repository_root" rev-parse --verify HEAD)}"
expected_dirty="${3:-false}"
info_plist="$app_path/Contents/Info.plist"

if [[ ! -d "$app_path" || ! -f "$info_plist" ]]; then
  echo "Development app is missing: $app_path" >&2
  exit 2
fi
if [[ ! "$expected_revision" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Expected source revision must contain 40 lowercase hexadecimal characters." >&2
  exit 2
fi
if [[ "$expected_dirty" != "true" && "$expected_dirty" != "false" ]]; then
  echo "Expected source dirty state must be true or false." >&2
  exit 2
fi

bundle_identifier="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist"
)"
source_revision="$(
  /usr/libexec/PlistBuddy -c 'Print :TypoverSourceRevision' "$info_plist"
)"
source_dirty="$(
  /usr/libexec/PlistBuddy -c 'Print :TypoverSourceDirty' "$info_plist" \
    | /usr/bin/tr '[:upper:]' '[:lower:]'
)"

if [[ "$bundle_identifier" != "com.malpern.typover" ]]; then
  echo "The development app has an unexpected bundle identifier." >&2
  exit 1
fi
if [[ "$source_revision" != "$expected_revision" ]]; then
  echo "The development app source revision does not match the build input." >&2
  exit 1
fi
if [[ "$source_dirty" != "$expected_dirty" ]]; then
  echo "The development app source dirty state does not match the build input." >&2
  exit 1
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"

echo "Development app provenance verified."
