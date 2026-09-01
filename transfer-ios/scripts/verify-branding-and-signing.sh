#!/bin/bash
set -euo pipefail

grep -q '^name: AiYueTransfer' project.yml
grep -q 'PRODUCT_BUNDLE_IDENTIFIER: com.luolihao.aiyuetransfer' project.yml
grep -q 'PRODUCT_BUNDLE_IDENTIFIER: com.luolihao.aiyuetransfer.share' project.yml
grep -q 'INFOPLIST_KEY_CFBundleDisplayName: 爱乐互传' project.yml
grep -q 'PROVISIONING_PROFILE_SPECIFIER: "$(AIYUE_APP_PROFILE_NAME)"' project.yml
grep -q 'PROVISIONING_PROFILE_SPECIFIER: "$(AIYUE_SHARE_PROFILE_NAME)"' project.yml
grep -q 'group.com.luolihao.aiyuetransfer' MuseTransfer/MuseTransfer.entitlements
grep -q 'group.com.luolihao.aiyuetransfer' MuseTransferShare/MuseTransferShare.entitlements
grep -q 'group.com.luolihao.aiyuetransfer' ../ios-app/LocalMusicPlayer/LocalMusicPlayer.entitlements
RELEASE_WORKFLOW=../.github/workflows/aiyue-transfer-release.yml
grep -q '^name: AiYue Transfer Release' "$RELEASE_WORKFLOW"
grep -q '^  windows:' "$RELEASE_WORKFLOW"
grep -q '^  ios:' "$RELEASE_WORKFLOW"
grep -q 'AIYUE_TRANSFER_APP_PROFILE_BASE64' "$RELEASE_WORKFLOW"
grep -q 'AIYUE_TRANSFER_SHARE_PROFILE_BASE64' "$RELEASE_WORKFLOW"
grep -q 'AiYueTransfer-signed.ipa' "$RELEASE_WORKFLOW"
grep -q 'AiYueTransfer-Setup.exe' "$RELEASE_WORKFLOW"
test ! -e ../.github/workflows/aiyue-transfer-ios-package.yml
test ! -e ../.github/workflows/muse-transfer-windows.yml
