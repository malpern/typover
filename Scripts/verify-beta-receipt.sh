#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
app_path="${1:-$repository_root/.build/beta/Typover.app}"
archive_path="${2:-$repository_root/.build/beta/Typover-0.1.zip}"
receipt_path="${3:-$repository_root/.build/beta/Typover-0.1.json}"

if [[ ! -d "$app_path" ]]; then
  echo "Beta app is missing: $app_path" >&2
  exit 1
fi
if [[ ! -f "$archive_path" ]]; then
  echo "Beta archive is missing: $archive_path" >&2
  exit 1
fi
if [[ ! -f "$receipt_path" ]]; then
  echo "Beta receipt is missing: $receipt_path" >&2
  exit 1
fi

receipt_value() {
  local key="$1"
  local type="$2"
  local value
  if ! value="$(
    /usr/bin/plutil -extract "$key" raw -expect "$type" \
      "$receipt_path" 2>/dev/null
  )"; then
    echo "The beta receipt is missing a valid $key value." >&2
    return 1
  fi
  printf '%s' "$value"
}

schema_version="$(receipt_value schemaVersion integer)"
bundle_identifier="$(receipt_value bundleIdentifier string)"
short_version="$(receipt_value version string)"
build_number="$(receipt_value build string)"
source_revision="$(receipt_value sourceRevision string)"
source_dirty="$(receipt_value sourceDirty bool)"
minimum_system_version="$(receipt_value minimumSystemVersion string)"
team_identifier="$(receipt_value teamIdentifier string)"
archive_name="$(receipt_value archive string)"
archive_sha256="$(receipt_value archiveSHA256 string)"
notarized="$(receipt_value notarized bool)"

if [[ "$schema_version" != "1" ]]; then
  echo "Unsupported beta receipt schema: $schema_version" >&2
  exit 1
fi

verify_arguments=("$app_path" "$archive_path")
if [[ "$notarized" == "true" ]]; then
  verify_arguments+=("--gatekeeper")
fi
"$script_directory/verify-beta-app.sh" "${verify_arguments[@]}" >/dev/null

info_plist="$app_path/Contents/Info.plist"
app_bundle_identifier="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist"
)"
app_short_version="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist"
)"
app_build_number="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist"
)"
app_source_revision="$(
  /usr/libexec/PlistBuddy -c 'Print :TypoverSourceRevision' "$info_plist"
)"
app_source_dirty="$(
  /usr/libexec/PlistBuddy -c 'Print :TypoverSourceDirty' "$info_plist"
)"
app_minimum_system_version="$(
  /usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info_plist"
)"
signature_details="$(/usr/bin/codesign -dvvv "$app_path" 2>&1)"
app_team_identifier="$(
  printf '%s\n' "$signature_details" \
    | /usr/bin/awk -F= '$1 == "TeamIdentifier" { print $2; exit }'
)"

if [[ "$bundle_identifier" != "$app_bundle_identifier" || \
      "$short_version" != "$app_short_version" || \
      "$build_number" != "$app_build_number" || \
      "$source_revision" != "$app_source_revision" || \
      "$source_dirty" != "$app_source_dirty" || \
      "$minimum_system_version" != "$app_minimum_system_version" || \
      "$team_identifier" != "$app_team_identifier" ]]; then
  echo "The beta receipt does not match the verified app metadata." >&2
  exit 1
fi
if [[ "$archive_name" != "$(basename "$archive_path")" ]]; then
  echo "The beta receipt names a different archive." >&2
  exit 1
fi
if [[ ! "$archive_sha256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "The beta receipt contains an invalid archive checksum." >&2
  exit 1
fi
actual_archive_sha256="$(
  /usr/bin/shasum -a 256 "$archive_path" | /usr/bin/awk '{ print $1 }'
)"
if [[ "$archive_sha256" != "$actual_archive_sha256" ]]; then
  echo "The beta receipt archive checksum does not match." >&2
  exit 1
fi

echo "Verified receipt for Typover $short_version ($build_number)"
echo "SHA-256 $archive_sha256"
echo "Source $source_revision dirty=$source_dirty notarized=$notarized"
