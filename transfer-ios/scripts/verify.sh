#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cmp MuseTransferTests/Resources/manifest-v2.json ../docs/transfer-protocol/vectors/manifest-v2.json
cmp MuseTransferTests/Resources/crypto-v2.json ../docs/transfer-protocol/vectors/crypto-v2.json
xcodegen generate
xcodebuild test -project AiYueTransfer.xcodeproj -scheme MuseTransfer -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project AiYueTransfer.xcodeproj -scheme MuseTransfer -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
/usr/libexec/PlistBuddy -c 'Print :NSLocalNetworkUsageDescription' "$(find ~/Library/Developer/Xcode/DerivedData -path '*MuseTransfer.app/Info.plist' | head -1)" >/dev/null
grep -q '_musetransfer._tcp' project.yml
grep -q 'group.com.luolihao.aiyuetransfer' MuseTransfer/MuseTransfer.entitlements
