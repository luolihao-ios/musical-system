"""通过现有团队 API 上传简体中文 iPhone 宣传图；不提交审核、不删除旧图。"""
import base64
import hashlib
import json
import os
from pathlib import Path
import struct
import sys
import time
import urllib.error
import urllib.request

import jwt

APP = "6806107359"
ROOT = Path(__file__).resolve().parents[1]
FOLDER = ROOT / "marketing/app-store-2026-10-24/iphone-65"
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"}


class AppleAPI:
    def __init__(self):
        key = base64.b64decode(os.environ["API_PRIVATE_KEY_BASE64"]).decode()
        now = int(time.time())
        self.token = jwt.encode({"iss": os.environ["API_ISSUER_ID"], "iat": now,
            "exp": now + 1100, "aud": "appstoreconnect-v1"}, key,
            algorithm="ES256", headers={"kid": os.environ["API_KEY_ID"], "typ": "JWT"})

    def call(self, path, method="GET", payload=None):
        request = urllib.request.Request("https://api.appstoreconnect.apple.com/v1/" + path,
            data=json.dumps(payload).encode() if payload is not None else None,
            headers={"Authorization": "Bearer " + self.token, "Content-Type": "application/json"}, method=method)
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                raw = response.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as error:
            body = json.loads(error.read())
            # 只输出结构化 API 错误，不记录认证头或签名上传地址。
            raise RuntimeError(json.dumps(body.get("errors", []), ensure_ascii=False)) from None


def validate_image(path):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"必须使用不透明 PNG：{path.name}")
    width, height, depth, color = struct.unpack(">IIBB", data[16:26])
    if (width, height, depth, color) != (1242, 2688, 8, 2):
        raise ValueError(f"图片尺寸/颜色格式不符：{path.name}, {width}x{height}, type={color}")
    return data


def main(mode):
    api = AppleAPI()
    app = api.call(f"apps/{APP}")["data"]
    if app["attributes"]["bundleId"] != "com.luolihao.musicalsystem":
        raise ValueError("目标 App 不匹配，停止")
    versions = api.call(f"apps/{APP}/appStoreVersions?filter[platform]=IOS&limit=50")["data"]
    print("商店版本：", json.dumps([{"id": v["id"], "version": v["attributes"]["versionString"],
        "state": v["attributes"]["appStoreState"]} for v in versions], ensure_ascii=False), flush=True)
    editable = [v for v in versions if v["attributes"]["appStoreState"] in EDITABLE]
    if len(editable) != 1:
        raise RuntimeError("没有唯一可编辑的商店版本，未修改任何截图")
    version = editable[0]
    locales = api.call(f"appStoreVersions/{version['id']}/appStoreVersionLocalizations?limit=50")["data"]
    locale = next((v for v in locales if v["attributes"]["locale"] == "zh-Hans"), None)
    if not locale:
        raise RuntimeError("当前版本没有简体中文本地化，未修改截图")
    sets = api.call(f"appStoreVersionLocalizations/{locale['id']}/appScreenshotSets?limit=50")["data"]
    print("简体中文截图组：", json.dumps([{"id": s["id"], "type": s["attributes"]["screenshotDisplayType"]} for s in sets], ensure_ascii=False), flush=True)
    if mode == "inspect":
        return
    files = sorted(FOLDER.glob("0[1-4]-*.png"))
    if len(files) != 4:
        raise ValueError("必须准备四张已确认宣传图")
    images = [(file, validate_image(file)) for file in files]
    target = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == "APP_IPHONE_65"), None)
    if target is None:
        target = api.call("appScreenshotSets", "POST", {"data": {"type": "appScreenshotSets",
            "attributes": {"screenshotDisplayType": "APP_IPHONE_65"},
            "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": locale["id"]}}}}})["data"]
    existing = api.call(f"appScreenshotSets/{target['id']}/appScreenshots?limit=50")["data"]
    names = {s["attributes"]["fileName"]: s for s in existing}
    new_files = [(file, data) for file, data in images if file.name not in names]
    if len(existing) + len(new_files) > 10:
        raise RuntimeError("旧图加新图超过十张，保留旧图并停止上传")
    selected = []
    for file, data in images:
        if file.name in names:
            item = names[file.name]
            if item["attributes"].get("sourceFileChecksum") != hashlib.md5(data).hexdigest():
                raise RuntimeError(f"存在同名不同内容图片，未覆盖：{file.name}")
        else:
            item = api.call("appScreenshots", "POST", {"data": {"type": "appScreenshots",
                "attributes": {"fileName": file.name, "fileSize": len(data)},
                "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": target["id"]}}}}})["data"]
            for operation in item["attributes"]["uploadOperations"]:
                headers = {h["name"]: h["value"] for h in operation.get("requestHeaders", [])}
                chunk = data[operation["offset"]:operation["offset"] + operation["length"]]
                request = urllib.request.Request(operation["url"], data=chunk,
                    headers=headers, method=operation["method"])
                with urllib.request.urlopen(request, timeout=120) as response:
                    response.read()
            api.call(f"appScreenshots/{item['id']}", "PATCH", {"data": {"type": "appScreenshots", "id": item["id"],
                "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
        selected.append(item["id"])
        print("已提交图片：", file.name, flush=True)
    for _ in range(12):
        states = [api.call(f"appScreenshots/{identity}")["data"] for identity in selected]
        print("处理状态：", [(s["attributes"]["fileName"], s["attributes"].get("assetDeliveryState")) for s in states], flush=True)
        delivery = [s["attributes"].get("assetDeliveryState", {}).get("state") for s in states]
        if all(state == "COMPLETE" for state in delivery):
            print(f"四张宣传图已在版本 {version['attributes']['versionString']} 简体中文 iPhone 6.5 组处理完成；未提交审核", flush=True)
            return
        if "FAILED" in delivery:
            raise RuntimeError("Apple 图片处理失败，请查看处理状态")
        time.sleep(10)
    raise RuntimeError("图片已提交，Apple 尚未完成处理；不能宣称上传验收通过")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "inspect")
