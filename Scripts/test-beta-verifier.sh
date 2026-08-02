#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
app_path="${1:-$repository_root/.build/beta/Typover.app}"
archive_path="${2:-$repository_root/.build/beta/Typover-0.1.zip}"

if [[ ! -d "$app_path" || ! -f "$archive_path" ]]; then
  echo "Build a local beta artifact before running verifier rejection tests." >&2
  exit 2
fi

temporary_directory="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/typover-beta-negative.XXXXXX")"
trap '/bin/rm -rf "$temporary_directory"' EXIT HUP INT TERM

extra_archive="$temporary_directory/extra.zip"
/bin/cp "$archive_path" "$extra_archive"
/usr/bin/zip -q "$extra_archive" /etc/hosts
if "$script_directory/verify-beta-app.sh" \
  "$app_path" "$extra_archive" >"$temporary_directory/extra.out" 2>&1
then
  echo "Verifier incorrectly accepted content outside Typover.app." >&2
  exit 1
fi
/usr/bin/grep -Fq \
  "The beta archive contains content outside Typover.app." \
  "$temporary_directory/extra.out"

mismatch_directory="$temporary_directory/mismatch"
/usr/bin/ditto -x -k --noextattr "$archive_path" "$mismatch_directory"
/bin/cp /etc/hosts \
  "$mismatch_directory/Typover.app/Contents/Resources/TypoverAppIcon.icns"
mismatch_archive="$temporary_directory/mismatch.zip"
/usr/bin/ditto -c -k --keepParent --norsrc --noextattr \
  "$mismatch_directory/Typover.app" "$mismatch_archive"
if "$script_directory/verify-beta-app.sh" \
  "$app_path" "$mismatch_archive" >"$temporary_directory/mismatch.out" 2>&1
then
  echo "Verifier incorrectly accepted a mismatched Typover.app." >&2
  exit 1
fi
/usr/bin/grep -Fq \
  "The beta archive does not contain the verified Typover.app exactly." \
  "$temporary_directory/mismatch.out"

background_directory="$temporary_directory/background"
/bin/mkdir -p "$background_directory"
/bin/cp -R "$app_path" "$background_directory/Typover.app"
/bin/mkdir -p "$background_directory/Typover.app/Contents/XPCServices"
background_archive="$temporary_directory/background.zip"
/usr/bin/ditto -c -k --keepParent --norsrc --noextattr \
  "$background_directory/Typover.app" "$background_archive"
if "$script_directory/verify-beta-app.sh" \
  "$background_directory/Typover.app" "$background_archive" \
    >"$temporary_directory/background.out" 2>&1
then
  echo "Verifier incorrectly accepted a forbidden background component." >&2
  exit 1
fi
/usr/bin/grep -Fq \
  "The beta app contains a forbidden background component: Contents/XPCServices" \
  "$temporary_directory/background.out"

minimum_directory="$temporary_directory/minimum"
/bin/mkdir -p "$minimum_directory"
/bin/cp -R "$app_path" "$minimum_directory/Typover.app"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion 26.0" \
  "$minimum_directory/Typover.app/Contents/Info.plist"
minimum_archive="$temporary_directory/minimum.zip"
/usr/bin/ditto -c -k --keepParent --norsrc --noextattr \
  "$minimum_directory/Typover.app" "$minimum_archive"
if "$script_directory/verify-beta-app.sh" \
  "$minimum_directory/Typover.app" "$minimum_archive" \
    >"$temporary_directory/minimum.out" 2>&1
then
  echo "Verifier incorrectly accepted an unsupported minimum system version." >&2
  exit 1
fi
/usr/bin/grep -Fq \
  "The beta app must declare macOS 27.0 as its minimum system version." \
  "$temporary_directory/minimum.out"

for permission_key in \
  NSAccessibilityUsageDescription \
  NSInputMonitoringUsageDescription
do
  permission_directory="$temporary_directory/permission-$permission_key"
  /bin/mkdir -p "$permission_directory"
  /bin/cp -R "$app_path" "$permission_directory/Typover.app"
  /usr/libexec/PlistBuddy -c "Delete :$permission_key" \
    "$permission_directory/Typover.app/Contents/Info.plist"
  permission_archive="$permission_directory/Typover.zip"
  /usr/bin/ditto -c -k --keepParent --norsrc --noextattr \
    "$permission_directory/Typover.app" "$permission_archive"
  if "$script_directory/verify-beta-app.sh" \
    "$permission_directory/Typover.app" "$permission_archive" \
      >"$permission_directory/output" 2>&1
  then
    echo "Verifier incorrectly accepted a missing permission purpose: $permission_key" >&2
    exit 1
  fi
done
/usr/bin/grep -Fq \
  "The beta app is missing its Accessibility purpose description." \
  "$temporary_directory/permission-NSAccessibilityUsageDescription/output"
/usr/bin/grep -Fq \
  "The beta app is missing its Input Monitoring purpose description." \
  "$temporary_directory/permission-NSInputMonitoringUsageDescription/output"

blank_purpose_directory="$temporary_directory/blank-permission-purpose"
/bin/mkdir -p "$blank_purpose_directory"
/bin/cp -R "$app_path" "$blank_purpose_directory/Typover.app"
/usr/bin/plutil -replace NSInputMonitoringUsageDescription -string "   " \
  "$blank_purpose_directory/Typover.app/Contents/Info.plist"
blank_purpose_archive="$blank_purpose_directory/Typover.zip"
/usr/bin/ditto -c -k --keepParent --norsrc --noextattr \
  "$blank_purpose_directory/Typover.app" "$blank_purpose_archive"
if "$script_directory/verify-beta-app.sh" \
  "$blank_purpose_directory/Typover.app" "$blank_purpose_archive" \
    >"$blank_purpose_directory/output" 2>&1
then
  echo "Verifier incorrectly accepted a blank permission purpose." >&2
  exit 1
fi
/usr/bin/grep -Fq \
  "The beta app is missing its Input Monitoring purpose description." \
  "$blank_purpose_directory/output"

for invalid_version in ../outside 0 beta; do
  if "$script_directory/build-beta-app.sh" "$invalid_version" \
    >"$temporary_directory/version.out" 2>&1
  then
    echo "Build incorrectly accepted version: $invalid_version" >&2
    exit 1
  fi
  /usr/bin/grep -Fq \
    "Version must contain two or three dot-separated numeric components." \
    "$temporary_directory/version.out"
done

if TYPOVER_BUILD_NUMBER=not-numeric \
  "$script_directory/build-beta-app.sh" 0.1 \
    >"$temporary_directory/build-number.out" 2>&1
then
  echo "Build incorrectly accepted a nonnumeric build number." >&2
  exit 1
fi
/usr/bin/grep -Fq \
  "TYPOVER_BUILD_NUMBER must contain 1-18 digits." \
  "$temporary_directory/build-number.out"

echo "Beta verifier rejection tests passed."
