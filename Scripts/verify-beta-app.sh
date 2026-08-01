#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
app_path="${1:-$repository_root/.build/beta/Typover.app}"
archive_path="${2:-$repository_root/.build/beta/Typover-0.1.zip}"
gatekeeper="${3:-}"

if [[ "$gatekeeper" != "" && "$gatekeeper" != "--gatekeeper" ]]; then
  echo "Usage: Scripts/verify-beta-app.sh [app] [archive] [--gatekeeper]" >&2
  exit 2
fi
if [[ ! -d "$app_path" ]]; then
  echo "Beta app is missing: $app_path" >&2
  exit 1
fi
if [[ ! -f "$archive_path" ]]; then
  echo "Beta archive is missing: $archive_path" >&2
  exit 1
fi

info_plist="$app_path/Contents/Info.plist"
executable="$app_path/Contents/MacOS/Typover"
bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")"
short_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"

if [[ "$bundle_identifier" != "com.malpern.typover" ]]; then
  echo "Unexpected bundle identifier: $bundle_identifier" >&2
  exit 1
fi
if [[ -z "$short_version" || -z "$build_number" ]]; then
  echo "The beta app is missing its version or build number." >&2
  exit 1
fi
if [[ ! -x "$executable" ]]; then
  echo "The Typover executable is missing or not executable." >&2
  exit 1
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"

if /usr/bin/otool -L "$executable" \
  | /usr/bin/tail -n +2 \
  | /usr/bin/awk '{ print $1 }' \
  | /usr/bin/grep -Ev '^(/System/Library/|/usr/lib/)'
then
  echo "The beta executable contains a non-system dynamic dependency." >&2
  exit 1
fi

if /usr/bin/unzip -Z1 "$archive_path" \
  | /usr/bin/grep -Eq '(^__MACOSX/|/\._)'
then
  echo "The beta archive contains AppleDouble metadata." >&2
  exit 1
fi

if [[ "$gatekeeper" == "--gatekeeper" ]]; then
  /usr/sbin/spctl --assess --type execute --verbose=2 "$app_path"
  /usr/bin/xcrun stapler validate "$app_path"
fi

echo "Verified Typover $short_version ($build_number)"
echo "$archive_path"
