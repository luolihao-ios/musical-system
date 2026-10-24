"""同步草稿的法语资料与各语言更新记录，不操作图片、构建或审核。"""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = "6806107359"
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"}


def editable(resource):
    attrs = resource["attributes"]
    return attrs.get("appStoreState", attrs.get("state")) in EDITABLE


def targets(snapshot, version):
    versions = [v for v in snapshot["versions"] if v["version"]["attributes"]["versionString"] == version and editable(v["version"])]
    infos = [v for v in snapshot["infos"] if editable(v["info"])]
    if len(versions) != 1 or len(infos) != 1:
        raise ValueError("必须唯一匹配可编辑版本与 App 信息，停止修改")
    return versions[0], infos[0]


def prepare_requests(snapshot, campaign):
    french = campaign["french"]
    if french["locale"] != "fr-FR":
        raise ValueError("本次只新增法国法语")
    for fields, limits in [(french["appInfo"], {"name": 30, "subtitle": 30}),
                           (french["versionInfo"], {"description": 4000, "keywords": 100, "promotionalText": 170}),
                           (campaign["whatsNew"], {k: 4000 for k in campaign["whatsNew"]})]:
        for key, limit in limits.items():
            if not fields.get(key) or len(fields[key]) > limit:
                raise ValueError(f"字段为空或超长：{key}")
    version, info = targets(snapshot, campaign["version"])
    for entry in version["locales"]:
        if entry["attributes"]["locale"] not in campaign["whatsNew"]:
            raise ValueError("缺少现有本地化的更新记录，停止部分更新")
    if "fr-FR" not in campaign["whatsNew"]:
        raise ValueError("缺少法语更新记录")
    requests = []

    def upsert(kind, entries, attrs, parent_kind, parent_type, parent_id):
        matches = [x for x in entries if x["attributes"]["locale"] == "fr-FR"]
        if len(matches) > 1:
            raise ValueError("法语本地化重复")
        data = {"type": kind, "attributes": dict(attrs)}
        if matches:
            data["id"] = matches[0]["id"]
            method, path = "PATCH", kind + "/" + data["id"]
        else:
            data["attributes"]["locale"] = "fr-FR"
            data["relationships"] = {parent_kind: {"data": {"type": parent_type, "id": parent_id}}}
            method, path = "POST", kind
        requests.append({"method": method, "path": path, "payload": {"data": data}})

    upsert("appInfoLocalizations", info["locales"], french["appInfo"], "appInfo", "appInfos", info["info"]["id"])
    upsert("appStoreVersionLocalizations", version["locales"],
           {**french["versionInfo"], "whatsNew": campaign["whatsNew"]["fr-FR"]},
           "appStoreVersion", "appStoreVersions", version["version"]["id"])
    for entry in version["locales"]:
        locale = entry["attributes"]["locale"]
        if locale != "fr-FR":
            requests.append({"method": "PATCH", "path": "appStoreVersionLocalizations/" + entry["id"],
                "payload": {"data": {"type": "appStoreVersionLocalizations", "id": entry["id"],
                "attributes": {"whatsNew": campaign["whatsNew"][locale]}}}})
    return requests


def snapshot(api):
    result = {"versions": [], "infos": []}
    for kind, child, key in [("appStoreVersions", "appStoreVersionLocalizations", "versions"), ("appInfos", "appInfoLocalizations", "infos")]:
        for parent in api.list_all(f"apps/{APP}/{kind}?limit=50"):
            result[key].append({"version" if key == "versions" else "info": parent,
                                "locales": api.list_all(f"{kind}/{parent['id']}/{child}?limit=200")})
    return result


def verify(before, after, campaign):
    old_version, old_info = targets(before, campaign["version"])
    version, info = targets(after, campaign["version"])
    for entry in version["locales"]:
        attrs = entry["attributes"]
        assert attrs["whatsNew"] == campaign["whatsNew"][attrs["locale"]], "更新记录回读不一致"
    for entries, expected in [(version["locales"], campaign["french"]["versionInfo"]), (info["locales"], campaign["french"]["appInfo"])]:
        french = next(x["attributes"] for x in entries if x["attributes"]["locale"] == "fr-FR")
        assert all(french.get(k) == v for k, v in expected.items()), "法语字段回读不一致"
    for kind, field, target in [("versions", "version", old_version["version"]["id"]), ("infos", "info", old_info["info"]["id"])]:
        current = {x[field]["id"]: x for x in after[kind]}
        for old in before[kind]:
            now = current[old[field]["id"]]
            for entry in old["locales"]:
                actual = next(x["attributes"] for x in now["locales"] if x["id"] == entry["id"])
                expected = dict(entry["attributes"])
                if old[field]["id"] == target:
                    locale = expected["locale"]
                    if field == "version":
                        expected["whatsNew"] = campaign["whatsNew"][locale]
                    if locale == "fr-FR":
                        expected.update(campaign["french"]["versionInfo" if field == "version" else "appInfo"])
                assert actual == expected, "非授权字段或已发布资料被改变"


def main():
    from app_store_screenshots import AppleAPI, list_placements
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="实际写入；默认仅检查")
    args = parser.parse_args()
    campaign = json.loads((ROOT / "marketing/app-store-2026-10-24/localizations/0.2.1.json").read_text(encoding="utf-8"))
    api = AppleAPI()
    assert api.call(f"apps/{APP}")["data"]["attributes"]["bundleId"] == "com.luolihao.musicalsystem"
    before = snapshot(api)
    requests = prepare_requests(before, campaign)
    backup = ROOT / ".api-inspection"
    backup.mkdir(exist_ok=True)
    import time
    stamp = str(int(time.time()))
    (backup / f"localization-sync-before-{stamp}.json").write_text(json.dumps(before, ensure_ascii=False, indent=2), encoding="utf-8")
    print("本次计划：", [(r["method"], r["path"]) for r in requests], flush=True)
    if not args.apply:
        return
    # 同时核对所有旧本地化的图片位置，保证本任务不影响宣传图。
    placements = {x["id"]: list_placements(api, x["id"]) for v in before["versions"] for x in v["locales"]}
    for request in requests:
        api.call(request["path"], request["method"], request["payload"])
        print("已保存：", request["path"], flush=True)
    after = snapshot(api)
    verify(before, after, campaign)
    for identity, items in placements.items():
        assert list_placements(api, identity) == items, "图片位置回读发生变化"
    version, info = targets(after, campaign["version"])
    report = {"version": campaign["version"], "versionId": version["version"]["id"],
              "locales": [x["attributes"]["locale"] for x in version["locales"]],
              "frenchFieldsVerified": True, "allWhatsNewVerified": True,
              "publishedMetadataUnchanged": True, "existingImagePlacementsUnchanged": True,
              "submittedForReview": False, "binaryUploaded": False}
    (ROOT / "marketing/app-store-2026-10-24/localizations/资料回读验收.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
