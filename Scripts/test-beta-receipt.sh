#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
app_path="${1:-$repository_root/.build/beta/Typover.app}"
archive_path="${2:-$repository_root/.build/beta/Typover-0.1.zip}"
receipt_path="${3:-$repository_root/.build/beta/Typover-0.1.json}"

if [[ ! -d "$app_path" || ! -f "$archive_path" || ! -f "$receipt_path" ]]; then
  echo "Build a local beta artifact and receipt before testing receipt rejection." >&2
  exit 2
fi

temporary_directory="$(
  /usr/bin/mktemp -d "${TMPDIR:-/tmp}/typover-beta-receipt.XXXXXX"
)"
trap '/bin/rm -rf "$temporary_directory"' EXIT HUP INT TERM

"$script_directory/verify-beta-receipt.sh" \
  "$app_path" "$archive_path" "$receipt_path" >/dev/null

checksum_receipt="$temporary_directory/checksum.json"
/bin/cp "$receipt_path" "$checksum_receipt"
/usr/bin/plutil -replace archiveSHA256 -string \
  '0000000000000000000000000000000000000000000000000000000000000000' \
  "$checksum_receipt"
if "$script_directory/verify-beta-receipt.sh" \
  "$app_path" "$archive_path" "$checksum_receipt" \
    >"$temporary_directory/checksum.out" 2>&1
then
  echo "Receipt verifier incorrectly accepted a mismatched checksum." >&2
  exit 1
fi
/usr/bin/grep -Fq \
  "The beta receipt archive checksum does not match." \
  "$temporary_directory/checksum.out"

source_receipt="$temporary_directory/source.json"
/bin/cp "$receipt_path" "$source_receipt"
/usr/bin/plutil -replace sourceRevision -string \
  '0000000000000000000000000000000000000000' "$source_receipt"
if "$script_directory/verify-beta-receipt.sh" \
  "$app_path" "$archive_path" "$source_receipt" \
    >"$temporary_directory/source.out" 2>&1
then
  echo "Receipt verifier incorrectly accepted mismatched app metadata." >&2
  exit 1
fi
/usr/bin/grep -Fq \
  "The beta receipt does not match the verified app metadata." \
  "$temporary_directory/source.out"

schema_receipt="$temporary_directory/schema.json"
/bin/cp "$receipt_path" "$schema_receipt"
/usr/bin/plutil -replace schemaVersion -integer 2 "$schema_receipt"
if "$script_directory/verify-beta-receipt.sh" \
  "$app_path" "$archive_path" "$schema_receipt" \
    >"$temporary_directory/schema.out" 2>&1
then
  echo "Receipt verifier incorrectly accepted an unknown schema." >&2
  exit 1
fi
/usr/bin/grep -Fq \
  "Unsupported beta receipt schema: 2" \
  "$temporary_directory/schema.out"

missing_receipt="$temporary_directory/missing.json"
/bin/cp "$receipt_path" "$missing_receipt"
/usr/bin/plutil -remove teamIdentifier "$missing_receipt"
if "$script_directory/verify-beta-receipt.sh" \
  "$app_path" "$archive_path" "$missing_receipt" \
    >"$temporary_directory/missing.out" 2>&1
then
  echo "Receipt verifier incorrectly accepted missing metadata." >&2
  exit 1
fi
/usr/bin/grep -Fq \
  "The beta receipt is missing a valid teamIdentifier value." \
  "$temporary_directory/missing.out"

notarization_receipt="$temporary_directory/notarization.json"
/bin/cp "$receipt_path" "$notarization_receipt"
/usr/bin/plutil -replace notarized -bool true "$notarization_receipt"
if "$script_directory/verify-beta-receipt.sh" \
  "$app_path" "$archive_path" "$notarization_receipt" \
    >"$temporary_directory/notarization.out" 2>&1
then
  echo "Receipt verifier incorrectly accepted a false notarization claim." >&2
  exit 1
fi

invalid_type_receipt="$temporary_directory/invalid-type.json"
/bin/cp "$receipt_path" "$invalid_type_receipt"
/usr/bin/plutil -replace sourceDirty -string false "$invalid_type_receipt"
if "$script_directory/verify-beta-receipt.sh" \
  "$app_path" "$archive_path" "$invalid_type_receipt" \
    >"$temporary_directory/invalid-type.out" 2>&1
then
  echo "Receipt verifier incorrectly accepted an invalid field type." >&2
  exit 1
fi
/usr/bin/grep -Fq \
  "The beta receipt is missing a valid sourceDirty value." \
  "$temporary_directory/invalid-type.out"

echo "Beta receipt rejection tests passed."
