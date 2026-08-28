#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild test -project MuseTransfer.xcodeproj -scheme MuseTransfer -destination 'platform=macOS,arch=arm64'
xcodebuild build -project MuseTransfer.xcodeproj -scheme MuseTransfer -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
/usr/libexec/PlistBuddy -c 'Print :NSLocalNetworkUsageDescription' "$(find ~/Library/Developer/Xcode/DerivedData -path '*MuseTransfer.app/Info.plist' | head -1)" >/dev/null
grep -q '_musetransfer._tcp' project.yml
grep -q 'group.com.luolihao.musetransfer' MuseTransfer/MuseTransfer.entitlements
