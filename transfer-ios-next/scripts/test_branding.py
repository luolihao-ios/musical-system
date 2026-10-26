#!/usr/bin/env python3
"""file send 品牌显示回归检查。"""
from pathlib import Path
import plistlib

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "MuseTransfer"


def text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def main() -> None:
    plist = text(APP / "Info.plist")
    metadata = plistlib.loads(plist.encode("utf-8"))
    assert metadata["CFBundleDisplayName"] == "ios file send", "默认显示名必须匹配商店英文标题"
    assert metadata["CFBundleName"] == "ios file send", "Bundle Name 必须匹配商店英文标题"
    assert "file send needs local network access" in plist, "默认局域网权限文案必须使用 file send"

    for language in ("en", "zh-Hans", "zh-Hant"):
        info = text(APP / "Resources" / f"{language}.lproj" / "InfoPlist.strings")
        assert '"CFBundleDisplayName" = "ios file send";' in info, f"{language} 显示名必须匹配英文标题"
        assert '"CFBundleName" = "ios file send";' in info, f"{language} Bundle Name 必须匹配英文标题"

    visible_files = [
        APP / "Features" / "TransferView.swift",
        APP / "Web" / "BrowserTransferView.swift",
        APP / "WebAssets" / "index.html",
        APP / "WebAssets" / "app.js",
        APP / "DiagnosticLog.swift",
        *(APP / "Resources" / f"{language}.lproj" / "Localizable.strings" for language in ("en", "zh-Hans", "zh-Hant")),
    ]
    for path in visible_files:
        assert "爱乐互传" not in text(path), f"{path.relative_to(ROOT)} 仍显示旧名称"
        assert "AiYue Transfer" not in text(path), f"{path.relative_to(ROOT)} 仍显示旧名称"

    migration = text(APP / "StorageMigration.swift")
    assert 'appendingPathComponent("爱乐互传"' in migration, "必须保留旧文件夹迁移，避免更新后丢失旧文件"
    assert "group.com.luolihao.aiyuetransfer" in migration, "必须保留既有 App Group 身份"


if __name__ == "__main__":
    main()
