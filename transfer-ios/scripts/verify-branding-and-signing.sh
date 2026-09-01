#!/bin/bash
set -euo pipefail

grep -q '^name: AiYueTransfer$' project.yml
grep -q 'PRODUCT_BUNDLE_IDENTIFIER: com.luolihao.aiyuetransfer$' project.yml
grep -q 'PRODUCT_BUNDLE_IDENTIFIER: com.luolihao.aiyuetransfer.share$' project.yml
grep -q 'INFOPLIST_KEY_CFBundleDisplayName: 爱乐互传$' project.yml
grep -q 'PROVISIONING_PROFILE_SPECIFIER: "$(AIYUE_APP_PROFILE_NAME)"' project.yml
grep -q 'PROVISIONING_PROFILE_SPECIFIER: "$(AIYUE_SHARE_PROFILE_NAME)"' project.yml
grep -q 'group.com.luolihao.aiyuetransfer' MuseTransfer/MuseTransfer.entitlements
grep -q 'group.com.luolihao.aiyuetransfer' MuseTransferShare/MuseTransferShare.entitlements
grep -q 'group.com.luolihao.aiyuetransfer' ../ios-app/LocalMusicPlayer/LocalMusicPlayer.entitlements
grep -q 'AIYUE_TRANSFER_APP_PROFILE_BASE64' ../.github/workflows/aiyue-transfer-ios-package.yml
grep -q 'AIYUE_TRANSFER_SHARE_PROFILE_BASE64' ../.github/workflows/aiyue-transfer-ios-package.yml
grep -q 'AiYueTransfer-signed.ipa' ../.github/workflows/aiyue-transfer-ios-package.yml
