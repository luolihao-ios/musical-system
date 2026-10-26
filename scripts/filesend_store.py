"""file send 的商店资料与构建号管理；由 GitHub Actions 使用团队密钥执行。"""
import argparse
import json
import os
from pathlib import Path

from app_store_screenshots import AppleAPI, EDITABLE

BUNDLE = "com.luolihao.aiyuetransfer"
LABELS = {
    "zh-Hans": {"name": "file send", "subtitle": "手机电脑双向互传，局域网轻松传文件"},
    "zh-Hant": {"name": "file send", "subtitle": "手機電腦雙向互傳，區域網路輕鬆傳檔"},
    "en-US": {"name": "file send", "subtitle": "Wi-Fi file transfer, made easy"},
}


def resolve_app(api):
    matches = api.call(f"apps?filter[bundleId]={BUNDLE}&limit=10")["data"]
    if len(matches) != 1 or matches[0]["attributes"]["bundleId"] != BUNDLE:
        raise ValueError("无法唯一确认 file send 的既有 Bundle ID")
    return matches[0]


def read_state(api):
    app = resolve_app(api)
    identity = app["id"]
    infos = api.call(f"apps/{identity}/appInfos?limit=50")["data"]
    versions = api.call(f"apps/{identity}/appStoreVersions?filter[platform]=IOS&limit=50")["data"]
    result = {"app": app, "infos": [], "versions": versions,
              "latestBuilds": api.call(f"builds?filter[app]={identity}&sort=-uploadedDate&limit=10")["data"]}
    for item in infos:
        result["infos"].append({"info": item,
            "locales": api.call(f"appInfos/{item['id']}/appInfoLocalizations?limit=50")["data"]})
    return result


def update_metadata(api, before):
    targets = [item for item in before["infos"] if
               item["info"]["attributes"].get("state", item["info"]["attributes"].get("appStoreState")) in EDITABLE]
    if len(targets) != 1:
        raise ValueError("没有唯一可编辑的 App 信息，停止名称及副标题修改")
    target = targets[0]
    locales = {item["attributes"]["locale"]: item for item in target["locales"]}
    for locale, labels in LABELS.items():
        if len(labels["name"]) > 30 or len(labels["subtitle"]) > 30:
            raise ValueError("商店名称或副标题超过 30 字符")
        if locale in locales:
            item = locales[locale]
            api.call(f"appInfoLocalizations/{item['id']}", "PATCH", {"data": {
                "type": "appInfoLocalizations", "id": item["id"], "attributes": labels}})
        else:
            api.call("appInfoLocalizations", "POST", {"data": {
                "type": "appInfoLocalizations", "attributes": {"locale": locale, **labels},
                "relationships": {"appInfo": {"data": {"type": "appInfos", "id": target["info"]["id"]}}}}})
    after = api.call(f"appInfos/{target['info']['id']}/appInfoLocalizations?limit=50")["data"]
    mapped = {item["attributes"]["locale"]: item["attributes"] for item in after}
    for locale, labels in LABELS.items():
        if any(mapped.get(locale, {}).get(key) != value for key, value in labels.items()):
            raise RuntimeError(f"名称/副标题回读不匹配：{locale}")
    return {locale: {key: mapped[locale][key] for key in labels} for locale, labels in LABELS.items()}


def next_build(api, app_id):
    builds = api.list_all(f"builds?filter[app]={app_id}&limit=200")
    values = [int(item["attributes"]["version"]) for item in builds
              if str(item["attributes"]["version"]).isdigit()]
    return max([110, *values]) + 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["inspect", "update-metadata", "next-build", "upload-library"])
    args = parser.parse_args()
    api = AppleAPI()
    state = read_state(api)
    report = Path(".api-inspection/filesend")
    report.mkdir(parents=True, exist_ok=True)
    (report / "before.json").write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(state, ensure_ascii=False, indent=2), flush=True)
    if args.operation == "update-metadata":
        updated = update_metadata(api, state)
        (report / "metadata-verified.json").write_text(json.dumps(updated, ensure_ascii=False, indent=2), encoding="utf-8")
        print("三语言名称与副标题回读通过：", json.dumps(updated, ensure_ascii=False), flush=True)
    elif args.operation == "next-build":
        version = next_build(api, state["app"]["id"])
        with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as stream:
            stream.write(f"FILE_SEND_BUILD={version}\n")
        print(f"营销版本沿用 1.0.1，本次构建号：{version}", flush=True)
    elif args.operation == "upload-library":
        import app_store_screenshots as assets
        assets.APP = state["app"]["id"]
        assets.CAMPAIGN_FOLDER = Path("marketing/file-send-2026-10-26")
        assets.CAMPAIGN_REFERENCE = "file send 20261026"
        assets.upload_library(api)


if __name__ == "__main__":
    main()
