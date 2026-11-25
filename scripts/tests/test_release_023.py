"""0.2.3 App Store Connect 版本发布资料与三设备宣传图离线测试。"""
import importlib.util
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

spec = importlib.util.spec_from_file_location("release_023", ROOT / "scripts/app_store_release_023.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class FakeAPI:
    def __init__(self, versions, existing_locales=None, existing_placements=None):
        self.versions = list(versions)
        self.locales = dict(existing_locales or {})
        self.placements = dict(existing_placements or {})
        self.calls = []
        self.seq = 0

    def list_all(self, path):
        if path.startswith(f"apps/{release.APP}/appStoreVersions"):
            return list(self.versions)
        if "/appStoreVersionLocalizations" in path:
            vid = path.split("/")[1]
            return list(self.locales.get(vid, []))
        if "/placements" in path:
            lid = path.split("/")[1]
            items = list(self.placements.get(lid, []))
            if "filter[placementGroup]=" in path:
                group = path.split("filter[placementGroup]=")[1].split("&")[0]
                return [p for p in items if p["attributes"]["placementGroup"] == group]
            return items
        raise AssertionError(path)

    def call(self, path, method="GET", payload=None):
        self.calls.append((method, path))
        if method == "PATCH" and path.startswith("appStoreVersions/"):
            vid = path.split("/")[1]
            for v in self.versions:
                if v["id"] == vid:
                    v["attributes"]["versionString"] = payload["data"]["attributes"]["versionString"]
                    return {"data": v}
        if method == "POST" and path == "appStoreVersions":
            self.seq += 1
            ver = {
                "id": f"ver-{self.seq}",
                "attributes": {**payload["data"]["attributes"], "appStoreState": "PREPARE_FOR_SUBMISSION"},
            }
            self.versions.append(ver)
            return {"data": ver}
        if method == "PATCH" and path.startswith("appStoreVersionLocalizations/"):
            lid = path.split("/")[1]
            for entries in self.locales.values():
                for e in entries:
                    if e["id"] == lid:
                        e["attributes"].update(payload["data"]["attributes"])
                        return {"data": e}
        if method == "POST" and path == "appStoreVersionLocalizations":
            self.seq += 1
            vid = payload["data"]["relationships"]["appStoreVersion"]["data"]["id"]
            loc = {"id": f"loc-{self.seq}", "attributes": dict(payload["data"]["attributes"])}
            self.locales.setdefault(vid, []).append(loc)
            return {"data": loc}
        if method == "DELETE" and path.startswith("appAssetLibraryPlacements/"):
            pid = path.split("/")[1]
            for lid, items in self.placements.items():
                self.placements[lid] = [p for p in items if p["id"] != pid]
            return {}
        if method == "POST" and path == "appAssetLibraryPlacements":
            self.seq += 1
            data = payload["data"]
            lid = data["relationships"]["appStoreVersionLocalization"]["data"]["id"]
            item = {
                "id": f"pl-{self.seq}",
                "attributes": dict(data["attributes"]),
                "relationships": {"image": data["relationships"]["image"]},
            }
            self.placements.setdefault(lid, []).append(item)
            return {"data": item}
        if method == "POST" and path == "appAssetLibraryPlacementOrderingRequests":
            data = payload["data"]
            lid = data["relationships"]["appStoreVersionLocalization"]["data"]["id"]
            group = data["attributes"]["placementGroup"]
            ordered_ids = [x["id"] for x in data["relationships"]["orderedPlacements"]["data"]]
            by_id = {p["id"]: p for p in self.placements.get(lid, []) if p["attributes"]["placementGroup"] == group}
            others = [p for p in self.placements.get(lid, []) if p["attributes"]["placementGroup"] != group]
            self.placements[lid] = others + [by_id[i] for i in ordered_ids]
            return {}
        raise AssertionError((method, path))


class Release023Tests(unittest.TestCase):
    def test_campaign_manifest_and_localizations_are_valid(self):
        campaign = json.loads((ROOT / "marketing/app-store-2026-11-26/localizations/0.2.3.json").read_text(encoding="utf-8"))
        manifest, prepared = release.validate_campaign(campaign)
        self.assertEqual(len(manifest), 12)
        self.assertEqual(len(prepared), 12)
        for group in ("iphone-medium", "iphone-duo", "ipad-13"):
            self.assertEqual(sum(m["file"].startswith(group + "/") for m in manifest), 4)

    def test_ensure_editable_version_creates_reuses_and_renames_safely(self):
        api_create = FakeAPI([{"id": "v21", "attributes": {"versionString": "0.2.1", "appStoreState": "READY_FOR_SALE"}}])
        ver, action = release.ensure_editable_version(api_create, "0.2.3")
        self.assertEqual(action, "created")
        self.assertEqual(ver["attributes"]["versionString"], "0.2.3")

        api_reuse = FakeAPI([{"id": "v23", "attributes": {"versionString": "0.2.3", "appStoreState": "PREPARE_FOR_SUBMISSION"}}])
        ver, action = release.ensure_editable_version(api_reuse, "0.2.3")
        self.assertEqual(action, "reused")
        self.assertEqual(ver["id"], "v23")

        api_rename = FakeAPI([{"id": "v22", "attributes": {"versionString": "0.2.2", "appStoreState": "PREPARE_FOR_SUBMISSION"}}])
        ver, action = release.ensure_editable_version(api_rename, "0.2.3")
        self.assertEqual(action, "renamed-from-0.2.2")
        self.assertEqual(ver["attributes"]["versionString"], "0.2.3")

        api_locked = FakeAPI([{"id": "v23", "attributes": {"versionString": "0.2.3", "appStoreState": "IN_REVIEW"}}])
        with self.assertRaises(ValueError):
            release.ensure_editable_version(api_locked, "0.2.3")

    def test_sync_localizations_and_placements_without_review_submission(self):
        campaign = json.loads((ROOT / "marketing/app-store-2026-11-26/localizations/0.2.3.json").read_text(encoding="utf-8"))
        api = FakeAPI(
            versions=[{"id": "v23", "attributes": {"versionString": "0.2.3", "appStoreState": "PREPARE_FOR_SUBMISSION"}}],
            existing_locales={"v23": [{"id": "loc-zh", "attributes": {"locale": "zh-Hans"}}]},
            existing_placements={
                "loc-zh": [
                    {
                        "id": "stale-1",
                        "attributes": {"placementType": "APP_SCREENSHOT", "placementGroup": "IPAD_13_PROFILE"},
                        "relationships": {"image": {"data": {"id": "old-img"}}},
                    },
                    {
                        "id": "creative-1",
                        "attributes": {"placementType": "PRODUCT_PAGE_HEADER_ASSET", "placementGroup": "DEFAULT_PROFILE"},
                        "relationships": {"image": {"data": {"id": "header-img"}}},
                    },
                ]
            },
        )
        locs = release.sync_localizations(api, "v23", campaign)
        self.assertEqual({x["attributes"]["locale"] for x in locs}, set(release.LOCALES))
        selected = [
            ({"file": "iphone-medium/01.png"}, "m1"),
            ({"file": "iphone-medium/02.png"}, "m2"),
            ({"file": "ipad-13/01.png"}, "p1"),
        ]
        report = release.sync_placements_for_locale(api, locs[0], selected)
        self.assertTrue(all(report["groupsVerified"].values()))
        # Creative asset in DEFAULT_PROFILE was untouched
        remaining_ids = {p["id"] for p in api.placements["loc-zh"]}
        self.assertIn("creative-1", remaining_ids)
        self.assertNotIn("stale-1", remaining_ids)
        self.assertFalse(any("reviewsubmission" in path.lower() for _, path in api.calls))


if __name__ == "__main__":
    unittest.main()
