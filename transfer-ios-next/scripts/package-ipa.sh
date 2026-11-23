#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <archive-path> <ipa-path> [export-options-plist]" >&2
  exit 64
fi

archive_path="$1"
ipa_path="$2"
export_options="${3:-}"
output_dir="$(dirname "$ipa_path")"
mkdir -p "$output_dir"

if [[ -n "$export_options" ]]; then
  xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$output_dir" \
    -exportOptionsPlist "$export_options"
  exported_ipa="$(find "$output_dir" -maxdepth 1 -name '*.ipa' -print -quit)"
  test -n "$exported_ipa"
  mv "$exported_ipa" "$ipa_path"
else
  app_path="$(find "$archive_path/Products/Applications" -maxdepth 1 -name '*.app' -print -quit)"
  test -n "$app_path"
  staging_dir="$(mktemp -d)"
  trap 'rm -rf "$staging_dir"' EXIT
  mkdir -p "$staging_dir/Payload"
  cp -R "$app_path" "$staging_dir/Payload/"
  ditto -c -k --sequesterRsrc --keepParent "$staging_dir/Payload" "$ipa_path"
fi

test -s "$ipa_path"
