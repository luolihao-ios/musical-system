#!/usr/bin/env python3
"""iPad / iPhone Duo 自适应布局回归检查。"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "MuseTransfer"


def main() -> None:
    swift = (APP / "Web" / "BrowserTransferView.swift").read_text(encoding="utf-8")
    css = (APP / "WebAssets" / "style.css").read_text(encoding="utf-8")
    html = (APP / "WebAssets" / "index.html").read_text(encoding="utf-8")

    assert "frame(maxWidth: .infinity, alignment: .leading)" in swift, "原生浏览器页必须可扩展至 iPad 宽度"
    assert "viewport-fit=cover" in html, "内置网页必须使用完整安全区视口"
    normalized_css = "".join(css.split())
    assert "@media(max-width:720px)" in normalized_css, "网页必须针对 iPhone Duo 紧凑宽度重排"
    assert "@media(min-width:768px)" in normalized_css, "网页必须针对 iPad 宽度排版"
    assert "width:min(100%,1180px)" in normalized_css, "网页主内容必须在宽屏占满可用空间且限制舒适阅读宽度"
    assert "min-height:100dvh" in css, "网页背景必须覆盖动态视口，不能露出黑边"
    assert "body.transferring{grid-template-columns:minmax(0,1fr)}" in normalized_css, "传输页必须移除侧栏占位，避免宽屏出现空白边"


if __name__ == "__main__":
    main()
