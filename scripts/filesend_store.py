"""file send 的商店资料与构建号管理；由 GitHub Actions 使用团队密钥执行。"""
import argparse
import json
import os
from pathlib import Path

from app_store_screenshots import AppleAPI, EDITABLE

BUNDLE = "com.luolihao.aiyuetransfer"
LABELS = {
    "en-US": {
        "name": "ios file send",
        "subtitle": "WiFi file transfer&ios deliver"
    },
    "zh-Hant": {
        "name": "ios 文件傳輸助手",
        "subtitle": "手機電腦雙向互傳，區域網路輕鬆傳檔"
    },
    "zh-Hans": {
        "name": "ios文件传输助手",
        "subtitle": "手机电脑双向互传，局域网轻松传文件"
    }
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


def ensure_draft(api, state, version):
    """仅使用工作流中明确指定的版本创建草稿，永不自行递增营销版本。"""
    existing = [item for item in state["versions"] if item["attributes"]["versionString"] == version]
    if existing:
        if len(existing) != 1 or existing[0]["attributes"]["appStoreState"] not in EDITABLE:
            raise ValueError("指定版本已发布或不可编辑")
        return existing[0]
    if any(item["attributes"]["appStoreState"] in EDITABLE for item in state["versions"]):
        raise ValueError("已有其他可编辑版本，停止创建")
    if version != "1.0.2":
        raise ValueError("本次只授权创建 1.0.2 草稿")
    return api.call("appStoreVersions", "POST", {"data": {
        "type": "appStoreVersions", "attributes": {"platform": "IOS", "versionString": version, "releaseType": "MANUAL"},
        "relationships": {"app": {"data": {"type": "apps", "id": state["app"]["id"]}}}}})["data"]


def update_whats_new(api, state, notes):
    targets = [item for item in state["versions"] if item["attributes"]["appStoreState"] in EDITABLE]
    if len(targets) != 1 or targets[0]["attributes"]["versionString"] != "1.0.2":
        raise ValueError("仅授权填写 1.0.2 可编辑草稿的新增内容")
    path = f"appStoreVersions/{targets[0]['id']}/appStoreVersionLocalizations?limit=50"
    before = api.call(path)["data"]
    if not before:
        raise ValueError("当前草稿没有语言版本")
    missing = [item["attributes"]["locale"] for item in before if not notes.get(item["attributes"]["locale"])]
    if missing:
        raise ValueError("缺少对应语言的更新说明：" + ", ".join(missing))
    if any(len(notes[item["attributes"]["locale"]]) > 4000 for item in before):
        raise ValueError("更新说明超过 4000 字符")
    for item in before:
        locale = item["attributes"]["locale"]
        api.call(f"appStoreVersionLocalizations/{item['id']}", "PATCH", {"data": {
            "type": "appStoreVersionLocalizations", "id": item["id"],
            "attributes": {"whatsNew": notes[locale]}}})
    after = api.call(path)["data"]
    mapped = {item["id"]: item["attributes"] for item in after}
    for item in before:
        attributes = mapped.get(item["id"], {})
        locale = item["attributes"]["locale"]
        if attributes.get("whatsNew") != notes[locale]:
            raise RuntimeError("更新说明回读不匹配：" + locale)
        if any(attributes.get(key) != value for key, value in item["attributes"].items() if key != "whatsNew"):
            raise RuntimeError("新增内容之外的字段发生变化：" + locale)
    return {item["attributes"]["locale"]: mapped[item["id"]]["whatsNew"] for item in before}


def next_build(api, app_id):
    builds = api.list_all(f"builds?filter[app]={app_id}&limit=200")
    values = [int(item["attributes"]["version"]) for item in builds
              if str(item["attributes"]["version"]).isdigit()]
    return max([110, *values]) + 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["inspect", "update-metadata", "next-build", "upload-library", "update-whats-new"])
    parser.add_argument("--draft-version", default="", help="明确授权创建的商店草稿版本")
    args = parser.parse_args()
    api = AppleAPI()
    state = read_state(api)
    report = Path(".api-inspection/filesend")
    report.mkdir(parents=True, exist_ok=True)
    (report / "before.json").write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"app": {"id": state["app"]["id"], "bundleId": state["app"]["attributes"]["bundleId"]},
        "versions": [{"version": item["attributes"]["versionString"], "state": item["attributes"]["appStoreState"]} for item in state["versions"]],
        "latestBuilds": [item["attributes"]["version"] for item in state["latestBuilds"]]}, ensure_ascii=False), flush=True)
    if args.operation == "update-metadata":
        if args.draft_version:
            ensure_draft(api, state, args.draft_version)
            state = read_state(api)
        updated = update_metadata(api, state)
        (report / "metadata-verified.json").write_text(json.dumps(updated, ensure_ascii=False, indent=2), encoding="utf-8")
        print("三语言名称与副标题回读通过：", json.dumps(updated, ensure_ascii=False), flush=True)
    elif args.operation == "update-whats-new":
        campaign = json.loads(Path("marketing/file-send-2026-10-26/localizations/1.0.2.json").read_text(encoding="utf-8"))
        if campaign["version"] != "1.0.2":
            raise ValueError("更新说明版本不匹配")
        updated = update_whats_new(api, state, campaign["whatsNew"])
        (report / "whats-new-verified.json").write_text(json.dumps(updated, ensure_ascii=False, indent=2), encoding="utf-8")
        print("新增内容已保存并回读：", json.dumps(updated, ensure_ascii=False), flush=True)
    elif args.operation == "next-build":
        version = next_build(api, state["app"]["id"])
        with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as stream:
            stream.write(f"FILE_SEND_BUILD={version}\n")
        print(f"本次构建号：{version}", flush=True)
    elif args.operation == "upload-library":
        targets = [item for item in state["versions"] if item["attributes"]["appStoreState"] in EDITABLE]
        if len(targets) != 1 or targets[0]["attributes"]["versionString"] != "1.0.2":
            raise ValueError("仅授权上传到 file send 的 1.0.2 可编辑草稿")
        campaign = Path("marketing/file-send-2026-10-26")
        entries = json.loads((campaign / "文件验收清单.json").read_text(encoding="utf-8"))
        groups = {group: sum(item["file"].startswith(group + "/") for item in entries)
                  for group in ("iphone-medium", "iphone-duo", "ipad-13", "creative")}
        if len(entries) != 15 or groups != {"iphone-medium": 5, "iphone-duo": 4, "ipad-13": 4, "creative": 2}:
            raise ValueError("全套必须有五张 iPhone、四张 Duo、四张 iPad 和两张独立宣传图")
        if not all(item.get("actualScreenshotPixelVerified") for item in entries):
            raise ValueError("存在未通过实际界面像素验收的素材")
        import app_store_screenshots as assets
        assets.APP = state["app"]["id"]
        assets.CAMPAIGN_FOLDER = Path("marketing/file-send-2026-10-26")
        assets.CAMPAIGN_REFERENCE = "file send 20261026"
        assets.upload_library(api, target_locales=("en-US", "zh-Hans", "zh-Hant"))


if __name__ == "__main__":
    main()
