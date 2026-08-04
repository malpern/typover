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
receipt_path="$output_directory/Typover-$version.json"
build_number="${TYPOVER_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M%S)}"

if [[ "$notarize" != "" && "$notarize" != "--notarize" ]]; then
  echo "Usage: Scripts/build-beta-app.sh [version] [--notarize]" >&2
  exit 2
fi
if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
  echo "Version must contain two or three dot-separated numeric components." >&2
  exit 2
fi
if [[ ! "$build_number" =~ ^[0-9]{1,18}$ ]]; then
  echo "TYPOVER_BUILD_NUMBER must contain 1-18 digits." >&2
  exit 2
fi

source_revision="$(git -C "$repository_root" rev-parse --verify HEAD)"
source_dirty=false
if [[ -n "$(git -C "$repository_root" status --porcelain --untracked-files=normal)" ]]; then
  source_dirty=true
fi
if [[ "$notarize" == "--notarize" && "$source_dirty" == "true" ]]; then
  echo "Notarized candidates require a clean Git worktree." >&2
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
/usr/libexec/PlistBuddy \
  -c "Add :TypoverSourceRevision string $source_revision" \
  "$app_path/Contents/Info.plist"
/usr/libexec/PlistBuddy \
  -c "Add :TypoverSourceDirty bool $source_dirty" \
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

verify_arguments=("$app_path" "$archive_path")
is_notarized=false
if [[ "$notarize" == "--notarize" ]]; then
  verify_arguments+=("--gatekeeper")
  is_notarized=true
fi
"$script_directory/verify-beta-app.sh" "${verify_arguments[@]}"

archive_sha256="$(
  /usr/bin/shasum -a 256 "$archive_path" | /usr/bin/awk '{ print $1 }'
)"
# macOS 27's Swift-backed plutil does not reliably persist a sequence of
# insertions into a newly created JSON plist. Build the typed property list in
# its native XML format, then convert the complete document to readable JSON.
/usr/bin/plutil -create xml1 "$receipt_path"
/usr/bin/plutil -insert schemaVersion -integer 1 "$receipt_path"
/usr/bin/plutil -insert bundleIdentifier -string com.malpern.typover \
  "$receipt_path"
/usr/bin/plutil -insert version -string "$version" "$receipt_path"
/usr/bin/plutil -insert build -string "$build_number" "$receipt_path"
/usr/bin/plutil -insert sourceRevision -string "$source_revision" \
  "$receipt_path"
/usr/bin/plutil -insert sourceDirty -bool "$source_dirty" "$receipt_path"
/usr/bin/plutil -insert minimumSystemVersion -string 27.0 "$receipt_path"
/usr/bin/plutil -insert teamIdentifier -string X2RKZ5TG99 "$receipt_path"
/usr/bin/plutil -insert archive -string "$(basename "$archive_path")" \
  "$receipt_path"
/usr/bin/plutil -insert archiveSHA256 -string "$archive_sha256" \
  "$receipt_path"
/usr/bin/plutil -insert notarized -bool "$is_notarized" "$receipt_path"
/usr/bin/plutil -convert json -r "$receipt_path"

"$script_directory/verify-beta-receipt.sh" \
  "$app_path" "$archive_path" "$receipt_path"
"$script_directory/test-beta-receipt.sh" \
  "$app_path" "$archive_path" "$receipt_path"

echo "$receipt_path"
echo "$archive_path"
