#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
version="${1:-0.1}"
notarize="${2:-}"
configuration="release"
output_directory="$repository_root/.build/beta"
app_path="$output_directory/Typover.app"
archive_path="$output_directory/Typover-$version.zip"
build_number="${TYPOVER_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"

if [[ "$notarize" != "" && "$notarize" != "--notarize" ]]; then
  echo "Usage: Scripts/build-beta-app.sh [version] [--notarize]" >&2
  exit 2
fi

cd "$repository_root"
swift build --configuration "$configuration" --product Typover
binary_directory="$(swift build --configuration "$configuration" --show-bin-path)"

signing_identity="${TYPOVER_DISTRIBUTION_SIGNING_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
  signing_identity="$({
    /usr/bin/security find-identity -v -p codesigning \
      | /usr/bin/awk '/Developer ID Application:/ { print $2; exit }'
  })"
fi
if [[ -z "$signing_identity" ]]; then
  echo "No Developer ID Application signing identity is available." >&2
  exit 1
fi

/bin/rm -rf "$output_directory"
/bin/mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
/bin/cp "$repository_root/Support/Typover-Info.plist" \
  "$app_path/Contents/Info.plist"
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleShortVersionString $version" \
  "$app_path/Contents/Info.plist"
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleVersion $build_number" \
  "$app_path/Contents/Info.plist"
/bin/cp "$binary_directory/Typover" "$app_path/Contents/MacOS/Typover"
/bin/cp "$repository_root/Sources/TypoverApp/Resources/TypoverAppIcon.icns" \
  "$app_path/Contents/Resources/TypoverAppIcon.icns"

for resource_bundle in "$binary_directory"/Typover_*.bundle; do
  if [[ -d "$resource_bundle" ]]; then
    /bin/cp -R "$resource_bundle" "$app_path/Contents/Resources/"
  fi
done

# Do not carry local build provenance, quarantine, or Finder metadata into the
# public code signature or zip. `ditto` otherwise serializes those attributes
# as AppleDouble `._*` files, which are unnecessary distribution noise.
/usr/bin/xattr -cr "$app_path"

/usr/bin/codesign \
  --force \
  --options runtime \
  --timestamp \
  --sign "$signing_identity" \
  "$app_path"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"

/usr/bin/ditto -c -k --keepParent --norsrc --noextattr \
  "$app_path" "$archive_path"

if [[ "$notarize" == "--notarize" ]]; then
  key_path="${TYPOVER_NOTARY_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_XQ4565NYZ7.p8}"
  key_id="${TYPOVER_NOTARY_KEY_ID:-XQ4565NYZ7}"
  issuer_id="${TYPOVER_NOTARY_ISSUER_ID:-60b8eb46-ca64-4580-a43b-850d92fcc7ab}"
  if [[ ! -f "$key_path" ]]; then
    echo "App Store Connect API key is missing: $key_path" >&2
    exit 1
  fi
  /usr/bin/xcrun notarytool submit "$archive_path" \
    --key "$key_path" \
    --key-id "$key_id" \
    --issuer "$issuer_id" \
    --wait
  /usr/bin/xcrun stapler staple "$app_path"
  /bin/rm -f "$archive_path"
  /usr/bin/ditto -c -k --keepParent --norsrc --noextattr \
    "$app_path" "$archive_path"
  /usr/sbin/spctl --assess --type execute --verbose=2 "$app_path"
fi

if /usr/bin/unzip -Z1 "$archive_path" \
  | /usr/bin/grep -Eq '(^__MACOSX/|/\._)'
then
  echo "Beta archive contains unexpected AppleDouble metadata." >&2
  exit 1
fi

echo "$archive_path"
