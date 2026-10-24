import importlib.util
import json
from pathlib import Path
import unittest

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
