"""创建或更新 0.2.3 商店版本资料、上传 2026-11-26 三设备宣传图并回读校验；不提交审核。"""
import argparse
import hashlib
import json
import re
import time
import urllib.request
from pathlib import Path

from app_store_screenshots import (
    APP,
    EDITABLE,
    ROOT,
    image_identity,
    list_placements,
    screenshot_group,
    validate_manifest_image,
)

CAMPAIGN_DIR = ROOT / "marketing" / "app-store-2026-11-26"
CAMPAIGN_REFERENCE = "爱乐之城 20261126"
LOCALES = ("zh-Hans", "zh-Hant", "en-US", "fr-FR")
FORBIDDEN_KEYWORD_TOKENS = ("ipod", "iphone", "ipad")
LIMITS = {
    "description": 4000,
    "keywords": 100,
    "promotionalText": 170,
    "whatsNew": 4000,
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def entry_device_folder(entry: dict) -> str:
    parts = entry["file"].split("/")
    if len(parts) >= 3:
        return parts[1]
    return parts[0]


def validate_campaign(campaign: dict, folder: Path = CAMPAIGN_DIR):
    require(campaign.get("version") == "0.2.3", "版本号必须是 0.2.3")
    locales = campaign.get("locales") or {}
    require(set(locales) == set(LOCALES), f"本地化语言不完整：{sorted(locales)}")
    for locale, attrs in locales.items():
        for field, limit in LIMITS.items():
            value = attrs.get(field)
            require(isinstance(value, str) and value.strip(), f"{locale} 缺少字段 {field}")
            require(len(value) <= limit, f"{locale} 字段 {field} 超长：{len(value)} > {limit}")
        kw_lower = attrs["keywords"].lower()
        for forbidden in FORBIDDEN_KEYWORD_TOKENS:
            require(forbidden not in kw_lower, f"{locale} 关键词包含敏感商标词：{forbidden}")

    manifest_path = folder / "文件验收清单.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    require(len(manifest) == 48, f"四语宣传图清单应为 48 张，实际 {len(manifest)}")
    for loc in LOCALES:
        loc_items = [e for e in manifest if e.get("locale") == loc]
        require(len(loc_items) == 12, f"{loc} 宣传图数量应为 12 张，实际 {len(loc_items)}")
        for dev in ("iphone-medium", "iphone-duo", "ipad-13"):
            cnt = sum(entry_device_folder(e) == dev for e in loc_items)
            require(cnt == 4, f"{loc}/{dev} 宣传图数量应为 4 张，实际 {cnt}")
    prepared = [(entry, validate_manifest_image(folder, entry)) for entry in manifest]
    return manifest, prepared


def version_state(version_resource: dict) -> str:
    attrs = version_resource["attributes"]
    return attrs.get("appStoreState", attrs.get("state", ""))


def ensure_editable_version(api, version_string: str = "0.2.3"):
    versions = api.list_all(f"apps/{APP}/appStoreVersions?filter[platform]=IOS&limit=50")
    existing_target = [v for v in versions if v["attributes"]["versionString"] == version_string]
    if existing_target:
        require(len(existing_target) == 1, f"发现多个 {version_string} 版本，停止")
        ver = existing_target[0]
        state = version_state(ver)
        require(state in EDITABLE, f"版本 {version_string} 当前状态 {state} 不可编辑，停止")
        return ver, "reused"

    editable_drafts = [v for v in versions if version_state(v) in EDITABLE]
    require(len(editable_drafts) <= 1, "存在多个可编辑版本，停止自动选择")
    if len(editable_drafts) == 1:
        draft = editable_drafts[0]
        state = version_state(draft)
        require(state == "PREPARE_FOR_SUBMISSION", f"现有可编辑版本状态为 {state}，无法安全重命名为 {version_string}")
        old_version = draft["attributes"]["versionString"]
        updated = api.call(
            f"appStoreVersions/{draft['id']}",
            "PATCH",
            {"data": {"type": "appStoreVersions", "id": draft["id"], "attributes": {"versionString": version_string}}},
        )["data"]
        return updated, f"renamed-from-{old_version}"

    created = api.call(
        "appStoreVersions",
        "POST",
        {
            "data": {
                "type": "appStoreVersions",
                "attributes": {"platform": "IOS", "versionString": version_string},
                "relationships": {"app": {"data": {"type": "apps", "id": APP}}},
            }
        },
    )["data"]
    return created, "created"


def sync_localizations(api, version_id: str, campaign: dict) -> list[dict]:
    existing = api.list_all(f"appStoreVersions/{version_id}/appStoreVersionLocalizations?limit=50")
    by_locale = {item["attributes"]["locale"]: item for item in existing}
    results = []
    for locale in LOCALES:
        attrs = dict(campaign["locales"][locale])
        if locale in by_locale:
            loc_id = by_locale[locale]["id"]
            saved = api.call(
                f"appStoreVersionLocalizations/{loc_id}",
                "PATCH",
                {"data": {"type": "appStoreVersionLocalizations", "id": loc_id, "attributes": attrs}},
            )["data"]
            action = "patched"
        else:
            saved = api.call(
                "appStoreVersionLocalizations",
                "POST",
                {
                    "data": {
                        "type": "appStoreVersionLocalizations",
                        "attributes": {"locale": locale, **attrs},
                        "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}},
                    }
                },
            )["data"]
            action = "created"
        results.append(saved)
        print(f"版本资料已同步 [{locale}] ({action}): {saved['id']}", flush=True)

    # 回读验证所有四语字段一致
    readback = {
        item["attributes"]["locale"]: item["attributes"]
        for item in api.list_all(f"appStoreVersions/{version_id}/appStoreVersionLocalizations?limit=50")
    }
    for locale in LOCALES:
        require(locale in readback, f"回读缺少语言 {locale}")
        for field, expected_value in campaign["locales"][locale].items():
            require(readback[locale].get(field) == expected_value, f"{locale} 字段 {field} 回读不一致")
    return results


def upload_campaign_images(api, prepared: list[tuple[dict, bytes]]) -> list[tuple[dict, str]]:
    library = api.call(f"apps/{APP}/assetLibrary")["data"]["id"]
    specs = api.call("appAssetLibraryRefData")["data"][0]["attributes"]["imageSpecs"]
    existing = api.list_all(f"appAssetLibraries/{library}/images?limit=200")
    by_name = {item["attributes"]["fileName"]: item for item in existing}

    selected = []
    for entry, data in prepared:
        width, height = entry["width"], entry["height"]
        matched = [
            s
            for s in specs
            if s["dimensions"]["minWidth"] <= width <= s["dimensions"]["maxWidth"]
            and s["dimensions"]["minHeight"] <= height <= s["dimensions"]["maxHeight"]
        ]
        require(bool(matched), f"Apple 素材规格中未匹配尺寸 {width}x{height}")

        filename = "v023-" + entry["file"].replace("/", "-")
        loc_tag = entry.get("locale", "zh-Hans")
        reference = f"{CAMPAIGN_REFERENCE} {loc_tag} {entry['title']} {width}x{height} {entry['sha256'][:12]}"
        item = by_name.get(filename)
        if item and item["attributes"].get("referenceName") == reference:
            selected.append((entry, item["id"]))
            print("复用已有素材：", filename, flush=True)
            continue

        if item:
            # 文件名相同但内容变更时追加哈希前缀避免覆盖已有素材
            filename = f"v023-{entry['sha256'][:6]}-" + entry["file"].replace("/", "-")
            item = by_name.get(filename)

        if not item:
            item = api.call(
                "appAssetLibraryImages",
                "POST",
                {
                    "data": {
                        "type": "appAssetLibraryImages",
                        "attributes": {
                            "fileName": filename,
                            "fileSize": len(data),
                            "category": "APP_SCREENSHOTS_AND_PREVIEWS",
                            "referenceName": reference,
                        },
                        "relationships": {"assetLibrary": {"data": {"type": "appAssetLibraries", "id": library}}},
                    }
                },
            )["data"]
            for op in item["attributes"]["uploadOperations"]:
                req = urllib.request.Request(
                    op["url"],
                    data=data[op["offset"] : op["offset"] + op["length"]],
                    headers={h["name"]: h["value"] for h in op.get("requestHeaders", [])},
                    method=op["method"],
                )
                with urllib.request.urlopen(req, timeout=120) as resp:
                    resp.read()
            api.call(
                f"appAssetLibraryImages/{item['id']}",
                "PATCH",
                {"data": {"type": "appAssetLibraryImages", "id": item["id"], "attributes": {"uploaded": True}}},
            )
            print("素材已上传：", filename, flush=True)
        selected.append((entry, item["id"]))

    for _ in range(18):
        states = [(entry, api.call(f"appAssetLibraryImages/{identity}")["data"]) for entry, identity in selected]
        summary = [(s["attributes"]["fileName"], s["attributes"]["state"]) for _, s in states]
        print("素材处理状态：", summary, flush=True)
        if any(s["attributes"]["state"] == "FAILED" for _, s in states):
            raise RuntimeError("Apple 素材处理失败：" + json.dumps([s["attributes"].get("stateDetails") for _, s in states], ensure_ascii=False))
        if all(s["attributes"]["state"] in {"PREPARE_FOR_SUBMISSION", "APPROVED"} for _, s in states):
            return selected
        time.sleep(10)
    raise RuntimeError("等待 Apple 素材处理超时")


def sync_placements_for_locale(api, locale_resource: dict, selected: list[tuple[dict, str]]) -> dict:
    locale_id = locale_resource["id"]
    locale_code = locale_resource["attributes"]["locale"]
    grouped_expected: dict[str, list[str]] = {}
    for entry, image_id in selected:
        if entry.get("locale") != locale_code:
            continue
        group = screenshot_group(f"{entry_device_folder(entry)}/poster.png")
        grouped_expected.setdefault(group, []).append(image_id)
    require(set(grouped_expected) == {"IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE", "IPHONE_DUO_PROFILE", "IPAD_13_PROFILE"},
            f"{locale_code} 缺少对应设备分组截图：{grouped_expected}")

    order_verified = {}
    for group, expected_ids in grouped_expected.items():
        current = list_placements(api, locale_id, group)
        # 移除不属于新 0.2.3 四张图的旧位置，保持该组只展示本版 4 张宣传图
        kept_by_image = {}
        for placement in current:
            img_id = image_identity(placement)
            if img_id in expected_ids and img_id not in kept_by_image:
                kept_by_image[img_id] = placement
            else:
                api.call(f"appAssetLibraryPlacements/{placement['id']}", "DELETE")

        for img_id in expected_ids:
            if img_id not in kept_by_image:
                created = api.call(
                    "appAssetLibraryPlacements",
                    "POST",
                    {
                        "data": {
                            "type": "appAssetLibraryPlacements",
                            "attributes": {"placementType": "APP_SCREENSHOT", "placementGroup": group},
                            "relationships": {
                                "image": {"data": {"type": "appAssetLibraryImages", "id": img_id}},
                                "appStoreVersionLocalization": {
                                    "data": {"type": "appStoreVersionLocalizations", "id": locale_id}
                                },
                            },
                        }
                    },
                )["data"]
                kept_by_image[img_id] = created

        ordered = [kept_by_image[img_id] for img_id in expected_ids]
        api.call(
            "appAssetLibraryPlacementOrderingRequests",
            "POST",
            {
                "data": {
                    "type": "appAssetLibraryPlacementOrderingRequests",
                    "attributes": {"placementGroup": group},
                    "relationships": {
                        "orderedPlacements": {
                            "data": [{"type": "appAssetLibraryPlacements", "id": p["id"]} for p in ordered]
                        },
                        "appStoreVersionLocalization": {
                            "data": {"type": "appStoreVersionLocalizations", "id": locale_id}
                        },
                    },
                }
            },
        )
        confirmed = list_placements(api, locale_id, group)
        actual_ids = [image_identity(p) for p in confirmed]
        require(actual_ids == expected_ids, f"{locale_code} {group} 回读位置顺序不一致：{actual_ids} != {expected_ids}")
        order_verified[group] = True

    return {"locale": locale_code, "localizationId": locale_id, "groupsVerified": order_verified}


def inspect_store(api) -> dict:
    app = api.call(f"apps/{APP}")["data"]
    require(app["attributes"]["bundleId"] == "com.luolihao.musicalsystem", "应用标识不符")
    versions = api.list_all(f"apps/{APP}/appStoreVersions?filter[platform]=IOS&limit=50")
    summary = []
    for ver in versions:
        locs = api.list_all(f"appStoreVersions/{ver['id']}/appStoreVersionLocalizations?limit=50")
        summary.append(
            {
                "id": ver["id"],
                "versionString": ver["attributes"]["versionString"],
                "state": version_state(ver),
                "locales": [x["attributes"]["locale"] for x in locs],
            }
        )
    return {"app": APP, "bundleId": app["attributes"]["bundleId"], "versions": summary}


def main():
    from app_store_screenshots import AppleAPI

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["inspect", "sync"])
    parser.add_argument("--apply", action="store_true", help="执行写入；默认仅离线校验与只读检查")
    args = parser.parse_args()

    campaign = json.loads((CAMPAIGN_DIR / "localizations/0.2.3.json").read_text(encoding="utf-8"))
    manifest, prepared = validate_campaign(campaign)

    out_dir = ROOT / ".api-inspection"
    out_dir.mkdir(exist_ok=True)

    api = AppleAPI()
    info = inspect_store(api)
    if args.operation == "inspect" or not args.apply:
        (out_dir / "store-023-inspect.json").write_text(
            json.dumps(info, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(json.dumps(info, ensure_ascii=False, indent=2), flush=True)
        return

    version, version_action = ensure_editable_version(api, "0.2.3")
    print(f"目标版本 0.2.3 ({version_action}): {version['id']}", flush=True)
    locale_resources = sync_localizations(api, version["id"], campaign)
    selected = upload_campaign_images(api, prepared)
    placement_reports = [sync_placements_for_locale(api, loc, selected) for loc in locale_resources]

    report = {
        "app": APP,
        "version": "0.2.3",
        "versionId": version["id"],
        "versionAction": version_action,
        "localesVerified": [loc["attributes"]["locale"] for loc in locale_resources],
        "imagesVerified": len(manifest),
        "placements": placement_reports,
        "submittedForReview": False,
    }
    (out_dir / "store-023-verification.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print("0.2.3 商店同步验收：", json.dumps(report, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
