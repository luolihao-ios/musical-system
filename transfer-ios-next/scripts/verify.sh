#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

xcodegen generate
xcodebuild -list -project AiYueTransferNext.xcodeproj
