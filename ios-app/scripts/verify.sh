#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ios_root="$repo_root/ios-app"

cd "$repo_root"
/usr/bin/python3 -m unittest discover \
  -s "$ios_root/scripts/tests" \
  -p "test_*.py" \
  -v

xcodegen generate --spec "$ios_root/project.yml"

simulator_id="$(
  xcrun simctl list devices available -j |
    /usr/bin/python3 -c '
import json, sys
data = json.load(sys.stdin)
for runtime in data.get("devices", {}).values():
    for device in runtime:
        if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
            print(device["udid"])
            raise SystemExit(0)
raise SystemExit("No available iPhone simulator was found.")
'
)"

xcodebuild test \
  -project "$ios_root/LocalMusicPlayer.xcodeproj" \
  -scheme LocalMusicPlayer \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath "$ios_root/build/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO
