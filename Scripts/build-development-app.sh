#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
configuration="${TYPOVER_BUILD_CONFIGURATION:-debug}"
app_path="$repository_root/.build/Typover.app"

cd "$repository_root"
swift build --configuration "$configuration"
binary_directory="$(swift build --configuration "$configuration" --show-bin-path)"

signing_identity="${TYPOVER_SIGNING_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
  signing_identity="$({
    /usr/bin/security find-identity -v -p codesigning \
      | /usr/bin/awk '/Apple Development:/ { print $2; exit }'
  })"
fi
if [[ -z "$signing_identity" ]]; then
  echo "No Apple Development signing identity is available." >&2
  echo "Set TYPOVER_SIGNING_IDENTITY to a stable signing identity." >&2
  exit 1
fi

/bin/mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
/bin/cp "$repository_root/Support/Typover-Info.plist" \
  "$app_path/Contents/Info.plist"
/bin/cp "$binary_directory/Typover" "$app_path/Contents/MacOS/Typover"
/bin/cp "$repository_root/Sources/TypoverApp/Resources/TypoverAppIcon.icns" \
  "$app_path/Contents/Resources/TypoverAppIcon.icns"

for resource_bundle in "$binary_directory"/Typover_*.bundle; do
  if [[ -d "$resource_bundle" ]]; then
    bundle_name="$(basename "$resource_bundle")"
    /bin/rm -rf "$app_path/Contents/Resources/$bundle_name"
    /bin/cp -R "$resource_bundle" "$app_path/Contents/Resources/$bundle_name"
  fi
done

/usr/bin/codesign \
  --force \
  --options runtime \
  --timestamp=none \
  --sign "$signing_identity" \
  "$app_path"

echo "$app_path"
