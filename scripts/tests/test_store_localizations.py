import importlib.util
import json
from pathlib import Path
import unittest
from copy import deepcopy

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("metadata_sync", ROOT / "scripts/app_store_localizations.py")
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)

def fixture(state="PREPARE_FOR_SUBMISSION"):
    return {"versions": [{"version": {"id": "draft", "attributes": {"versionString": "0.2.1", "appStoreState": state}},
            "locales": [{"id": "existing-en", "attributes": {"locale": "en-US", "description": "Existing description", "whatsNew": None}}]}],
            "infos": [{"info": {"id": "info-draft", "attributes": {"appStoreState": "PREPARE_FOR_SUBMISSION"}}, "locales": []}]}

class StoreLocalizationTests(unittest.TestCase):
    def setUp(self):
        self.campaign = json.loads((ROOT / "marketing/app-store-2026-10-24/localizations/0.2.1.json").read_text(encoding="utf-8"))

    def test_existing_description_is_preserved_and_french_is_created_in_draft(self):
        requests = sync.prepare_requests(fixture(), self.campaign)
        english = next(r for r in requests if r["path"] == "appStoreVersionLocalizations/existing-en")
        self.assertEqual(english["payload"]["data"]["attributes"], {"whatsNew": self.campaign["whatsNew"]["en-US"]})
        french = next(r for r in requests if r["path"] == "appStoreVersionLocalizations")
        self.assertEqual(french["payload"]["data"]["attributes"]["locale"], "fr-FR")
        self.assertEqual(french["payload"]["data"]["relationships"]["appStoreVersion"]["data"]["id"], "draft")
        self.assertFalse(any("placement" in r["path"].lower() or "submission" in r["path"].lower() for r in requests))

    def test_published_version_is_rejected_before_any_request(self):
        with self.assertRaisesRegex(ValueError, "可编辑"):
            sync.prepare_requests(fixture("READY_FOR_SALE"), self.campaign)

    def test_field_limits_and_missing_locale_translation_are_rejected(self):
        self.campaign["french"]["versionInfo"]["keywords"] = "x" * 101
        with self.assertRaises(ValueError):
            sync.prepare_requests(fixture(), self.campaign)

    def test_repeated_run_updates_existing_french_instead_of_creating_duplicate(self):
        data = fixture()
        data["versions"][0]["locales"].append({"id": "fr-version", "attributes": {"locale": "fr-FR"}})
        data["infos"][0]["locales"].append({"id": "fr-info", "attributes": {"locale": "fr-FR"}})
        requests = sync.prepare_requests(data, self.campaign)
        self.assertTrue(all(r["method"] == "PATCH" for r in requests))

    def test_french_version_auto_created_after_info_creation_is_updated(self):
        data = fixture()
        # Apple 创建 appInfoLocalization 时可能同时建立空版本本地化。
        data["infos"][0]["locales"].append({"id": "fr-info", "attributes": {"locale": "fr-FR"}})
        data["versions"][0]["locales"].append({"id": "auto-fr-version", "attributes": {"locale": "fr-FR"}})
        requests = sync.prepare_requests(data, self.campaign)
        french = next(r for r in requests if r["path"].endswith("/auto-fr-version"))
        self.assertEqual(french["method"], "PATCH")
        self.assertEqual(french["payload"]["data"]["attributes"]["description"], self.campaign["french"]["versionInfo"]["description"])

    def test_missing_existing_locale_translation_is_rejected(self):
        del self.campaign["whatsNew"]["en-US"]
        with self.assertRaises(ValueError):
            sync.prepare_requests(fixture(), self.campaign)

    def verified_fixture(self):
        before = fixture()
        before["versions"].append({"version": {"id": "published", "attributes": {"versionString": "0.2", "appStoreState": "READY_FOR_SALE"}},
                                  "locales": [{"id": "published-en", "attributes": {"locale": "en-US", "description": "Published description"}}]})
        after = deepcopy(before)
        after["versions"][0]["locales"][0]["attributes"]["whatsNew"] = self.campaign["whatsNew"]["en-US"]
        after["versions"][0]["locales"].append({"id": "fr-version", "attributes": {"locale": "fr-FR", **self.campaign["french"]["versionInfo"], "whatsNew": self.campaign["whatsNew"]["fr-FR"]}})
        after["infos"][0]["locales"].append({"id": "fr-info", "attributes": {"locale": "fr-FR", **self.campaign["french"]["appInfo"]}})
        return before, after

    def test_readback_accepts_only_authorized_fields(self):
        before, after = self.verified_fixture()
        sync.verify(before, after, self.campaign)
        for version_index in [0, 1]:
            changed = deepcopy(after)
            changed["versions"][version_index]["locales"][0]["attributes"]["description"] = "Unintended change"
            with self.assertRaises(ValueError):
                sync.verify(before, changed, self.campaign)

    def test_readback_rejects_incorrect_french_fields(self):
        before, after = self.verified_fixture()
        after["versions"][0]["locales"][1]["attributes"]["description"] = "Incorrect description"
        with self.assertRaises(ValueError):
            sync.verify(before, after, self.campaign)
