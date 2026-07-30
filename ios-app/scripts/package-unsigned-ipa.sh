#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ios_root="$repo_root/ios-app"
build_root="$ios_root/build"
payload_root="$build_root/ipa/Payload"
app_path="$build_root/DeviceBuild/Build/Products/Release-iphoneos/LocalMusicPlayer.app"
ipa_path="$build_root/ipa/LocalMusicPlayer-unsigned.ipa"

cd "$repo_root"
xcodegen generate --spec "$ios_root/project.yml"

xcodebuild build \
  -project "$ios_root/LocalMusicPlayer.xcodeproj" \
  -scheme LocalMusicPlayer \
  -configuration Release \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$build_root/DeviceBuild" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO

test -d "$app_path"
rm -rf "$build_root/ipa"
mkdir -p "$payload_root"
cp -R "$app_path" "$payload_root/"

cd "$build_root/ipa"
ditto -c -k --sequesterRsrc --keepParent Payload "$ipa_path"
test -f "$ipa_path"
printf 'Unsigned IPA: %s\n' "$ipa_path"
