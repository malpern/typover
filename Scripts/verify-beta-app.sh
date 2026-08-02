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

temporary_directory="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/typover-beta-verify.XXXXXX")"
trap '/bin/rm -rf "$temporary_directory"' EXIT HUP INT TERM

info_plist="$app_path/Contents/Info.plist"
executable="$app_path/Contents/MacOS/Typover"
bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")"
short_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"
source_revision="$(/usr/libexec/PlistBuddy -c 'Print :TypoverSourceRevision' "$info_plist")"
source_dirty="$(/usr/libexec/PlistBuddy -c 'Print :TypoverSourceDirty' "$info_plist")"
minimum_system_version="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info_plist")"
accessibility_purpose="$({
  /usr/libexec/PlistBuddy -c 'Print :NSAccessibilityUsageDescription' \
    "$info_plist" 2>/dev/null || true
})"
input_monitoring_purpose="$({
  /usr/libexec/PlistBuddy -c 'Print :NSInputMonitoringUsageDescription' \
    "$info_plist" 2>/dev/null || true
})"

if [[ "$bundle_identifier" != "com.malpern.typover" ]]; then
  echo "Unexpected bundle identifier: $bundle_identifier" >&2
  exit 1
fi
if [[ -z "$short_version" || -z "$build_number" ]]; then
  echo "The beta app is missing its version or build number." >&2
  exit 1
fi
if [[ ! "$source_revision" =~ ^[0-9a-f]{40}$ ]]; then
  echo "The beta app is missing a valid source revision." >&2
  exit 1
fi
if [[ "$source_dirty" != "true" && "$source_dirty" != "false" ]]; then
  echo "The beta app is missing its source cleanliness marker." >&2
  exit 1
fi
if [[ "$minimum_system_version" != "27.0" ]]; then
  echo "The beta app must declare macOS 27.0 as its minimum system version." >&2
  exit 1
fi
if [[ ! "$accessibility_purpose" =~ [^[:space:]] ]]; then
  echo "The beta app is missing its Accessibility purpose description." >&2
  exit 1
fi
if [[ ! "$input_monitoring_purpose" =~ [^[:space:]] ]]; then
  echo "The beta app is missing its Input Monitoring purpose description." >&2
  exit 1
fi
if [[ ! -x "$executable" ]]; then
  echo "The Typover executable is missing or not executable." >&2
  exit 1
fi

for forbidden_component in \
  "$app_path/Contents/Library/LaunchAgents" \
  "$app_path/Contents/Library/LaunchDaemons" \
  "$app_path/Contents/Library/LaunchServices" \
  "$app_path/Contents/Library/LoginItems" \
  "$app_path/Contents/Library/PrivilegedHelperTools" \
  "$app_path/Contents/XPCServices"
do
  if [[ -e "$forbidden_component" ]]; then
    echo "The beta app contains a forbidden background component: ${forbidden_component#"$app_path/"}" >&2
    exit 1
  fi
done
for forbidden_key in LSBackgroundOnly LSUIElement SMPrivilegedExecutables; do
  if /usr/libexec/PlistBuddy -c "Print :$forbidden_key" "$info_plist" \
    >/dev/null 2>&1
  then
    echo "The beta app declares forbidden background behavior: $forbidden_key" >&2
    exit 1
  fi
done

/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"

binary_minimum_system_version="$(
  /usr/bin/otool -l "$executable" \
    | /usr/bin/awk '
        $1 == "cmd" && $2 == "LC_BUILD_VERSION" { build_version = 1; next }
        build_version && $1 == "minos" { print $2; exit }
      '
)"
if [[ "$binary_minimum_system_version" != "$minimum_system_version" ]]; then
  echo "The beta bundle and executable minimum system versions do not match." >&2
  exit 1
fi

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

archive_listing="$(/usr/bin/unzip -Z1 "$archive_path")"
if [[ -z "$archive_listing" ]] || \
  printf '%s\n' "$archive_listing" \
    | /usr/bin/grep -Ev '^Typover\.app(/|$)' \
    | /usr/bin/grep -q .
then
  echo "The beta archive contains content outside Typover.app." >&2
  exit 1
fi
if printf '%s\n' "$archive_listing" \
  | /usr/bin/grep -Eq '(^/|(^|/)\.\.(/|$))'
then
  echo "The beta archive contains an unsafe path." >&2
  exit 1
fi

/usr/bin/ditto -x -k --noextattr "$archive_path" "$temporary_directory"
archived_app="$temporary_directory/Typover.app"
if [[ ! -d "$archived_app" ]]; then
  echo "The beta archive does not expand to Typover.app." >&2
  exit 1
fi
if ! /usr/bin/diff -qr "$app_path" "$archived_app" >/dev/null; then
  echo "The beta archive does not contain the verified Typover.app exactly." >&2
  exit 1
fi

archived_info_plist="$archived_app/Contents/Info.plist"
archived_bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$archived_info_plist")"
archived_short_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$archived_info_plist")"
archived_build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$archived_info_plist")"
archived_source_revision="$(/usr/libexec/PlistBuddy -c 'Print :TypoverSourceRevision' "$archived_info_plist")"
archived_source_dirty="$(/usr/libexec/PlistBuddy -c 'Print :TypoverSourceDirty' "$archived_info_plist")"
if [[ "$archived_bundle_identifier" != "$bundle_identifier" || \
      "$archived_short_version" != "$short_version" || \
      "$archived_build_number" != "$build_number" || \
      "$archived_source_revision" != "$source_revision" || \
      "$archived_source_dirty" != "$source_dirty" ]]; then
  echo "The expanded beta metadata does not match the verified app." >&2
  exit 1
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$archived_app"

if [[ "$gatekeeper" == "--gatekeeper" ]]; then
  /usr/sbin/spctl --assess --type execute --verbose=2 "$archived_app"
  /usr/bin/xcrun stapler validate "$archived_app"
fi

echo "Verified Typover $short_version ($build_number)"
echo "Source $source_revision dirty=$source_dirty"
echo "$archive_path"
