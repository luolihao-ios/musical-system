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

collect_player_diagnostics() {
  local data_dir
  data_dir="$(xcrun simctl get_app_container "$simulator_id" com.luolihao.musicalsystem data 2>/dev/null || true)"
  if [ -n "$data_dir" ] && [ -f "$data_dir/Documents/music-player-interaction.log" ]; then
    cp "$data_dir/Documents/music-player-interaction.log" "$ios_root/build/music-player-interaction.log"
  fi
  # 测试结束后 simctl 容器查询可能失效，保留每个测试容器的实际日志。
  mkdir -p "$ios_root/build/player-evidence"
  find "$HOME/Library/Developer/CoreSimulator/Devices" \
    -path '*/data/Containers/Data/Application/*/Documents/music-player-interaction.log' \
    -type f -print | while IFS= read -r logfile; do
      container_id="$(basename "$(dirname "$(dirname "$logfile")")")"
      cp "$logfile" "$ios_root/build/player-evidence/$container_id.log"
    done
  xcrun xcresulttool export attachments \
    --path "$ios_root/build/PlayerTests.xcresult" \
    --output-path "$ios_root/build/player-evidence/screenshots" || true
}
trap collect_player_diagnostics EXIT

xcodebuild test \
  -project "$ios_root/LocalMusicPlayer.xcodeproj" \
  -scheme LocalMusicPlayer \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath "$ios_root/build/DerivedData" \
  -resultBundlePath "$ios_root/build/PlayerTests.xcresult" \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO
