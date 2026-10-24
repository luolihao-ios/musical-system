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

APP = "6806107359"
ROOT = Path(__file__).resolve().parents[1]
FOLDER = ROOT / "marketing/app-store-2026-10-24/iphone-65"
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"}


class AppleAPI:
    def __init__(self):
        import jwt

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

    def list_all(self, path):
        items = []
        while path:
            response = self.call(path)
            items.extend(response["data"])
            next_url = response.get("links", {}).get("next")
            if next_url and not next_url.startswith("https://api.appstoreconnect.apple.com/v1/"):
                raise ValueError("分页地址不是 Apple 官方 API，停止")
            path = next_url.removeprefix("https://api.appstoreconnect.apple.com/v1/") if next_url else None
        return items


def validate_manifest_image(folder, entry):
    file = (folder / entry["file"]).resolve()
    if not file.is_relative_to(folder.resolve()):
        raise ValueError("素材路径越界")
    data = file.read_bytes()
    if hashlib.sha256(data).hexdigest() != entry["sha256"]:
        raise ValueError(f"图片校验和不一致：{file.name}")
    if len(data) < 33 or data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"必须使用 PNG：{file.name}")
    width, height, depth, color = struct.unpack(">IIBB", data[16:26])
    if (width, height, depth, color) != (entry["width"], entry["height"], 8, 2):
        raise ValueError(f"尺寸或无透明格式验收失败：{file.name}")
    offset = 8
    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        kind = data[offset + 4:offset + 8]
        if offset + length + 12 > len(data):
            raise ValueError(f"PNG 数据不完整：{file.name}")
        if kind == b"tRNS":
            raise ValueError(f"PNG 含透明颜色：{file.name}")
        offset += length + 12
        if kind == b"IEND":
            return data
    raise ValueError(f"PNG 缺少结束块：{file.name}")


def image_identity(placement):
    return (placement.get("relationships", {}).get("image", {}).get("data") or {}).get("id")


def list_placements(api, locale_id, group=None):
    # JSON:API 默认只返回关联链接；显式 include 才包含 image.data.id。
    path = f"appStoreVersionLocalizations/{locale_id}/placements?limit=200&include=image"
    if group:
        path += f"&filter[placementGroup]={group}&sort=placementGroupPosition"
    return api.list_all(path)


def validate_image(path):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"必须使用不透明 PNG：{path.name}")
    width, height, depth, color = struct.unpack(">IIBB", data[16:26])
    if (width, height, depth, color) != (1242, 2688, 8, 2):
        raise ValueError(f"图片尺寸/颜色格式不符：{path.name}, {width}x{height}, type={color}")
    return data


def upload_library(api):
    library = api.call(f"apps/{APP}/assetLibrary")["data"]["id"]
    specs = api.call("appAssetLibraryRefData")["data"][0]["attributes"]["imageSpecs"]
    folder = ROOT / "marketing/app-store-2026-10-24"
    manifest = json.loads((folder / "文件验收清单.json").read_text(encoding="utf-8"))
    existing = api.list_all(f"appAssetLibraries/{library}/images?limit=200")
    names = {item["attributes"]["fileName"]: item for item in existing}
    selected = []
    # 先验收全部本地文件，避免传到一半才发现文件格式错误。
    prepared = [(entry, validate_manifest_image(folder, entry)) for entry in manifest]
    for entry, data in prepared:
        width, height = entry["width"], entry["height"]
        matched = [s for s in specs if s["dimensions"]["minWidth"] <= width <= s["dimensions"]["maxWidth"]
            and s["dimensions"]["minHeight"] <= height <= s["dimensions"]["maxHeight"]]
        if not matched:
            raise ValueError(f"Apple 规格中未找到此尺寸：{width}x{height}")
        filename = entry["file"].replace("/", "-")
        reference = f"爱乐之城 20261024 {entry['title']} {width}x{height} {entry['sha256'][:12]}"
        item = names.get(filename)
        if item:
            if item["attributes"].get("referenceName") != reference:
                raise ValueError(f"同名素材内容不同，保留原文件：{filename}")
        else:
            item = api.call("appAssetLibraryImages", "POST", {"data": {"type": "appAssetLibraryImages",
                "attributes": {"fileName": filename, "fileSize": len(data),
                    "category": entry.get("category", "APP_SCREENSHOTS_AND_PREVIEWS"), "referenceName": reference},
                "relationships": {"assetLibrary": {"data": {"type": "appAssetLibraries", "id": library}}}}})["data"]
            for operation in item["attributes"]["uploadOperations"]:
                request = urllib.request.Request(operation["url"],
                    data=data[operation["offset"]:operation["offset"] + operation["length"]],
                    headers={h["name"]: h["value"] for h in operation.get("requestHeaders", [])}, method=operation["method"])
                with urllib.request.urlopen(request, timeout=120) as response:
                    response.read()
            api.call(f"appAssetLibraryImages/{item['id']}", "PATCH", {"data": {"type": "appAssetLibraryImages",
                "id": item["id"], "attributes": {"uploaded": True}}})
        selected.append((entry, item["id"]))
        print("素材已传输：", filename, flush=True)
    for attempt in range(12):
        states = [(entry, api.call(f"appAssetLibraryImages/{identity}")["data"]) for entry, identity in selected]
        print("素材处理：", [(s["attributes"]["fileName"], s["attributes"]["state"]) for _, s in states], flush=True)
        if any(s["attributes"]["state"] == "FAILED" for _, s in states):
            raise RuntimeError("Apple 素材处理失败：" + json.dumps([s["attributes"].get("stateDetails") for _, s in states], ensure_ascii=False))
        if all(s["attributes"]["state"] in {"PREPARE_FOR_SUBMISSION", "APPROVED"} for _, s in states):
            break
        time.sleep(10)
    else:
        raise RuntimeError("素材已传输，等待 Apple 处理完成；未放置到产品页")
    versions = api.call(f"apps/{APP}/appStoreVersions?filter[platform]=IOS&limit=50")["data"]
    editable = [v for v in versions if v["attributes"]["appStoreState"] in EDITABLE]
    if len(editable) != 1:
        raise RuntimeError("素材库上传成功；没有唯一可编辑版本，未设置展示位置")
    locales = api.call(f"appStoreVersions/{editable[0]['id']}/appStoreVersionLocalizations?limit=50")["data"]
    locale = next(v for v in locales if v["attributes"]["locale"] == "zh-Hans")
    placements = list_placements(api, locale["id"])
    groups = {"iphone-65": "IPHONE_FACE_ID_LARGE_PROFILE", "iphone-large": "IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE",
        "iphone-medium": "IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE", "ipad-13": "IPAD_13_PROFILE"}
    expected = []
    for entry, identity in selected:
        requests = [("APP_SCREENSHOT", groups[entry["file"].split("/")[0]])] if entry.get("category") != "CREATIVE_ASSETS" else [
            ("PRODUCT_PAGE_HEADER_ASSET", "DEFAULT_PROFILE"), ("APP_STORE_SEARCH_RESULTS_ASSET", "DEFAULT_PROFILE")]
        for kind, group in requests:
            expected.append((kind, group, identity))
            in_group = [p for p in placements if p["attributes"]["placementType"] == kind and p["attributes"]["placementGroup"] == group]
            if any(image_identity(p) == identity for p in in_group):
                continue
            if len(in_group) >= (10 if kind == "APP_SCREENSHOT" else 1):
                print("保留已有素材，位置已满：", kind, group, flush=True)
                continue
            placed = api.call("appAssetLibraryPlacements", "POST", {"data": {"type": "appAssetLibraryPlacements",
                "attributes": {"placementType": kind, "placementGroup": group}, "relationships": {
                    "image": {"data": {"type": "appAssetLibraryImages", "id": identity}},
                    "appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": locale["id"]}}}}})["data"]
            placements.append(placed)
            print("已设置展示位置：", kind, group, entry["file"], flush=True)
    # 新宣传图优先展示，旧素材仍保留在后面；不移除已有预览视频。
    order_expected = {}
    for group in dict.fromkeys(group for kind, group, _ in expected if kind == "APP_SCREENSHOT"):
        in_group = list_placements(api, locale["id"], group)
        new_images = [identity for kind, target, identity in expected if kind == "APP_SCREENSHOT" and target == group]
        new_placements = [p for identity in new_images for p in in_group if image_identity(p) == identity]
        old_placements = [p for p in in_group if image_identity(p) not in new_images]
        ordered = new_placements + old_placements
        order_expected[group] = [p["id"] for p in ordered]
        api.call("appAssetLibraryPlacementOrderingRequests", "POST", {"data": {
            "type": "appAssetLibraryPlacementOrderingRequests", "attributes": {"placementGroup": group},
            "relationships": {"orderedPlacements": {"data": [{"type": "appAssetLibraryPlacements", "id": p["id"]} for p in ordered]},
                "appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": locale["id"]}}}}})
    confirmed = list_placements(api, locale["id"])
    actual = {(p["attributes"]["placementType"], p["attributes"]["placementGroup"], image_identity(p)) for p in confirmed}
    missing = [item for item in expected if item not in actual]
    order_verified = {}
    for group, ordered in order_expected.items():
        actual_order = list_placements(api, locale["id"], group)
        order_verified[group] = [p["id"] for p in actual_order] == ordered
    report = {"app": APP, "version": editable[0]["attributes"]["versionString"], "locale": "zh-Hans",
        "libraryImagesVerified": len(selected), "placementsVerified": len(expected) - len(missing),
        "missingPlacements": missing, "orderVerified": order_verified, "submittedForReview": False}
    target = ROOT / ".api-inspection"
    target.mkdir(exist_ok=True)
    (target / "upload-verification.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("回读验收：", json.dumps(report, ensure_ascii=False), flush=True)
    if missing or not all(order_verified.values()):
        raise RuntimeError("素材已在库中，但部分展示位置未设置；保留原素材，没有提交审核")


def main(mode):
    api = AppleAPI()
    app = api.call(f"apps/{APP}")["data"]
    if app["attributes"]["bundleId"] != "com.luolihao.musicalsystem":
        raise ValueError("目标 App 不匹配，停止")
    if mode == "upload-library":
        return upload_library(api)
    if mode == "inspect-library":
        library = api.call(f"apps/{APP}/assetLibrary")
        print("素材库：", json.dumps(library, ensure_ascii=False), flush=True)
        reference = api.call("appAssetLibraryRefData")
        target = ROOT / ".api-inspection"
        target.mkdir(exist_ok=True)
        (target / "asset-refdata.json").write_text(json.dumps(reference, ensure_ascii=False, indent=2), encoding="utf-8")
        print("素材规格：", json.dumps(reference, ensure_ascii=False)[:50000], flush=True)
        return
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
